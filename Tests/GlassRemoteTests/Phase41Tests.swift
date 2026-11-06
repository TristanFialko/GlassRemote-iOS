import XCTest
import SwiftUI
@testable import GlassRemote

/// Phase 4.1: contrast maths, palette extraction, pager gesture policy, dock geometry, measured seeking.
final class Phase41Tests: XCTestCase {

    // MARK: Colour maths

    func testLuminanceExtremes() {
        XCTAssertEqual(ColorMath.luminance(r: 0, g: 0, b: 0), 0, accuracy: 0.001)
        XCTAssertEqual(ColorMath.luminance(r: 1, g: 1, b: 1), 1, accuracy: 0.001)
        XCTAssertEqual(ColorMath.contrast(1, 0), 21, accuracy: 0.01)
    }

    func testLuminanceMatchedColourHitsTargetForEveryHue() {
        for step in 0..<12 {
            let hue = Double(step) / 12
            for target in [0.17, 0.36] {
                let c = ColorMath.color(hue: hue, saturation: 0.9, luminance: target)
                let l = ColorMath.luminance(r: c.r, g: c.g, b: c.b)
                XCTAssertEqual(l, target, accuracy: 0.03, "hue \(hue) target \(target)")
            }
        }
    }

    func testHsvRoundTrip() {
        let c = ColorMath.rgb(hue: 0.6, saturation: 0.7, value: 0.8)
        let back = ColorMath.hsv(r: c.r, g: c.g, b: c.b)
        XCTAssertEqual(back.h, 0.6, accuracy: 0.001)
        XCTAssertEqual(back.s, 0.7, accuracy: 0.001)
        XCTAssertEqual(back.v, 0.8, accuracy: 0.001)
    }

