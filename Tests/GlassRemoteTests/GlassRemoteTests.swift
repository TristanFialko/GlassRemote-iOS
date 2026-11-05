import XCTest
@testable import GlassRemote

final class TextEntryTests: XCTestCase {
    func testSpacesBecomePercentS() {
        XCTAssertEqual(RemoteModel.escapeInputText("hello world"), "hello%sworld")
    }

    func testChunksNeverContainLiteralPercentS() {
        // Android's `input text` would turn a literal "%s" into a space, so it must be split apart.
        let chunks = RemoteModel.textChunks("100%send", maxLength: 160)
        XCTAssertEqual(chunks.joined(), "100%send")
        XCTAssertFalse(chunks.contains { $0.contains("%s") })
    }

    func testChunksRespectMaxLength() {
        let text = String(repeating: "a", count: 350)
        let chunks = RemoteModel.textChunks(text, maxLength: 160)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 160 })
    }
}

final class LiveTypingMappingTests: XCTestCase {
    func testLettersAndDigits() {
        XCTAssertEqual(VirtualKeyboard.hid(for: "a")?.usage, 0x04)
        XCTAssertEqual(VirtualKeyboard.hid(for: "z")?.usage, 0x1D)
        XCTAssertEqual(VirtualKeyboard.hid(for: "1")?.usage, 0x1E)
        XCTAssertEqual(VirtualKeyboard.hid(for: "0")?.usage, 0x27)
        XCTAssertEqual(VirtualKeyboard.hid(for: " ")?.usage, 0x2C)
    }

    func testShiftedCharacters() {
        let capital = VirtualKeyboard.hid(for: "A")
        XCTAssertEqual(capital?.usage, 0x04)
        XCTAssertEqual(capital?.shift, true)
        XCTAssertEqual(VirtualKeyboard.hid(for: "!")?.usage, 0x1E)
        XCTAssertEqual(VirtualKeyboard.hid(for: "!")?.shift, true)
        XCTAssertEqual(VirtualKeyboard.hid(for: "?")?.shift, true)
        XCTAssertEqual(VirtualKeyboard.hid(for: "/")?.shift, false)
    }

    func testNonASCIIIsSkipped() {
        XCTAssertNil(VirtualKeyboard.hid(for: "é"))
        XCTAssertEqual(VirtualKeyboard.lines(forTyping: "aéb"), ["K 4\n", "K 5\n"])
    }

    func testProtocolLines() {
        XCTAssertEqual(VirtualKeyboard.lines(forTyping: "Hi"), ["S 11\n", "K 12\n"])
    }
}

final class MediaParsingTests: XCTestCase {
    func testNoSessionReturnsNil() {
        XCTAssertNil(MediaParser.parse(""))
        XCTAssertNil(MediaParser.parse("12345.67 8901.2\nSessions Stack - have 0 sessions:"))
    }

    func testPlayingSessionIsParsed() {
        let sample = """
        12345.67 8901.2
          Sessions Stack - have 1 sessions:
            Stremio com.stremio.one/Session (userId=0)
              ownerPid=1234, ownerUid=10050, userId=0
              package=com.stremio.one
              active=true
              state=PlaybackState {state=3, position=60000, buffered position=0, speed=1.0, updated=12345000, actions=567}
              metadata: size=3, description=Some Title, null, null
        """
        let state = MediaParser.parse(sample)
        XCTAssertEqual(state?.package, "com.stremio.one")
        XCTAssertEqual(state?.title, "Some Title")
        XCTAssertEqual(state?.isPlaying, true)
        XCTAssertEqual(state?.positionMs, 60670)   // 60000 + 670 ms played since the state was reported
    }

    func testTimeFormatting() {
        XCTAssertEqual(MediaState.format(65), "1:05")
        XCTAssertEqual(MediaState.format(3725), "1:02:05")
    }
}

