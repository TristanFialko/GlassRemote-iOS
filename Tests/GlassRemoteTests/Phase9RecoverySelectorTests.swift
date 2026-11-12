import SwiftUI
import UIKit
import XCTest
@testable import GlassRemote

/// Phase 9 recovery §2A / §2B: every selection bubble (the Discover All / Movies / Series filter,
/// the Android TV / Samsung TV switch, Mouse / D-pad and the dock) is clear glass on every theme.
/// The theme accent moves to the selected icon or label beneath the bubble, falling back to ink only
/// where the accent would be unreadable on the bar.
final class Phase9RecoverySelectorTests: XCTestCase {
    private var themes: [GlassTheme] {
        var all: [GlassTheme] = []
        for id in ThemeID.allCases where id != .adaptive && id != .auto {
            all.append(GlassTheme.base(for: id, systemScheme: .dark))
            all.append(GlassTheme.base(for: id, systemScheme: .light))
        }
        return all
    }

    func testThemesUnderTestHaveColouredAccents() {
        XCTAssertFalse(themes.isEmpty)
        XCTAssertTrue(themes.contains { !isNeutral($0.accent) },
                      "at least one theme needs a coloured accent for the neutral-glass checks to mean anything")
    }

    func testSelectionBubbleGlassIsNeutralOnEveryTheme() {
        for t in themes {
            XCTAssertTrue(isNeutral(t.lensGlassTint), "\(t.id): the bubble glass must not carry the accent")
            XCTAssertTrue(isNeutral(t.lensFill), "\(t.id): the bubble fill must not carry the accent")
            if t.isLight {
                XCTAssertTrue(isNeutral(t.lensEdge), "\(t.id): the bubble edge must not carry the accent")
            }
        }
    }

    func testSelectionBubbleStaysTranslucent() {
        for t in themes {
            XCTAssertLessThanOrEqual(components(t.lensGlassTint)?.a ?? 1, 0.10, "\(t.id): no opaque glass tint")
            XCTAssertLessThanOrEqual(components(t.lensFill)?.a ?? 1, 0.10, "\(t.id): no opaque fill")
        }
    }

    func testSelectedContentTakesTheAccentWhenReadable() {
        var accentThemes = 0
        for t in themes {
            guard let lum = luminance(t.lensTint) else { XCTFail("\(t.id): accent not resolvable"); continue }
            let ink = SelectorInk.selected(t)
            if DockStyle.usesAccent(accentLuminance: lum, light: t.isLight) {
                accentThemes += 1
                XCTAssertEqual(ink, t.lensTint, "\(t.id): the selected item should take the theme accent")
                XCTAssertGreaterThanOrEqual(ColorMath.contrast(lum, DockStyle.backdropLuminance(light: t.isLight)),
                                            DockStyle.minimumContrast, "\(t.id)")
            } else {
                XCTAssertEqual(ink, Color.ink, "\(t.id): an unreadable accent falls back to full-strength ink")
            }
        }
        XCTAssertGreaterThan(accentThemes, 0, "the accent must show on the selected item for at least one theme")
    }

    func testUnselectedContentStaysMutedInk() {
        XCTAssertLessThan(SelectorInk.unselectedOpacity, 1)
        XCTAssertGreaterThanOrEqual(SelectorInk.unselectedOpacity, 0.6, "unselected items must stay legible")
        for t in themes {
            XCTAssertEqual(SelectorInk.color(selected: true, theme: t), SelectorInk.selected(t))
            XCTAssertNotEqual(SelectorInk.color(selected: false, theme: t), SelectorInk.selected(t), "\(t.id)")
        }
    }

    func testModeSelectorIconUsesTheReadableAccent() {
        for t in themes {
            let ink = SelectorInk.selected(t)
            XCTAssertEqual(ModeSelectorStyle.iconColor(selected: true, accent: ink), ink, "\(t.id)")
        }
    }

    func testTwoItemSelectorsMapTouchesConsistentlyUnderRapidSwitching() {
        // Android / Samsung and Mouse / D-pad: two segments, compact (portrait) and wide (landscape).
        for width in [CGFloat(108), CGFloat(300)] {
            let inset: CGFloat = 4
            let segment = (width - 2 * inset) / 2
            let first = inset + segment * 0.25
            let second = inset + segment * 1.25
            for _ in 0..<20 {
                XCTAssertEqual(ScrubGeometry.index(forOffset: first, inset: inset, segment: segment, count: 2), 0)
                XCTAssertEqual(ScrubGeometry.index(forOffset: second, inset: inset, segment: segment, count: 2), 1)
            }
        }
    }

    func testReduceMotionKeepsSelectorBubblesRigid() {
        let rigid = ScrubGeometry.lensScale(dragging: true, speed: 4000, reduceMotion: true)
        XCTAssertEqual(rigid.along, 1)
        XCTAssertEqual(rigid.across, 1)
        let resting = ScrubGeometry.lensScale(dragging: false, speed: 4000, reduceMotion: false)
        XCTAssertEqual(resting.along, 1)
        XCTAssertEqual(resting.across, 1)
    }

    func testEverySelectorTintsItsContentNotItsGlass() throws {
        let style = try source("GlassRemote/GlassStyle.swift")
        let lens = section(of: style, from: "private struct ThemedGlassLens", to: "final class ScrubTouch")
        XCTAssertFalse(lens.contains("lensTint"), "the bubble glass must not be tinted with the accent")
        XCTAssertTrue(lens.contains("Glass.clear.tint(theme.lensGlassTint)"))
        let segmented = section(of: style, from: "struct GlassSegmented", to: "struct GlassGroup")
        XCTAssertTrue(segmented.contains("SelectorInk.color(selected: selected, theme: theme)"))
        XCTAssertTrue(style.contains("ModeSelectorStyle.iconColor(selected: selected, accent: SelectorInk.selected(theme))"))
        XCTAssertTrue(style.contains(".glassLens(Capsule())"), "the dock and the controls share the one clear lens")
        let chrome = try source("GlassRemote/Remote/RemoteChrome.swift")
        let target = section(of: chrome, from: "struct RemoteTargetSwitch", to: "enum RemoteSurfaceHints")
        XCTAssertTrue(target.contains("SelectorInk.color(selected: selected, theme: theme)"))
        XCTAssertFalse(target.contains("Color.ink :"), "the selected TV icon takes the accent, not plain ink")
    }

    func testDiscoverFiltersUseTheSharedAccentedSelector() throws {
        let discover = try source("GlassRemote/DiscoverPage.swift")
        XCTAssertTrue(discover.contains("GlassSegmented("))
        XCTAssertTrue(discover.contains("value: .all, title: \"All\""))
        XCTAssertTrue(discover.contains("value: .movies, title: \"Movies\""))
        XCTAssertTrue(discover.contains("value: .series, title: \"Series\""))
    }

    // MARK: - Helpers

    private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private func isNeutral(_ color: Color) -> Bool {
        guard let c = components(color) else { return false }
        return abs(c.r - c.g) < 0.01 && abs(c.g - c.b) < 0.01
    }

    private func luminance(_ color: Color) -> Double? {
        guard let c = components(color) else { return nil }
        return ColorMath.luminance(r: c.r, g: c.g, b: c.b)
    }

    private func section(of text: String, from start: String, to end: String) -> String {
        guard let a = text.range(of: start) else { XCTFail("missing \(start)"); return "" }
        guard let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { XCTFail("missing \(end)"); return "" }
        return String(text[a.lowerBound..<b.lowerBound])
    }

    private func source(_ path: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(path)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw XCTSkip("sources not readable from the test host")
        }
        return text
    }
}
