import XCTest
@testable import GlassRemote

/// Audit remediation, Priority C (truthful connection and playback feedback). Pure logic; the real
/// box's helper failures, ADB prompt and app sessions still need the hardware acceptance checklist.
final class RemediationFeedbackTests: XCTestCase {

    private func readiness(adb: Bool = true, shell: Bool = true, keyboard: Bool = true, mouse: Bool = true,
                           busy: Bool = false, reconnect: Bool = false) -> ConnectionReadiness {
        ConnectionReadiness(adbConnected: adb, commandShellReady: shell, keyboardReady: keyboard,
                            mouseReady: mouse, busy: busy, requiresUserReconnect: reconnect)
    }

    // MARK: UX-001

    func testConnectedOnlyWhenEveryInputPathIsReady() {
        XCTAssertEqual(readiness().state, .connected)
        XCTAssertNil(readiness().guidance)
        XCTAssertEqual(readiness(keyboard: false).state, .degraded)
        XCTAssertEqual(readiness(mouse: false).state, .degraded)
        XCTAssertEqual(readiness(shell: false).state, .degraded)
    }

    func testDegradedNamesWhatIsBrokenAndHowToFixIt() {
        let r = readiness(keyboard: false, mouse: false)
        XCTAssertEqual(r.missing, ["D-pad", "trackpad"])
        XCTAssertTrue(r.guidance?.contains("D-pad, trackpad") ?? false)
        XCTAssertTrue(r.guidance?.contains("Reconnect") ?? false)
    }

    func testStartingHelpersIsConnectingNotDegraded() {
        XCTAssertEqual(readiness(keyboard: false, mouse: false, busy: true).state, .connecting)
        XCTAssertEqual(readiness(adb: false, busy: true).state, .connecting)
        XCTAssertEqual(readiness(adb: false).state, .offline)
        XCTAssertEqual(readiness(reconnect: true).state, .reconnectNeeded)
        XCTAssertTrue(readiness(adb: false).missing.isEmpty, "nothing is 'missing' without a connection")
    }

    // MARK: UX-015

    func testADBRefusalTellsTheUserWhatToDoOnTheTV() {
        XCTAssertTrue(ADBAuthorisationGuidance.message.contains("Allow"))
        XCTAssertTrue(ADBAuthorisationGuidance.message.contains("Connect"))
    }

    // MARK: BUG-016

    func testLauncherRestartNeedsAndroidsConfirmation() {
        XCTAssertTrue(LauncherRestartOutcome.started(output: """
            Starting: Intent { act=android.intent.action.MAIN cat=[android.intent.category.HOME] cmp=com.glasslauncher/.MainActivity }
            Status: ok
            __exit=0
            """))
        XCTAssertFalse(LauncherRestartOutcome.started(output: """
            Starting: Intent { cmp=com.glasslauncher/.MainActivity }
            Error type 3
            Error: Activity class {com.glasslauncher/com.glasslauncher.MainActivity} does not exist.
            __exit=0
            """))
        XCTAssertFalse(LauncherRestartOutcome.started(output: ""), "no answer is not success")
        XCTAssertFalse(LauncherRestartOutcome.started(output: "Starting: Intent { }\n__exit=1"))
        XCTAssertTrue(LauncherRestartOutcome.reason(output: "Error: Activity not found\n__exit=0").hasPrefix("Error:"))
    }

    // MARK: UX-005

    func testTransportFailureIsShownBrieflyThenClears() {
        let at = Date(timeIntervalSince1970: 100)
        let failure = MediaFailureReport.notAccepted(.pause, at: at)
        XCTAssertEqual(failure.text, "TV didn't accept Pause")
        XCTAssertTrue(failure.isVisible(at: at.addingTimeInterval(1)))
        XCTAssertFalse(failure.isVisible(at: at.addingTimeInterval(MediaFailureReport.visibleFor)))
        XCTAssertEqual(MediaCommand.fastForward.displayName, "Fast-forward")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .playing, seek: failure.text), failure.text)
    }

    // MARK: BUG-011 / UX-007

    private func dump(state: String, uptime: String = "12345.67", updated: String = "12000000") -> String {
        """
        \(uptime) 8901.2
          Sessions Stack - have 1 sessions:
            Spotify com.spotify.tv.android/MediaSession (userId=0)
              ownerPid=2222, ownerUid=10080, userId=0
              package=com.spotify.tv.android
              active=true
              state=PlaybackState {state=\(state), position=5000, buffered position=0, speed=1.0, updated=\(updated), actions=823}
              metadata: size=4, description=Song, Artist, null
        """
    }

    func testTransientStatesKeepTheLastSample() {
        for state in ["4", "5", "8", "9", "10", "11", "SKIPPING_TO_NEXT(10)"] {
            XCTAssertEqual(MediaParser.read(dump(state: state)), .unreadable, "state \(state)")
        }
        let playing = MediaParser.read(dump(state: "3"))
        guard case .session(let sample) = playing else { return XCTFail("playing session not read") }
        XCTAssertEqual(MediaPollPolicy.next(current: sample, read: MediaParser.read(dump(state: "10"))), sample,
                       "skipping tracks never flashes Nothing playing")
    }

    func testStoppedStillEndsTheSession() {
        XCTAssertEqual(MediaParser.read(dump(state: "1")), .none)
    }

    func testARecentPauseStaysAndAnAbandonedOneEnds() {
        guard case .session = MediaParser.read(dump(state: "2")) else { return XCTFail("a 6-minute pause is kept") }
        // Paused 40 minutes ago by the box's own clock.
        let abandoned = dump(state: "2", uptime: "3000.00", updated: "600000")
        XCTAssertEqual(MediaParser.read(abandoned), .none)
        XCTAssertFalse(MediaSessionAge.isAbandonedPause(state: 3, updatedMs: 1, uptimeMs: 99_999_999), "playing is never abandoned")
        XCTAssertFalse(MediaSessionAge.isAbandonedPause(state: 2, updatedMs: 0, uptimeMs: 99_999_999), "no timestamp, no guess")
    }

    // MARK: UX-013 / UX-014 / A11Y-002

    func testNoTimelineTrackWithoutARealDuration() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let page = try? String(contentsOf: root.appendingPathComponent("GlassRemote/PlayerPage.swift"), encoding: .utf8) else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        XCTAssertTrue(page.contains("if total != nil {"), "the track is drawn only with a real total")
    }

    func testUnknownAppsGetReadableNames() {
        XCTAssertEqual(PlayerAppName.name(forPackage: "com.stremio.one"), "Stremio")
        XCTAssertEqual(PlayerAppName.name(forPackage: "com.nuvio.debug"), "Nuvio")
        XCTAssertEqual(PlayerAppName.name(forPackage: "com.example.player.tv"), "Player")
        XCTAssertEqual(PlayerAppName.name(forPackage: "com.google.android.gms"), "Google Cast")
        XCTAssertFalse(PlayerSessionPhase.idle.hint.contains("Nuvio"), "the idle hint is app-neutral")
    }

    func testSecondaryTextIsMuchMoreLegible() {
        XCTAssertGreaterThanOrEqual(PlayerTextContrast.standard, 0.75)
        XCTAssertEqual(PlayerTextContrast.secondary(increased: true), 1)
    }
}