final class QuickActionTests: XCTestCase {
    func testRoundTripThroughJSON() throws {
        let action = QuickAction(name: "Movie Night", steps: [.key("HOME"), .delay(1.5), .launch("com.stremio.one"), .volume("VOLUME_UP", count: 3)])
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(QuickAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testPowerKeysAreNeverAllowed() {
        XCTAssertFalse(QuickActionStore.allowedKeys.contains("TV_POWER"))
        XCTAssertFalse(QuickActionStore.allowedKeys.contains("POWER"))
    }

    func testEveryAllowedKeyHasATitle() {
        for key in QuickActionStore.allowedKeys {
            XCTAssertNotNil(QuickActionStore.keyTitles[key], "\(key) has no title")
        }
    }
}


@MainActor
final class LiveTypingToggleTests: XCTestCase {
    /// Regression: a keystroke the virtual keyboard cannot accept (disconnected / helper not ready)
    /// must never switch the Live typing toggle off.
    func testFailedKeystrokeDoesNotResetToggle() {
        let remote = RemoteModel()
        remote.liveTyping = true
        XCTAssertFalse(remote.typeLive("a"))          // not connected: keyboard refuses
        XCTAssertTrue(remote.liveTyping)
        XCTAssertFalse(remote.typeLive("B", backspaces: 1))
        XCTAssertTrue(remote.liveTyping)
        remote.liveTyping = false                     // restore the persisted default
    }

    func testDiffPlanAppendCapitalSymbolAndDelete() {
        XCTAssertEqual(LiveTypingDiff.plan(from: "", to: "a").added, "a")
        XCTAssertEqual(LiveTypingDiff.plan(from: "a", to: "aB!").added, "B!")
        let del = LiveTypingDiff.plan(from: "abc", to: "ab")
        XCTAssertEqual(del.backspaces, 1)
        XCTAssertEqual(del.added, "")
    }

    func testRetryAfterFailureSendsWholeUndeliveredText() {
        // lastSent stays "" after a failed send, so the next edit carries everything.
        XCTAssertEqual(LiveTypingDiff.plan(from: "", to: "ab").added, "ab")
    }
}

// MARK: - v0.3 Phase 1

final class PagerMathTests: XCTestCase {
    func testLandingPageIsRemoteAndOrderIsStable() {
        XCTAssertEqual(AppPage.landing, .remote)
        XCTAssertEqual(AppPage.allCases, [.remote, .player, .discover, .apps])
    }

    func testTargetPageThresholdsAndClamping() {
        XCTAssertEqual(AppPage.target(from: .remote, translation: -200, predicted: -250, width: 390), .player)
        XCTAssertEqual(AppPage.target(from: .remote, translation: -40, predicted: -60, width: 390), .remote)   // too small
        XCTAssertEqual(AppPage.target(from: .remote, translation: -30, predicted: -300, width: 390), .player)  // flick
        XCTAssertEqual(AppPage.target(from: .remote, translation: 300, predicted: 400, width: 390), .remote)   // clamped at start
        XCTAssertEqual(AppPage.target(from: .apps, translation: -300, predicted: -400, width: 390), .apps)     // clamped at end
        XCTAssertEqual(AppPage.target(from: .discover, translation: 200, predicted: 260, width: 390), .player)
    }

    func testEdgeResistance() {
        XCTAssertEqual(AppPage.resisted(100, on: .remote), 25)
        XCTAssertEqual(AppPage.resisted(-100, on: .apps), -25)
        XCTAssertEqual(AppPage.resisted(100, on: .player), 100)
    }
}

final class StremioCatalogTests: XCTestCase {
    func testSearchURLEncodesQuery() {
        let url = StremioCatalog.searchURL(kind: .movie, query: "The Matrix: Reloaded/x")
        XCTAssertEqual(url?.absoluteString, "https://v3-cinemeta.strem.io/catalog/movie/top/search=The%20Matrix%3A%20Reloaded%2Fx.json")
        XCTAssertNil(StremioCatalog.searchURL(kind: .series, query: "   "))
    }

    func testParseToleratesMissingFields() {
        let json = #"{"metas":[{"id":"tt0133093","name":"The Matrix","poster":"https://example.com/p.jpg","releaseInfo":"1999","imdbRating":"8.7"},{"name":"No id"},{"id":"tt1","poster":"http://insecure/x.jpg","name":"Insecure poster"}]}"#
        let items = StremioCatalog.parse(Data(json.utf8), kind: .movie)
        XCTAssertEqual(items.map(\.name), ["The Matrix", "Insecure poster"])
        XCTAssertNotNil(items[0].posterURL)
        XCTAssertNil(items[1].posterURL)            // non-https artwork is dropped
        XCTAssertTrue(StremioCatalog.parse(Data("garbage".utf8), kind: .series).isEmpty)
    }

    func testDeepLinkValidationRejectsUnsafeIds() {
        XCTAssertEqual(RemoteModel.stremioDetailLink(kind: .movie, id: "tt0133093"), "stremio:///detail/movie/tt0133093/tt0133093")
        XCTAssertEqual(RemoteModel.stremioDetailLink(kind: .series, id: "tt0903747"), "stremio:///detail/series/tt0903747")
        XCTAssertNil(RemoteModel.stremioDetailLink(kind: .movie, id: "tt0133093'; reboot; '"))
        XCTAssertNil(RemoteModel.stremioDetailLink(kind: .series, id: "kitsu:1"))
    }
}

final class MediaSubtitleTests: XCTestCase {
    func testDescriptionSplit() {
        XCTAssertEqual(MediaParser.splitDescription("Show, S1E2 Pilot, null").headline, "Show")
        XCTAssertEqual(MediaParser.splitDescription("Show, S1E2 Pilot, null").subtitle, "S1E2 Pilot")
        XCTAssertEqual(MediaParser.splitDescription("Movie, null, null").subtitle, "")
        XCTAssertEqual(MediaParser.splitDescription("Just a title").headline, "Just a title")
        XCTAssertEqual(MediaParser.splitDescription("Hello, World, Ep 3, null").headline, "Hello, World")
    }

    func testDurationIsNeverInvented() {
        XCTAssertNil(MediaState.idle.durationMs)
    }
}

final class FavouritesAndArtworkTests: XCTestCase {
    func testFavouriteToggleKeepsOrder() {
        XCTAssertEqual(AppFavourites.toggled(["a"], "b"), ["a", "b"])
        XCTAssertEqual(AppFavourites.toggled(["a", "b"], "a"), ["b"])
    }

    func testPosterOnlyForMatchingTitle() {
        XCTAssertTrue(PlayerArtworkStore.matches(session: "The Matrix", hint: "the matrix"))
        XCTAssertFalse(PlayerArtworkStore.matches(session: "Something Else", hint: "The Matrix"))
        XCTAssertFalse(PlayerArtworkStore.matches(session: "", hint: "The Matrix"))
    }
}

// MARK: - v0.4

final class RemoteRoutingTests: XCTestCase {
    func testExplicitTargetsNeverCrossOver() {
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .android, androidConnected: true, samsungReady: true), .android)
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .samsung, androidConnected: true, samsungReady: true), .samsung)
        XCTAssertNil(RemoteRouting.device(for: .navigation, target: .samsung, androidConnected: true, samsungReady: false))
        XCTAssertNil(RemoteRouting.device(for: .navigation, target: .android, androidConnected: false, samsungReady: true))
    }

    func testAutoPrefersBoxForNavigationAndTVForTVOnlyCapabilities() {
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .auto, androidConnected: true, samsungReady: true), .android)
        XCTAssertEqual(RemoteRouting.device(for: .media, target: .auto, androidConnected: true, samsungReady: true), .android)
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .auto, androidConnected: false, samsungReady: true), .samsung)
        XCTAssertEqual(RemoteRouting.device(for: .source, target: .auto, androidConnected: true, samsungReady: true), .samsung)
        XCTAssertNil(RemoteRouting.device(for: .channel, target: .auto, androidConnected: true, samsungReady: false))
    }

    func testVolumeKeepsExistingPreference() {
        XCTAssertEqual(RemoteRouting.device(for: .volume, target: .auto, androidConnected: true, samsungReady: true), .samsung)
        XCTAssertEqual(RemoteRouting.device(for: .volume, target: .auto, androidConnected: true, samsungReady: false), .android)
    }
}

