import CoreGraphics
import XCTest
@testable import GlassRemote

/// Continuation §D: the retained axis maths and gesture-ownership helpers, and the Remote's swipe
/// areas. v5 §2 removed page swiping (the dock and rail switch pages), so the swipe-target tests are gone.
final class Phase9NavigationTests: XCTestCase {

    // MARK: Axis

    func testPortraitStaysHorizontalAndLandscapeRunsVertically() {
        XCTAssertEqual(PagerAxis.resolve(isLandscape: false), .horizontal)
        XCTAssertEqual(PagerAxis.resolve(isLandscape: true), .vertical)
        XCTAssertEqual(AppPage.allCases, [.remote, .discover, .profile], "one page order for both axes")
    }

    func testPortraitStripIsTheOldFormula() {
        // Portrait (and right-to-left portrait, which mirrors the same HStack) keeps the pre-§D offset.
        let width: CGFloat = 393
        for page in AppPage.allCases {
            for travel in [-120, 0, 80] as [CGFloat] {
                let offset = PagerAxis.horizontal.stripOffset(page: page, travel: travel, stride: width)
                XCTAssertEqual(offset.width, -CGFloat(page.rawValue) * width + travel)
                XCTAssertEqual(offset.height, 0)
            }
        }
        XCTAssertEqual(PagerAxis.pageStride(.horizontal, size: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34), 393)
        XCTAssertEqual(PagerAxis.pageGap(.horizontal, safeTop: 59, safeBottom: 34), 0)
        XCTAssertEqual(PagerAxis.horizontal.component(CGPoint(x: -40, y: 300)), -40)
        XCTAssertEqual(PagerAxis.horizontal.stripOffset(page: .discover, travel: 0, stride: 393), CGSize(width: -393, height: 0))
    }

    func testLandscapeStacksPagesTopToBottom() {
        let size = CGSize(width: 852, height: 372)
        let stride = PagerAxis.pageStride(.vertical, size: size, safeTop: 0, safeBottom: 21)
        XCTAssertEqual(stride, 393, "a whole screen per page, home-indicator zone included")
        XCTAssertEqual(PagerAxis.pageGap(.vertical, safeTop: 0, safeBottom: 21), 21)
        XCTAssertEqual(PagerAxis.vertical.stripOffset(page: .discover, travel: -50, stride: 400), CGSize(width: 0, height: -450))
        XCTAssertEqual(PagerAxis.vertical.stripOffset(page: .remote, travel: 0, stride: stride), .zero, "Remote is at the top")
        XCTAssertEqual(PagerAxis.vertical.stripOffset(page: .profile, travel: 0, stride: stride).height, -2 * stride, "Profile at the bottom")
        XCTAssertEqual(PagerAxis.vertical.component(CGPoint(x: -40, y: 300)), 300)
    }

    func testNeighboursNeverShowInTheSafeAreas() {
        let size = CGSize(width: 852, height: 372)
        let frame = CGRect(origin: .zero, size: size)
        for (top, bottom) in [(0, 21), (24, 20), (0, 0)] as [(CGFloat, CGFloat)] {
            let clip = PagerAxis.clipRect(.vertical, in: frame, safeTop: top, safeBottom: bottom)
            let stride = PagerAxis.pageStride(.vertical, size: size, safeTop: top, safeBottom: bottom)
            XCTAssertEqual(clip.minY, -top)
            XCTAssertEqual(clip.maxY, size.height + bottom)
            // The next page, even drawn up into its own top safe area, starts at or below the clip's foot;
            // the previous page, drawn down into its bottom safe area, ends at or above the clip's top.
            XCTAssertGreaterThanOrEqual(stride - top, clip.maxY - 0.001)
            XCTAssertLessThanOrEqual(-stride + size.height + bottom, clip.minY + 0.001)
            XCTAssertTrue(clip.contains(CGPoint(x: -1_500, y: 10)), "content may still run sideways under the rail")
        }
        let portrait = PagerAxis.clipRect(.horizontal, in: CGRect(x: 0, y: 0, width: 393, height: 852), safeTop: 59, safeBottom: 34)
        XCTAssertEqual(portrait.minX, 0)
        XCTAssertEqual(portrait.maxX, 393)
        XCTAssertLessThan(portrait.minY, -59, "Discover's hero still runs under the status bar")
    }

    // MARK: Gestures

    func testOnlyAClearlyVerticalDragPagesInLandscape() {
        XCTAssertTrue(PagerAxis.vertical.isDominant(dx: 2, dy: -20))
        XCTAssertTrue(PagerAxis.vertical.isDominant(dx: -6, dy: 14))
        XCTAssertFalse(PagerAxis.vertical.isDominant(dx: 10, dy: 12), "a diagonal drag stays with the page")
        XCTAssertFalse(PagerAxis.vertical.isDominant(dx: 30, dy: 4), "a carousel drag is never a page swipe")
        XCTAssertTrue(PagerAxis.horizontal.isDominant(dx: 30, dy: 4), "portrait rule unchanged")
        XCTAssertFalse(PagerAxis.horizontal.isDominant(dx: 2, dy: -20))
    }

