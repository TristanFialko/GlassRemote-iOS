import Foundation

/// One pairing attempt on TCP 6467. Drives RemoteV2PairingMachine over a channel: the TV shows a code,
/// the user types it, the code's check byte is verified against the TV key from this TLS session,
/// and only then is the secret sent. A wrong code is rejected locally (nothing sent) so the user can
/// retype while the TV still shows it. All state is confined to `queue`; callbacks go to
/// `callbackQueue`. Callbacks from a replaced or cancelled channel are ignored.
final class RemoteV2PairingSession {
    static let port: UInt16 = 6467
    /// Each protocol step must be answered within this time.
    static let stepTimeout: TimeInterval = 15
    /// How long the TV's code stays usable here before pairing is abandoned.
    static let codeTimeout: TimeInterval = 300

    let host: String
    /// Phase changes, delivered on callbackQueue. Set before start().
    var onPhase: ((RemoteV2PairingPhase) -> Void)?
    /// A typed code was refused before anything was sent (malformed or check byte mismatch).
    var onCodeRejected: ((RemoteV2PairingFailure) -> Void)?

    private let clientName: String
    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let loadCredential: () throws -> RemoteV2ClientCredential
    private let makeChannel: RemoteV2ChannelFactory

    private var machine = RemoteV2PairingMachine()
    private var decoder = RemoteV2FrameDecoder()
    private var channel: RemoteV2Channel?
    private var credential: RemoteV2ClientCredential?
    /// The TV key the accepted code was checked against; pinned when the TV confirms the secret.
    private var verifiedServerKey: RemoteV2RSAPublicKey?
    private var generation = 0
    private var timeoutToken = 0
    private var started = false
    private var finished = false

    init(host: String,
         clientName: String = "GlassRemote",
         queue: DispatchQueue = DispatchQueue(label: "GlassRemote.RemoteV2.pairing"),
         callbackQueue: DispatchQueue = .main,
         loadCredential: @escaping () throws -> RemoteV2ClientCredential = {
             try RemoteV2KeychainIdentityStore.shared.loadOrCreate()
         },
         makeChannel: @escaping RemoteV2ChannelFactory = RemoteV2TLSChannel.factory) {
        self.host = host
        self.clientName = clientName
        self.queue = queue
        self.callbackQueue = callbackQueue
        self.loadCredential = loadCredential
        self.makeChannel = makeChannel
    }

    func start() { queue.async { [weak self] in self?.begin() } }

    func submit(code: String) { queue.async { [weak self] in self?.handleCode(code) } }

    func cancel() { queue.async { [weak self] in self?.fail(.cancelled) } }

    private func begin() {
        guard !started, !finished else { return }
        started = true
        generation += 1
        let token = generation
        let credential: RemoteV2ClientCredential
        do {
            credential = try loadCredential()
        } catch {
            fail(.identityUnavailable)
            return
        }
        self.credential = credential
        let channel = makeChannel(host, Self.port, credential, queue)
        self.channel = channel
        channel.onReady = { [weak self] in
            guard let self = self, self.generation == token, !self.finished else { return }
            self.write(self.machine.start(clientName: self.clientName))
            self.armTimeout(Self.stepTimeout)
            self.publish()
        }
        channel.onReceive = { [weak self] bytes in
            guard let self = self, self.generation == token else { return }
            self.receive(bytes)
        }
        channel.onClose = { [weak self] _ in
            guard let self = self, self.generation == token else { return }
            self.channel = nil
            self.fail(.connectionLost)
        }
        channel.start()
        armTimeout(Self.stepTimeout)
    }

    private func receive(_ bytes: [UInt8]) {
        guard !finished else { return }
        let bodies: [[UInt8]]
        do {
            bodies = try decoder.append(bytes)
        } catch {
            fail(.unexpectedMessage)
            return
        }
        for body in bodies {
            guard !finished else { return }
            guard let message = try? PoloMessage.decode(body) else {
                fail(.unexpectedMessage)
                return
            }
            if let reply = machine.receive(message) { write(reply) }
            switch machine.phase {
            case .paired:
                finish()
                return
            case .failed:
                finish()
                return
            case .awaitingCode:
                armTimeout(Self.codeTimeout)
            default:
                armTimeout(Self.stepTimeout)
            }
            publish()
        }
    }

    private func handleCode(_ text: String) {
        guard !finished, machine.phase == .awaitingCode else { return }
        guard let code = RemoteV2PairingCode.parse(text) else {
            reject(.malformedCode)
            return
        }
        guard let client = credential?.publicKey, let server = channel?.peerPublicKey else {
            fail(.connectionLost)
            return
        }
        let secret: [UInt8]
        do {
            secret = try RemoteV2PairingCode.secret(code: code, client: client, server: server)
        } catch let failure as RemoteV2PairingFailure {
            reject(failure)
            return
        } catch {
            reject(.malformedCode)
            return
        }
        guard let message = machine.submit(secret: secret) else { return }
        verifiedServerKey = server
        write(message)
        armTimeout(Self.stepTimeout)
        publish()
    }

    private func write(_ message: PoloMessage) {
        channel?.send(RemoteV2FrameDecoder.frame(message.encoded()))
    }

    private func armTimeout(_ seconds: TimeInterval) {
        timeoutToken += 1
        let token = timeoutToken
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self, self.timeoutToken == token, !self.finished else { return }
            self.fail(.timedOut)
        }
    }

    private func fail(_ failure: RemoteV2PairingFailure) {
        guard !finished else { return }
        machine.fail(failure)
        finish()
    }

    /// Ends the attempt (paired or failed): closes the channel and ignores anything still in flight.
    private func finish() {
        finished = true
        timeoutToken += 1
        generation += 1
        channel?.cancel()
        channel = nil
        if machine.phase == .paired, let tvKey = verifiedServerKey {
            RemoteV2PairingRecord.markPaired(host, tvKey: tvKey)
        }
        publish()
    }

    private func publish() {
        let phase = machine.phase
        let handler = onPhase
        callbackQueue.async { handler?(phase) }
    }

    private func reject(_ failure: RemoteV2PairingFailure) {
        let handler = onCodeRejected
        callbackQueue.async { handler?(failure) }
    }
}
