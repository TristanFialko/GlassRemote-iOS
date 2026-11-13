import XCTest
@testable import GlassRemote

private final class FakeChannel: RemoteV2Channel {
    var onReady: (() -> Void)?
    var onReceive: (([UInt8]) -> Void)?
    var onClose: ((RemoteV2ChannelClose) -> Void)?
    var peerPublicKey: RemoteV2RSAPublicKey?
    var started = false
    var cancelled = false
    var sent: [[UInt8]] = []

    func start() { started = true }
    func send(_ bytes: [UInt8]) { sent.append(bytes) }
    func cancel() { cancelled = true }

    func frames() throws -> [[UInt8]] {
        var decoder = RemoteV2FrameDecoder()
        return try decoder.append(sent.flatMap { $0 })
    }
}

private struct FakeCredential: RemoteV2ClientCredential {
    let publicKey: RemoteV2RSAPublicKey
}

private final class Harness {
    let queue = DispatchQueue(label: "GlassRemoteTests.RemoteV2")
    var channels: [FakeChannel] = []
    var peer: RemoteV2RSAPublicKey?

    var factory: RemoteV2ChannelFactory {
        return { [unowned self] _, _, _, _ in
            let channel = FakeChannel()
            channel.peerPublicKey = self.peer
            self.channels.append(channel)
            return channel
        }
    }

    func flush() {
        queue.sync {}
        queue.sync {}
    }

    func deliver(_ channel: FakeChannel, _ bytes: [UInt8]) {
        queue.sync { channel.onReceive?(RemoteV2FrameDecoder.frame(bytes)) }
        flush()
    }
}

/// The pairing and control connections driven over a fake channel (no network).
final class RemoteV2ConnectionTests: XCTestCase {
    private let client = RemoteV2RSAPublicKey(modulus: [0xC1, 0x02], exponent: [0x01, 0x00, 0x01])
    private let server = RemoteV2RSAPublicKey(modulus: [0xD3, 0x04, 0x05], exponent: [0x03])
    private let host = "remote-v2-test.invalid"

    override func tearDown() {
        RemoteV2PairingRecord.forget(host)
        super.tearDown()
    }

    private func makePairing(_ h: Harness, credential: Bool = true) -> RemoteV2PairingSession {
        let key = client
        return RemoteV2PairingSession(host: host, queue: h.queue, callbackQueue: h.queue, loadCredential: {
            guard credential else { throw RemoteV2IdentityError.identityUnavailable }
            return FakeCredential(publicKey: key)
        }, makeChannel: h.factory)
    }

    private func tv(_ h: Harness, _ channel: FakeChannel, _ payload: PoloPayload, status: UInt64 = 200) {
        h.deliver(channel, PoloMessage(status: status, payload: payload).encoded())
    }

    private func payloads(_ channel: FakeChannel) throws -> [PoloPayload] {
        try channel.frames().map { try PoloMessage.decode($0).payload }
    }

    private func pairToCode(_ h: Harness, _ session: RemoteV2PairingSession) throws -> FakeChannel {
        session.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        XCTAssertTrue(channel.started)
        h.queue.sync { channel.onReady?() }
        h.flush()
        tv(h, channel, .pairingRequestAck(serverName: "TV"))
        tv(h, channel, .options(inputEncodings: [.hexSix], outputEncodings: [], preferredRole: nil))
        tv(h, channel, .configurationAck)
        return channel
    }

