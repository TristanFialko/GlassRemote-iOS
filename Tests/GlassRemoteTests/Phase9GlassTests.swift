import XCTest
import CoreGraphics
@testable import GlassRemote

/// Phase 9 §0 and continuation §B: the bounded refraction lens (Swift mirror of Refraction.metal)
/// and its policy. Continuation §B: no magnification, a fixed centre, a stronger rim and restrained
/// rim-only dispersion.
final class Phase9GlassTests: XCTestCase {
    private let lens = CGRect(x: 40, y: 4, width: 80, height: 32)
    private let style = RefractionStyle.selector

    private func sample(_ x: CGFloat, _ y: CGFloat, lens: CGRect? = nil, radius: CGFloat = .infinity,
                        style: RefractionStyle? = nil) -> CGPoint {
        RefractionGeometry.samplePoint(for: CGPoint(x: x, y: y), lens: lens ?? self.lens, cornerRadius: radius,
                                       style: style ?? self.style)
    }

    private func signedDistance(_ x: CGFloat, _ y: CGFloat, lens: CGRect, radius: CGFloat) -> CGFloat {
        let r = RefractionGeometry.clampedRadius(radius, lens: lens)
        return RefractionGeometry.distance(CGPoint(x: x - lens.midX, y: y - lens.midY),
                                           halfSize: CGSize(width: lens.width / 2, height: lens.height / 2), radius: r)
    }