    func testLandscapeRemotePagesOnlyFromItsFreeColumnSpace() {
        let size = CGSize(width: 852, height: 393)
        let areas = [CGRect(x: 120, y: 160, width: 219, height: 116), CGRect(x: 640, y: 130, width: 190, height: 140)]
        func accepts(_ page: AppPage, _ point: CGPoint, _ zones: [CGRect]) -> Bool {
            PagerGesturePolicy.acceptsTouch(on: page, at: point, in: size, edgeWidth: 16, axis: .vertical, swipeAreas: zones)
        }
        XCTAssertTrue(accepts(.remote, CGPoint(x: 200, y: 200), areas))
        XCTAssertTrue(accepts(.remote, CGPoint(x: 700, y: 150), areas))
        XCTAssertFalse(accepts(.remote, CGPoint(x: 420, y: 200), areas), "the pad keeps its touches")
        XCTAssertFalse(accepts(.remote, CGPoint(x: 5, y: 200), areas), "no portrait edge strips in landscape")
        XCTAssertFalse(accepts(.remote, CGPoint(x: 200, y: 200), []), "folder open: no swipe areas")
        for page in [AppPage.discover, .profile] {
            XCTAssertTrue(accepts(page, CGPoint(x: 420, y: 200), []))
        }
        // Portrait is unchanged: edge strips only, and swipe areas are ignored.
        let portrait = CGSize(width: 393, height: 852)
        XCTAssertTrue(PagerGesturePolicy.acceptsTouch(on: .remote, at: CGPoint(x: 5, y: 400), in: portrait, edgeWidth: 16, axis: .horizontal, swipeAreas: areas))
        XCTAssertFalse(PagerGesturePolicy.acceptsTouch(on: .remote, at: CGPoint(x: 200, y: 200), in: portrait, edgeWidth: 16, axis: .horizontal, swipeAreas: areas))
        XCTAssertEqual(PagerGesturePolicy.acceptsTouch(on: .remote, at: CGPoint(x: 5, y: 0), in: portrait, edgeWidth: 16, axis: .horizontal, swipeAreas: []),
                       PagerGesturePolicy.acceptsTouch(on: .remote, x: 5, width: 393, edgeWidth: 16))
    }

    func testRailTapsStayTheRails() {
        XCTAssertTrue(PagerGesturePolicy.inRail(x: 40, width: 852, railZone: DockMetrics.railZone(safeLeading: 59), rightToLeft: false))
    }

    func testVerticalSwipesNeverStealDiscoverScrolling() {
        func yields(_ dy: CGFloat, at offset: CGFloat, insetTop: CGFloat = 0, insetBottom: CGFloat = 0) -> Bool {
            PagerGesturePolicy.scrollerYieldsVerticalPage(dy: dy, offsetY: offset, contentHeight: 2_000, boundsHeight: 393,
                                                          insetTop: insetTop, insetBottom: insetBottom)
        }
        XCTAssertTrue(yields(20, at: 0), "pulling down at the top goes to the page above")
        XCTAssertFalse(yields(-20, at: 0), "pushing up at the top scrolls Discover")
        XCTAssertFalse(yields(20, at: 600))
        XCTAssertFalse(yields(-20, at: 600), "mid-scroll the scroll view owns both directions")
        XCTAssertTrue(yields(-20, at: 1_607), "pushing up at the end goes to the page below")
        XCTAssertFalse(yields(20, at: 1_607), "pulling down at the end scrolls back")
        XCTAssertTrue(yields(20, at: -24, insetTop: 24))
        XCTAssertFalse(yields(20, at: -10, insetTop: 24))
        XCTAssertTrue(yields(-20, at: 1_627, insetBottom: 20))
        XCTAssertFalse(yields(-20, at: 1_607, insetBottom: 20))
        XCTAssertFalse(yields(0, at: 0))
    }

    func testOnlyRealVerticalScrollersAreConsulted() {
        XCTAssertTrue(PagerGesturePolicy.isVerticalScroller(contentHeight: 2_000, boundsHeight: 393, insetTop: 0, insetBottom: 0, scrollEnabled: true))
        XCTAssertFalse(PagerGesturePolicy.isVerticalScroller(contentHeight: 210, boundsHeight: 210, insetTop: 0, insetBottom: 0, scrollEnabled: true),
                       "a carousel has no vertical range")
        XCTAssertFalse(PagerGesturePolicy.isVerticalScroller(contentHeight: 300, boundsHeight: 393, insetTop: 0, insetBottom: 0, scrollEnabled: true))
        XCTAssertFalse(PagerGesturePolicy.isVerticalScroller(contentHeight: 2_000, boundsHeight: 393, insetTop: 0, insetBottom: 0, scrollEnabled: false))
        XCTAssertTrue(PagerGesturePolicy.isVerticalScroller(contentHeight: 380, boundsHeight: 393, insetTop: 24, insetBottom: 0, scrollEnabled: true))
    }