    func testPairingSendsTheSecretOnlyForTheCodeMatchingThisSessionsKeys() throws {
        let h = Harness()
        h.peer = server
        let session = makePairing(h)
        var phases: [RemoteV2PairingPhase] = []
        var rejected: [RemoteV2PairingFailure] = []
        session.onPhase = { phases.append($0) }
        session.onCodeRejected = { rejected.append($0) }

        let channel = try pairToCode(h, session)
        XCTAssertEqual(try payloads(channel), [
            .pairingRequest(serviceName: "atvremote", clientName: "GlassRemote"),
            .options(inputEncodings: [.hexSix], outputEncodings: [], preferredRole: PoloRole.input.rawValue),
            .configuration(encoding: .hexSix, clientRole: PoloRole.input.rawValue),
        ])
        XCTAssertEqual(phases.last, .awaitingCode)

        session.submit(code: "12")
        session.submit(code: "E9ABCD")
        h.flush()
        XCTAssertEqual(rejected, [.malformedCode, .codeMismatch])
        XCTAssertEqual(try channel.frames().count, 3, "Nothing is sent for a rejected code")
        XCTAssertEqual(phases.last, .awaitingCode, "The user can retype while the TV shows the code")

        session.submit(code: "e8abcd")
        h.flush()
        let expected = try RemoteV2PairingCode.secret(code: [0xE8, 0xAB, 0xCD], client: client, server: server)
        XCTAssertEqual(try payloads(channel).last, .secret(expected))
        XCTAssertEqual(phases.last, .awaitingSecretAck)

        tv(h, channel, .secretAck(expected))
        XCTAssertEqual(phases.last, .paired)
        XCTAssertTrue(channel.cancelled)
        XCTAssertTrue(RemoteV2PairingRecord.isPaired(host))
        XCTAssertEqual(RemoteV2PairingRecord.tvKeyFingerprint(for: host), server.fingerprint,
                       "The TV key the code was checked against is pinned")
    }

    func testPairingFailsWhenTheTVRejectsTheSecret() throws {
        let h = Harness()
        h.peer = server
        let session = makePairing(h)
        var phases: [RemoteV2PairingPhase] = []
        session.onPhase = { phases.append($0) }
        let channel = try pairToCode(h, session)
        session.submit(code: "E8ABCD")
        h.flush()
        tv(h, channel, .none, status: PoloStatus.badSecret.rawValue)
        XCTAssertEqual(phases.last, .failed(.deviceStatus(402)))
        XCTAssertTrue(channel.cancelled)
        XCTAssertFalse(RemoteV2PairingRecord.isPaired(host))
    }

    func testPairingIgnoresStaleCallbacksAfterTheConnectionDrops() throws {
        let h = Harness()
        h.peer = server
        let session = makePairing(h)
        var phases: [RemoteV2PairingPhase] = []
        session.onPhase = { phases.append($0) }
        let channel = try pairToCode(h, session)
        let sentBefore = try channel.frames().count
        h.queue.sync { channel.onClose?(.remoteClosed) }
        h.flush()
        XCTAssertEqual(phases.last, .failed(.connectionLost))
        tv(h, channel, .pairingRequestAck(serverName: nil))
        session.submit(code: "E8ABCD")
        h.flush()
        XCTAssertEqual(try channel.frames().count, sentBefore)
        XCTAssertEqual(phases.last, .failed(.connectionLost))
    }

    func testPairingWithoutAnIdentityFailsBeforeConnecting() {
        let h = Harness()
        let session = makePairing(h, credential: false)
        var phases: [RemoteV2PairingPhase] = []
        session.onPhase = { phases.append($0) }
        session.start()
        h.flush()
        XCTAssertTrue(h.channels.isEmpty)
        XCTAssertEqual(phases.last, .failed(.identityUnavailable))
    }

    /// A control connection whose pinned TV key is `server` unless `pinned` says otherwise
    /// (`.some(nil)` = nothing pinned). The fake TV presents `h.peer`, `server` by default.
    private func makeControl(_ h: Harness, pinned: String?? = nil) -> RemoteV2ControlConnection {
        if h.peer == nil { h.peer = server }
        let key = client
        let pin: String? = pinned ?? server.fingerprint
        return RemoteV2ControlConnection(host: host, queue: h.queue, callbackQueue: h.queue,
                                         loadCredential: { FakeCredential(publicKey: key) },
                                         makeChannel: h.factory,
                                         expectedTVKey: { pin })
    }

