import XCTest
@testable import GlassRemote

final class NuvioAuthParsingTests: XCTestCase {
    func testDeviceLinkStartResponseMatchesTheOfficialRowShape() throws {
        let json = #"[{"device_code":"dev-123","user_code":"abc123","verification_uri_complete":"https://nuvio.tv/link?code=ABC123","poll_interval_seconds":5}]"#
        let link = try NuvioParsers.deviceLink(Data(json.utf8))
        XCTAssertEqual(link.deviceCode, "dev-123")
        XCTAssertEqual(link.pollIntervalSeconds, 5)
        XCTAssertEqual(NuvioParsers.formatUserCode(link.userCode), "ABC-123")
        let defaulted = try NuvioParsers.deviceLink(Data(#"[{"device_code":"d","user_code":"x","verification_uri_complete":"https://nuvio.tv/l"}]"#.utf8))
        XCTAssertEqual(defaulted.pollIntervalSeconds, 3)      // the official default
    }

    func testDeviceLinkRejectsIncompleteOrInsecureRows() {
        XCTAssertThrowsError(try NuvioParsers.deviceLink(Data("[]".utf8)))
        XCTAssertThrowsError(try NuvioParsers.deviceLink(Data(#"[{"device_code":"","user_code":"a","verification_uri_complete":"https://x"}]"#.utf8)))
        XCTAssertThrowsError(try NuvioParsers.deviceLink(Data(#"[{"device_code":"d","user_code":"a","verification_uri_complete":"http://nuvio.tv/link"}]"#.utf8)))
        XCTAssertThrowsError(try NuvioParsers.deviceLink(Data(#"[{"device_code":"d","user_code":"a","verification_uri_complete":"javascript:alert(1)"}]"#.utf8)))
    }

    func testPollStatusIsNormalised() throws {
        XCTAssertEqual(try NuvioParsers.pollStatus(Data(#"[{"status":" Pending "}]"#.utf8)), "pending")
        XCTAssertEqual(try NuvioParsers.pollStatus(Data(#"[{"status":"approved"}]"#.utf8)), "approved")
        XCTAssertThrowsError(try NuvioParsers.pollStatus(Data("[]".utf8)))
    }

    func testExchangeNeedsBothTokensAndAPositiveExpiry() throws {
        let t = try NuvioParsers.tokens(Data(#"{"access_token":"a","refresh_token":"r","token_type":"bearer","expires_in":3600}"#.utf8))
        XCTAssertEqual(t, NuvioTokens(accessToken: "a", refreshToken: "r", expiresIn: 3600))
        XCTAssertThrowsError(try NuvioParsers.tokens(Data(#"{"access_token":"a","refresh_token":"r"}"#.utf8)))
        XCTAssertThrowsError(try NuvioParsers.tokens(Data(#"{"access_token":"a","refresh_token":"r","expires_in":0}"#.utf8)))
        XCTAssertThrowsError(try NuvioParsers.tokens(Data(#"{"access_token":"","refresh_token":"r","expires_in":9}"#.utf8)))
    }

    func testBackendConfigIsReadFromTheFileNotHardCoded() {
        let key = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.abcdefghijk"
        let js = "window.NUVIO_CONFIG = { supabaseUrl: \"https://api.example.test\", supabaseAnonKey: \"\(key)\" };"
        let b = NuvioConfigParser.parse(js)
        XCTAssertEqual(b?.baseURL.absoluteString, "https://api.example.test")
        XCTAssertEqual(b?.anonKey, key)
        XCTAssertNil(NuvioConfigParser.parse("window.x = {}"))                 // no key: no backend
        XCTAssertEqual(NuvioConfigParser.parse("k=\"\(key)\"")?.baseURL, NuvioConfigParser.fallbackURL)
        XCTAssertEqual(NuvioConfigParser.parse("url: \"http://evil.test\", key: \"\(key)\"")?.baseURL, NuvioConfigParser.fallbackURL)   // non-https never used
    }

    func testProfileIdFallsBackToOne() {
        XCTAssertEqual(NuvioParsers.profileID(Data(#"[{"profile_index":3},{"profile_index":2}]"#.utf8)), 2)
        XCTAssertEqual(NuvioParsers.profileID(Data("garbage".utf8)), 1)
        XCTAssertEqual(NuvioParsers.profileID(Data("[]".utf8)), 1)
    }
}

final class NuvioProgressTests: XCTestCase {
    private let json = #"""
    [{"content_id":"tt0903747","content_type":"series","video_id":"tt0903747:2:3","season":2,"episode":3,"position":1200000,"duration":2700000,"last_watched":1790000000000,"progress_key":"k1"},
     {"content_id":"tt0903747","content_type":"series","video_id":"tt0903747:1:1","season":1,"episode":1,"position":2600000,"duration":2700000,"last_watched":1780000000000,"progress_key":"k0"},
     {"content_id":"tt0111161","content_type":"movie","video_id":"tt0111161","position":1900,"duration":2000,"last_watched":1785000000000},
     {"content_id":"kitsu:1","content_type":"series","video_id":"kitsu:1:1","position":10,"duration":20,"last_watched":1795000000000},
     {"content_type":"movie"}]
    """#

    func testRowsDecodeWithTheOfficialFieldNames() throws {
        let entries = try NuvioParsers.progress(Data(json.utf8))
        XCTAssertEqual(entries.count, 4)                                   // the row without content_id is dropped
        let e = try XCTUnwrap(entries.first { $0.progressKey == "k1" })
        XCTAssertEqual(e.season, 2); XCTAssertEqual(e.episode, 3)
        XCTAssertEqual(e.positionMs, 1_200_000); XCTAssertEqual(e.durationMs, 2_700_000)
        XCTAssertThrowsError(try NuvioParsers.progress(Data("nope".utf8)))
    }

    func testLatestEntryPerTitleAndNonImdbIdsAreSkipped() throws {
        let latest = NuvioWatchAggregator.latestPerTitle(try NuvioParsers.progress(Data(json.utf8)))
        XCTAssertEqual(latest.map(\.contentId), ["tt0903747", "tt0111161"])    // newest first; kitsu skipped
        XCTAssertEqual(latest.first?.season, 2)                               // the more recent episode wins
    }

    func testContinueWatchingNeedsProgressBelowTheFinishedThreshold() throws {
        let latest = NuvioWatchAggregator.latestPerTitle(try NuvioParsers.progress(Data(json.utf8)))
        func item(_ e: NuvioProgressEntry, _ kind: MediaTitle.Kind) -> NuvioWatchItem {
            NuvioWatchAggregator.item(e, meta: MediaTitle(id: e.contentId, kind: kind, name: "T", year: "", posterURL: nil, rating: ""))
        }
        let bb = item(latest[0], .series)
        XCTAssertTrue(bb.isContinueWatching)
        XCTAssertEqual(bb.progress, 1_200_000.0 / 2_700_000.0, accuracy: 0.0001)
        XCTAssertEqual(bb.episode?.season, 2); XCTAssertEqual(bb.episode?.episode, 3)
        XCTAssertNotNil(bb.lastWatched)
        let done = item(latest[1], .movie)
        XCTAssertFalse(done.isContinueWatching)                                // 95 %+ is finished
        XCTAssertTrue(done.isCompleted); XCTAssertTrue(done.hasWatchHistory)
    }

    func testContentTypeMapping() {
        func e(_ t: String, season: Int? = nil) -> NuvioProgressEntry {
            NuvioProgressEntry(progressKey: "", contentId: "tt1234567", contentType: t, videoId: "", season: season, episode: nil, positionMs: 0, durationMs: 0, lastWatchedMs: 0)
        }
        XCTAssertEqual(NuvioWatchAggregator.kind(for: e("movie")), .movie)
        XCTAssertEqual(NuvioWatchAggregator.kind(for: e("series")), .series)
        XCTAssertEqual(NuvioWatchAggregator.kind(for: e("other", season: 1)), .series)
        XCTAssertNil(NuvioWatchAggregator.kind(for: e("other")))
    }
}

final class NuvioLinkTests: XCTestCase {
    func testSearchLinkIsEncodedAndBounded() {
        XCTAssertEqual(RemoteModel.nuvioSearchLink(query: "the matrix"), "nuvio://search?q=the%20matrix")
        let nasty = RemoteModel.nuvioSearchLink(query: "a'; rm -rf /; echo '")!
        XCTAssertFalse(nasty.contains("'") || nasty.contains(";") || nasty.contains(" "))
        XCTAssertNil(RemoteModel.nuvioSearchLink(query: "a"))
        XCTAssertNil(RemoteModel.nuvioSearchLink(query: String(repeating: "x", count: 81)))
    }

    func testIntentCommandIsRestrictedToNuvioAndCarriesNoAutoplay() {
        let cmd = RemoteModel.nuvioIntentCommand(link: "nuvio://detail/movie/tt0133093")
        XCTAssertTrue(cmd.contains("-p com.nuvio.app"))
        XCTAssertFalse(cmd.lowercased().contains("autoplay"))
    }

    func testIntentOutcomeNeedsExitZeroAndNoError() {
        XCTAssertTrue(RemoteModel.intentAccepted("Starting: Intent\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted("Error: Activity not started\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted("Permission Denial: not exported\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted(""))
        // BUG-017: the echoed link is never judged; a search for "terror" was misread as a failure.
        XCTAssertTrue(RemoteModel.intentAccepted(
            "Starting: Intent { act=android.intent.action.VIEW dat=nuvio://search?q=terror pkg=com.nuvio.app }\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted(
            "Starting: Intent { act=android.intent.action.VIEW dat=nuvio://search?q=x }\nError type 3\nError: Activity class does not exist.\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted("Starting: Intent { dat=nuvio://search?q=x }\nGLASSREMOTE_INTENT_EXIT:1"))
    }
}

final class PlayerArtworkLandscapeTests: XCTestCase {
    @MainActor
    func testLandscapeHintIsReturnedOnlyForTheMatchingTitle() {
        let store = PlayerArtworkStore.shared
        store.remember(title: "Severance", posterURL: nil, landscapeURL: URL(string: "https://x/bg.jpg"))
        XCTAssertNotNil(store.landscapeURL(forSessionTitle: "Severance"))
        XCTAssertNil(store.landscapeURL(forSessionTitle: "Another Show"))
    }
}