    func testRotationMidSwipeCancelsTheSwipe() {
        XCTAssertTrue(PagerGesturePolicy.cancelsOnAxisChange(active: true, from: .horizontal, to: .vertical))
        XCTAssertTrue(PagerGesturePolicy.cancelsOnAxisChange(active: true, from: .vertical, to: .horizontal))
        XCTAssertFalse(PagerGesturePolicy.cancelsOnAxisChange(active: false, from: .horizontal, to: .vertical))
        XCTAssertFalse(PagerGesturePolicy.cancelsOnAxisChange(active: true, from: .vertical, to: .vertical))
    }

    // MARK: Remote swipe areas

    private func androidStage(width: CGFloat, height: CGFloat) -> RemoteStageLayout.Frames {
        RemoteStageLayout.frames(width: width, height: height,
                                 leading: [96, 40, 58], leadingBottom: [false, false, true],
                                 trailing: [114], trailingBottom: [false],
                                 hasPad: true, spacing: 10, columnSpacing: 14, reservesColumns: true, deck: true)
    }

    private func samsungStage(width: CGFloat, height: CGFloat) -> RemoteStageLayout.Frames {
        RemoteStageLayout.frames(width: width, height: height,
                                 leading: [96, 52], leadingBottom: [false, true],
                                 trailing: [52, 52], trailingBottom: [false, true],
                                 hasPad: true, spacing: 10, columnSpacing: 14, reservesColumns: true, deck: true)
    }

    private func assertClearOfControls(_ frames: RemoteStageLayout.Frames, file: StaticString = #filePath, line: UInt = #line) throws {
        let leadingGap = try XCTUnwrap(frames.leadingGap, file: file, line: line)
        let trailingGap = try XCTUnwrap(frames.trailingGap, file: file, line: line)
        var controls = frames.leading + frames.trailing
        if let pad = frames.pad { controls.append(pad) }
        if let deck = frames.deck { controls.append(deck) }
        for rect in controls {
            XCTAssertFalse(rect.intersects(leadingGap), "\(rect) overlaps the leading swipe area", file: file, line: line)
            XCTAssertFalse(rect.intersects(trailingGap), "\(rect) overlaps the trailing swipe area", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(leadingGap.height, RemoteStageLayout.swipeAreaMinHeight, file: file, line: line)
        XCTAssertGreaterThanOrEqual(trailingGap.height, RemoteStageLayout.swipeAreaMinHeight, file: file, line: line)
    }

    func testAndroidStageOffersItsFreeColumnSpace() throws {
        for width in [568, 700, 812, 932] as [CGFloat] {
            for height in [300, 340, 380] as [CGFloat] {
                let frames = androidStage(width: width, height: height)
                try assertClearOfControls(frames)
                let leadingGap = try XCTUnwrap(frames.leadingGap)
                let trailingGap = try XCTUnwrap(frames.trailingGap)
                let deck = try XCTUnwrap(frames.deck)
                XCTAssertEqual(leadingGap.minY, frames.leading[1].maxY + 10, accuracy: 0.5)
                XCTAssertEqual(leadingGap.maxY, frames.leading[2].minY - 10, accuracy: 0.5)
                XCTAssertEqual(leadingGap.minX, frames.leading[0].minX, accuracy: 0.5)
                XCTAssertEqual(leadingGap.width, frames.leading[0].width, accuracy: 0.5)
                XCTAssertEqual(trailingGap.minY, frames.trailing[0].maxY + 10, accuracy: 0.5)
                XCTAssertEqual(trailingGap.maxY + 10, deck.minY, accuracy: 0.5)
            }
        }
    }

    func testSamsungStageOffersItsFreeColumnSpace() throws {
        for width in [568, 812, 932] as [CGFloat] {
            let frames = samsungStage(width: width, height: 340)
            try assertClearOfControls(frames)
            let leadingGap = try XCTUnwrap(frames.leadingGap)
            let trailingGap = try XCTUnwrap(frames.trailingGap)
            XCTAssertEqual(leadingGap.minY, frames.leading[0].maxY + 10, accuracy: 0.5)
            XCTAssertEqual(leadingGap.maxY, frames.leading[1].minY - 10, accuracy: 0.5)
            XCTAssertEqual(trailingGap.minY, frames.trailing[0].maxY + 10, accuracy: 0.5)
            XCTAssertEqual(trailingGap.maxY, frames.trailing[1].minY - 10, accuracy: 0.5)
        }
    }

    func testTooShortColumnsOfferNoSwipeArea() {
        let frames = androidStage(width: 812, height: 200)
        XCTAssertNil(frames.leadingGap)
        XCTAssertNil(frames.trailingGap)
    }
}