final class SamsungKeyTests: XCTestCase {
    func testAllowlistContainsOnlyKeyNames() {
        XCTAssertTrue(SamsungKey.allCases.allSatisfy { $0.rawValue.hasPrefix("KEY_") })
        XCTAssertTrue(SamsungKey.allowlist.contains("KEY_VOLUP"))
        XCTAssertFalse(SamsungKey.allowlist.contains("KEY_ANYTHING_ELSE"))
    }

    func testAppKeyMapping() {
        XCTAssertEqual(SamsungKey.forAppKey("OK"), .enter)
        XCTAssertEqual(SamsungKey.forAppKey("BACK"), .back)
        XCTAssertEqual(SamsungKey.forAppKey("TV_SOURCE"), .source)
        XCTAssertNil(SamsungKey.forAppKey("NOT_A_KEY"))
    }
}

final class VolumeCalibrationTests: XCTestCase {
    func testDefaultRangeReachesExactEndsAndMiddle() {
        let c = VolumeCalibration.standard
        XCTAssertEqual(c.raw(forFraction: 0), 0)
        XCTAssertEqual(c.raw(forFraction: 1), 100)
        XCTAssertEqual(c.raw(forFraction: 0.5), 50)
        XCTAssertEqual(c.fraction(forRaw: 0), 0)
        XCTAssertEqual(c.fraction(forRaw: 100), 1)
        XCTAssertEqual(c.fraction(forRaw: 37), 0.37, accuracy: 0.0001)
    }

