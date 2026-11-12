import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 9 §A: Player layout, artwork crop, background contrast, capability detection, play / pause
/// routing, seek and track-skip safety, position throttling, transitions and the volume readout.
final class Phase9PlayerTests: XCTestCase {

    private func media(package: String = "com.nuvio.app", title: String = "Dune", state: Int = 3,
                       actions: Int64 = 0, sampledAt: Date = Date()) -> MediaState {
        MediaState(package: package, title: title, state: state, positionMs: 60_000, speed: 1,
                   sampledAt: sampledAt, actions: actions)
    }

    // MARK: Layout and crop

    func testArtworkFramesKeepTheirProportionsAndFit() {
        let regions = [CGSize(width: 345, height: 420), CGSize(width: 345, height: 180), CGSize(width: 200, height: 600)]
        for kind in [PlayerArtworkKind.poster, .landscape, .appIcon] {
            for region in regions {
                let frame = PlayerLayoutPolicy.portraitArtwork(kind: kind, region: region)
                XCTAssertEqual(frame.width / frame.height, kind.aspect, accuracy: 0.001, "\(kind) is never stretched")
                XCTAssertLessThanOrEqual(frame.width, region.width + 0.001)
                XCTAssertLessThanOrEqual(frame.height, region.height + 0.001)
            }
        }
        XCTAssertEqual(PlayerLayoutPolicy.fit(aspect: 1, in: .zero), .zero)
        XCTAssertEqual(PlayerLayoutPolicy.portraitArtwork(kind: .poster, region: CGSize(width: 345, height: -20)), .zero)
    }

    func testPortraitArtworkDominatesTheRegion() {
        let region = CGSize(width: 345, height: 420)
        let poster = PlayerLayoutPolicy.portraitArtwork(kind: .poster, region: region)
        XCTAssertEqual(poster.height, 420, accuracy: 0.001, "a poster uses the full height above the controls")
        XCTAssertEqual(poster.width, 280, accuracy: 0.001)
        let wide = PlayerLayoutPolicy.portraitArtwork(kind: .landscape, region: region)
        XCTAssertEqual(wide.width, 345, accuracy: 0.001, "16:9 art uses the full width")
        let icon = PlayerLayoutPolicy.portraitArtwork(kind: .appIcon, region: region)
        XCTAssertEqual(icon.width, 345 * PlayerLayoutPolicy.iconShare, accuracy: 0.001)
        XCTAssertLessThan(icon.height, poster.height, "app artwork is a smaller square")
    }

    func testArtworkKindPrefersPosterThenLandscape() {
        let url = URL(string: "https://example.com/a.jpg")
        XCTAssertEqual(PlayerArtworkKind.resolve(posterURL: url, landscapeURL: url), .poster)
        XCTAssertEqual(PlayerArtworkKind.resolve(posterURL: nil, landscapeURL: url), .landscape)
        XCTAssertEqual(PlayerArtworkKind.resolve(posterURL: nil, landscapeURL: nil), .appIcon)
    }

    func testLandscapeSplitIsSquareAndBalanced() {
        // Pages after the rail: iPhone 15 Pro, Pro Max and SE in landscape.
        let pages = [CGSize(width: 664, height: 372), CGSize(width: 744, height: 409), CGSize(width: 585, height: 375)]
        for page in pages {
            let split = PlayerLayoutPolicy.landscape(page: page, bottomClearance: 8)
            XCTAssertGreaterThan(split.artSide, 200, "artwork stays large on \(page)")
            XCTAssertLessThanOrEqual(split.artSide, page.height - 8 - 2 * PlayerLayoutPolicy.landscapeVerticalPadding + 0.001)
            XCTAssertGreaterThanOrEqual(split.column, PlayerLayoutPolicy.landscapeMinColumn - 0.001, "controls keep their room")
            XCTAssertLessThanOrEqual(split.artSide + split.column + split.spacing + 2 * PlayerLayoutPolicy.landscapeMargin,
                                     page.width + 0.001)
            for kind in [PlayerArtworkKind.poster, .landscape, .appIcon] {
                let frame = PlayerLayoutPolicy.landscapeArtwork(kind: kind, side: split.artSide)
                XCTAssertLessThanOrEqual(frame.width, split.artSide + 0.001)
                XCTAssertLessThanOrEqual(frame.height, split.artSide + 0.001)
                XCTAssertEqual(frame.width / frame.height, kind.aspect, accuracy: 0.001)
            }
        }
        XCTAssertEqual(PlayerLayoutPolicy.landscape(page: .zero, bottomClearance: 8).artSide, 0)
    }

