import XCTest
import SwiftUI
@testable import GlassRemote

/// Phase 6: landscape layout, the page rail, page depth and the glass selector geometry. All pure:
/// nothing here touches ADB, the HID helpers or the Samsung socket.
final class Phase6Tests: XCTestCase {
    @MainActor func testOrientationComesFromTheSizeClassNotTheGeometry() {
        XCTAssertTrue(LayoutContext.resolve(verticalSizeClass: .compact, size: CGSize(width: 852, height: 393)).isLandscape)
        XCTAssertFalse(LayoutContext.resolve(verticalSizeClass: .regular, size: CGSize(width: 393, height: 852)).isLandscape)
        // The keyboard shrinks the page in portrait; that must never switch to the landscape layout.
        XCTAssertFalse(LayoutContext.resolve(verticalSizeClass: .regular, size: CGSize(width: 393, height: 300)).isLandscape)
        // No size class (previews, tests): fall back to the aspect ratio.
        XCTAssertTrue(LayoutContext.resolve(verticalSizeClass: nil, size: CGSize(width: 852, height: 393)).isLandscape)
        XCTAssertFalse(LayoutContext.resolve(verticalSizeClass: nil, size: CGSize(width: 393, height: 852)).isLandscape)
    }

    @MainActor func testRailMetrics() {
        XCTAssertEqual(DockMetrics.railLength(count: 3), 3 * 62 + 12, accuracy: 0.001)
        XCTAssertEqual(DockMetrics.railDrop(safeLeading: 0), 0, accuracy: 0.001)
        XCTAssertEqual(DockMetrics.railDrop(safeLeading: 59), 11.8, accuracy: 0.001)
        XCTAssertEqual(DockMetrics.railDrop(safeLeading: 200), 12, accuracy: 0.001)
        // Pages clear the rail, and the rail's touch zone covers all of it.
        let safe: CGFloat = 59
        let railTrailingEdge = safe + DockMetrics.railGap - DockMetrics.railDrop(safeLeading: safe) + DockMetrics.railWidth
        XCTAssertGreaterThan(safe + DockMetrics.railClearance(safeLeading: safe), railTrailingEdge)
        XCTAssertGreaterThan(DockMetrics.railZone(safeLeading: safe), railTrailingEdge)
        XCTAssertGreaterThan(DockMetrics.railZone(safeLeading: 0), DockMetrics.railWidth)
    }

    @MainActor func testRailTouchesNeverStartAPageSwipe() {
        XCTAssertTrue(PagerGesturePolicy.inRail(x: 40, width: 852, railZone: 130, rightToLeft: false))
        XCTAssertFalse(PagerGesturePolicy.inRail(x: 400, width: 852, railZone: 130, rightToLeft: false))
        XCTAssertTrue(PagerGesturePolicy.inRail(x: 820, width: 852, railZone: 130, rightToLeft: true))
        XCTAssertFalse(PagerGesturePolicy.inRail(x: 40, width: 852, railZone: 130, rightToLeft: true))
        // Portrait: no rail.
        XCTAssertFalse(PagerGesturePolicy.inRail(x: 10, width: 393, railZone: 0, rightToLeft: false))
    }

