import XCTest
import SwiftUI
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
        XCTAssertEqual(AppPage.allCases, [.remote, .player, .discover, .profile])
    }

    func testTargetPageThresholdsAndClamping() {
        XCTAssertEqual(AppPage.target(from: .remote, translation: -200, predicted: -250, width: 390), .player)
        XCTAssertEqual(AppPage.target(from: .remote, translation: -40, predicted: -60, width: 390), .remote)   // too small
        XCTAssertEqual(AppPage.target(from: .remote, translation: -30, predicted: -300, width: 390), .player)  // flick
        XCTAssertEqual(AppPage.target(from: .remote, translation: 300, predicted: 400, width: 390), .remote)   // clamped at start
        XCTAssertEqual(AppPage.target(from: .discover, translation: -200, predicted: -260, width: 390), .profile)
        XCTAssertEqual(AppPage.target(from: .profile, translation: -300, predicted: -400, width: 390), .profile)     // clamped at end
        XCTAssertEqual(AppPage.target(from: .discover, translation: 200, predicted: 260, width: 390), .player)
    }

    func testEdgeResistance() {
        XCTAssertEqual(AppPage.resisted(100, on: .remote), 25)
        XCTAssertEqual(AppPage.resisted(-100, on: .profile), -25)
        XCTAssertEqual(AppPage.resisted(-100, on: .discover), -100)
        XCTAssertEqual(AppPage.resisted(100, on: .player), 100)
    }
}

final class CinemetaCatalogTests: XCTestCase {
    func testSearchURLEncodesQuery() {
        let url = CinemetaCatalog.searchURL(kind: .movie, query: "The Matrix: Reloaded/x")
        XCTAssertEqual(url?.absoluteString, "https://v3-cinemeta.strem.io/catalog/movie/top/search=The%20Matrix%3A%20Reloaded%2Fx.json")
        XCTAssertNil(CinemetaCatalog.searchURL(kind: .series, query: "   "))
    }

    func testParseToleratesMissingFields() {
        let json = #"{"metas":[{"id":"tt0133093","name":"The Matrix","poster":"https://example.com/p.jpg","releaseInfo":"1999","imdbRating":"8.7"},{"name":"No id"},{"id":"tt1","poster":"http://insecure/x.jpg","name":"Insecure poster"}]}"#
        let items = CinemetaCatalog.parse(Data(json.utf8), kind: .movie)
        XCTAssertEqual(items.map(\.name), ["The Matrix", "Insecure poster"])
        XCTAssertNotNil(items[0].posterURL)
        XCTAssertNil(items[1].posterURL)            // non-https artwork is dropped
        XCTAssertTrue(CinemetaCatalog.parse(Data("garbage".utf8), kind: .series).isEmpty)
    }

