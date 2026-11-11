import XCTest
import SwiftUI
@testable import GlassRemote

/// v5 §3: the Apple Music style Now Playing page. Layout, timeline and background decisions are pure
/// (PlayerPolicy.swift), so they are tested here; the page only reads them.
final class Phase9NowPlayingV5Tests: XCTestCase {
    private let kinds: [PlayerArtworkKind] = [.poster, .landscape, .appIcon]

    func testArtworkIsLargeAndNearSquare() {
        let region = CGSize(width: 342, height: 420)
        for kind in kinds {
            let frame = PlayerLayoutPolicy.nowPlayingArtwork(kind: kind, region: region)
            XCTAssertLessThanOrEqual(frame.width, region.width + 0.001, "\(kind)")
            XCTAssertLessThanOrEqual(frame.height, region.height + 0.001, "\(kind)")
            let aspect = frame.width / frame.height
            XCTAssertEqual(aspect, PlayerLayoutPolicy.nowPlayingAspect(kind: kind), accuracy: 0.001, "uniform scale, never stretched")
            XCTAssertGreaterThanOrEqual(aspect, 0.75, "\(kind) stays near-square")
            XCTAssertLessThanOrEqual(aspect, 1.34, "\(kind) stays near-square")
            XCTAssertGreaterThanOrEqual(frame.width, region.width * 0.95, "\(kind) dominates the upper screen")
        }
        let square = PlayerLayoutPolicy.nowPlayingArtwork(kind: .appIcon, region: region)
        XCTAssertEqual(square.width, square.height, accuracy: 0.001)
        XCTAssertEqual(square.width, region.width, accuracy: 0.001)
    }

    func testShortRegionsShrinkTheArtworkInsteadOfOverflowing() {
        let short = CGSize(width: 342, height: 240)
        for kind in kinds {
            let frame = PlayerLayoutPolicy.nowPlayingArtwork(kind: kind, region: short)
            XCTAssertLessThanOrEqual(frame.height, short.height + 0.001)
            XCTAssertLessThanOrEqual(frame.width, short.width + 0.001)
        }
        XCTAssertEqual(PlayerLayoutPolicy.nowPlayingArtwork(kind: .poster, region: .zero), .zero)
        XCTAssertEqual(PlayerLayoutPolicy.nowPlayingArtwork(kind: .appIcon, region: CGSize(width: 300, height: -10)), .zero)
    }

    func testLandscapeArtworkFitsItsSquareRegion() {
        for page in [CGSize(width: 780, height: 360), CGSize(width: 870, height: 400), CGSize(width: 1100, height: 760)] {
            let split = PlayerLayoutPolicy.landscape(page: page, bottomClearance: 8)
            XCTAssertGreaterThan(split.artSide, 0)
            for kind in kinds {
                let frame = PlayerLayoutPolicy.nowPlayingArtwork(kind: kind, region: CGSize(width: split.artSide, height: split.artSide))
                XCTAssertLessThanOrEqual(max(frame.width, frame.height), split.artSide + 0.001, "\(kind) in \(page)")
            }
        }
    }

    func testTimelineClockStopsWhileHidden() {
        XCTAssertFalse(PlayerTimeline.isPaused(sceneActive: true, presented: true))
        XCTAssertTrue(PlayerTimeline.isPaused(sceneActive: true, presented: false), "no ticking behind the pages")
        XCTAssertTrue(PlayerTimeline.isPaused(sceneActive: false, presented: true), "no ticking in the background")
        XCTAssertTrue(PlayerTimeline.isPaused(sceneActive: false, presented: false))
    }

