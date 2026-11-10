import XCTest
import SwiftUI
@testable import GlassRemote

// Phase 7.1: gesture and input fixes (pure geometry and policy; the touches themselves need a device).
final class Phase71GestureTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 300, height: 300)

    func testDpadQuadrantsStayInsideThePad() {
        for key in DpadKey.arrows {
            let bounds = DpadQuadrant(angle: key.angle).path(in: rect).boundingRect
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(key) reaches outside the pad")
        }
    }

    func testTouchAboveThePadNeverPressesUp() {
        let up = DpadQuadrant(angle: DpadKey.up.angle).path(in: rect)
        XCTAssertFalse(up.contains(CGPoint(x: 150, y: -10)))   // where the Mouse / D-pad selector sits
        XCTAssertFalse(up.contains(CGPoint(x: 150, y: -60)))
        XCTAssertTrue(up.contains(CGPoint(x: 150, y: 10)))
    }

    func testEdgesGoToTheNearestArrow() {
        let point = CGPoint(x: 290, y: 110)   // right edge, a little above the middle
        XCTAssertTrue(DpadQuadrant(angle: DpadKey.right.angle).path(in: rect).contains(point))
        XCTAssertFalse(DpadQuadrant(angle: DpadKey.up.angle).path(in: rect).contains(point))
    }

    func testEveryPointOnThePadBelongsToAnArrow() {
        let paths = DpadKey.arrows.map { DpadQuadrant(angle: $0.angle).path(in: rect) }
        for x in stride(from: 5.0, to: 300.0, by: 37.0) {
            for y in stride(from: 5.0, to: 300.0, by: 41.0) {
                let p = CGPoint(x: x, y: y)
                XCTAssertTrue(paths.contains { $0.contains(p) }, "\(p) is not on any arrow")
            }
        }
    }

    func testModeSwitchBlocksTheDpadBriefly() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(RemoteInputGuard.blocks(now: t0.addingTimeInterval(0.1), modeChangedAt: t0, scrubActive: false))
        XCTAssertFalse(RemoteInputGuard.blocks(now: t0.addingTimeInterval(0.5), modeChangedAt: t0, scrubActive: false))
        XCTAssertTrue(RemoteInputGuard.blocks(now: t0.addingTimeInterval(5), modeChangedAt: t0, scrubActive: true))
        XCTAssertFalse(RemoteInputGuard.blocks(now: t0, modeChangedAt: .distantPast, scrubActive: false))
    }

    func testPagerIgnoresTouchesOnSelectors() {
        let filter = CGRect(x: 16, y: 120, width: 343, height: 36)
        XCTAssertTrue(PagerGesturePolicy.inExcludedZone(CGPoint(x: 200, y: 138), zones: [filter]))
        XCTAssertTrue(PagerGesturePolicy.inExcludedZone(CGPoint(x: 200, y: 160), zones: [filter]))   // within the slop
        XCTAssertFalse(PagerGesturePolicy.inExcludedZone(CGPoint(x: 200, y: 300), zones: [filter]))
        XCTAssertFalse(PagerGesturePolicy.inExcludedZone(CGPoint(x: 200, y: 138), zones: []))
    }
}
