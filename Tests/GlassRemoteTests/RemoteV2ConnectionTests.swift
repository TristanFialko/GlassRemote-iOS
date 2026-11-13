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

    private func makeControl(_ h: Harness) -> RemoteV2ControlConnection {
        let key = client
        return RemoteV2ControlConnection(host: host, queue: h.queue, callbackQueue: h.queue,
                                         loadCredential: { FakeCredential(publicKey: key) },
                                         makeChannel: h.factory)
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
