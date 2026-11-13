import XCTest
@testable import GlassRemote

/// Android TV Remote Service v2: the pure protocol layer (wire codec, framing, pairing, control
/// session) and the routing rules that keep volume, text, mouse and helpers off Remote v2.
final class RemoteV2ProtocolTests: XCTestCase {
    private func hex(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            out.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    // MARK: Wire codec

    func testVarintRoundTrip() throws {
        XCTAssertEqual(ProtoVarint.encode(0), [0x00])
        XCTAssertEqual(ProtoVarint.encode(300), [0xAC, 0x02])
        for value: UInt64 in [0, 1, 127, 128, 300, 16_383, 16_384, UInt64(UInt32.max), UInt64.max] {
            let decoded = try XCTUnwrap(try ProtoVarint.decode(ProtoVarint.encode(value), from: 0))
            XCTAssertEqual(decoded.value, value)
        }
        // An unfinished varint is "need more bytes", not an error.
        XCTAssertNil(try ProtoVarint.decode([0x80], from: 0))
        XCTAssertThrowsError(try ProtoVarint.decode([UInt8](repeating: 0xFF, count: 11), from: 0))
    }

    func testNegativeInt32IsSignExtendedToTenBytes() throws {
        var w = ProtoWriter()
        w.int32(1, -1)
        XCTAssertEqual(w.bytes.count, 11)
        XCTAssertEqual(try ProtoMessage(w.bytes).int32(1), -1)
    }

    func testMessageRejectsWrongWireTypeAndTruncation() {
        // Field 1 as a varint, read as a string.
        XCTAssertThrowsError(try ProtoMessage([0x08, 0x01]).string(1)) { error in
            XCTAssertEqual(error as? ProtoWireError, .unexpectedWireType(field: 1))
        }
        // Length-delimited field declaring 5 bytes with only 1 present.
        XCTAssertThrowsError(try ProtoMessage([0x0A, 0x05, 0x01])) { error in
            XCTAssertEqual(error as? ProtoWireError, .truncated)
        }
        // Field number 0 is invalid.
        XCTAssertThrowsError(try ProtoMessage([0x00, 0x01]))
    }

    // MARK: Framing

    func testFrameDecoderHandlesArbitrarySplits() throws {
        let body = (0..<200).map { UInt8($0 & 0xFF) }
        let framed = RemoteV2FrameDecoder.frame(body)
        XCTAssertEqual(Array(framed.prefix(2)), [0xC8, 0x01])
        var decoder = RemoteV2FrameDecoder()
        XCTAssertEqual(try decoder.append([framed[0]]), [])
        XCTAssertEqual(try decoder.append(Array(framed[1..<100])), [])
        XCTAssertEqual(try decoder.append(Array(framed[100...])), [body])
        XCTAssertEqual(decoder.bufferedByteCount, 0)

        // Two frames and part of a third in one read.
        let a = RemoteV2FrameDecoder.frame([1, 2, 3])
        let b = RemoteV2FrameDecoder.frame([4])
        let c = RemoteV2FrameDecoder.frame([5, 6])
        XCTAssertEqual(try decoder.append(a + b + [c[0]]), [[1, 2, 3], [4]])
        XCTAssertEqual(try decoder.append(Array(c[1...])), [[5, 6]])
    }

    func testFrameDecoderRejectsOversizedFrames() {
        var decoder = RemoteV2FrameDecoder(maxFrameLength: 4)
        XCTAssertThrowsError(try decoder.append([0x05, 1, 2, 3, 4, 5])) { error in
            XCTAssertEqual(error as? ProtoWireError, .frameTooLarge(5))
        }
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    // MARK: Pairing (polo)

    func testPairingRequestBytesMatchReferenceSerialisation() throws {
        let message = PoloMessage(payload: .pairingRequest(serviceName: "atvremote", clientName: "GlassRemote"))
        let expected: [UInt8] = [0x08, 0x02, 0x10, 0xC8, 0x01, 0x52, 0x18, 0x0A, 0x09] + Array("atvremote".utf8)
            + [0x12, 0x0B] + Array("GlassRemote".utf8)
        XCTAssertEqual(message.encoded(), expected)
        XCTAssertEqual(try PoloMessage.decode(expected), message)
    }

    func testPoloRoundTripForEveryPayload() throws {
        let payloads: [PoloPayload] = [
            .pairingRequestAck(serverName: "TV"),
            .options(inputEncodings: [.hexSix], outputEncodings: [], preferredRole: PoloRole.input.rawValue),
            .configuration(encoding: .hexSix, clientRole: PoloRole.input.rawValue),
            .configurationAck,
            .secret([1, 2, 3]),
            .secretAck([4, 5]),
        ]
        for payload in payloads {
            let message = PoloMessage(payload: payload)
            XCTAssertEqual(try PoloMessage.decode(message.encoded()), message)
        }
    }

    func testPairingMachineHappyPath() {
        var machine = RemoteV2PairingMachine()
        let request = machine.start(clientName: "GlassRemote")
        XCTAssertEqual(request.payload, .pairingRequest(serviceName: "atvremote", clientName: "GlassRemote"))
        XCTAssertNil(machine.submit(secret: [1]), "No secret before the TV shows a code")

        let options = machine.receive(PoloMessage(payload: .pairingRequestAck(serverName: nil)))
        XCTAssertEqual(options?.payload, .options(inputEncodings: [.hexSix], outputEncodings: [],
                                                  preferredRole: PoloRole.input.rawValue))
        let configuration = machine.receive(PoloMessage(payload: .options(inputEncodings: [.hexSix],
                                                                          outputEncodings: [], preferredRole: nil)))
        XCTAssertEqual(configuration?.payload, .configuration(encoding: .hexSix, clientRole: PoloRole.input.rawValue))
        XCTAssertNil(machine.receive(PoloMessage(payload: .configurationAck)))
        XCTAssertEqual(machine.phase, .awaitingCode)

        XCTAssertEqual(machine.submit(secret: [9, 9])?.payload, .secret([9, 9]))
        XCTAssertNil(machine.submit(secret: [9, 9]), "The secret is sent once")
        XCTAssertNil(machine.receive(PoloMessage(payload: .secretAck([9, 9]))))
        XCTAssertEqual(machine.phase, .paired)
    }

    func testPairingMachineFailsOnErrorStatusAndOutOfOrderMessages() {
        var rejected = RemoteV2PairingMachine()
        _ = rejected.start(clientName: "x")
        XCTAssertNil(rejected.receive(PoloMessage(status: PoloStatus.badSecret.rawValue, payload: .none)))
        XCTAssertEqual(rejected.phase, .failed(.deviceStatus(402)))
        XCTAssertEqual(RemoteV2PairingFailure.deviceStatus(402).message, "The TV rejected the code. Start pairing again.")

        var outOfOrder = RemoteV2PairingMachine()
        _ = outOfOrder.start(clientName: "x")
        XCTAssertNil(outOfOrder.receive(PoloMessage(payload: .configurationAck)))
        XCTAssertEqual(outOfOrder.phase, .failed(.unexpectedMessage))
        // Once failed, further messages are ignored.
        XCTAssertNil(outOfOrder.receive(PoloMessage(payload: .pairingRequestAck(serverName: nil))))
    }

    // MARK: Pairing code and secret

    func testPairingCodeParsing() {
        XCTAssertEqual(RemoteV2PairingCode.parse(" e8abCD "), [0xE8, 0xAB, 0xCD])
        XCTAssertNil(RemoteV2PairingCode.parse("12345"))
        XCTAssertNil(RemoteV2PairingCode.parse("1234567"))
        XCTAssertNil(RemoteV2PairingCode.parse("12345G"))
    }

    /// Fixture computed independently (Python hashlib) from the androidtvremote2 algorithm:
    /// SHA-256(minimal client n, client e, server n, server e, code nonce).
    func testSecretMatchesIndependentFixtureAndChecksTheCheckByte() throws {
        let client = RemoteV2RSAPublicKey(modulus: [0x00, 0xC1, 0x02], exponent: [0x01, 0x00, 0x01])
        let server = RemoteV2RSAPublicKey(modulus: [0xD3, 0x04, 0x05], exponent: [0x03])
        let expected = hex("e8931a15e66b0863b9315eb2bfea24326fc179d2b8143eec6e90b40bd48e9cda")
        XCTAssertEqual(try RemoteV2PairingCode.secret(code: [0xE8, 0xAB, 0xCD], client: client, server: server), expected)
        XCTAssertThrowsError(try RemoteV2PairingCode.secret(code: [0xE9, 0xAB, 0xCD], client: client, server: server)) { error in
            XCTAssertEqual(error as? RemoteV2PairingFailure, .codeMismatch)
        }
        XCTAssertThrowsError(try RemoteV2PairingCode.secret(code: [0xE8], client: client, server: server)) { error in
            XCTAssertEqual(error as? RemoteV2PairingFailure, .malformedCode)
        }
    }

    func testPKCS1PublicKeyParsing() throws {
        let der: [UInt8] = [0x30, 0x0A, 0x02, 0x03, 0x00, 0xC1, 0x02, 0x02, 0x03, 0x01, 0x00, 0x01]
        let key = try RemoteV2RSAPublicKey(pkcs1: der)
        XCTAssertEqual(key.modulus, [0xC1, 0x02])
        XCTAssertEqual(key.exponent, [0x01, 0x00, 0x01])
        XCTAssertThrowsError(try RemoteV2RSAPublicKey(pkcs1: Array(der.dropLast())))
    }

    // MARK: Control session

    func testOutboundEncodings() {
        XCTAssertEqual(RemoteV2Outbound.key(code: 23, direction: .short).encoded(), [0x52, 0x04, 0x08, 0x17, 0x10, 0x03])
        XCTAssertEqual(RemoteV2Outbound.pingResponse(val1: 5).encoded(), [0x4A, 0x02, 0x08, 0x05])
        XCTAssertEqual(RemoteV2Outbound.appLink("x").logDescription, "app_link")
    }

    func testSessionHandshake() throws {
        var session = RemoteV2Session()
        // RemoteConfigure { code1: 622, device_info { model: "X" } }
        let configure = try RemoteV2Inbound.decode([0x0A, 0x08, 0x08, 0xEE, 0x04, 0x12, 0x03, 0x0A, 0x01, 0x58])
        guard case let .configure(features, device) = configure else { return XCTFail("expected configure") }
        XCTAssertEqual(features.rawValue, 622)
        XCTAssertEqual(device.model, "X")

        let reply = session.handle(configure)
        let negotiated = RemoteV2Features.requested.intersection(RemoteV2Features(rawValue: 622))
        XCTAssertEqual(reply, .configure(features: negotiated, device: .client))
        XCTAssertFalse(negotiated.contains(.ime), "Text never moves to v2 implicitly")
        XCTAssertFalse(session.supports(.key), "Nothing is usable before RemoteStart")

        XCTAssertEqual(session.handle(.setActive), .setActive(negotiated))
        XCTAssertEqual(session.handle(try RemoteV2Inbound.decode([0x42, 0x02, 0x08, 0x07])), .pingResponse(val1: 7))
        XCTAssertNil(session.handle(try RemoteV2Inbound.decode([0xC2, 0x02, 0x02, 0x08, 0x01])))
        XCTAssertTrue(session.supports(.key))
        XCTAssertEqual(session.isOn, true)
    }

    // MARK: Routing and volume safety

    private let v2Full = RemoteTransportAvailability(v2Ready: true, v2Features: .requested, adbReady: true, preferV2: true)

    func testAdbOnlyOperationsNeverRouteToV2() {
        let adbOnly: [RemoteOperation] = [.text, .mouse, .scroll, .appDiscovery, .diagnostics, .helpers, .soundbarVolume]
        for operation in adbOnly {
            XCTAssertEqual(RemoteTransportPolicy.route(operation, v2Full), .adb, "\(operation)")
            XCTAssertNil(RemoteTransportPolicy.route(operation, RemoteTransportAvailability(
                v2Ready: true, v2Features: .requested, adbReady: false, preferV2: true)), "\(operation)")
        }
    }

    func testStandardKeysPreferV2AndFallBackOnlyBeforeTheCommandStarts() {
        XCTAssertEqual(RemoteTransportPolicy.route(.dpad, v2Full), .remoteV2)
        XCTAssertEqual(RemoteTransportPolicy.route(.dpad, .adbOnly), .adb)
        var off = v2Full
        off.preferV2 = false
        XCTAssertEqual(RemoteTransportPolicy.route(.media, off), .adb)
        var noAppLink = v2Full
        noAppLink.v2Features = [.key]
        XCTAssertEqual(RemoteTransportPolicy.route(.appLaunch, noAppLink), .adb)
        XCTAssertEqual(RemoteTransportPolicy.route(.select, noAppLink), .remoteV2)
        XCTAssertNil(RemoteTransportPolicy.route(.dpad, RemoteTransportAvailability(
            v2Ready: false, v2Features: [], adbReady: false, preferV2: true)))
    }

    func testVolumeAndMuteAreNeverRemoteV2Keys() {
        for key in ["VOLUME_UP", "VOLUME_DOWN", "MUTE", "VOLUME_MUTE"] {
            XCTAssertNil(RemoteV2KeyMap.code(for: key), key)
            XCTAssertNil(RemoteV2KeyMap.operation(for: key), key)
        }
        for (key, code) in RemoteV2KeyMap.codes {
            XCTAssertFalse(RemoteV2KeyMap.forbidden.contains(code), key)
            XCTAssertNotNil(RemoteV2KeyMap.operation(for: key), key)
        }
        XCTAssertEqual(RemoteV2KeyMap.code(for: "OK"), 23, "OK is DPAD_CENTER, never ENTER")
    }

    func testHeldKeysStayOnTheirTransportAndNeverSwitchMidGesture() {
        var ledger = GestureTransportLedger()
        XCTAssertEqual(ledger.begin("UP", operation: .dpad, links: v2Full), .remoteV2)
        XCTAssertEqual(ledger.repeatTick("UP", links: v2Full), .remoteV2)
        var v2Down = v2Full
        v2Down.v2Ready = false
        // The owner went down: the gesture stops, it does not continue over ADB.
        XCTAssertNil(ledger.repeatTick("UP", links: v2Down))
        XCTAssertFalse(ledger.hasHeldKeys)
        // A fresh press may start on ADB.
        XCTAssertEqual(ledger.begin("UP", operation: .dpad, links: v2Down), .adb)
        XCTAssertEqual(ledger.begin("UP", operation: .dpad, links: v2Full), .adb, "Owner is fixed for the gesture")
        XCTAssertEqual(ledger.end("UP"), .adb)
        XCTAssertNil(ledger.end("UP"))

        XCTAssertEqual(ledger.begin("LEFT", operation: .dpad, links: v2Full), .remoteV2)
        XCTAssertEqual(ledger.begin("OK", operation: .select, links: .adbOnly), .adb)
        XCTAssertEqual(ledger.transportLost(.remoteV2), ["LEFT"])
        XCTAssertEqual(ledger.heldKeys, ["OK"])
    }

    func testBackoffAndStatusText() {
        XCTAssertEqual(RemoteV2Backoff.delay(afterFailures: 0), 0)
        XCTAssertEqual(RemoteV2Backoff.delay(afterFailures: 1), 1)
        XCTAssertEqual(RemoteV2Backoff.delay(afterFailures: 5), 16)
        XCTAssertEqual(RemoteV2Backoff.delay(afterFailures: 6), 30)
        XCTAssertEqual(RemoteV2Backoff.delay(afterFailures: 1_000), 30)
        XCTAssertEqual(RemoteV2StatusText.summary(v2: .connected, adbReady: true),
                       "Remote v2 connected · Input via ADB available")
    }
}
