import XCTest
@testable import GlassRemote

/// Phase 9 recovery §3: Samsung pairing. The TV answered `ms.channel.unauthorized` and never showed
/// its Allow prompt because a saved token was always presented, the denial was then overwritten by
/// the deadline, and there was no way to forget the token. These tests pin the corrected decisions.
final class Phase9RecoverySamsungPairingTests: XCTestCase {

    // MARK: In-memory Keychain for the token store

    private final class MemorySecrets {
        var items: [String: String] = [:]
    }

    private func makeStore(_ secrets: MemorySecrets, _ defaults: UserDefaults) -> SamsungTokenStore {
        SamsungTokenStore(readSecret: { secrets.items[$0] },
                          writeSecret: { account, value in secrets.items[account] = value },
                          removeSecret: { secrets.items[$0] = nil },
                          defaults: defaults)
    }

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "Phase9RecoverySamsungPairingTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Token presentation

    func testNoTokenIsPresentedOnFirstPairing() {
        XCTAssertNil(SamsungPairingPolicy.tokenToPresent(storedToken: nil, tokenHost: nil, host: "192.168.1.20"))
        XCTAssertNil(SamsungPairingPolicy.tokenToPresent(storedToken: "", tokenHost: nil, host: "192.168.1.20"))
        XCTAssertNil(SamsungPairingPolicy.tokenToPresent(storedToken: "   ", tokenHost: "192.168.1.20", host: "192.168.1.20"))
    }

    func testSavedTokenGoesOnlyToTheTVThatIssuedIt() {
        XCTAssertEqual(SamsungPairingPolicy.tokenToPresent(storedToken: "11223344", tokenHost: "192.168.1.20", host: "192.168.1.20"), "11223344")
        XCTAssertEqual(SamsungPairingPolicy.tokenToPresent(storedToken: "11223344", tokenHost: "192.168.1.20", host: " 192.168.1.20 "), "11223344")
        XCTAssertNil(SamsungPairingPolicy.tokenToPresent(storedToken: "11223344", tokenHost: "192.168.1.20", host: "192.168.1.21"),
                     "a token from another TV/address must not be sent: the TV refuses it without prompting")
    }

    func testLegacyTokenWithoutRecordedHostIsStillPresented() {
        XCTAssertEqual(SamsungPairingPolicy.tokenToPresent(storedToken: "99", tokenHost: nil, host: "10.0.0.5"), "99")
        XCTAssertEqual(SamsungPairingPolicy.tokenToPresent(storedToken: "99", tokenHost: "", host: "10.0.0.5"), "99")
    }

    // MARK: URL