    func testDeepLinkValidationRejectsUnsafeIds() {
        XCTAssertEqual(RemoteModel.nuvioDetailLink(kind: .movie, id: "tt0133093"), "nuvio://detail/movie/tt0133093")
        XCTAssertEqual(RemoteModel.nuvioDetailLink(kind: .series, id: "tt0903747"), "nuvio://detail/series/tt0903747")
        XCTAssertNil(RemoteModel.nuvioDetailLink(kind: .movie, id: "tt0133093'; reboot; '"))
        XCTAssertNil(RemoteModel.nuvioDetailLink(kind: .series, id: "kitsu:1"))
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
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .android, androidConnected: true, samsungRemoteReady: true), .android)
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .samsung, androidConnected: true, samsungRemoteReady: true), .samsung)
        XCTAssertNil(RemoteRouting.device(for: .navigation, target: .samsung, androidConnected: true, samsungRemoteReady: false))
        XCTAssertNil(RemoteRouting.device(for: .navigation, target: .android, androidConnected: false, samsungRemoteReady: true))
    }

    func testThereAreExactlyTwoTargetsAndNoAuto() {
        XCTAssertEqual(RemoteTarget.allCases, [.android, .samsung])
        XCTAssertFalse(RemoteTarget.allCases.map(\.rawValue).contains("auto"))
    }

    func testLegacyAutoSelectionRestoresToAndroidAndLastExplicitChoiceIsKept() {
        XCTAssertEqual(RemoteTarget.restored(from: "auto"), .android)   // saved by an older build
        XCTAssertEqual(RemoteTarget.restored(from: nil), .android)
        XCTAssertEqual(RemoteTarget.restored(from: "garbage"), .android)
        XCTAssertEqual(RemoteTarget.restored(from: "samsung"), .samsung)
        XCTAssertEqual(RemoteTarget.restored(from: "android"), .android)
    }

    func testDisconnectedSelectedDeviceNeverFallsBackToTheOther() {
        // Samsung selected, TV down, box up: nothing is sent (no silent control of the box).
        for kind in [RemoteCommandKind.navigation, .media, .volume, .power, .source, .channel, .guide] {
            XCTAssertNil(RemoteRouting.device(for: kind, target: .samsung, androidConnected: true, samsungRemoteReady: false), "\(kind)")
        }
        // Android selected, box down, TV up: navigation/media/power are not redirected to the TV.
        for kind in [RemoteCommandKind.navigation, .media, .power] {
            XCTAssertNil(RemoteRouting.device(for: kind, target: .android, androidConnected: false, samsungRemoteReady: true), "\(kind)")
        }
    }

    func testSamsungTargetSendsEveryKindToTheTV() {
        for kind in [RemoteCommandKind.navigation, .media, .volume, .power, .source, .channel, .guide] {
            XCTAssertEqual(RemoteRouting.device(for: kind, target: .samsung, androidConnected: true, samsungRemoteReady: true), .samsung, "\(kind)")
        }
    }

    func testAndroidTargetHasNoTVOnlyCapabilities() {
        for kind in [RemoteCommandKind.source, .channel, .guide] {
            XCTAssertNil(RemoteRouting.device(for: kind, target: .android, androidConnected: true, samsungRemoteReady: true), "\(kind)")
        }
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .android, androidConnected: true, samsungRemoteReady: true), .android)
    }

    func testVolumeKeepsExistingPreference() {
        XCTAssertEqual(RemoteRouting.device(for: .volume, target: .android, androidConnected: true, samsungRemoteReady: true), .samsung)
        XCTAssertEqual(RemoteRouting.device(for: .volume, target: .android, androidConnected: true, samsungRemoteReady: false), .android)
        XCTAssertNil(RemoteRouting.device(for: .volume, target: .android, androidConnected: false, samsungRemoteReady: false))
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

    func testMagnetIsSymmetricAtBothEnds() {
        let m = VolumeCalibration.magnetMargin
        for d in [0.0, 0.005, 0.01, m] {                       // inside or exactly on the zone
            XCTAssertEqual(VolumeCalibration.magnet(d), 0, "low end, distance \(d)")
            XCTAssertEqual(VolumeCalibration.magnet(1 - d), 1, "high end, distance \(d)")
        }
        for d in [m + 0.001, 0.02, 0.03] {                     // just outside the zone
            XCTAssertEqual(VolumeCalibration.magnet(d), d, accuracy: 1e-12, "low end, distance \(d)")
            XCTAssertEqual(VolumeCalibration.magnet(1 - d), 1 - d, accuracy: 1e-12, "high end, distance \(d)")
        }
    }

    func testMagnetBoundariesAndOutOfRange() {
        XCTAssertEqual(VolumeCalibration.magnet(0.015), 0)
        XCTAssertEqual(VolumeCalibration.magnet(0.985), 1)
        XCTAssertEqual(VolumeCalibration.magnet(0.016), 0.016, accuracy: 1e-12)
        XCTAssertEqual(VolumeCalibration.magnet(0.984), 0.984, accuracy: 1e-12)
        XCTAssertEqual(VolumeCalibration.magnet(-0.2), 0)
        XCTAssertEqual(VolumeCalibration.magnet(1.2), 1)
    }

    func testMagnetThenCalibrationReachesLearnedEnds() {
        let c = VolumeCalibration(lo: 2, hi: 98)
        XCTAssertEqual(c.raw(forFraction: VolumeCalibration.magnet(0.985)), 98)
        XCTAssertEqual(c.raw(forFraction: VolumeCalibration.magnet(0.015)), 2)
        XCTAssertEqual(c.raw(forFraction: VolumeCalibration.magnet(0.5)), 50)
    }

    func testMagnetFineStepsKeepTightMargin() {
        // VoiceOver increment/decrement uses margin 0.001 and must not jump to an end early.
        XCTAssertEqual(VolumeCalibration.magnet(0.98, margin: 0.001), 0.98, accuracy: 1e-12)
        XCTAssertEqual(VolumeCalibration.magnet(0.9995, margin: 0.001), 1)
        XCTAssertEqual(VolumeCalibration.magnet(0.0005, margin: 0.001), 0)
    }

    // --- EndpointLearner (v0.4 review: strict rules) ---

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testLearnsOnlyAfterSettleDelayAndThreeSpacedIdenticalReadings() {
        var learner = EndpointLearner()
        let cal = VolumeCalibration.standard
        learner.commandSent(raw: 100, isMax: true, at: t0)
        XCTAssertEqual(learner.reading(98, at: at(0.4), dragging: false, calibration: cal), .none)   // TV not settled
        XCTAssertEqual(learner.reading(98, at: at(1.2), dragging: false, calibration: cal), .none)   // 1st counted
        XCTAssertEqual(learner.reading(98, at: at(1.4), dragging: false, calibration: cal), .none)   // too soon after the last
        XCTAssertEqual(learner.reading(98, at: at(2.0), dragging: false, calibration: cal), .none)   // 2nd
        let outcome = learner.reading(98, at: at(2.8), dragging: false, calibration: cal)             // 3rd
        XCTAssertEqual(outcome, .tentative(VolumeCalibration(lo: 0, hi: 98)))
    }

    func testSecondIndependentAttemptConfirmsAndOnlyThenPersists() {
        var learner = EndpointLearner()
        let cal = VolumeCalibration.standard
        func attempt(from start: Double) -> EndpointLearner.Outcome {
            learner.commandSent(raw: 100, isMax: true, at: at(start))
            _ = learner.reading(98, at: at(start + 1.2), dragging: false, calibration: cal)
            _ = learner.reading(98, at: at(start + 2.0), dragging: false, calibration: cal)
            return learner.reading(98, at: at(start + 2.8), dragging: false, calibration: cal)
        }
        XCTAssertEqual(attempt(from: 0), .tentative(VolumeCalibration(lo: 0, hi: 98)))
        XCTAssertEqual(attempt(from: 20), .confirmed(VolumeCalibration(lo: 0, hi: 98)))
    }

    func testDifferentValueOnSecondAttemptStaysTentative() {
        var learner = EndpointLearner()
        let cal = VolumeCalibration.standard
        learner.commandSent(raw: 100, isMax: true, at: t0)
        _ = learner.reading(98, at: at(1.2), dragging: false, calibration: cal)
        _ = learner.reading(98, at: at(2.0), dragging: false, calibration: cal)
        _ = learner.reading(98, at: at(2.8), dragging: false, calibration: cal)
        learner.commandSent(raw: 100, isMax: true, at: at(20))
        _ = learner.reading(97, at: at(21.2), dragging: false, calibration: cal)
        _ = learner.reading(97, at: at(22.0), dragging: false, calibration: cal)
        XCTAssertEqual(learner.reading(97, at: at(22.8), dragging: false, calibration: cal),
                       .tentative(VolumeCalibration(lo: 0, hi: 97)))
    }

    func testDiscardsDraggingStaleNewerCommandInconsistentAndHonoured() {
        let cal = VolumeCalibration.standard
        var learner = EndpointLearner()

        learner.commandSent(raw: 100, isMax: true, at: t0)                 // user is dragging
        XCTAssertEqual(learner.reading(98, at: at(1.5), dragging: true, calibration: cal), .none)
        XCTAssertFalse(learner.isArmed)

        learner.commandSent(raw: 100, isMax: true, at: t0)                 // stale: window expired
        XCTAssertEqual(learner.reading(98, at: at(30), dragging: false, calibration: cal), .none)
        XCTAssertFalse(learner.isArmed)

        learner.commandSent(raw: 100, isMax: true, at: t0)                 // newer command issued
        learner.invalidate()
        XCTAssertEqual(learner.reading(98, at: at(1.5), dragging: false, calibration: cal), .none)

        learner.commandSent(raw: 100, isMax: true, at: t0)                 // far from the command
        XCTAssertEqual(learner.reading(60, at: at(1.5), dragging: false, calibration: cal), .none)
        XCTAssertFalse(learner.isArmed)

        learner.commandSent(raw: 100, isMax: true, at: t0)                 // inconsistent readings
        _ = learner.reading(98, at: at(1.2), dragging: false, calibration: cal)
        _ = learner.reading(97, at: at(2.0), dragging: false, calibration: cal)
        XCTAssertEqual(learner.reading(98, at: at(2.8), dragging: false, calibration: cal), .none)

        learner.commandSent(raw: 0, isMax: false, at: t0)                  // TV honoured the command
        XCTAssertEqual(learner.reading(0, at: at(1.5), dragging: false, calibration: cal), .none)
        XCTAssertFalse(learner.isArmed)
    }

    func testImplausibleValuesAreNeverLearned() {
        var learner = EndpointLearner()
        learner.commandSent(raw: 100, isMax: true, at: t0)
        XCTAssertEqual(learner.reading(70, at: at(1.5), dragging: false, calibration: .standard), .none)   // not near a top
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


final class DirectionalTrackpadTests: XCTestCase {
    func testDeadZoneProducesNoKeysAndMarksTap() {
        var pad = DirectionalTrackpad()
        pad.begin()
        XCTAssertTrue(pad.move(dx: 3, dy: 2).isEmpty)
        XCTAssertFalse(pad.didMove)
    }

    func testDirectionsAndSingleAxisBias() {
        var pad = DirectionalTrackpad(); pad.acceleration = false; pad.begin()
        XCTAssertEqual(pad.move(dx: 40, dy: 5), [.right])
        pad.begin()
        XCTAssertEqual(pad.move(dx: -40, dy: 5), [.left])
        pad.begin()
        XCTAssertEqual(pad.move(dx: 4, dy: 40), [.down])
        pad.begin()
        XCTAssertEqual(pad.move(dx: 4, dy: -40), [.up])
    }

    func testSensitivityAndAcceleration() {
        func count(_ sensitivity: Double, _ accel: Bool, speedStep: CGFloat) -> Int {
            var pad = DirectionalTrackpad()
            pad.sensitivity = sensitivity; pad.acceleration = accel; pad.maxKeysPerEvent = 10; pad.begin()
            var n = 0
            for _ in 0..<10 { n += pad.move(dx: speedStep, dy: 0).count }
            return n
        }
        XCTAssertGreaterThan(count(3, false, speedStep: 8), count(0.5, false, speedStep: 8))
        XCTAssertGreaterThan(count(1.5, true, speedStep: 20), count(1.5, false, speedStep: 20))
    }

    func testKeysPerEventAreCapped() {
        var pad = DirectionalTrackpad(); pad.acceleration = false; pad.begin()
        XCTAssertEqual(pad.move(dx: 400, dy: 0).count, pad.maxKeysPerEvent)
    }
}

final class SamsungDiagnosticsTests: XCTestCase {
    func testSummaryDoesNotClaimConfirmation() {
        var stats = SamsungCommandStats()
        XCTAssertEqual(stats.summary, "No Samsung keys sent yet")
        stats.queued = 3; stats.written = 3; stats.lastKey = "KEY_UP"; stats.lastCommand = "Click"
        XCTAssertTrue(stats.summary.contains("handed to the TV connection 3 of 3"))
        XCTAssertTrue(stats.summary.contains("does not confirm"))
    }

    func testOnlyVolumeKeysHaveAFallbackName() {
        XCTAssertEqual(SamsungKey.volUp.legacyVolumeName, "VOLUME_UP")
        XCTAssertEqual(SamsungKey.mute.legacyVolumeName, "MUTE")
        XCTAssertNil(SamsungKey.up.legacyVolumeName)
        XCTAssertNil(SamsungKey.enter.legacyVolumeName)
    }

    func testCapabilitiesAreIndependentInRouting() {
        // Remote works with no volume link: routing only looks at the remote WebSocket flag.
        XCTAssertEqual(RemoteRouting.device(for: .navigation, target: .samsung, androidConnected: false, samsungRemoteReady: true), .samsung)
    }
}


// MARK: - UI refactor

final class SamsungRemoteLayoutTests: XCTestCase {
    private var primary: [SamsungKey] { SamsungRemoteLayout.primaryRows.flatMap { $0.map(\.key) } }

    func testNoDpadKeysOnTheSamsungSurface() {
        for key in SamsungRemoteLayout.removedFromSurface {
            XCTAssertFalse(primary.contains(key), "\(key) must not be a button; the trackpad replaces the D-pad")
            XCTAssertFalse(SamsungRemoteLayout.menuKeys.map(\.key).contains(key))
        }
    }

    func testPrimaryKeysAreTheShortSet() {
        XCTAssertEqual(primary, [.back, .home, .mute, .rewind, .play, .fastForward])   // .play is the combined Play/Pause button
    }

    func testNothingUsefulWasLost() {
        // Everything the old 15-button layout had is still reachable from the surface, the menu or power.
        let reachable = Set(primary + SamsungRemoteLayout.menuKeys.map(\.key) + SamsungRemoteLayout.powerMenuKeys)
        let old: [SamsungKey] = [.back, .home, .menu, .info, .guide, .rewind, .play, .pause, .fastForward, .stop,
                                 .channelUp, .channelDown, .mute, .source, .power]
        for key in old { XCTAssertTrue(reachable.contains(key), "\(key) is no longer reachable") }
    }

    func testEveryMenuKeyIsAllowlisted() {
        for item in SamsungRemoteLayout.menuKeys + SamsungRemoteLayout.primaryRows.flatMap({ $0 }) {
            XCTAssertTrue(SamsungKey.allowlist.contains(item.key.rawValue))
        }
    }
}

final class MenuRoutingTests: XCTestCase {
    func testPowerMenuListsEachActionOnceAndTVActionsNeedSamsung() {
        let withTV = PowerMenu.items(samsungEnabled: true)
        let without = PowerMenu.items(samsungEnabled: false)
        XCTAssertEqual(Set(withTV).count, withTV.count)
        XCTAssertTrue(withTV.contains(.tvPower) && withTV.contains(.turnOffBoth))
        XCTAssertFalse(without.contains(.tvPower) || without.contains(.turnOffBoth))
        XCTAssertEqual(withTV.last, .restartBox)   // destructive item last
    }

    func testPowerActionsThatNeedConfirmationMapToTheirDialogs() {
        XCTAssertEqual(PowerMenu.powerAction(for: .standby), .standby)
        XCTAssertEqual(PowerMenu.powerAction(for: .restartBox), .restartBox)
        XCTAssertEqual(PowerMenu.powerAction(for: .turnOffBoth), .everythingOff)
        XCTAssertEqual(PowerMenu.powerAction(for: .restartLauncher), .restartLauncher)
        XCTAssertNil(PowerMenu.powerAction(for: .wake))
        XCTAssertNil(PowerMenu.powerAction(for: .tvPower))
    }

    func testGlobalMenuNeverRepeatsPowerActions() {
        // Power lives only in the power menu; the global menu has none of it.
        var all: [GlobalMenuSpec.Entry] = []
        for section in [GlobalMenuSpec.Section.device, .samsung, .advanced] {
            all += GlobalMenuSpec.entries(in: section, boxOnline: false, samsungEnabled: true, samsungConnected: false)
        }
        XCTAssertEqual(Set(all).count, all.count, "an entry appears twice")
    }

    func testReconnectEntriesAppearOnlyWhenNeeded() {
        let online = GlobalMenuSpec.entries(in: .device, boxOnline: true, samsungEnabled: true, samsungConnected: true)
        XCTAssertEqual(online, [.connection])
        let down = GlobalMenuSpec.entries(in: .device, boxOnline: false, samsungEnabled: true, samsungConnected: false)
        XCTAssertEqual(down, [.connection, .reconnectBox, .reconnectSamsung])
    }

    func testSamsungSectionOffersSetupWhenDisabled() {
        XCTAssertEqual(GlobalMenuSpec.entries(in: .samsung, boxOnline: true, samsungEnabled: false, samsungConnected: false), [.setUpSamsung])
        XCTAssertEqual(GlobalMenuSpec.entries(in: .samsung, boxOnline: true, samsungEnabled: true, samsungConnected: true), [.samsungKeys, .routeVolume])
    }

    func testAdvancedHoldsScreenshotAndDeviceInfo() {
        XCTAssertEqual(GlobalMenuSpec.entries(in: .advanced, boxOnline: true, samsungEnabled: false, samsungConnected: false), [.screenshot, .deviceInfo])
    }
}

final class DiscoverArtworkTests: XCTestCase {
    func testFallbackPosterOnlyForRealImdbIds() {
        let ok = MediaTitle(id: "tt0133093", kind: .movie, name: "X", year: "", posterURL: nil, rating: "")
        XCTAssertEqual(ok.fallbackPosterURL?.scheme, "https")
        let bad = MediaTitle(id: "kitsu:123", kind: .series, name: "X", year: "", posterURL: nil, rating: "")
        XCTAssertNil(bad.fallbackPosterURL)
    }

    func testHttpPostersAreDropped() {
        let json = #"{"metas":[{"id":"tt0133093","name":"A","poster":"http://x/p.jpg"}]}"#.data(using: .utf8)!
        XCTAssertNil(CinemetaCatalog.parse(json, kind: .movie).first?.posterURL)
    }
}


final class TabTests: XCTestCase {
    /// Phase 7 adds Profile; the original three tabs keep their names and order.
    func testFourTabsInOrderKeepingTheOriginalThree() {
        XCTAssertEqual(AppPage.allCases.map(\.title), ["Remote", "Player", "Discover", "Profile"])
    }
    func testEveryTabHasASymbol() {
        for page in AppPage.allCases { XCTAssertFalse(page.symbol.isEmpty) }
    }
}

final class PlayerArtworkMatcherTests: XCTestCase {
    private func t(_ name: String, _ kind: MediaTitle.Kind, year: String = "") -> MediaTitle {
        MediaTitle(id: "tt1234567", kind: kind, name: name, year: year, posterURL: URL(string: "https://x/\(name).jpg"), rating: "")
    }

    func testNormalisationIgnoresCasePunctuationAndLeadingArticle() {
        XCTAssertEqual(PlayerArtworkMatcher.normalise("The Matrix"), PlayerArtworkMatcher.normalise("matrix"))
        XCTAssertEqual(PlayerArtworkMatcher.normalise("Spider-Man: No Way Home"), "spider man no way home")
    }

    func testEpisodeNamesYieldTheShowName() {
        let q = PlayerArtworkMatcher.query(title: "Breaking Bad S01E05 Gray Matter")
        XCTAssertEqual(q.names.first, "Breaking Bad"); XCTAssertTrue(q.looksEpisodic)
        let q2 = PlayerArtworkMatcher.query(title: "Severance", subtitle: "S2:E3 - Who Is Alive?")
        XCTAssertTrue(q2.looksEpisodic); XCTAssertEqual(q2.names.first, "Severance")
    }

    func testFileNameStyleTitlesAreCleaned() {
        let q = PlayerArtworkMatcher.query(title: "Blade.Runner.2049.2017.1080p.WEB-DL")
        XCTAssertEqual(q.year, "2017"); XCTAssertEqual(q.names.first, "Blade Runner 2049")
    }

    func testYearOnlyTitleIsNotStripped() {
        XCTAssertEqual(PlayerArtworkMatcher.query(title: "1917").names, ["1917"])
    }

    func testOnlyExactNamesMatchAndSeriesPosterWinsForEpisodes() {
        let results = [t("Dune: Part Two", .movie), t("Dune", .movie, year: "2021"), t("Dune", .series, year: "2000")]
        XCTAssertEqual(PlayerArtworkMatcher.best(from: results, for: .init(names: ["Dune"], year: nil, looksEpisodic: true))?.kind, .series)
        XCTAssertEqual(PlayerArtworkMatcher.best(from: results, for: .init(names: ["Dune"], year: nil, looksEpisodic: false))?.kind, .movie)
        XCTAssertEqual(PlayerArtworkMatcher.best(from: results, for: .init(names: ["Dune"], year: "2021", looksEpisodic: false))?.year, "2021")
        XCTAssertNil(PlayerArtworkMatcher.best(from: results, for: .init(names: ["Dun"], year: nil, looksEpisodic: false)))   // no fuzzy guesses
    }
}


final class ThemeSystemTests: XCTestCase {
    func testElevenThemesAndAutoDoesNotMeanAdaptive() {
        XCTAssertEqual(ThemeID.allCases.count, 11)
        XCTAssertEqual(Set(ThemeID.allCases.map(\.rawValue)).count, 11)
        XCTAssertNotEqual(ThemeID.adaptive, ThemeID.auto)
    }

    func testAutoFollowsSystemSchemeAndOthersForceTheirOwn() {
        XCTAssertFalse(GlassTheme.base(for: .auto, systemScheme: .dark).isLight)
        XCTAssertTrue(GlassTheme.base(for: .auto, systemScheme: .light).isLight)
        XCTAssertNil(GlassTheme.base(for: .auto, systemScheme: .dark).scheme)
        XCTAssertEqual(GlassTheme.base(for: .lightGlass, systemScheme: .dark).scheme, .light)
        XCTAssertEqual(GlassTheme.base(for: .glassWhite, systemScheme: .dark).scheme, .light)
        XCTAssertEqual(GlassTheme.base(for: .violet, systemScheme: .light).scheme, .dark)
    }

    func testNeutralPaletteLeavesAdaptiveBaseUntouched() {
        let base = GlassTheme.base(for: .adaptive, systemScheme: .dark)
        XCTAssertEqual(base.adapted(to: .neutral), base)
        let tinted = base.adapted(to: ArtworkPalette(hue: 0.6, saturation: 0.7, brightness: 0.7, secondaryHue: 0.7, isNeutral: false))
        XCTAssertNotEqual(tinted.accent, base.accent)
        XCTAssertEqual(tinted.id, .adaptive)
    }

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 1024) -> [UInt8] {
        (0..<count).flatMap { _ in [r, g, b, 255] }
    }

    func testExtractorFindsDominantHueAndIgnoresGreyscale() {
        let blue = ArtworkPaletteExtractor.palette(fromRGBA: solid(30, 90, 230))
        XCTAssertFalse(blue.isNeutral)
        XCTAssertEqual(blue.hue, 0.61, accuracy: 0.06)
        XCTAssertTrue(ArtworkPaletteExtractor.palette(fromRGBA: solid(120, 120, 120)).isNeutral)
        XCTAssertTrue(ArtworkPaletteExtractor.palette(fromRGBA: solid(0, 0, 0)).isNeutral)
    }

    func testMostlyBlueWithSomeOrangePicksBlue() {
        let pixels = solid(30, 90, 230, count: 800) + solid(240, 130, 30, count: 224)
        XCTAssertEqual(ArtworkPaletteExtractor.palette(fromRGBA: pixels).hue, 0.61, accuracy: 0.06)
    }
}

final class CatalogPagingTests: XCTestCase {
    // Kept local to this test class; private helpers in other XCTestCase classes are not visible here.
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 1024) -> [UInt8] {
        (0..<count).flatMap { _ in [r, g, b, 255] }
    }

    func testBrowseURLsUseAddonExtrasInThePath() {
        XCTAssertEqual(CinemetaCatalog.browseURL(kind: .movie, catalog: "top")?.absoluteString, "https://v3-cinemeta.strem.io/catalog/movie/top.json")
        XCTAssertEqual(CinemetaCatalog.browseURL(kind: .series, catalog: "year", skip: 100)?.absoluteString, "https://v3-cinemeta.strem.io/catalog/series/year/skip=100.json")
        XCTAssertEqual(CinemetaCatalog.browseURL(kind: .movie, catalog: "top", genre: "Sci-Fi", skip: 50)?.absoluteString,
                       "https://v3-cinemeta.strem.io/catalog/movie/top/genre=Sci-Fi&skip=50.json")
        XCTAssertNil(CinemetaCatalog.browseURL(kind: .movie, catalog: "top/../x"))
        XCTAssertNil(CinemetaCatalog.browseURL(kind: .movie, catalog: "top", skip: -1))
    }

    @MainActor
    func testHomeRowsAreUniqueAndGenreRowsComeAfterTheCoreOnes() {
        let rows = DiscoverModel.makeRows()
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertEqual(rows.prefix(6).map(\.source.catalog), ["top", "top", "imdbRating", "imdbRating", "year", "year"])
        XCTAssertTrue(rows.dropFirst(6).allSatisfy { $0.source.genre != nil })
        XCTAssertEqual(rows.count, 6 + CinemetaCatalog.genres.count * 2)
    }

    // MARK: Phase 4.1

    func testPaletteFadesToAndFromNeutralWithoutJumping() {
        let blue = ArtworkPaletteExtractor.palette(fromRGBA: solid(30, 90, 230))
        let half = ArtworkPalette.neutral.mixed(to: blue, 0.5)
        XCTAssertFalse(half.isNeutral)
        XCTAssertEqual(half.strength, 0.5, accuracy: 0.001)
        XCTAssertTrue(blue.mixed(to: .neutral, 1).isNeutral)
        XCTAssertEqual(blue.mixed(to: blue, 0.3).hue, blue.hue, accuracy: 0.0001)
    }

    func testSecondaryHueIsNeverACopyOfThePrimary() {
        let blue = ArtworkPaletteExtractor.palette(fromRGBA: solid(30, 90, 230))
        XCTAssertNotEqual(blue.secondaryHue, blue.hue, accuracy: 0.02)
    }

    func testCatalogueEligibilityOnlyForFilmApps() {
        XCTAssertTrue(PlayerArtworkStore.usesCatalogue(package: "com.nuvio.app"))
        XCTAssertFalse(PlayerArtworkStore.usesCatalogue(package: "com.stremio.one"))
        XCTAssertFalse(PlayerArtworkStore.usesCatalogue(package: "com.google.android.youtube.tv"))
    }
}