    func testTimelineFractionIsClamped() {
        XCTAssertEqual(PlayerTimeline.fraction(position: 30, total: 120), 0.25, accuracy: 0.0001)
        XCTAssertEqual(PlayerTimeline.fraction(position: -5, total: 120), 0)
        XCTAssertEqual(PlayerTimeline.fraction(position: 500, total: 120), 1)
        XCTAssertEqual(PlayerTimeline.fraction(position: 10, total: 0), 0)
        XCTAssertEqual(PlayerTimeline.fraction(position: .nan, total: 100), 0)
        XCTAssertEqual(PlayerTimeline.fraction(position: 10, total: .infinity), 0)
    }

    func testPausedArtworkEasesBackUnlessReduceMotion() {
        XCTAssertEqual(PlayerLayoutPolicy.artworkScale(isPlaying: true, reduceMotion: false), 1)
        XCTAssertLessThan(PlayerLayoutPolicy.artworkScale(isPlaying: false, reduceMotion: false), 1)
        XCTAssertGreaterThanOrEqual(PlayerLayoutPolicy.artworkScale(isPlaying: false, reduceMotion: false), 0.85, "restrained")
        XCTAssertEqual(PlayerLayoutPolicy.artworkScale(isPlaying: false, reduceMotion: true), 1)
    }

    func testSecondaryLineSkipsEmptyAndRepeatedParts() {
        XCTAssertEqual(PlayerTitlePolicy.secondaryLine(subtitle: "S1 E2", appName: "Nuvio", title: "Severance"), "S1 E2 \u{00B7} Nuvio")
        XCTAssertEqual(PlayerTitlePolicy.secondaryLine(subtitle: "", appName: "Nuvio", title: "Severance"), "Nuvio")
        XCTAssertEqual(PlayerTitlePolicy.secondaryLine(subtitle: "  ", appName: "YouTube", title: "YouTube"), "")
        XCTAssertEqual(PlayerTitlePolicy.secondaryLine(subtitle: "nuvio", appName: "Nuvio", title: "X"), "nuvio")
        XCTAssertEqual(PlayerTitlePolicy.secondaryLine(subtitle: "", appName: "", title: "X"), "")
    }

    func testTransportAndVolumeKeepFullTouchTargets() {
        XCTAssertGreaterThanOrEqual(PlayerLayoutPolicy.transportHeight, 44)
        XCTAssertGreaterThan(PlayerLayoutPolicy.playGlyph, PlayerLayoutPolicy.secondaryGlyph, "play is primary")
        XCTAssertGreaterThanOrEqual(ThinVolumeMetrics.controlHeight(ThinVolumeMetrics.minimumTouchTarget), 44)
        XCTAssertLessThanOrEqual(PlayerLayoutPolicy.timelineHeight, 6, "thin timeline")
    }

    func testFallbackBackgroundIsOneRestrainedFullScreenWash() {
        for adaptive in [true, false] {
            let opacity = PlayerBackdropPolicy.fallbackOpacity(adaptive: adaptive)
            XCTAssertGreaterThan(opacity.top, opacity.bottom, "light from the top, calm under the controls")
            XCTAssertLessThanOrEqual(opacity.top, 0.4, "restrained: ink stays legible")
            XCTAssertGreaterThan(opacity.bottom, 0, "continuous to the bottom edge")
        }
        XCTAssertGreaterThan(PlayerBackdropPolicy.fallbackOpacity(adaptive: true).top,
                             PlayerBackdropPolicy.fallbackOpacity(adaptive: false).top)
    }

    /// Source guard: no radial glow and no live blur on the page, and the clock can pause.
    func testNowPlayingHasNoRadialGlowOrPerTickBlur() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let page = try? String(contentsOf: repo.appendingPathComponent("GlassRemote/PlayerPage.swift"), encoding: .utf8) else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        XCTAssertFalse(page.contains("RadialGradient"), "one continuous background, not a small radial glow")
        XCTAssertFalse(page.contains(".blur("), "no blur work on the page (it redraws with the clock)")
        XCTAssertTrue(page.contains("paused: paused"), "the timeline clock pauses while hidden")
        XCTAssertFalse(page.contains("glassBar("), "plain transport glyphs, no glass bar")
    }
}