    func testURLCarriesBase64NameAndTokenOnlyWhenGiven() throws {
        let first = try XCTUnwrap(SamsungPairingPolicy.url(host: "192.168.1.20", token: nil))
        XCTAssertEqual(first.scheme, "wss")
        XCTAssertEqual(first.host, "192.168.1.20")
        XCTAssertEqual(first.port, 8002)
        XCTAssertEqual(first.path, "/api/v2/channels/samsung.remote.control")
        let firstItems = URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(firstItems.first(where: { $0.name == "name" })?.value, "R2xhc3NSZW1vdGU=")
        XCTAssertEqual(Data(base64Encoded: SamsungPairingPolicy.encodedName).flatMap { String(data: $0, encoding: .utf8) }, "GlassRemote")
        XCTAssertNil(firstItems.first(where: { $0.name == "token" }), "first pairing must not send a token item")

        let paired = try XCTUnwrap(SamsungPairingPolicy.url(host: "192.168.1.20", token: "11223344"))
        let pairedItems = URLComponents(url: paired, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(pairedItems.first(where: { $0.name == "token" })?.value, "11223344")
        XCTAssertEqual(pairedItems.first(where: { $0.name == "name" })?.value, "R2xhc3NSZW1vdGU=")

        XCTAssertNil(SamsungPairingPolicy.url(host: "  ", token: nil))
        let emptyToken = try XCTUnwrap(SamsungPairingPolicy.url(host: "192.168.1.20", token: ""))
        XCTAssertFalse(emptyToken.absoluteString.contains("token="))
    }

    // MARK: Channel events

    func testTokenFromConnectAcceptsStringAndNumber() {
        XCTAssertEqual(SamsungPairingPolicy.token(fromConnectData: ["token": "12345678"]), "12345678")
        XCTAssertEqual(SamsungPairingPolicy.token(fromConnectData: ["token": 12345678]), "12345678")
        XCTAssertEqual(SamsungPairingPolicy.token(fromConnectData: ["token": NSNumber(value: 87654321)]), "87654321")
        XCTAssertNil(SamsungPairingPolicy.token(fromConnectData: ["token": ""]))
        XCTAssertNil(SamsungPairingPolicy.token(fromConnectData: ["token": NSNumber(value: true)]))
        XCTAssertNil(SamsungPairingPolicy.token(fromConnectData: ["id": "abc"]))
        XCTAssertNil(SamsungPairingPolicy.token(fromConnectData: nil))
    }

    func testEventParsing() {
        XCTAssertEqual(SamsungPairingPolicy.event(from: #"{"event":"ms.channel.unauthorized"}"#), .unauthorized)
        XCTAssertEqual(SamsungPairingPolicy.event(from: #"{"event":"ms.channel.timeout"}"#), .timeout)
        XCTAssertEqual(SamsungPairingPolicy.event(from: #"{"event":"ms.channel.connect","data":{"token":"42","clients":[]}}"#), .connected(token: "42"))
        XCTAssertEqual(SamsungPairingPolicy.event(from: #"{"event":"ms.channel.connect","data":{"token":42}}"#), .connected(token: "42"))
        XCTAssertEqual(SamsungPairingPolicy.event(from: #"{"event":"ms.channel.connect","data":{}}"#), .connected(token: nil))
        XCTAssertEqual(SamsungPairingPolicy.event(from: #"{"event":"ms.channel.clientConnect"}"#), .other("ms.channel.clientConnect"))
        XCTAssertNil(SamsungPairingPolicy.event(from: "not json"))
        XCTAssertNil(SamsungPairingPolicy.event(from: #"{"data":{}}"#))
    }

    // MARK: Denial vs timeout vs network

    func testUnauthorizedIsClassifiedByWhetherTheSavedTokenWasSent() {
        XCTAssertEqual(SamsungPairingPolicy.denialReason(unauthorizedWithTokenPresented: true), .savedTokenRejected)
        XCTAssertEqual(SamsungPairingPolicy.denialReason(unauthorizedWithTokenPresented: false), .refusedOnTV)
        XCTAssertTrue(SamsungDenialReason.savedTokenRejected.suggestsReset)
        XCTAssertTrue(SamsungDenialReason.refusedOnTV.suggestsReset)
        XCTAssertFalse(SamsungDenialReason.approvalTimedOut.suggestsReset)
    }

    func testDeadlineNeverOverwritesADenial() {
        let afterDenial = SamsungPairingPolicy.stateAfterDeadline(.denied)
        XCTAssertEqual(afterDenial.state, .denied)
        XCTAssertNil(afterDenial.reason, "the reason the TV gave is kept")
        XCTAssertTrue(afterDenial.blocksAutoConnect)

        let unansweredPrompt = SamsungPairingPolicy.stateAfterDeadline(.pairing)
        XCTAssertEqual(unansweredPrompt.state, .denied)
        XCTAssertEqual(unansweredPrompt.reason, .approvalTimedOut)
        XCTAssertTrue(unansweredPrompt.blocksAutoConnect, "an unanswered prompt must not be re-raised every few seconds")

        let silentReconnect = SamsungPairingPolicy.stateAfterDeadline(.connecting)
        XCTAssertEqual(silentReconnect.state, .unreachable)
        XCTAssertNil(silentReconnect.reason)
        XCTAssertFalse(silentReconnect.blocksAutoConnect, "a network problem keeps the supervisor retrying")
    }

    func testSocketCloseAfterDenialIsNotReportedAsRetrying() {
        XCTAssertFalse(SamsungPairingPolicy.reportsDropAsUnreachable(state: .denied, pairingBlocked: true))
        XCTAssertFalse(SamsungPairingPolicy.reportsDropAsUnreachable(state: .denied, pairingBlocked: false))
        XCTAssertFalse(SamsungPairingPolicy.reportsDropAsUnreachable(state: .pairing, pairingBlocked: true))
        XCTAssertTrue(SamsungPairingPolicy.reportsDropAsUnreachable(state: .connected, pairingBlocked: false))
        XCTAssertTrue(SamsungPairingPolicy.reportsDropAsUnreachable(state: .connecting, pairingBlocked: false))
    }

    func testDenialMessagesAreDistinctAndActionable() {
        let texts = SamsungDenialReason.allCases.map(\.statusText)
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertEqual(Set(SamsungDenialReason.allCases.map(\.bannerText)).count, SamsungDenialReason.allCases.count)
        XCTAssertTrue(SamsungDenialReason.savedTokenRejected.statusText.contains("Reset Samsung pairing"))
        XCTAssertTrue(SamsungDenialReason.refusedOnTV.statusText.contains("Device Connection Manager"))
        XCTAssertTrue(SamsungDenialReason.approvalTimedOut.statusText.contains("timed out"))
        for text in texts { XCTAssertFalse(text.localizedCaseInsensitiveContains("ADB"), text) }
    }

    // MARK: Diagnostics without secrets

    func testDiagnosticsNeverContainTheTokenOrAddress() {
        let line = SamsungPairingPolicy.diagnostics(tokenSaved: true, tokenPresented: true, lastAnswer: "ms.channel.unauthorized", attempts: 3)
        XCTAssertTrue(line.contains("saved approval yes"))
        XCTAssertTrue(line.contains("sent with last attempt yes"))
        XCTAssertTrue(line.contains("ms.channel.unauthorized"))
        XCTAssertTrue(line.contains("attempts 3"))
        XCTAssertTrue(SamsungPairingPolicy.diagnostics(tokenSaved: false, tokenPresented: false, lastAnswer: nil, attempts: 0).contains("none yet"))
    }

    @MainActor func testTVDiagnosticsDoNotLeakTheSavedToken() {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let store = makeStore(secrets, defaults)
        store.save(token: "SECRET-778899", host: "192.168.1.20")
        let tv = SamsungTV(tokens: store)
        XCTAssertTrue(tv.hasStoredToken)
        XCTAssertFalse(tv.pairingDiagnostics.contains("SECRET-778899"))
        XCTAssertFalse(tv.pairingDiagnostics.contains("192.168.1.20"))
    }

    // MARK: Token store and the explicit reset

    func testSaveRecordsTheIssuingTV() {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let store = makeStore(secrets, defaults)
        store.save(token: "555", host: " 192.168.1.20 ")
        XCTAssertEqual(store.token(), "555")
        XCTAssertEqual(store.tokenHost, "192.168.1.20")
        XCTAssertNil(defaults.string(forKey: SamsungTokenStore.tokenKey), "the token itself never goes to UserDefaults")
    }

    func testLegacyUserDefaultsTokenMovesToTheKeychain() {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        defaults.set("legacy-1", forKey: SamsungTokenStore.tokenKey)
        let store = makeStore(secrets, defaults)
        XCTAssertEqual(store.token(), "legacy-1")
        XCTAssertEqual(secrets.items[SamsungTokenStore.tokenKey], "legacy-1")
        XCTAssertNil(defaults.string(forKey: SamsungTokenStore.tokenKey))
        store.recordHostIfMissing("10.0.0.7")
        XCTAssertEqual(store.tokenHost, "10.0.0.7")
        store.recordHostIfMissing("10.0.0.8")
        XCTAssertEqual(store.tokenHost, "10.0.0.7", "an existing issuing host is never replaced")
    }

    func testResetRemovesOnlyTheSamsungApproval() {
        let secrets = MemorySecrets()
        secrets.items["nuvio.session"] = "keep-me"
        secrets.items["addon.secret"] = "keep-me-too"
        let defaults = freshDefaults()
        defaults.set("192.168.1.20", forKey: "glassRemote.samsungHost")
        defaults.set("192.168.1.50", forKey: "tvHost")
        defaults.set("samsung", forKey: "glassRemote.target")
        let store = makeStore(secrets, defaults)
        store.save(token: "555", host: "192.168.1.20")
        defaults.set("legacy", forKey: SamsungTokenStore.tokenKey)

        store.reset()

        XCTAssertNil(store.token())
        XCTAssertNil(store.tokenHost)
        XCTAssertNil(secrets.items[SamsungTokenStore.tokenKey])
        XCTAssertNil(defaults.string(forKey: SamsungTokenStore.tokenKey))
        XCTAssertEqual(secrets.items["nuvio.session"], "keep-me")
        XCTAssertEqual(secrets.items["addon.secret"], "keep-me-too")
        XCTAssertEqual(defaults.string(forKey: "glassRemote.samsungHost"), "192.168.1.20", "the TV address is kept")
        XCTAssertEqual(defaults.string(forKey: "tvHost"), "192.168.1.50", "the Android box address is kept")
        XCTAssertEqual(defaults.string(forKey: "glassRemote.target"), "samsung")
    }

    @MainActor func testTVResetClearsTokenBlockAndDenial() {
        let secrets = MemorySecrets()
        let defaults = freshDefaults()
        let store = makeStore(secrets, defaults)
        store.save(token: "555", host: "192.168.1.20")
        let tv = SamsungTV(tokens: store)
        var denials: [SamsungDenialReason?] = []
        tv.onDenial = { denials.append($0) }
        var statuses: [String] = []
        tv.onStatus = { statuses.append($0) }

        tv.resetPairing()

        XCTAssertFalse(tv.hasStoredToken)
        XCTAssertFalse(tv.pairingBlocked)
        XCTAssertNil(tv.denialReason)
        XCTAssertEqual(tv.state, .off)
        XCTAssertFalse(tv.isReady)
        XCTAssertFalse(tv.isAttempting)
        XCTAssertTrue(statuses.last?.contains("pairing reset") ?? false)
        XCTAssertTrue(denials.isEmpty, "no denial was set, so none is reported as cleared")
    }

    func testResetExplanationNamesWhatIsKept() {
        let text = SamsungPairingPolicy.resetExplanation
        XCTAssertTrue(text.contains("only the Samsung TV's approval"))
        XCTAssertTrue(text.contains("ADB key"))
        XCTAssertTrue(text.contains("Allow prompt"))
    }

    // MARK: Source guards (wiring that cannot be exercised without a TV)

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testUnauthorizedStopsTheAttemptAndReconnectIsUserInitiated() throws {
        let tv = try source("GlassRemote/SamsungTV.swift")
        XCTAssertTrue(tv.contains("case .unauthorized:"))
        XCTAssertTrue(tv.contains("deny(reason)"))
        XCTAssertTrue(tv.contains("stop(report: false, keepState: true)"))
        XCTAssertFalse(tv.contains("KeychainStore.set(value, for: tokenKey)"), "token writes go through SamsungTokenStore")
        let features = try source("GlassRemote/RemoteModel+Features.swift")
        XCTAssertTrue(features.contains("tv.connect(host: samsungHost, userInitiated: true)"))
        XCTAssertTrue(features.contains("func resetSamsungPairing()"))
        XCTAssertTrue(features.contains("!tv.pairingBlocked"), "automatic connects still respect a denial")
        let sheet = try source("GlassRemote/ConnectionSheet.swift")
        XCTAssertTrue(sheet.contains("confirmationDialog(\"Reset Samsung pairing?\""), "the reset is confirmed first")
        XCTAssertFalse(sheet.contains("use ADB as before"), "stale ADB volume fallback text is gone")
    }
}