    /// Drives the TV's handshake (configure, set-active, start) to `.connected`.
    private func connect(_ h: Harness, _ channel: FakeChannel) {
        h.queue.sync { channel.onReady?() }
        h.flush()
        h.deliver(channel, [0x0A, 0x08, 0x08, 0xEE, 0x04, 0x12, 0x03, 0x0A, 0x01, 0x58])
        h.deliver(channel, [0x12, 0x00])
        h.deliver(channel, [0xC2, 0x02, 0x02, 0x08, 0x01])
    }

    func testControlRefusesATVWhoseKeyDiffersFromThePairedKey() throws {
        let h = Harness()
        h.peer = RemoteV2RSAPublicKey(modulus: [0xEE, 0x01], exponent: [0x03]) // an impostor
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        h.queue.sync { channel.onReady?() }
        h.flush()
        XCTAssertEqual(states.last, .identityMismatch)
        XCTAssertTrue(channel.cancelled)
        h.deliver(channel, [0x0A, 0x08, 0x08, 0xEE, 0x04, 0x12, 0x03, 0x0A, 0x01, 0x58])
        control.send(.key(code: 23, direction: .short))
        h.flush()
        XCTAssertTrue(channel.sent.isEmpty, "Nothing is answered or sent to an unverified TV")
        XCTAssertEqual(h.channels.count, 1, "No automatic retry after an identity mismatch")
        XCTAssertEqual(states.last, .identityMismatch)
    }

    func testControlWithoutAPinnedTVKeyIsNotPaired() throws {
        let h = Harness()
        let control = makeControl(h, pinned: .some(nil))
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        h.queue.sync { channel.onReady?() }
        h.flush()
        XCTAssertEqual(states.last, .notPaired)
        XCTAssertTrue(channel.cancelled)
        XCTAssertTrue(channel.sent.isEmpty)
        XCTAssertEqual(h.channels.count, 1)
    }