    func testPixelsOutsideTheLensShapeAreUntouched() {
        // Left of, right of and below the capsule, plus a point in its rounded corner that is still
        // inside its bounding box: no rectangular bound, nothing outside the shape moves.
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 39, y: 20), CGPoint(x: 121, y: 20),
                      CGPoint(x: 80, y: 37), CGPoint(x: 41, y: 5)]
        for point in points {
            let s = sample(point.x, point.y)
            XCTAssertEqual(s.x, point.x, accuracy: 0.0001, "\(point)")
            XCTAssertEqual(s.y, point.y, accuracy: 0.0001, "\(point)")
            XCTAssertEqual(RefractionGeometry.spread(for: point, lens: lens, cornerRadius: .infinity, style: style), 0)
        }
    }

    func testTheCentreIsAFixedPoint() {
        for s in [RefractionStyle.selector, .thumb] {
            let c = sample(80, 20, style: s)
            XCTAssertEqual(c.x, 80, accuracy: 0.0001)
            XCTAssertEqual(c.y, 20, accuracy: 0.0001)
        }
        let thumb = CGRect(x: 0, y: 0, width: 48, height: 48)
        let c = sample(24, 24, lens: thumb, radius: 24, style: .thumb)
        XCTAssertEqual(c, CGPoint(x: 24, y: 24))
    }

    func testTheInteriorIsNotMagnified() {
        // Everything deeper than the rim band samples itself: text under the lens keeps its size.
        for (box, radius, s) in [(lens, CGFloat.infinity, RefractionStyle.selector),
                                 (CGRect(x: 0, y: 0, width: 48, height: 48), CGFloat(24), RefractionStyle.thumb),
                                 (CGRect(x: 10, y: 10, width: 140, height: 44), CGFloat(14), RefractionStyle.selector)] {
            let band = RefractionGeometry.rimWidth(lens: box, style: s)
            var interiorPoints = 0
            var x = box.minX
            while x <= box.maxX {
                var y = box.minY
                while y <= box.maxY {
                    if signedDistance(x, y, lens: box, radius: radius) <= -band - 0.01 {
                        interiorPoints += 1
                        let p = sample(x, y, lens: box, radius: radius, style: s)
                        XCTAssertEqual(p.x, x, accuracy: 0.0001, "\(box) \(x),\(y)")
                        XCTAssertEqual(p.y, y, accuracy: 0.0001, "\(box) \(x),\(y)")
                    }
                    y += 1
                }
                x += 1
            }
            XCTAssertGreaterThan(interiorPoints, 0, "every lens keeps a fixed interior: \(box)")
        }
        let s = sample(90, 20)
        XCTAssertEqual(s.x, 90, accuracy: 0.0001, "the old lens pulled this point toward the centre")
    }

    func testTheRimNeverMagnifiesAlongTheNormal() {
        // Sample spacing along the outward normal is never smaller than pixel spacing: the rim
        // compresses (bends outward) and never enlarges what is under it.
        var x: CGFloat = 100
        var previous = sample(x, 20).x
        while x < 119.5 {
            x += 0.5
            let current = sample(x, 20).x
            XCTAssertGreaterThanOrEqual(current - previous, 0.5 - 0.0001, "x \(x)")
            previous = current
        }
    }

    func testTheRimBendsLightOutwardMoreStronglyThanBefore() {
        let s = sample(119.5, 20)
        XCTAssertGreaterThan(s.x - 119.5, RefractionStyle.previousSelectorBend, "stronger than the checkpoint lens")
        XCTAssertLessThanOrEqual(s.x - 119.5, style.bend + 0.0001)
        XCTAssertEqual(s.y, 20, accuracy: 0.0001)
        XCTAssertGreaterThan(RefractionStyle.selector.bend, RefractionStyle.previousSelectorBend)
        XCTAssertGreaterThan(RefractionStyle.thumb.bend, RefractionStyle.previousThumbBend)
        // The rim profile is smooth: zero at the inner edge of the band, one at the glass edge.
        XCTAssertEqual(RefractionGeometry.edgeWeight(0), 0)
        XCTAssertEqual(RefractionGeometry.edgeWeight(1), 1)
        XCTAssertEqual(RefractionGeometry.edgeWeight(0.5), 0.5, accuracy: 0.0001)
    }

    func testDispersionStaysOnTheOutermostRim() {
        let spread = { (x: CGFloat) in
            RefractionGeometry.spread(for: CGPoint(x: x, y: 20), lens: self.lens, cornerRadius: .infinity, style: self.style)
        }
        XCTAssertEqual(spread(80), 0, "no colour fringe in the interior")
        XCTAssertEqual(spread(100), 0)
        XCTAssertLessThan(spread(110), 0.05, "next to nothing at the inner part of the rim")
        XCTAssertGreaterThan(spread(119.5), style.dispersion * 0.8)
        XCTAssertLessThanOrEqual(spread(119.5), style.dispersion)
        XCTAssertLessThanOrEqual(RefractionStyle.selector.dispersion, 1.5, "restrained")
        XCTAssertLessThanOrEqual(RefractionStyle.thumb.dispersion, 1.5, "restrained")
    }

    func testRimWidthAlwaysLeavesAFixedCentre() {
        XCTAssertEqual(RefractionGeometry.rimWidth(lens: lens, style: style), 12)
        let small = CGRect(x: 0, y: 0, width: 16, height: 16)
        XCTAssertEqual(RefractionGeometry.rimWidth(lens: small, style: style), 6)
        XCTAssertEqual(sample(8, 8, lens: small, radius: 8), CGPoint(x: 8, y: 8))
    }

    func testEveryDisplacementFitsTheDeclaredSampleOffset() {
        for s in [RefractionStyle.selector, .thumb] {
            let bound = RefractionPolicy.maxSampleOffset(lens: lens, style: s)
            XCTAssertEqual(bound, RefractionPolicy.maxSampleOffset(lens: CGRect(x: 0, y: 0, width: 400, height: 60), style: s),
                           "the bound no longer grows with the lens")
            var x = lens.minX
            while x <= lens.maxX {
                var y = lens.minY
                while y <= lens.maxY {
                    let p = sample(x, y, style: s)
                    let chroma = RefractionGeometry.spread(for: CGPoint(x: x, y: y), lens: lens, cornerRadius: .infinity, style: s)
                    XCTAssertLessThanOrEqual(abs(p.x - x) + chroma, bound.width)
                    XCTAssertLessThanOrEqual(abs(p.y - y) + chroma, bound.height)
                    y += 1
                }
                x += 1
            }
        }
    }

    func testRefractionFallsBackToNativeGlassForAccessibilitySettings() {
        XCTAssertTrue(RefractionPolicy.isEnabled(reduceMotion: false, increaseContrast: false, reduceTransparency: false, lens: lens))
        XCTAssertFalse(RefractionPolicy.isEnabled(reduceMotion: true, increaseContrast: false, reduceTransparency: false, lens: lens))
        XCTAssertFalse(RefractionPolicy.isEnabled(reduceMotion: false, increaseContrast: true, reduceTransparency: false, lens: lens))
        XCTAssertFalse(RefractionPolicy.isEnabled(reduceMotion: false, increaseContrast: false, reduceTransparency: true, lens: lens))
    }

    func testDegenerateLensesAreSkipped() {
        XCTAssertFalse(RefractionPolicy.isEnabled(reduceMotion: false, increaseContrast: false, reduceTransparency: false,
                                                  lens: CGRect(x: 0, y: 0, width: 8, height: 30)))
        XCTAssertFalse(RefractionPolicy.isEnabled(reduceMotion: false, increaseContrast: false, reduceTransparency: false,
                                                  lens: CGRect(x: CGFloat.nan, y: 0, width: 40, height: 30)))
        let zero = CGRect(x: 10, y: 10, width: 0, height: 0)
        let p = RefractionGeometry.samplePoint(for: CGPoint(x: 10, y: 10), lens: zero, cornerRadius: 4, style: style)
        XCTAssertEqual(p, CGPoint(x: 10, y: 10))
        XCTAssertEqual(RefractionGeometry.spread(for: CGPoint(x: 10, y: 10), lens: zero, cornerRadius: 4, style: style), 0)
    }

    func testCapsuleRadiusClampsToHalfTheShortSide() {
        XCTAssertEqual(RefractionGeometry.clampedRadius(.infinity, lens: lens), 16)
        XCTAssertEqual(RefractionGeometry.clampedRadius(6, lens: lens), 6)
        XCTAssertEqual(RefractionGeometry.clampedRadius(-3, lens: lens), 0)
    }

    func testVolumeThumbLensSitsExactlyOnTheThumb() {
        let thumb = VolumeSliderGeometry.thumbDiameter(height: 58)
        XCTAssertEqual(thumb, 48)
        let fill = VolumeSliderGeometry.fillWidth(value: 0.5, width: 300, thumb: thumb)
        let rect = VolumeSliderGeometry.thumbRect(fillWidth: fill, thumb: thumb)
        XCTAssertEqual(rect, CGRect(x: 97, y: 5, width: 48, height: 48))
        let pressed = VolumeSliderGeometry.thumbRect(fillWidth: fill, thumb: thumb, scale: 1.08)
        XCTAssertEqual(pressed.midX, rect.midX, accuracy: 0.0001)
        XCTAssertEqual(pressed.midY, rect.midY, accuracy: 0.0001)
        XCTAssertEqual(pressed.width, 48 * 1.08, accuracy: 0.0001)
        XCTAssertEqual(VolumeSliderGeometry.thumbX(fillWidth: 0, thumb: thumb), VolumeSliderGeometry.inset)
    }
}
