import XCTest
import CoreGraphics
@testable import GlassRemote

/// Phase 9 §0: the bounded refraction lens (Swift mirror of Refraction.metal) and its policy.
final class Phase9GlassTests: XCTestCase {
    private let lens = CGRect(x: 40, y: 4, width: 80, height: 32)
    private let style = RefractionStyle.selector

    private func sample(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        RefractionGeometry.samplePoint(for: CGPoint(x: x, y: y), lens: lens, cornerRadius: .infinity, style: style)
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
        }
    }

    func testTheCentreIsAFixedPoint() {
        let s = sample(80, 20)
        XCTAssertEqual(s.x, 80, accuracy: 0.0001)
        XCTAssertEqual(s.y, 20, accuracy: 0.0001)
    }

    func testTheInteriorMagnifiesTowardTheCentre() {
        let s = sample(90, 20)
        XCTAssertLessThan(s.x, 90)
        XCTAssertGreaterThan(s.x, 80)
        XCTAssertEqual(s.y, 20, accuracy: 0.0001)
    }

    func testTheRimBendsLightOutward() {
        let s = sample(119.5, 20)
        let magnifiedOnly = 80 + 39.5 * (1 - style.zoom)
        XCTAssertGreaterThan(s.x, magnifiedOnly + 1)
    }

    func testEveryDisplacementFitsTheDeclaredSampleOffset() {
        let bound = RefractionPolicy.maxSampleOffset(lens: lens, style: style)
        var x = lens.minX
        while x <= lens.maxX {
            var y = lens.minY
            while y <= lens.maxY {
                let s = sample(x, y)
                XCTAssertLessThanOrEqual(abs(s.x - x), bound.width)
                XCTAssertLessThanOrEqual(abs(s.y - y), bound.height)
                y += 1
            }
            x += 1
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