    func testBackdropMeshCoversTheWholeWindow() {
        // The wash is drawn, not an image: its outer control points sit on the canvas edges for any
        // artwork, so it covers portrait and landscape windows alike with nothing to crop or enlarge.
        for lean in [0.0, 0.3, 0.75, 1.0, -2, 7, .nan] {
            let points = PlayerBackdropPolicy.meshPoints(lean: lean)
            XCTAssertEqual(points.count, 9)
            for (index, point) in points.enumerated() {
                XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "point \(index) for lean \(lean)")
            }
            for corner in [0, 2, 6, 8] { XCTAssertTrue(points[corner].x == 0 || points[corner].x == 1) }
            XCTAssertEqual(points[3].x, 0); XCTAssertEqual(points[5].x, 1)
            XCTAssertEqual(points[1].y, 0); XCTAssertEqual(points[7].y, 1)
        }
        XCTAssertNotEqual(PlayerBackdropPolicy.meshPoints(lean: 0)[4], PlayerBackdropPolicy.meshPoints(lean: 1)[4],
                          "different artwork gives a differently shaped wash")
    }

    // MARK: Background contrast

    func testTransferFunctionsRoundTrip() {
        for step in 0...20 {
            let l = Double(step) / 20
            XCTAssertEqual(PlayerBackdropPolicy.linear(PlayerBackdropPolicy.encoded(l)), l, accuracy: 1e-6)
        }
    }

    func testWashKeepsInkLegibleOverAnyArtwork() throws {
        // Grey ramp: from black to white artwork, every colour the mesh draws keeps the ink at 4.5:1.
        for step in 0...40 {
            let v = Double(step) / 40
            let swatches = [ArtworkSwatch(r: v, g: v, b: v, share: 1)]
            for light in [false, true] {
                let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: swatches, light: light))
                for tone in PlayerBackdropPolicy.meshColors(palette, light: light) {
                    XCTAssertGreaterThanOrEqual(PlayerBackdropPolicy.inkContrast(over: tone, light: light),
                                                PlayerBackdropPolicy.minimumContrast, "grey \(v), light \(light)")
                }
            }
        }
    }

    func testBrightArtIsDarkenedAndDarkArtKeepsItsColour() {
        let white = NowPlayingPalette.make(swatches: [ArtworkSwatch(r: 1, g: 1, b: 1, share: 1)], light: false)!
        XCTAssertLessThanOrEqual(white.base.luminance, PlayerBackdropPolicy.darkMaxLuminance + 0.001)
        let black = NowPlayingPalette.make(swatches: [ArtworkSwatch(r: 0, g: 0, b: 0, share: 1)], light: false)!
        XCTAssertGreaterThanOrEqual(black.base.luminance, PlayerBackdropPolicy.darkMinLuminance - 0.001,
                                    "black artwork still gives a wash, not an empty background")
        let deepRed = ArtworkSwatch(r: 0.35, g: 0.02, b: 0.05, share: 1)
        let red = NowPlayingPalette.make(swatches: [deepRed], light: false)!
        XCTAssertEqual(red.base, NowPlayingPalette.Tone(deepRed), "an already legible colour is kept as it is")
    }

    // MARK: Capabilities

    func testControlsFollowAdvertisedActions() {
        let full = PlayerControls.resolve(media: media(actions: 2 | 4 | 8 | 64))
        XCTAssertTrue(full.playPause)
        XCTAssertTrue(full.rewind)
        XCTAssertTrue(full.fastForward)
        XCTAssertTrue(full.hasSecondary)

        let bare = PlayerControls.resolve(media: media(actions: 4))
        XCTAssertTrue(bare.playPause)
        XCTAssertFalse(bare.rewind, "not advertised: hidden, not an inert button")
        XCTAssertFalse(bare.fastForward)
        XCTAssertFalse(bare.hasSecondary)

        XCTAssertFalse(PlayerControls.resolve(media: media(actions: 0)).playPause)
        XCTAssertEqual(PlayerControls.resolve(media: MediaState.idle), PlayerControls.none)
    }

    func testTrackSkipNeverAppearsForVideoOrNuvio() {
        let skip: Int64 = 4 | 16 | 32
        for package in ["com.nuvio.app", "com.stremio.one", "com.google.android.youtube.tv", "org.videolan.vlc"] {
            let controls = PlayerControls.resolve(media: media(package: package, actions: skip))
            XCTAssertFalse(controls.previousTrack, "\(package): previous would be episode / video navigation")
            XCTAssertFalse(controls.nextTrack, "\(package)")
        }
        XCTAssertEqual(PlayerSessionKind.resolve(package: "com.nuvio.app"), .video)

        let music = PlayerControls.resolve(media: media(package: "com.spotify.tv.android", actions: skip))
        XCTAssertTrue(music.previousTrack)
        XCTAssertTrue(music.nextTrack)
        XCTAssertEqual(PlayerSessionKind.resolve(package: " COM.SPOTIFY.TV.ANDROID "), .audio)

        let musicWithoutSkip = PlayerControls.resolve(media: media(package: "com.spotify.tv.android", actions: 4))
        XCTAssertFalse(musicWithoutSkip.nextTrack, "only when the session advertises it")
    }

    func testProgressOnlyWithAReliableDuration() {
        XCTAssertFalse(PlayerControls.hasReliableDuration(nil))
        XCTAssertFalse(PlayerControls.hasReliableDuration(0))
        XCTAssertFalse(PlayerControls.hasReliableDuration(-5))
        XCTAssertTrue(PlayerControls.hasReliableDuration(120_000))
        XCTAssertFalse(PlayerControls.resolve(media: media(actions: 2 | 4 | 256)).progress,
                       "advertising seekTo is not a duration: no progress bar")
    }

    func testPlayPauseSendsExplicitCommands() {
        XCTAssertEqual(PlayerControls.playPauseCommand(for: media(state: 3)), .pause)
        XCTAssertEqual(PlayerControls.playPauseCommand(for: media(state: 6)), .pause, "buffering counts as playing")
        XCTAssertEqual(PlayerControls.playPauseCommand(for: media(state: 2)), .play)
        XCTAssertEqual(PlayerControls.playPauseCommand(for: MediaState.idle), .play)
    }

    // MARK: State and throttling

    func testSessionPhases() {
        let now = Date()
        XCTAssertEqual(PlayerSessionPhase.resolve(media: .idle, connected: false, connecting: false, now: now), .disconnected)
        XCTAssertEqual(PlayerSessionPhase.resolve(media: .idle, connected: false, connecting: true, now: now), .connecting)
        XCTAssertEqual(PlayerSessionPhase.resolve(media: .idle, connected: true, connecting: false, now: now), .idle)
        XCTAssertEqual(PlayerSessionPhase.resolve(media: media(state: 3, sampledAt: now), connected: true, connecting: false, now: now), .playing)
        XCTAssertEqual(PlayerSessionPhase.resolve(media: media(state: 2, sampledAt: now), connected: true, connecting: false, now: now), .paused)
        XCTAssertEqual(PlayerSessionPhase.resolve(media: media(state: 6, sampledAt: now), connected: true, connecting: false, now: now), .buffering)
        let old = now.addingTimeInterval(-(PlayerSessionPhase.staleAfter + 1))
        XCTAssertEqual(PlayerSessionPhase.resolve(media: media(state: 3, sampledAt: old), connected: true, connecting: false, now: now), .stale)
        XCTAssertTrue(PlayerSessionPhase.stale.showsSession)
        XCTAssertFalse(PlayerSessionPhase.idle.showsSession)
        XCTAssertGreaterThan(PlayerSessionPhase.staleAfter, 10, "longer than one poll interval")
    }

    func testPositionUpdatesAreThrottled() {
        XCTAssertEqual(PlayerTimeline.refreshInterval(isPlaying: true), 1)
        XCTAssertGreaterThan(PlayerTimeline.refreshInterval(isPlaying: false), 1, "no per-second redraw while paused")

        let sampled = Date().addingTimeInterval(-40)
        let stale = media(state: 3, sampledAt: sampled)
        XCTAssertEqual(PlayerTimeline.position(media: stale, phase: .stale, at: Date()), 60, accuracy: 0.001,
                       "a stale sample is frozen, not extrapolated")
        let live = media(state: 3, sampledAt: sampled)
        XCTAssertEqual(PlayerTimeline.position(media: live, phase: .playing, at: sampled.addingTimeInterval(2)), 62, accuracy: 0.001)
    }

    func testArtworkAndMetadataShareOneTransitionKey() {
        let base = media(title: "Dune")
        var moved = base
        moved.positionMs = 90_000
        moved.state = 2
        moved.sampledAt = Date().addingTimeInterval(5)
        XCTAssertEqual(PlayerTransition.key(media: base), PlayerTransition.key(media: moved), "polls do not restart the transition")

        var other = base
        other.title = "Arrival"
        XCTAssertNotEqual(PlayerTransition.key(media: base), PlayerTransition.key(media: other))
        var episode = base
        episode.subtitle = "S1 E2"
        XCTAssertNotEqual(PlayerTransition.key(media: base), PlayerTransition.key(media: episode))
        XCTAssertEqual(PlayerTransition.key(media: .idle), "")
    }

    // MARK: Volume

    func testVolumeReadoutStaysWithinZeroToHundred() {
        XCTAssertEqual(VolumeReadout.text(percent: 57), "57%")
        XCTAssertEqual(VolumeReadout.text(percent: 140), "100%")
        XCTAssertEqual(VolumeReadout.text(percent: -3), "0%")
    }
}
