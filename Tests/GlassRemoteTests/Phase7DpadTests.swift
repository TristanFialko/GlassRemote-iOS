import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 7 D-pad redesign: the keys still send the Phase 5 ADB names, and the new wedge hit areas give
/// every point on the ring to exactly one arrow.
final class Phase7DpadTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 200)

    private func owners(of point: CGPoint) -> [DpadKey] {
        DpadKey.arrows.filter { DpadWedge(angle: $0.angle, outer: 1.42).path(in: rect).contains(point) }
    }

    func testKeysSendTheSameNamesAsBefore() {
        XCTAssertEqual(DpadKey.allCases.map(\.rawValue), ["UP", "RIGHT", "DOWN", "LEFT", "OK"])
        XCTAssertEqual(DpadKey.arrows.map(\.label), ["Up", "Right", "Down", "Left"])
        XCTAssertEqual(DpadKey.ok.label, "Select")
        XCTAssertEqual(DpadKey.ok.vector, .zero)
    }

    func testCardinalPointsBelongToTheirArrow() {
        XCTAssertEqual(owners(of: CGPoint(x: 100, y: 8)), [.up])
        XCTAssertEqual(owners(of: CGPoint(x: 192, y: 100)), [.right])
        XCTAssertEqual(owners(of: CGPoint(x: 100, y: 192)), [.down])
        XCTAssertEqual(owners(of: CGPoint(x: 8, y: 100)), [.left])
    }

    func testNearDiagonalsAndCornersGoToTheClosestArrow() {
        XCTAssertEqual(owners(of: CGPoint(x: 150, y: 40)), [.up])      // -50°
        XCTAssertEqual(owners(of: CGPoint(x: 160, y: 60)), [.right])   // -34°
        XCTAssertEqual(owners(of: CGPoint(x: 60, y: 170)), [.down])    // 120°
        XCTAssertEqual(owners(of: CGPoint(x: 40, y: 150)), [.left])    // 140°, nearer left than down
        XCTAssertEqual(owners(of: CGPoint(x: 195, y: 160)), [.right])  // outside the disc, still reachable
        XCTAssertEqual(owners(of: CGPoint(x: 5, y: 40)), [.left])
    }

    func testHighlightWedgeLeavesTheCentreToOK() {
        let wedge = DpadWedge(angle: DpadKey.up.angle, inner: 0.5, outer: 0.97).path(in: rect)
        XCTAssertFalse(wedge.contains(CGPoint(x: 100, y: 80)))
        XCTAssertTrue(wedge.contains(CGPoint(x: 100, y: 20)))
        XCTAssertFalse(wedge.contains(CGPoint(x: 180, y: 100)))
    }

    func testProportionsNest() {
        XCTAssertLessThan(GlassDpad.Metrics.pebble, GlassDpad.Metrics.okHit)
        XCTAssertLessThan(GlassDpad.Metrics.okHit, GlassDpad.Metrics.groove)
        XCTAssertGreaterThan(GlassDpad.Metrics.glyphRadius, GlassDpad.Metrics.groove / 2)
        XCTAssertLessThan(GlassDpad.Metrics.glyphRadius, 0.5)
    }
}
