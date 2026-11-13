import Foundation

/// The control connection on TCP 6466. Answers the TV's handshake (configure, set-active, pings),
/// reports `.connected` only after RemoteStart, and sends keys and app links only while connected
/// and only for negotiated features. A dropped link reconnects with bounded backoff; a rejected
/// TLS handshake means the TV no longer knows this iPhone, so it stops and reports `.notPaired`.
/// Before anything is read or sent, the TV must present the RSA key pinned at pairing; a different
/// key stops the connection with `.identityMismatch` (no retry), and no pinned key means `.notPaired`.
/// Volume/mute, power/standby/wake key codes and app links are dropped here too, as a last line of
/// defence (all ADB-only by policy).
final class RemoteV2ControlConnection {
    static let port: UInt16 = 6466

    let host: String
    /// Link state and the features usable right now (empty unless connected). On callbackQueue.
    var onState: ((RemoteV2LinkState, RemoteV2Features) -> Void)?

    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let loadCredential: () throws -> RemoteV2ClientCredential
    private let makeChannel: RemoteV2ChannelFactory
    private let idleTimeout: TimeInterval
    private let expectedTVKey: () -> String?

    private var session = RemoteV2Session()
    private var decoder = RemoteV2FrameDecoder()
    private var channel: RemoteV2Channel?
    private var generation = 0
    private var idleToken = 0
    private var running = false
    private var failures = 0
    private var state: RemoteV2LinkState = .off
    private var peerVerified = false

    init(host: String,
         queue: DispatchQueue = DispatchQueue(label: "GlassRemote.RemoteV2.control"),
         callbackQueue: DispatchQueue = .main,
         idleTimeout: TimeInterval = RemoteV2Session.idleTimeout,
         loadCredential: @escaping () throws -> RemoteV2ClientCredential = {
             try RemoteV2KeychainIdentityStore.shared.loadOrCreate()
         },
         makeChannel: @escaping RemoteV2ChannelFactory = RemoteV2TLSChannel.factory,
         expectedTVKey: (() -> String?)? = nil) {
        self.host = host
        self.expectedTVKey = expectedTVKey ?? { RemoteV2PairingRecord.tvKeyFingerprint(for: host) }
        self.queue = queue
        self.callbackQueue = callbackQueue
        self.idleTimeout = idleTimeout
        self.loadCredential = loadCredential
        self.makeChannel = makeChannel
    }

    func start() {
        queue.async { [weak self] in
            guard let self = self, !self.running else { return }
            self.running = true
            self.failures = 0
            self.connect()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.running = false
            self.teardown()
            self.set(.off)
        }
    }

    /// Sends a command if the session is connected and has negotiated the feature; otherwise drops it.
    /// Never queued for later: a key that cannot go now must not arrive late.
    func send(_ outbound: RemoteV2Outbound) {
        queue.async { [weak self] in self?.sendCommand(outbound) }
    }

    private func connect() {
        guard running, channel == nil else { return }
        generation += 1
        let token = generation
        session = RemoteV2Session()
        decoder.reset()
        peerVerified = false
        let credential: RemoteV2ClientCredential
        do {
            credential = try loadCredential()
        } catch {
            running = false
            set(.failed("no remote identity"))
            return
        }
        set(.connecting)
        let channel = makeChannel(host, Self.port, credential, queue)
        self.channel = channel
        channel.onReady = { [weak self] in
            guard let self = self, self.generation == token else { return }
            guard self.verifyPeer(self.channel?.peerPublicKey) else { return }
            self.armIdle()
        }
        channel.onReceive = { [weak self] bytes in
            guard let self = self, self.generation == token else { return }
            self.receive(bytes)
        }
        channel.onClose = { [weak self] reason in
            guard let self = self, self.generation == token else { return }
            self.channelClosed(reason)
        }
        channel.start()
    }

    /// The TV must present the key it proved during pairing. Runs once the TLS handshake completes,
    /// before any frame is processed or written.
    private func verifyPeer(_ key: RemoteV2RSAPublicKey?) -> Bool {
        guard let expected = expectedTVKey() else {
            running = false
            teardown()
            set(.notPaired)
            return false
        }
        guard let key = key, key.fingerprint == expected else {
            running = false
            teardown()
            set(.identityMismatch)
            return false
        }
        peerVerified = true
        return true
    }

    private func receive(_ bytes: [UInt8]) {
        guard peerVerified else { return }
        let bodies: [[UInt8]]
        do {
            bodies = try decoder.append(bytes)
        } catch {
            dropAndReconnect()
            return
        }
        armIdle()
        for body in bodies {
            guard let inbound = try? RemoteV2Inbound.decode(body) else {
                dropAndReconnect()
                return
            }
            let wasReady = session.ready
            if let reply = session.handle(inbound) { write(reply) }
            if session.ready && !wasReady {
                failures = 0
                set(.connected)
            }
        }
    }

    private func sendCommand(_ outbound: RemoteV2Outbound) {
        guard channel != nil, peerVerified, session.ready else { return }
        switch outbound {
        case let .key(code, _):
            guard !RemoteV2KeyMap.forbidden.contains(code), !RemoteV2KeyMap.adbOnlyCodes.contains(code),
                  session.supports(.key) else { return }
        case .appLink:
            return // app launch is ADB-only by policy
        case .configure, .setActive, .pingResponse:
            return
        }
        write(outbound)
    }

    private func write(_ outbound: RemoteV2Outbound) {
        channel?.send(RemoteV2FrameDecoder.frame(outbound.encoded()))
    }

    private func channelClosed(_ reason: RemoteV2ChannelClose) {
        channel = nil
        idleToken += 1
        guard running else {
            set(.off)
            return
        }
        if reason == .authenticationRejected {
            running = false
            set(.notPaired)
        } else {
            scheduleReconnect()
        }
    }

    private func dropAndReconnect() {
        teardown()
        if running { scheduleReconnect() }
    }

    private func teardown() {
        generation += 1
        idleToken += 1
        channel?.cancel()
        channel = nil
    }

    private func scheduleReconnect() {
        failures += 1
        let delay = RemoteV2Backoff.delay(afterFailures: failures)
        set(.unreachable(retryIn: Int(delay.rounded(.up))))
        let token = generation
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.running, self.generation == token, self.channel == nil else { return }
            self.connect()
        }
    }

    /// The TV pings an idle session every few seconds; silence past the timeout means the link is dead.
    private func armIdle() {
        idleToken += 1
        let token = idleToken
        queue.asyncAfter(deadline: .now() + idleTimeout) { [weak self] in
            guard let self = self, self.idleToken == token, self.channel != nil else { return }
            self.dropAndReconnect()
        }
    }

    private func set(_ newState: RemoteV2LinkState) {
        state = newState
        let features: RemoteV2Features = newState == .connected ? session.active : []
        let handler = onState
        callbackQueue.async { handler?(newState, features) }
    }
}
