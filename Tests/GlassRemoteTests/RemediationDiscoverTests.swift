import XCTest
@testable import GlassRemote

// Audit remediation, Priority D (Discover, Nuvio, add-ons): the deterministic rules behind
// BUG-012/013/014/017/018, UX-009/010/017, A11Y-003 and A11Y-005. No network is used.

@MainActor
final class RemediationDiscoverTests: XCTestCase {

    // MARK: BUG-012 episode selection

    private func episode(_ season: Int, _ number: Int) -> CinemetaCatalog.Episode {
        CinemetaCatalog.Episode(id: "tt0903747:\(season):\(number)", season: season, number: number, title: "E\(number)", released: nil)
    }

    func testPickerStartsOnTheRequestedEpisode() {
        let list = [episode(1, 2), episode(1, 1), episode(1, 3), episode(2, 1)]
        XCTAssertEqual(EpisodeSelection.start(in: list, season: 1, requested: 3), 3)
        XCTAssertEqual(EpisodeSelection.start(in: list, season: 2, requested: 1), 1)
    }

    func testPickerFallsBackToTheSeasonsFirstEpisode() {
        let list = [episode(1, 2), episode(1, 1), episode(2, 4), episode(2, 5)]
        XCTAssertEqual(EpisodeSelection.start(in: list, season: 1, requested: nil), 1, "nil keeps the old behaviour")
        XCTAssertEqual(EpisodeSelection.start(in: list, season: 2, requested: 9), 4, "an episode the season lacks is ignored")
        XCTAssertNil(EpisodeSelection.start(in: [], season: 1, requested: 3))
    }

    func testPlayResumesTheWatchedEpisodeOnlyInItsSeason() {
        XCTAssertEqual(EpisodeSelection.resume(season: 2, watching: (season: 2, episode: 7)), 7)
        XCTAssertNil(EpisodeSelection.resume(season: 1, watching: (season: 2, episode: 7)))
        XCTAssertNil(EpisodeSelection.resume(season: 1, watching: nil))
    }

    // MARK: BUG-017 intent outcome

