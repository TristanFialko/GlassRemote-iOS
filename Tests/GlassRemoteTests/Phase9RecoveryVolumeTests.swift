import XCTest
@testable import GlassRemote

/// Phase 9 recovery §5: Samsung soundbar volume. Strict UPnP reply parsing (no partial-data success,
/// SOAP faults detected), the button route (remote socket key, then UPnP step / mute, never Android)
/// and source guards against the old behaviour returning.
final class Phase9RecoveryVolumeTests: XCTestCase {

    private func reply(_ head: String, _ body: String) -> Data { Data((head + "\r\n\r\n" + body).utf8) }

    private let setVolumeOK = "<s:Envelope><s:Body><u:SetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"/></s:Body></s:Envelope>"

    // MARK: Framing

    func testContentLengthReplyIsCompleteOnlyWhenEveryByteArrived() {
        let body = "<CurrentVolume>17</CurrentVolume>"
        let full = reply("HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)", body)
        guard case .complete(let response) = UPnPHTTPResponse.parse(full, connectionClosed: false) else {
            return XCTFail("complete reply not accepted")
        }
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, body)
        XCTAssertEqual(response.headers["content-length"], "\(body.utf8.count)")

        let partial = full.prefix(full.count - 5)
        XCTAssertEqual(UPnPHTTPResponse.parse(Data(partial), connectionClosed: false), .incomplete)
        // Even if the TV then closes, a short body is still incomplete (the caller treats it as failure).
        XCTAssertEqual(UPnPHTTPResponse.parse(Data(partial), connectionClosed: true), .incomplete)
    }

    func testBytesBeyondContentLengthAreIgnored() {
        let data = reply("HTTP/1.1 200 OK\r\ncontent-length: 4", "abcdEXTRA")
        guard case .complete(let response) = UPnPHTTPResponse.parse(data, connectionClosed: false) else { return XCTFail() }
        XCTAssertEqual(response.body, "abcd")
    }

    func testHeaderNamesAreCaseInsensitive() {
        let data = reply("HTTP/1.1 200 OK\r\nCONTENT-LENGTH: 2\r\nX-Thing:  spaced ", "ok")
        guard case .complete(let response) = UPnPHTTPResponse.parse(data, connectionClosed: false) else { return XCTFail() }
        XCTAssertEqual(response.headers["x-thing"], "spaced")
        XCTAssertEqual(response.body, "ok")
    }

    func testChunkedReplyIsDecodedAndNeedsTheTerminatingChunk() {
        let chunks = "5\r\nhello\r\n7;ext=1\r\n, world\r\n0\r\n\r\n"
        let data = reply("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked", chunks)
        guard case .complete(let response) = UPnPHTTPResponse.parse(data, connectionClosed: false) else { return XCTFail() }
        XCTAssertEqual(response.body, "hello, world")

        let cut = reply("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked", "5\r\nhello\r\n7\r\n, wo")
        XCTAssertEqual(UPnPHTTPResponse.parse(cut, connectionClosed: false), .incomplete)
        XCTAssertEqual(UPnPHTTPResponse.parse(cut, connectionClosed: true), .incomplete)
        let noTerminator = reply("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked", "5\r\nhello\r\n")
        XCTAssertEqual(UPnPHTTPResponse.parse(noTerminator, connectionClosed: false), .incomplete)
    }

    func testMalformedChunkSizeIsRejected() {
        let data = reply("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked", "zz\r\nhello\r\n0\r\n\r\n")
        XCTAssertEqual(UPnPHTTPResponse.parse(data, connectionClosed: false), .malformed)
        XCTAssertEqual(UPnPHTTPResponse.decodeChunked(Data("3\r\nabcXY0\r\n\r\n".utf8)), .malformed)
    }

    func testUnframedBodyEndsOnlyWhenTheTVClosesCleanly() {
        let data = reply("HTTP/1.1 200 OK\r\nConnection: close", "<CurrentVolume>3</CurrentVolume>")
        XCTAssertEqual(UPnPHTTPResponse.parse(data, connectionClosed: false), .incomplete)
        guard case .complete(let response) = UPnPHTTPResponse.parse(data, connectionClosed: true) else { return XCTFail() }
        XCTAssertEqual(response.body, "<CurrentVolume>3</CurrentVolume>")
    }

    func testHeadersStillArrivingOrGarbageAreNotAReply() {
        XCTAssertEqual(UPnPHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Le".utf8), connectionClosed: false), .incomplete)
        XCTAssertEqual(UPnPHTTPResponse.parse(Data(), connectionClosed: false), .incomplete)
        XCTAssertEqual(UPnPHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Le".utf8), connectionClosed: true), .malformed)
        XCTAssertEqual(UPnPHTTPResponse.parse(reply("GARBAGE", ""), connectionClosed: true), .malformed)
        XCTAssertEqual(UPnPHTTPResponse.parse(reply("HTTP/1.1 abc OK", ""), connectionClosed: true), .malformed)
        XCTAssertEqual(UPnPHTTPResponse.parse(reply("HTTP/1.1 200 OK\r\nContent-Length: -1", ""), connectionClosed: false), .malformed)
    }

    // MARK: Acceptance (fault / status / action response)

    func testOnlyAComplete200ActionResponseCountsAsSuccess() throws {
        let ok = UPnPHTTPResponse(status: 200, headers: [:], body: setVolumeOK)
        XCTAssertTrue(ok.confirms("SetVolume"))
        XCTAssertNoThrow(try SamsungVolumeLink.check(ok, action: "SetVolume"))

        // An empty 200 (what a cut-short reply used to look like) is not a confirmation.
        let empty = UPnPHTTPResponse(status: 200, headers: [:], body: "")
        XCTAssertThrowsError(try SamsungVolumeLink.check(empty, action: "SetVolume")) { error in
            XCTAssertEqual(error as? SamsungVolumeLink.LinkError, .badReply)
        }
        // The wrong action's response does not confirm this one.
        XCTAssertThrowsError(try SamsungVolumeLink.check(ok, action: "SetMute"))

        let server = UPnPHTTPResponse(status: 503, headers: [:], body: "busy")
        XCTAssertThrowsError(try SamsungVolumeLink.check(server, action: "SetVolume")) { error in
            XCTAssertEqual(error as? SamsungVolumeLink.LinkError, .http(503))
        }
    }

    func testSOAPFaultIsAFailureEvenWithHTTP200() {
        let fault = "<s:Envelope><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>"
            + "<detail><UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>401</errorCode>"
            + "<errorDescription>Invalid Action</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>"
        for status in [200, 500] {
            let response = UPnPHTTPResponse(status: status, headers: [:], body: fault)
            XCTAssertTrue(response.isSOAPFault)
            XCTAssertEqual(response.upnpErrorCode, 401)
            XCTAssertFalse(response.confirms("SetVolume"))
            XCTAssertThrowsError(try SamsungVolumeLink.check(response, action: "SetVolume")) { error in
                XCTAssertEqual(error as? SamsungVolumeLink.LinkError, .fault(401), "status \(status)")
            }
        }
        XCTAssertFalse(UPnPHTTPResponse(status: 200, headers: [:], body: setVolumeOK).isSOAPFault)
    }

    // MARK: Values read back

    func testCurrentVolumeAndMuteAreReadStrictly() {
        XCTAssertEqual(UPnPRenderingControl.currentVolume(in: "<u:GetVolumeResponse><CurrentVolume>23</CurrentVolume></u:GetVolumeResponse>"), 23)
        XCTAssertEqual(UPnPRenderingControl.currentVolume(in: "<CurrentVolume> 0 </CurrentVolume>"), 0)
        XCTAssertEqual(UPnPRenderingControl.currentVolume(in: "<x:CurrentVolume>100</x:CurrentVolume>"), 100)
        XCTAssertNil(UPnPRenderingControl.currentVolume(in: "<CurrentVolume>101</CurrentVolume>"))
        XCTAssertNil(UPnPRenderingControl.currentVolume(in: "<CurrentVolume>-1</CurrentVolume>"))
        XCTAssertNil(UPnPRenderingControl.currentVolume(in: "<CurrentVolume>2"))   // cut short
        XCTAssertNil(UPnPRenderingControl.currentVolume(in: ""))

        XCTAssertEqual(UPnPRenderingControl.currentMute(in: "<CurrentMute>1</CurrentMute>"), true)
        XCTAssertEqual(UPnPRenderingControl.currentMute(in: "<CurrentMute>0</CurrentMute>"), false)
        XCTAssertEqual(UPnPRenderingControl.currentMute(in: "<CurrentMute>true</CurrentMute>"), true)
        XCTAssertEqual(UPnPRenderingControl.currentMute(in: "<CurrentMute>False</CurrentMute>"), false)
        XCTAssertNil(UPnPRenderingControl.currentMute(in: "<CurrentMute>maybe</CurrentMute>"))
    }

    func testRequestDeclaresItsRealLengthAndAction() {
        let data = UPnPRenderingControl.request(host: "192.168.1.20", action: "SetVolume",
                                                arguments: UPnPRenderingControl.setVolumeArguments(140))
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.components(separatedBy: "\r\n\r\n")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].hasPrefix("POST /upnp/control/RenderingControl1 HTTP/1.1"))
        XCTAssertTrue(parts[0].contains("HOST: 192.168.1.20:9197"))
        XCTAssertTrue(parts[0].contains("SOAPACTION: \"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\""))
        XCTAssertTrue(parts[0].contains("CONTENT-LENGTH: \(parts[1].utf8.count)"))
        XCTAssertTrue(parts[1].contains("<DesiredVolume>100</DesiredVolume>"), "levels are clamped to 0...100")
        XCTAssertTrue(UPnPRenderingControl.setVolumeArguments(-4).contains("<DesiredVolume>0</DesiredVolume>"))
        XCTAssertTrue(UPnPRenderingControl.setMuteArguments(true).hasSuffix("<DesiredMute>1</DesiredMute>"))
        XCTAssertTrue(UPnPRenderingControl.setMuteArguments(false).hasSuffix("<DesiredMute>0</DesiredMute>"))
    }

    @MainActor
    func testTheLinkRefusesStepsAndMuteUntilTheTVHasAnswered() {
        let link = SamsungVolumeLink()
        XCTAssertFalse(link.isAvailable)
        XCTAssertNil(link.lastVolume)
        XCTAssertFalse(link.step(by: 1))
        XCTAssertFalse(link.toggleMute())
        link.stop()
        XCTAssertNil(link.isMuted)
    }

    // MARK: Source guards

    private func source(_ file: String) throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: repo.appendingPathComponent(file), encoding: .utf8) else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        return text
    }

    func testPartialRepliesCanNoLongerCountAsSuccess() throws {
        let link = try source("GlassRemote/SamsungVolume.swift")
        XCTAssertFalse(link.contains(".success(box.snapshot)"), "partial data must never be a success")
        XCTAssertTrue(link.contains("UPnPHTTPResponse.parse("))
        XCTAssertTrue(link.contains("Self.check(response, action: action)"))
        XCTAssertFalse(link.contains("WebSocket/ADB key paths"), "stale ADB fallback comment")
    }

    func testVolumeButtonsUseThePolicyAndNeverAndroid() throws {
        let features = try source("GlassRemote/RemoteModel+Features.swift")
        XCTAssertTrue(features.contains("VolumeButtonPolicy.route(for: name"))
        XCTAssertFalse(features.contains("guard tvVolumeEnabled, tv.send(name)"), "socket-only volume buttons returned")
        let dual = try source("GlassRemote/RemoteModel+Dual.swift")
        XCTAssertTrue(dual.contains("if let name = key.legacyVolumeName { return volume(name) }"))
        let panel = try source("GlassRemote/SamsungRemotePanel.swift")
        XCTAssertTrue(panel.contains("remote.volumeButtonsAvailable"))
        for file in ["GlassRemote/UPnPHTTP.swift", "GlassRemote/SamsungVolume.swift"] {
            let text = try source(file)
            for banned in ["sendPersistentCommand", "androidKey(", "input keyevent"] {
                XCTAssertFalse(text.contains(banned), "\(file) contains \(banned)")
            }
        }
    }
}
