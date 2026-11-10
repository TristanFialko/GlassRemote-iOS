import XCTest
import CoreGraphics
@testable import GlassRemote

/// Phase 7.3: hero swipe and pager exclusion policies.
final class Phase73GestureTests: XCTestCase {
    func testLeftSwipeShowsTheNextTitle() {
        XCTAssertEqual(HeroSwipePolicy.step(translation: CGSize(width: -80, height: 6), predicted: CGSize(width: -120, height: 6)), 1)
    }

    func testRightSwipeShowsThePreviousTitle() {
        XCTAssertEqual(HeroSwipePolicy.step(translation: CGSize(width: 80, height: -4), predicted: CGSize(width: 90, height: 0)), -1)
    }

    func testVerticalScrollIsNeverAHeroSwipe() {
        XCTAssertNil(HeroSwipePolicy.step(translation: CGSize(width: 40, height: 160), predicted: CGSize(width: 60, height: 400)))
        XCTAssertNil(HeroSwipePolicy.step(translation: CGSize(width: 70, height: 60), predicted: CGSize(width: 90, height: 80)))
    }

    func testShortDragDoesNothingButAFlickCounts() {
        XCTAssertNil(HeroSwipePolicy.step(translation: CGSize(width: -30, height: 0), predicted: CGSize(width: -35, height: 0)))
        XCTAssertEqual(HeroSwipePolicy.step(translation: CGSize(width: -30, height: 0), predicted: CGSize(width: -140, height: 0)), 1)
    }

    func testFlickBackUsesTheFingerNotThePrediction() {
        XCTAssertNil(HeroSwipePolicy.step(translation: CGSize(width: -40, height: 0), predicted: CGSize(width: 120, height: 0)))
    }

    func testTextFollowIsResisted() {
        XCTAssertEqual(HeroSwipePolicy.follow(100), 35, accuracy: 0.001)
        XCTAssertEqual(HeroSwipePolicy.follow(-1000), -HeroSwipePolicy.maxFollow)
        XCTAssertEqual(HeroSwipePolicy.follow(0), 0)
    }

    func testOffscreenAndEmptyZonesAreIgnored() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let onScreen = CGRect(x: 0, y: 120, width: 390, height: 420)          // the hero
        let nextPage = CGRect(x: 390 + 40, y: 600, width: 300, height: 40)    // Remote's selector, one page over
        let empty = CGRect(x: 20, y: 20, width: 0, height: 30)
        XCTAssertEqual(PagerGesturePolicy.visibleZones([onScreen, nextPage, empty, .null], in: screen), [onScreen])
    }

    func testAZoneOnAnotherPageDoesNotBlockPaging() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let other = CGRect(x: -390 + 40, y: 600, width: 300, height: 40)
        let zones = PagerGesturePolicy.visibleZones([other], in: screen)
        XCTAssertFalse(PagerGesturePolicy.inExcludedZone(CGPoint(x: 100, y: 620), zones: zones))
    }

    func testHeroZoneBlocksPagingOnlyOnTheHero() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let zones = PagerGesturePolicy.visibleZones([CGRect(x: 0, y: -40, width: 390, height: 460)], in: screen)
        XCTAssertTrue(PagerGesturePolicy.inExcludedZone(CGPoint(x: 200, y: 300), zones: zones))
        XCTAssertFalse(PagerGesturePolicy.inExcludedZone(CGPoint(x: 200, y: 600), zones: zones), "rows below still page")
    }
}