    func testFramesBeforeTheTVKeyIsVerifiedAreIgnored() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        h.deliver(channel, [0x0A, 0x08, 0x08, 0xEE, 0x04, 0x12, 0x03, 0x0A, 0x01, 0x58])
        h.deliver(channel, [0x12, 0x00])
        h.deliver(channel, [0xC2, 0x02, 0x02, 0x08, 0x01])
        XCTAssertTrue(channel.sent.isEmpty)
        XCTAssertEqual(states.last, .connecting)
    }

    func testControlNeverSendsPowerStandbyWakeOrAppLinksEvenWhenConnected() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        var features: RemoteV2Features = []
        control.onState = { states.append($0); features = $1 }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        connect(h, channel)
        XCTAssertEqual(states.last, .connected)
        XCTAssertTrue(features.contains(.key))
        let count = try channel.frames().count
        for code: Int32 in [26, 223, 224, 24, 25, 164, 91] { control.send(.key(code: code, direction: .short)) }
        control.send(.appLink("https://www.youtube.com"))
        h.flush()
        XCTAssertEqual(try channel.frames().count, count, "Power, standby, wake, volume and app links stay on ADB")
        control.send(.key(code: 85, direction: .short))
        h.flush()
        XCTAssertEqual(try channel.frames().count, count + 1, "Media keys still go over v2")
    }

    func testCoalescedAndFragmentedHandshakeFramesConnectOnce() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        h.queue.sync { channel.onReady?() }
        h.flush()
        let bytes = RemoteV2FrameDecoder.frame([0x0A, 0x08, 0x08, 0xEE, 0x04, 0x12, 0x03, 0x0A, 0x01, 0x58])
            + RemoteV2FrameDecoder.frame([0x12, 0x00]) + RemoteV2FrameDecoder.frame([0xC2, 0x02, 0x02, 0x08, 0x01])
        let split = 7
        h.queue.sync { channel.onReceive?(Array(bytes[..<split])) }
        h.flush()
        XCTAssertNotEqual(states.last, .connected)
        h.queue.sync { channel.onReceive?(Array(bytes[split...])) }
        h.flush()
        XCTAssertEqual(states.filter { $0 == .connected }.count, 1)
        XCTAssertEqual(try channel.frames().count, 2, "One configure and one set-active reply")
    }

    func testOversizedFrameDropsTheLinkAndReconnects() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        h.queue.sync { channel.onReady?() }
        h.flush()
        // Length prefix 1 MiB (> 64 KiB cap), no body.
        h.queue.sync { channel.onReceive?(ProtoVarint.encode(UInt64(1 << 20))) }
        h.flush()
        XCTAssertTrue(channel.cancelled)
        XCTAssertEqual(states.last, .unreachable(retryIn: 1))
        XCTAssertTrue(channel.sent.isEmpty)
    }

    func testControlHandshakeThenKeysOnlyWhileConnectedAndNeverVolume() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        var features: RemoteV2Features = []
        control.onState = { states.append($0); features = $1 }
        control.start()
        h.flush()
        XCTAssertEqual(states.last, .connecting)
        let channel = try XCTUnwrap(h.channels.first)
        h.queue.sync { channel.onReady?() }

        control.send(.key(code: 23, direction: .short))
        h.flush()
        XCTAssertTrue(channel.sent.isEmpty, "No commands before RemoteStart")

        // RemoteConfigure { code1: 622, device_info { model: "X" } }
        h.deliver(channel, [0x0A, 0x08, 0x08, 0xEE, 0x04, 0x12, 0x03, 0x0A, 0x01, 0x58])
        let negotiated = RemoteV2Features.requested.intersection(RemoteV2Features(rawValue: 622))
        XCTAssertEqual(try channel.frames().last, RemoteV2Outbound.configure(features: negotiated, device: .client).encoded())
        h.deliver(channel, [0x12, 0x00]) // RemoteSetActive {}
        XCTAssertEqual(try channel.frames().last, RemoteV2Outbound.setActive(negotiated).encoded())
        XCTAssertNotEqual(states.last, .connected)

        h.deliver(channel, [0xC2, 0x02, 0x02, 0x08, 0x01]) // RemoteStart { started: true }
        XCTAssertEqual(states.last, .connected)
        XCTAssertEqual(features, negotiated)

        control.send(.key(code: 23, direction: .short))
        h.flush()
        XCTAssertEqual(try channel.frames().last, [0x52, 0x04, 0x08, 0x17, 0x10, 0x03])
        let count = try channel.frames().count
        for code: Int32 in [24, 25, 164, 91] { control.send(.key(code: code, direction: .short)) }
        control.send(.pingResponse(val1: 1))
        h.flush()
        XCTAssertEqual(try channel.frames().count, count, "Volume/mute keys and handshake frames are never sent as commands")

        h.deliver(channel, [0x42, 0x02, 0x08, 0x07]) // RemotePingRequest { val1: 7 }
        XCTAssertEqual(try channel.frames().last, RemoteV2Outbound.pingResponse(val1: 7).encoded())

        h.queue.sync { channel.onClose?(.remoteClosed) }
        h.flush()
        XCTAssertEqual(states.last, .unreachable(retryIn: 1))
        XCTAssertEqual(features, [])

        control.stop()
        h.flush()
        XCTAssertEqual(states.last, .off)
    }

    func testRejectedHandshakeMeansNotPairedAndNoRetry() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        h.queue.sync { channel.onClose?(.authenticationRejected) }
        h.flush()
        XCTAssertEqual(states.last, .notPaired)
        XCTAssertEqual(h.channels.count, 1)
    }

    func testStaleChannelCallbacksAfterStopAreIgnored() throws {
        let h = Harness()
        let control = makeControl(h)
        var states: [RemoteV2LinkState] = []
        control.onState = { state, _ in states.append(state) }
        control.start()
        h.flush()
        let channel = try XCTUnwrap(h.channels.first)
        control.stop()
        h.flush()
        XCTAssertTrue(channel.cancelled)
        h.deliver(channel, [0xC2, 0x02, 0x02, 0x08, 0x01])
        h.queue.sync { channel.onClose?(.remoteClosed) }
        h.flush()
        XCTAssertEqual(states.last, .off)
    }
}