    func testEchoedLinkTextNeverCountsAsAFailure() {
        let echo = "Starting: Intent { act=android.intent.action.VIEW dat=nuvio://search?q=terror pkg=com.nuvio.app }"
        XCTAssertTrue(RemoteModel.intentAccepted("\(echo)\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertTrue(RemoteModel.intentAccepted("Starting: Intent { dat=nuvio://search?q=Exception }\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentReportedFailure(echo))
    }

    func testAmFailureLinesAreRecognised() {
        let echo = "Starting: Intent { act=android.intent.action.VIEW dat=nuvio://detail/movie/tt0133093 }"
        XCTAssertFalse(RemoteModel.intentAccepted("\(echo)\nError: Activity not started, unable to resolve Intent { act=android.intent.action.VIEW }\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted("\(echo)\nException occurred while executing 'start':\njava.lang.SecurityException: Permission Denial\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted("\(echo)\nError type 3\nGLASSREMOTE_INTENT_EXIT:0"))
        XCTAssertFalse(RemoteModel.intentAccepted("\(echo)\nGLASSREMOTE_INTENT_EXIT:255"), "a non-zero exit is still a failure")
    }

    func testFailedHandoffResultIsNotASuccess() {
        let result = HandoffResult.failed("The TV didn't accept the request.")
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "The TV didn't accept the request.")
    }

    // MARK: BUG-018 partial Cinemeta search

    private func title(_ id: String, _ kind: MediaTitle.Kind) -> MediaTitle {
        MediaTitle(id: id, kind: kind, name: id, year: "", posterURL: nil, rating: "")
    }

    func testOneFailedSearchSideKeepsTheOthersResults() throws {
        let movies = [title("tt1", .movie)]
        let series = [title("tt2", .series)]
        let failure: Result<[MediaTitle], Error> = .failure(URLError(.timedOut))
        XCTAssertEqual(try CinemetaCatalog.mergeSearch(movies: .success(movies), series: .success(series)).map(\.id), ["tt1", "tt2"])
        XCTAssertEqual(try CinemetaCatalog.mergeSearch(movies: .success(movies), series: failure).map(\.id), ["tt1"])
        XCTAssertEqual(try CinemetaCatalog.mergeSearch(movies: failure, series: .success(series)).map(\.id), ["tt2"])
    }

    func testSearchFailsOnlyWhenBothSidesFail() {
        let failure: Result<[MediaTitle], Error> = .failure(URLError(.notConnectedToInternet))
        XCTAssertThrowsError(try CinemetaCatalog.mergeSearch(movies: failure, series: failure)) { error in
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    // MARK: UX-010 recent searches

    func testOnlyExplicitActionsSaveARecentSearch() {
        XCTAssertFalse(RecentSearches.remembers(.liveResults), "debounced live results never save")
        XCTAssertTrue(RecentSearches.remembers(.submit))
        XCTAssertTrue(RecentSearches.remembers(.openedResult))
    }

    // MARK: BUG-014 missing add-on links, UX-017 duplicates

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remD-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func record(_ id: UUID, manifestID: String, name: String) -> String {
        let manifest = #"{"id":"\#(manifestID)","version":"1.0.0","name":"\#(name)","types":["movie"],"catalogs":[],"resources":["stream"]}"#
        return #"{"installID":"\#(id.uuidString)","manifest":\#(manifest),"displayURL":"\#(name).example.com","enabled":true,"installedAt":700000001,"refreshedAt":700000001}"#
    }

    func testRestoredAddonWithoutItsKeychainLinkIsFlaggedNotCountedAndKept() throws {
        let dir = try tempDirectory()
        let profile = UUID()
        let linked = UUID()
        let restored = UUID()
        let list = "[" + [record(linked, manifestID: "org.linked", name: "linked"),
                          record(restored, manifestID: "org.restored", name: "restored")].joined(separator: ",") + "]"
        try Data(list.utf8).write(to: dir.appendingPathComponent("addons-\(profile.uuidString).json"))
        let secrets = AddonSecrets.memory()
        secrets.write(AddonStore.account(profile, linked.uuidString), "https://linked.example.com/manifest.json")

        let store = AddonStore(directory: dir, client: AddonClient(session: URLSession(configuration: .ephemeral)), secrets: secrets)
        store.load(profile: profile)
        let ok = try XCTUnwrap(store.addon(linked.uuidString))
        let missing = try XCTUnwrap(store.addon(restored.uuidString))

        XCTAssertFalse(store.linkMissing(ok))
        XCTAssertTrue(store.linkMissing(missing))
        XCTAssertEqual(store.streamAddonCount, 1, "only add-ons that can be asked are counted")
        XCTAssertEqual(store.linkMissingStreamAddonCount, 1)
        XCTAssertEqual(store.streamSources(type: "movie", id: "tt0133093").map(\.addonID), [linked.uuidString])
        XCTAssertEqual(store.addons.count, 2, "nothing is deleted automatically")
    }

    func testDuplicateLinksIgnoreHostCaseButNotPathCase() throws {
        let a = try XCTUnwrap(URL(string: "https://Torrentio.Example.COM/token=AbC/manifest.json"))
        let b = try XCTUnwrap(URL(string: "https://torrentio.example.com/token=AbC/manifest.json"))
        let c = try XCTUnwrap(URL(string: "https://torrentio.example.com/token=abc/manifest.json"))
        XCTAssertTrue(AddonStore.sameLink(a, b))
        XCTAssertFalse(AddonStore.sameLink(b, c), "configured paths carry case-sensitive tokens")
    }

    // MARK: BUG-013 sign-out invalidation, UX-009 refresh rate limit

    func testRefreshFromAnOlderSessionNeverCommits() {
        XCTAssertTrue(NuvioSessionManager.mayCommit(started: 3, current: 3, cancelled: false))
        XCTAssertFalse(NuvioSessionManager.mayCommit(started: 3, current: 4, cancelled: false), "sign-out happened meanwhile")
        XCTAssertFalse(NuvioSessionManager.mayCommit(started: 3, current: 3, cancelled: true))
    }

    func testForegroundRefreshIsRateLimitedAndNeedsASignedInIdleAccount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(NuvioAccount.shouldAutoRefresh(signedIn: true, loading: false, lastRefresh: nil, now: now))
        XCTAssertFalse(NuvioAccount.shouldAutoRefresh(signedIn: true, loading: false, lastRefresh: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(NuvioAccount.shouldAutoRefresh(signedIn: true, loading: false, lastRefresh: now.addingTimeInterval(-61), now: now))
        XCTAssertFalse(NuvioAccount.shouldAutoRefresh(signedIn: false, loading: false, lastRefresh: nil, now: now))
        XCTAssertFalse(NuvioAccount.shouldAutoRefresh(signedIn: true, loading: true, lastRefresh: nil, now: now))
    }

    // MARK: A11Y-003 hero auto-advance, A11Y-005 card labels

    func testHeroStopsRotatingForVoiceOverAndReduceMotion() {
        XCTAssertTrue(HeroAutoAdvancePolicy.allowed(reduceMotion: false, voiceOver: false, active: true))
        XCTAssertFalse(HeroAutoAdvancePolicy.allowed(reduceMotion: false, voiceOver: true, active: true))
        XCTAssertFalse(HeroAutoAdvancePolicy.allowed(reduceMotion: true, voiceOver: false, active: true))
        XCTAssertFalse(HeroAutoAdvancePolicy.allowed(reduceMotion: false, voiceOver: false, active: false))
    }

    func testCardLabelsIncludeTheProgressCaption() {
        XCTAssertEqual(DiscoverMetaLine.cardLabel(name: "Breaking Bad", year: "2008", caption: "S1 · E3 · 20 min left"),
                       "Breaking Bad, S1, E3, 20 min left")
        XCTAssertEqual(DiscoverMetaLine.cardLabel(name: "Dune", year: "2021", caption: nil), "Dune, 2021")
        XCTAssertEqual(DiscoverMetaLine.cardLabel(name: "Dune", year: "", caption: ""), "Dune")
    }
}
