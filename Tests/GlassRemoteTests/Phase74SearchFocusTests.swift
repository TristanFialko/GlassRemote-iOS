import XCTest
import CoreGraphics
@testable import GlassRemote

/// Phase 7.4: the Remote's Search shortcut focus request, and header vs hero taps.
final class Phase74SearchFocusTests: XCTestCase {
    private func ready(_ p: inout SearchFocusPolicy) { p.setFieldMounted(true) }

    func testFocusWaitsForTheSlideToFinish() {
        var p = SearchFocusPolicy(page: .remote); ready(&p)
        p.request(); p.pageChanged(to: .discover)
        XCTAssertFalse(p.consumeIfReady(), "no keyboard while the page is still sliding")
        p.pageSettled(.discover)
        XCTAssertTrue(p.consumeIfReady())
        XCTAssertFalse(p.consumeIfReady(), "one focus per request")
    }

    func testAlreadyOnDiscoverFocusesImmediately() {
        var p = SearchFocusPolicy(page: .discover); ready(&p)
        p.pageSettled(.discover)
        p.request()
        XCTAssertTrue(p.consumeIfReady())
    }

    func testRepeatedTapsMakeOneFocus() {
        var p = SearchFocusPolicy(page: .remote); ready(&p)
        p.request(); p.request(); p.pageChanged(to: .discover); p.request()
        p.pageSettled(.discover)
        XCTAssertTrue(p.consumeIfReady())
        XCTAssertFalse(p.consumeIfReady())
    }

    func testNavigatingAwayCancelsTheRequest() {
        var p = SearchFocusPolicy(page: .remote); ready(&p)
        p.request(); p.pageChanged(to: .discover)
        p.pageChanged(to: .profile)                       // user swiped on before arrival
        p.pageSettled(.profile)
        p.pageChanged(to: .discover); p.pageSettled(.discover)
        XCTAssertFalse(p.consumeIfReady(), "a stale request never steals focus later")
    }

    func testStaleSettleReportIsIgnored() {
        var p = SearchFocusPolicy(page: .remote); ready(&p)
        p.request(); p.pageChanged(to: .discover)
        p.pageSettled(.remote)                            // report for the old target
        XCTAssertFalse(p.consumeIfReady())
    }

    func testBackgroundCancelsAndForegroundDoesNotRevive() {
        var p = SearchFocusPolicy(page: .remote); ready(&p)
        p.request(); p.pageChanged(to: .discover)
        p.setSceneActive(false)
        p.pageSettled(.discover)
        p.setSceneActive(true)
        XCTAssertFalse(p.consumeIfReady())
    }

    func testWaitsForTheFieldToMount() {
        var p = SearchFocusPolicy(page: .remote)
        p.request(); p.pageChanged(to: .discover); p.pageSettled(.discover)
        XCTAssertFalse(p.consumeIfReady())
        p.setFieldMounted(true)
        XCTAssertTrue(p.consumeIfReady())
    }

    func testSettleDetection() {
        XCTAssertTrue(PageSettlePolicy.isSettled(position: 2, target: 2))
        XCTAssertFalse(PageSettlePolicy.isSettled(position: 1.98, target: 2))
        XCTAssertFalse(PageSettlePolicy.isSettled(position: 2.02, target: 2), "spring overshoot is not settled")
    }

    func testTapsOnTheHeaderNeverOpenTheHero() {
        let headerBottom: CGFloat = 160
        XCTAssertFalse(DiscoverTouchPolicy.heroMayOpen(tapY: 100, headerBottom: headerBottom))
        XCTAssertFalse(DiscoverTouchPolicy.heroMayOpen(tapY: 164, headerBottom: headerBottom), "within slop")
        XCTAssertTrue(DiscoverTouchPolicy.heroMayOpen(tapY: 300, headerBottom: headerBottom))
    }

    func testHeaderZoneBlocksPagingFromTheSearchCapsule() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let header = CGRect(x: 0, y: 47, width: 390, height: 113)
        let zones = PagerGesturePolicy.visibleZones([header], in: screen)
        XCTAssertTrue(PagerGesturePolicy.inExcludedZone(CGPoint(x: 150, y: 80), zones: zones))
        XCTAssertFalse(PagerGesturePolicy.inExcludedZone(CGPoint(x: 150, y: 400), zones: zones))
    }
}