    // MARK: Palette

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 1024) -> [UInt8] {
        (0..<count).flatMap { _ in [r, g, b, 255] }
    }

    func testEdgeBordersDoNotDecideThePalette() {
        // 32 x 32: a red picture in the middle, a white border around it.
        var pixels: [UInt8] = []
        for y in 0..<32 { for x in 0..<32 {
            let inside = (8..<24).contains(x) && (8..<24).contains(y)
            pixels += inside ? [220, 30, 30, 255] : [255, 255, 255, 255]
        } }
        let p = ArtworkPaletteExtractor.palette(fromRGBA: pixels)
        XCTAssertFalse(p.isNeutral)
        XCTAssertLessThan(min(p.hue, 1 - p.hue), 0.05)   // red
    }

    func testAccentIsCalmAndComparableAcrossHues() {
        for hue in [0.0, 0.15, 0.33, 0.6, 0.8] {
            let p = ArtworkPalette(hue: hue, saturation: 1, brightness: 1, secondaryHue: hue, isNeutral: false)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(UIColor(p.accentColor(light: false)).getRed(&r, green: &g, blue: &b, alpha: &a))
            let l = ColorMath.luminance(r: Double(r), g: Double(g), b: Double(b))
            XCTAssertEqual(l, 0.36, accuracy: 0.04)
        }
    }

    func testSimilarPalettesDoNotRecolour() {
        let a = ArtworkPalette(hue: 0.60, saturation: 0.7, brightness: 0.7, secondaryHue: 0.7, isNeutral: false)
        var b = a; b.hue = 0.61
        XCTAssertTrue(a.isSimilar(to: b))
        b.hue = 0.80
        XCTAssertFalse(a.isSimilar(to: b))
        XCTAssertFalse(a.isSimilar(to: .neutral))
    }

    func testDockInkContrastsWithItsScrimInEveryTheme() {
        for id in ThemeID.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let t = GlassTheme.base(for: id, systemScheme: scheme)
                // Ink and scrim have opposite polarity by construction.
                XCTAssertNotEqual(t.isLight, t.dockInk == .white, "\(id)")
            }
        }
    }

    // MARK: Pager gesture policy

    func testVerticalDragsNeverPage() {
        XCTAssertFalse(PagerGesturePolicy.isHorizontalDominant(dx: 6, dy: 14))
        XCTAssertFalse(PagerGesturePolicy.isHorizontalDominant(dx: 10, dy: 9))
        XCTAssertTrue(PagerGesturePolicy.isHorizontalDominant(dx: 14, dy: 4))
    }

    func testRemotePagesOnlyFromEdges() {
        XCTAssertFalse(PagerGesturePolicy.acceptsTouch(on: .remote, x: 195, width: 390, edgeWidth: 16))
        XCTAssertTrue(PagerGesturePolicy.acceptsTouch(on: .remote, x: 6, width: 390, edgeWidth: 16))
        XCTAssertTrue(PagerGesturePolicy.acceptsTouch(on: .remote, x: 384, width: 390, edgeWidth: 16))
        XCTAssertTrue(PagerGesturePolicy.acceptsTouch(on: .discover, x: 195, width: 390, edgeWidth: 16))
    }

    func testCarouselDetection() {
        XCTAssertTrue(PagerGesturePolicy.isHorizontalScroller(contentSize: CGSize(width: 900, height: 200), bounds: CGSize(width: 390, height: 200), scrollEnabled: true))
        XCTAssertFalse(PagerGesturePolicy.isHorizontalScroller(contentSize: CGSize(width: 390, height: 2400), bounds: CGSize(width: 390, height: 700), scrollEnabled: true))
        XCTAssertFalse(PagerGesturePolicy.isHorizontalScroller(contentSize: CGSize(width: 900, height: 200), bounds: CGSize(width: 390, height: 200), scrollEnabled: false))
    }

    // MARK: Dock geometry

    func testDockSinksOnlyIntoTheSafeArea() {
        XCTAssertEqual(DockMetrics.drop(safeBottom: 0), 0)
        XCTAssertEqual(DockMetrics.drop(safeBottom: 34), 10)
        XCTAssertLessThanOrEqual(DockMetrics.drop(safeBottom: 60), 10)
        // Pages always keep the dock plus breathing room clear.
        for inset in [0, 20, 34] as [CGFloat] {
            XCTAssertGreaterThanOrEqual(DockMetrics.clearance(safeBottom: inset), DockMetrics.height)
        }
    }

    // MARK: Measured seeking

    private func sample(pos: Int64, uptime: Int64, state: Int = 3) -> MediaState {
        var m = MediaState(package: "com.stremio.one", title: "Show", state: state, positionMs: pos, speed: 1, sampledAt: Date(), actions: 0)
        m.deviceUptimeMs = uptime
        return m
    }

    func testNormalPlaybackIsNotASeek() {
        // 3 s of device time passed and the position advanced 3 s.
        XCTAssertEqual(SeekMeasurement.measure(before: sample(pos: 100_000, uptime: 50_000), after: sample(pos: 103_000, uptime: 53_000)), .unchanged)
    }

    func testForwardSeekIsMeasuredNetOfPlayback() {
        // 3 s elapsed, position moved 13 s: a 10 s jump.
        XCTAssertEqual(SeekMeasurement.measure(before: sample(pos: 100_000, uptime: 50_000), after: sample(pos: 113_000, uptime: 53_000)), .confirmed(seconds: 10))
    }

    func testBackwardSeek() {
        XCTAssertEqual(SeekMeasurement.measure(before: sample(pos: 100_000, uptime: 50_000), after: sample(pos: 98_000, uptime: 53_000)), .confirmed(seconds: -5))
    }

    func testDifferentItemIsUnknown() {
        var other = sample(pos: 5_000, uptime: 53_000); other.title = "Another"
        XCTAssertEqual(SeekMeasurement.measure(before: sample(pos: 100_000, uptime: 50_000), after: other), .unknown)
    }

    func testLearnerNeedsTwoAgreeingMeasurements() {
        var l = SeekStepLearner()
        let pkg = "com.stremio.one"
        l.record(package: pkg, command: .fastForward, seconds: 10.2)
        XCTAssertNil(l.step(package: pkg, command: .fastForward))
        l.record(package: pkg, command: .fastForward, seconds: 9.8)
        XCTAssertEqual(l.step(package: pkg, command: .fastForward) ?? 0, 10, accuracy: 0.11)
        XCTAssertFalse(l.isTenSecond(package: pkg))      // rewind not measured yet
        l.record(package: pkg, command: .rewind, seconds: -10)
        l.record(package: pkg, command: .rewind, seconds: -10.4)
        XCTAssertTrue(l.isTenSecond(package: pkg))
    }

    func testLearnerRejectsWrongDirectionAndDisagreement() {
        var l = SeekStepLearner()
        l.record(package: "p", command: .rewind, seconds: 10)          // wrong sign
        l.record(package: "p", command: .rewind, seconds: -10)
        XCTAssertNil(l.step(package: "p", command: .rewind))
        l.record(package: "p", command: .rewind, seconds: -30)          // disagrees
        XCTAssertNil(l.step(package: "p", command: .rewind))
    }

    func testFifteenSecondStepIsNotRelabelledTen() {
        var l = SeekStepLearner()
        for s in [15.0, 15.1] { l.record(package: "p", command: .fastForward, seconds: s) }
        for s in [-5.0, -5.2] { l.record(package: "p", command: .rewind, seconds: s) }
        XCTAssertFalse(l.isTenSecond(package: "p"))
    }
}