    func testNarrowedRangeStillMapsToFullSlider() {
        let c = VolumeCalibration(lo: 2, hi: 98)
        XCTAssertEqual(c.raw(forFraction: 0), 2)
        XCTAssertEqual(c.raw(forFraction: 1), 98)
        XCTAssertEqual(c.fraction(forRaw: 2), 0)
        XCTAssertEqual(c.fraction(forRaw: 98), 1)
        XCTAssertEqual(c.fraction(forRaw: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(c.fraction(forRaw: 0), 0)       // below the range clamps, never negative
    }

    func testMagnetSnapsOnlyNearTheEnds() {
        XCTAssertEqual(VolumeCalibration.magnet(0.985), 1)
        XCTAssertEqual(VolumeCalibration.magnet(0.01), 0)
        XCTAssertEqual(VolumeCalibration.magnet(0.5), 0.5)
        XCTAssertEqual(VolumeCalibration.magnet(0.97), 0.97)
    }

    func testLearnsLimitOnlyAfterTwoIdenticalSettledReadings() {
        var learner = EndpointLearner()
        let cal = VolumeCalibration.standard
        learner.commandSent(raw: 100, isMax: true)
        XCTAssertNil(learner.reading(98, calibration: cal))            // one reading proves nothing
        let learned = learner.reading(98, calibration: cal)
        XCTAssertEqual(learned?.hi, 98)
        XCTAssertEqual(learned?.lo, 0)
    }

    func testDoesNotLearnWhenTVHonoursOrIsFarOrMoving() {
        var learner = EndpointLearner()
        let cal = VolumeCalibration.standard
        learner.commandSent(raw: 0, isMax: false)
        XCTAssertNil(learner.reading(0, calibration: cal))             // honoured
        learner.commandSent(raw: 100, isMax: true)
        XCTAssertNil(learner.reading(60, calibration: cal))            // far from the command: not an end
        learner.commandSent(raw: 100, isMax: true)
        XCTAssertNil(learner.reading(97, calibration: cal))
        XCTAssertNil(learner.reading(98, calibration: cal))            // still moving
    }
}

final class MediaCommandTests: XCTestCase {
    func testExplicitPlayAndPauseKeycodes() {
        XCTAssertEqual(MediaCommand.play.keycode, 126)
        XCTAssertEqual(MediaCommand.pause.keycode, 127)
        XCTAssertEqual(MediaCommand.next.keycode, 87)
        XCTAssertEqual(MediaCommand.previous.keycode, 88)
        XCTAssertEqual(MediaCommand.rewind.keycode, 89)
        XCTAssertEqual(MediaCommand.fastForward.keycode, 90)
    }

    func testSatisfactionFollowsSessionState() {
        var state = MediaState.idle
        state.state = 3
        XCTAssertEqual(MediaCommand.play.satisfied(by: state), true)
        XCTAssertEqual(MediaCommand.pause.satisfied(by: state), false)
        state.state = 2
        XCTAssertEqual(MediaCommand.play.satisfied(by: state), false)
        XCTAssertEqual(MediaCommand.pause.satisfied(by: state), true)
        XCTAssertNil(MediaCommand.next.satisfied(by: state))
    }
}

final class RecentSearchesTests: XCTestCase {
    func testNewestFirstDedupedAndLimited() {
        var list: [String] = []
        for q in ["matrix", "Dune", "MATRIX", "a", "  ", "alien"] { list = RecentSearches.adding(list, q) }
        XCTAssertEqual(list, ["alien", "MATRIX", "Dune"])
        for i in 0..<20 { list = RecentSearches.adding(list, "title \(i)") }
        XCTAssertEqual(list.count, RecentSearches.limit)
    }
}
