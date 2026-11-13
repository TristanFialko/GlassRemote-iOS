import Foundation
import Network
import Security

// The byte link under both Remote v2 connections. Production uses TLS (Network.framework) with the
// Keychain client identity; tests inject a fake. Every callback runs on the queue passed in.

enum RemoteV2ChannelClose: Equatable {
    /// The owner cancelled the channel.
    case cancelled
    /// The TV closed the connection.
    case remoteClosed
    /// The TLS handshake failed: on 6466 this means the TV does not accept this client's certificate
    /// (never paired, or the pairing was removed on the TV), so the app asks for pairing again.
    case authenticationRejected
    /// Anything else (unreachable, timeout, reset). Retried with backoff.
    case failed(String)
}

/// What the connection layer needs from the client identity. The pairing secret uses the public key.
protocol RemoteV2ClientCredential {
    var publicKey: RemoteV2RSAPublicKey { get }
}

extension RemoteV2ClientIdentity: RemoteV2ClientCredential {}

protocol RemoteV2Channel: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onReceive: (([UInt8]) -> Void)? { get set }
    /// Called at most once, and never after the owner calls cancel().
    var onClose: ((RemoteV2ChannelClose) -> Void)? { get set }
    /// The TV's RSA public key from this TLS session's leaf certificate (nil before the handshake).
    var peerPublicKey: RemoteV2RSAPublicKey? { get }
    func start()
    func send(_ bytes: [UInt8])
    func cancel()
}

typealias RemoteV2ChannelFactory = (_ host: String, _ port: UInt16, _ credential: RemoteV2ClientCredential,
                                    _ queue: DispatchQueue) -> RemoteV2Channel

/// TLS 1.2+ with the client certificate. The TV's certificate is self-signed, so it is accepted
/// without chain validation; its public key is captured because the pairing secret is bound to it.
final class RemoteV2TLSChannel: RemoteV2Channel {
    var onReady: (() -> Void)?
    var onReceive: (([UInt8]) -> Void)?
    var onClose: ((RemoteV2ChannelClose) -> Void)?
    var peerPublicKey: RemoteV2RSAPublicKey? { peer.key }

    static let factory: RemoteV2ChannelFactory = { host, port, credential, queue in
        RemoteV2TLSChannel(host: host, port: port, identity: credential as? RemoteV2ClientIdentity, queue: queue)
    }

    private final class PeerKeyBox { var key: RemoteV2RSAPublicKey? }

    private let peer: PeerKeyBox
    private let connection: NWConnection?
    private let queue: DispatchQueue
    private let setupFailure: RemoteV2ChannelClose?
    private var closed = false

    init(host: String, port: UInt16, identity: RemoteV2ClientIdentity?, queue: DispatchQueue) {
        let box = PeerKeyBox()
        peer = box
        self.queue = queue
        guard let identity = identity, let endpointPort = NWEndpoint.Port(rawValue: port),
              let local = sec_identity_create(identity.identity) else {
            connection = nil
            setupFailure = .failed("No client identity")
            return
        }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(options, local)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first {
                box.key = RemoteV2TLSChannel.publicKey(of: leaf)
            }
            complete(true)
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 8
        tcp.noDelay = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort,
                                  using: NWParameters(tls: tls, tcp: tcp))
        setupFailure = nil
    }

    static func publicKey(of certificate: SecCertificate) -> RemoteV2RSAPublicKey? {
        guard let key = SecCertificateCopyKey(certificate) else { return nil }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else { return nil }
        return try? RemoteV2RSAPublicKey(pkcs1: Array(data))
    }

    func start() {
        guard let connection = connection else {
            let failure = setupFailure ?? .failed("Unavailable")
            queue.async { [weak self] in self?.finish(failure) }
            return
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.closed else { return }
            switch state {
            case .ready:
                self.onReady?()
                self.receiveNext()
            case let .waiting(error):
                self.finish(Self.classify(error))
            case let .failed(error):
                self.finish(Self.classify(error))
            case .cancelled:
                self.finish(.cancelled)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ bytes: [UInt8]) {
        guard !closed, let connection = connection else { return }
        connection.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            if let error = error { self?.finish(Self.classify(error)) }
        })
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: RemoteV2FrameDecoder.defaultMaxFrameLength) {
            [weak self] data, _, isComplete, error in
            guard let self = self, !self.closed else { return }
            if let data = data, !data.isEmpty { self.onReceive?(Array(data)) }
            guard !self.closed else { return }
            if let error = error {
                self.finish(Self.classify(error))
            } else if isComplete {
                self.finish(.remoteClosed)
            } else {
                self.receiveNext()
            }
        }
    }

    private func finish(_ reason: RemoteV2ChannelClose) {
        guard !closed else { return }
        closed = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        onClose?(reason)
    }

    static func classify(_ error: NWError) -> RemoteV2ChannelClose {
        switch error {
        case .tls:
            return .authenticationRejected
        default:
            return .failed(error.debugDescription)
        }
    }
}

/// Which TVs this iPhone has paired with (a UX hint only; the TV keeps the real pairing, bound to the
/// Keychain key). Never stores codes or secrets.
enum RemoteV2PairingRecord {
    static let defaultsKey = "remoteV2.pairedHosts"

    static func isPaired(_ host: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: defaultsKey) ?? []).contains(host)
    }

    static func markPaired(_ host: String, defaults: UserDefaults = .standard) {
        var hosts = defaults.stringArray(forKey: defaultsKey) ?? []
        if !hosts.contains(host) { hosts.append(host) }
        defaults.set(hosts, forKey: defaultsKey)
    }

    static func forget(_ host: String, defaults: UserDefaults = .standard) {
        let hosts = (defaults.stringArray(forKey: defaultsKey) ?? []).filter { $0 != host }
        defaults.set(hosts, forKey: defaultsKey)
    }
}