    @MainActor func testPageDepth() {
        let pages = AppPage.allCases
        XCTAssertGreaterThanOrEqual(pages.count, 2)
        let a = pages[0], b = pages[1]
        let delta = CGFloat(b.rawValue - a.rawValue)
        XCTAssertEqual(PageDepth.distance(of: a, current: a, travel: 0, width: 400), 0, accuracy: 0.0001)
        XCTAssertEqual(PageDepth.distance(of: b, current: a, travel: 0, width: 400), 1, accuracy: 0.0001)
        // Halfway through a swipe towards `b`, both pages are half a page from the centre.
        XCTAssertEqual(PageDepth.distance(of: b, current: a, travel: -200 * delta, width: 400), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PageDepth.distance(of: a, current: a, travel: -200 * delta, width: 400), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PageDepth.scale(0, reduceMotion: false), 1, accuracy: 0.0001)
        XCTAssertLessThan(PageDepth.scale(1, reduceMotion: false), 1)
        XCTAssertEqual(PageDepth.scale(1, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(PageDepth.opacity(1, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(PageDepth.opacity(0, reduceMotion: false), 1, accuracy: 0.0001)
    }

    @MainActor func testScrubGeometry() {
        let seg = ScrubGeometry.segment(length: 300, inset: 6, count: 3)
        XCTAssertEqual(seg, 96, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.clamp(-50, inset: 6, length: 300, segment: seg), 6, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.clamp(500, inset: 6, length: 300, segment: seg), 300 - 6 - seg, accuracy: 0.001)
        // Selection flips exactly as the bubble's centre crosses a midpoint.
        XCTAssertEqual(ScrubGeometry.index(forOffset: 6, inset: 6, segment: seg, count: 3), 0)
        XCTAssertEqual(ScrubGeometry.index(forOffset: 6 + seg * 0.49, inset: 6, segment: seg, count: 3), 0)
        XCTAssertEqual(ScrubGeometry.index(forOffset: 6 + seg * 0.51, inset: 6, segment: seg, count: 3), 1)
        XCTAssertEqual(ScrubGeometry.index(forOffset: 1000, inset: 6, segment: seg, count: 3), 2)
        XCTAssertEqual(ScrubGeometry.index(forOffset: -1000, inset: 6, segment: seg, count: 3), 0)
        XCTAssertEqual(ScrubGeometry.progress(offset: 6, inset: 6, length: 300, segment: seg), 0, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.progress(offset: 300 - 6 - seg, inset: 6, length: 300, segment: seg), 1, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.stretch(speed: 0), 1, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.stretch(speed: -100_000), 1.16, accuracy: 0.001)
        // Phase 7: no magnification; the dock reflection follows the bubble, travelling less than it.
        XCTAssertEqual(ScrubGeometry.sheenCentre(progress: 0), 0.12, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.sheenCentre(progress: 1), 0.88, accuracy: 0.001)
        XCTAssertEqual(ScrubGeometry.sheenCentre(progress: 5), 0.88, accuracy: 0.001)
        // The vertical rail uses the same maths along its length.
        let railSeg = ScrubGeometry.segment(length: DockMetrics.railLength(count: 3), inset: DockMetrics.railInset, count: 3)
        XCTAssertEqual(railSeg, DockMetrics.railSegment, accuracy: 0.001)
    }

    @MainActor func testRemoteLandscapeLayoutKeepsAFullHeightPadBesideTheControls() {
        let heights: [CGFloat] = [36, 38, 46, 32, 48, 44]
        let bottom = [false, false, false, false, true, true]
        let f = RemoteLandscapeLayout.frames(width: 700, height: 360, heights: heights, bottom: bottom, hasPad: true,
                                             spacing: 6, columnSpacing: 14, maxColumnWidth: 340,
                                             padMinHeight: 200, padMaxHeight: nil)
        let column = RemoteLandscapeLayout.columnWidth(for: 700, maxColumnWidth: 340)
        XCTAssertEqual(column, 322, accuracy: 0.001)
        XCTAssertEqual(f.column[0].minY, 0, accuracy: 0.001)
        XCTAssertEqual(f.column[1].minY, 42, accuracy: 0.001)
        XCTAssertEqual(f.column[5].maxY, 360, accuracy: 0.001)
        XCTAssertEqual(f.column[4].maxY, 360 - 44 - 6, accuracy: 0.001)
        XCTAssertEqual(f.pad?.minX ?? -1, column + 14, accuracy: 0.001)
        XCTAssertEqual(f.pad?.maxX ?? -1, 700, accuracy: 0.001)
        XCTAssertEqual(f.pad?.height ?? -1, 360, accuracy: 0.001)
        XCTAssertEqual(f.size, CGSize(width: 700, height: 360))
        // Nothing overlaps in the column.
        let sorted = f.column.sorted { $0.minY < $1.minY }
        for (upper, lower) in zip(sorted, sorted.dropFirst()) { XCTAssertLessThanOrEqual(upper.maxY, lower.minY + 0.001) }
        // Wide screens cap the column so the pad gets the rest.
        XCTAssertEqual(RemoteLandscapeLayout.columnWidth(for: 1000, maxColumnWidth: 340), 340, accuracy: 0.001)
    }

    @MainActor func testRemoteLandscapeLayoutWhileScrolling() {
        // The Apps grid is expanded: the page scrolls, the column keeps its natural height, the pad is capped.
        let heights: [CGFloat] = [36, 38, 400, 32, 48, 44]
        let bottom = [false, false, false, false, true, true]
        let s = RemoteLandscapeLayout.frames(width: 700, height: nil, heights: heights, bottom: bottom, hasPad: true,
                                             spacing: 6, columnSpacing: 14, maxColumnWidth: 340,
                                             padMinHeight: 200, padMaxHeight: 250)
        XCTAssertEqual(s.size.height, heights.reduce(0, +) + 5 * 6, accuracy: 0.001)
        XCTAssertEqual(s.pad?.height ?? -1, 250, accuracy: 0.001)
        // Without a pad the column takes the whole width (and nothing crashes).
        let noPad = RemoteLandscapeLayout.frames(width: 500, height: 300, heights: [40], bottom: [false], hasPad: false,
                                                 spacing: 6, columnSpacing: 14, maxColumnWidth: 340,
                                                 padMinHeight: 200, padMaxHeight: nil)
        XCTAssertNil(noPad.pad)
        XCTAssertEqual(noPad.column[0].width, 500, accuracy: 0.001)
    }
}
