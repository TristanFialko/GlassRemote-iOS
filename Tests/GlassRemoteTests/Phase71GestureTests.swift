import XCTest
import SwiftUI
@testable import GlassRemote

// Phase 7.1 / 7.2: gesture and input fixes (pure geometry and policy; the touches themselves need a device).
final class Phase71GestureTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
    private var centre: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    private var radius: CGFloat { rect.width / 2 }

    /// The hit shape GlassDpad gives each arrow.
    private func sector(_ key: DpadKey, in rect: CGRect? = nil) -> Path {
        DpadWedge(angle: key.angle, inner: 0, outer: 1).path(in: rect ?? self.rect)
    }

    private func owners(of point: CGPoint) -> [DpadKey] {
        DpadKey.arrows.filter { sector($0).contains(point) }
    }

    private func onPad(_ r: CGFloat, _ degrees: Double) -> CGPoint {
        DpadGeometry.point(centre, r, degrees)
    }

    func testArrowHitAreasStayInsideThePad() {
        for key in DpadKey.arrows {
            let bounds = sector(key).boundingRect
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(key) reaches outside the pad")
        }
    }

    func testTouchAboveThePadNeverPressesUp() {
        for point in [CGPoint(x: 150, y: -10), CGPoint(x: 150, y: -60)] {   // where the Mouse / D-pad selector sits
            XCTAssertFalse(sector(.up).contains(point))
            XCTAssertNil(DpadHitPolicy.key(at: point, in: rect))
        }
        XCTAssertTrue(sector(.up).contains(CGPoint(x: 150, y: 10)))
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 150, y: 10), in: rect), .up)
    }

    func testEdgesGoToTheNearestArrow() {
        let point = CGPoint(x: 290, y: 110)   // right edge, a little above the middle
        XCTAssertEqual(DpadHitPolicy.key(at: point, in: rect), .right)
        XCTAssertEqual(owners(of: point), [.right])
    }

    /// Replaces the Phase 7.1 square-grid test, which sampled the corners outside the disc and points
    /// exactly on the diagonals. This samples the visible ring between OK and the rim.
    func testEveryPointOnTheVisibleRingBelongsToExactlyOneArrow() {
        let inner = radius * DpadHitPolicy.okRadius + 2
        for r in stride(from: inner, through: radius - 2, by: 9) {
            for degrees in stride(from: 0.0, to: 360.0, by: 4.0) {
                // Two sectors share an edge on the exact diagonals; DpadHitPolicy breaks that tie below.
                if abs(degrees.truncatingRemainder(dividingBy: 90) - 45) < 0.5 { continue }
                let point = onPad(r, degrees)
                let hits = owners(of: point)
                XCTAssertEqual(hits.count, 1, "\(point) is on \(hits.count) arrows")
                XCTAssertEqual(hits.first, DpadHitPolicy.key(at: point, in: rect), "\(point) shape and policy disagree")
            }
        }
    }

    func testCardinalDirectionsUseScreenCoordinates() {
        XCTAssertEqual(DpadHitPolicy.key(at: onPad(110, -90), in: rect), .up)      // +y is down
        XCTAssertEqual(DpadHitPolicy.key(at: onPad(110, 90), in: rect), .down)
        XCTAssertEqual(DpadHitPolicy.key(at: onPad(110, 0), in: rect), .right)
        XCTAssertEqual(DpadHitPolicy.key(at: onPad(110, 180), in: rect), .left)
    }

    func testCentreBelongsToOK() {
        let okEdge = radius * DpadHitPolicy.okRadius
        XCTAssertEqual(DpadHitPolicy.key(at: centre, in: rect), .ok)
        XCTAssertEqual(DpadHitPolicy.key(at: onPad(okEdge - 1, 30), in: rect), .ok)
        XCTAssertEqual(DpadHitPolicy.key(at: onPad(okEdge + 1, 30), in: rect), .right)
    }

    func testCornersOutsideTheDiscAreInactive() {
        for corner in [CGPoint(x: 5, y: 5), CGPoint(x: 295, y: 5), CGPoint(x: 5, y: 295), CGPoint(x: 295, y: 295)] {
            XCTAssertNil(DpadHitPolicy.key(at: corner, in: rect), "\(corner)")
            XCTAssertEqual(owners(of: corner), [], "\(corner)")
        }
    }

    func testPointsJustOutsideThePadAreInactive() {
        for degrees in stride(from: 0.0, to: 360.0, by: 15.0) {
            let point = onPad(radius + 1, degrees)
            XCTAssertNil(DpadHitPolicy.key(at: point, in: rect), "\(point)")
            XCTAssertEqual(owners(of: point), [], "\(point)")
        }
    }

    func testDiagonalTiesAreDeterministic() {
        // |dx| == |dy| exactly: the horizontal arrow wins.
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 230, y: 230), in: rect), .right)
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 230, y: 70), in: rect), .right)
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 70, y: 70), in: rect), .left)
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 70, y: 230), in: rect), .left)
        // Just off the diagonal goes to the nearer axis.
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 229, y: 231), in: rect), .down)
        XCTAssertEqual(DpadHitPolicy.key(at: CGPoint(x: 229, y: 69), in: rect), .up)
    }

    func testHitAreasScaleWithThePad() {
        for size in [CGFloat(180), 240, 320] {
            let pad = CGRect(x: 0, y: 0, width: size, height: size)
            let point = CGPoint(x: size * 0.85, y: size * 0.5)
            XCTAssertEqual(DpadHitPolicy.key(at: point, in: pad), .right)
            XCTAssertTrue(sector(.right, in: pad).contains(point))
            XCTAssertNil(DpadHitPolicy.key(at: CGPoint(x: size * 0.03, y: size * 0.03), in: pad))
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
