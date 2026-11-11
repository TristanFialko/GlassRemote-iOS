import XCTest
@testable import GlassRemote

/// Phase 9 recovery §4: Now Playing visibility. The parser accepts the Android 14+ PlaybackState
/// shape, an unreadable sample no longer resets the session to idle, and the probe re-evaluates on
/// every model change instead of relying on the timeline alone.
final class Phase9RecoveryNowPlayingTests: XCTestCase {

    private func dump(state: String, active: Bool = true, extra: String = "") -> String {
        """
        12345.67 8901.2
          Sessions Stack - have 1 sessions:
            Nuvio com.nuvio.tv/MediaSession (userId=0)
              ownerPid=2222, ownerUid=10080, userId=0
              package=com.nuvio.tv
              active=\(active)
              state=\(state)\(extra)
              metadata: size=4, description=Movie Name, null, null
        """
    }

    func testAndroid14NamedStateIsParsed() {
        let output = dump(state: "PlaybackState {state=PLAYING(3), position=60000, buffered position=90000, speed=1.0, updated=12345000, actions=823, custom actions=[], active item id=-1, error=null}")
        guard case .session(let media) = MediaParser.read(output) else { return XCTFail("Android 14 session was not read") }
        XCTAssertEqual(media.package, "com.nuvio.tv")
        XCTAssertEqual(media.state, 3)
        XCTAssertTrue(media.isPlaying)
        XCTAssertEqual(media.positionMs, 60670, "buffered position must never be read as the position")
        XCTAssertTrue(media.canPlayPause)
        XCTAssertEqual(media.title, "Movie Name")
        XCTAssertEqual(MediaParser.parse(output), media)
    }

    func testPausedAndBufferingInBothShapes() {
        for text in ["state=2", "state=PAUSED(2)"] {
            let output = dump(state: "PlaybackState {\(text), position=5000, buffered position=99999, speed=0.0, updated=12000000, actions=518}")
            XCTAssertEqual(MediaParser.parse(output)?.state, 2, text)
            XCTAssertEqual(MediaParser.parse(output)?.positionMs, 5000, "a paused position is not extrapolated (\(text))")
        }
        for text in ["state=6", "state=BUFFERING(6)"] {
            let output = dump(state: "PlaybackState {\(text), position=0, buffered position=0, speed=1.0, updated=0, actions=0}")
            XCTAssertEqual(MediaParser.parse(output)?.state, 6, text)
        }
    }

    func testFieldsAreReadIndividually() {
        let reordered = "PlaybackState {state=3, buffered position=7, position=1000, actions=4, speed=2.0, updated=12345000}"
        let fields = MediaParser.playbackFields(in: "state=" + reordered)
        XCTAssertEqual(fields, PlaybackFields(state: 3, position: 1000, speed: 2.0, updated: 12345000, actions: 4))
        XCTAssertNil(MediaParser.playbackFields(in: "state=null"))
        XCTAssertNil(MediaParser.playbackFields(in: "state=PlaybackState {mState=PLAYING}"))
    }

    func testStoppedOrInactiveSessionsAreNothingPlaying() {
        XCTAssertEqual(MediaParser.read(""), .none)
        XCTAssertEqual(MediaParser.read("12345.67 8901.2\nSessions Stack - have 0 sessions:"), .none)
        XCTAssertEqual(MediaParser.read(dump(state: "PlaybackState {state=STOPPED(1), position=0, buffered position=0, speed=1.0, updated=0, actions=0}")), .none)
        XCTAssertEqual(MediaParser.read(dump(state: "null")), .none)
        XCTAssertEqual(MediaParser.read(dump(state: "PlaybackState {state=3, position=0, buffered position=0, speed=1.0, updated=0, actions=0}", active: false)), .none)
    }

    func testAnActiveSessionInAnUnknownShapeIsUnreadableNotIdle() {
        let output = dump(state: "PlaybackState {mState=PLAYING, mPosition=1}")
        XCTAssertEqual(MediaParser.read(output), .unreadable)
        XCTAssertNil(MediaParser.parse(output))
        // Unreadable only for an active session; an inactive one is ignored as before.
        XCTAssertEqual(MediaParser.read(dump(state: "PlaybackState {mState=PLAYING}", active: false)), .none)
    }

    func testPollPolicyHoldsTheLastSampleThroughAnUnreadableRead() {
        let sampled = Date(timeIntervalSince1970: 1_000_000)
        let playing = MediaState(package: "com.nuvio.tv", title: "Movie", state: 3, positionMs: 1000, speed: 1,
                                 sampledAt: sampled, actions: 518)
        let newer = MediaState(package: "com.nuvio.tv", title: "Movie", state: 2, positionMs: 9000, speed: 1,
                               sampledAt: sampled.addingTimeInterval(9), actions: 518)
        XCTAssertEqual(MediaPollPolicy.next(current: playing, read: .unreadable), playing)
        XCTAssertEqual(MediaPollPolicy.next(current: playing, read: .session(newer)), newer)
        XCTAssertEqual(MediaPollPolicy.next(current: playing, read: .none), .idle)
        XCTAssertEqual(MediaPollPolicy.next(current: .idle, read: .unreadable), .idle)

        // The held sample keeps its own time, so it still hides once it goes stale.
        let held = MediaPollPolicy.next(current: playing, read: .unreadable)
        XCTAssertTrue(MiniPlayerPolicy.isVisible(media: held, connected: true, connecting: false, now: sampled.addingTimeInterval(10)))
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: held, connected: true, connecting: false,
                                                  now: sampled.addingTimeInterval(PlayerSessionPhase.staleAfter + 1)))
    }

    func testAParsedAndroid14SessionShowsTheMiniPlayer() {
        let now = Date()
        let output = dump(state: "PlaybackState {state=PLAYING(3), position=1, buffered position=2, speed=1.0, updated=12345000, actions=518}")
        let media = MediaPollPolicy.next(current: .idle, read: MediaParser.read(output, now: now))
        XCTAssertTrue(MiniPlayerPolicy.isVisible(media: media, connected: true, connecting: false, now: now))
        XCTAssertTrue(MiniPlayerPolicy.isShown(sessionVisible: true, playerPresented: false))
        XCTAssertFalse(MiniPlayerPolicy.isShown(sessionVisible: true, playerPresented: true))
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: media, connected: false, connecting: false, now: now))
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

    func testPollingAndProbeUseTheRecoveredPaths() throws {
        let features = try source("GlassRemote/RemoteModel+Features.swift")
        XCTAssertFalse(features.contains("media = MediaParser.parse(output) ?? .idle"), "an unreadable read must not reset to idle")
        XCTAssertTrue(features.contains("MediaPollPolicy.next(current: media, read: sample)"))
        let root = try source("GlassRemote/RootPagerView.swift")
        XCTAssertTrue(root.contains(".onChange(of: shownNow)"), "the probe must re-evaluate on every model change")
        XCTAssertTrue(root.contains(".onAppear { report(shownNow) }"))
        XCTAssertTrue(root.contains("NowPlayingMiniPlayer()"))
        XCTAssertTrue(root.contains("NowPlayingRailTile()"))
    }
}
