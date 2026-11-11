import SwiftUI
import UIKit
import XCTest
@testable import GlassRemote

/// Phase 8 themes: new distinct themes, Mountains removed (with migration), and the toned-down Play.
final class Phase8ThemeTests: XCTestCase {
    private func rgb(_ c: Color) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b)]
    }

    func testNewThemesExistAndArePickable() {
        for id in [ThemeID.synthwave, .rosewood, .graphite, .glacier] {
            XCTAssertFalse(id.title.isEmpty)
            XCTAssertEqual(GlassTheme.base(for: id, systemScheme: .dark).id, id)
        }
        XCTAssertTrue(GlassTheme.glacier.isLight)
        XCTAssertFalse(GlassTheme.synthwave.isLight)
    }

    func testFixedThemesHaveDistinctAccents() {
        let fixed = ThemeID.allCases.filter { $0 != .adaptive && $0 != .auto }
        let accents = fixed.map { rgb(GlassTheme.base(for: $0, systemScheme: .dark).accent) }
        for i in accents.indices {
            for j in accents.indices where j > i {
                let d = zip(accents[i], accents[j]).map { abs($0 - $1) }.reduce(0, +)
                XCTAssertGreaterThan(d, 0.12, "\(fixed[i]) and \(fixed[j]) look the same")
            }
        }
    }

    func testMountainsIsGoneAndMigrates() {
        XCTAssertFalse(AmbientStyle.allCases.map(\.rawValue).contains("mountains"))
        XCTAssertEqual(AmbientStyle.migrated("mountains"), .dusk)
        XCTAssertEqual(AmbientStyle.migrated("aurora"), .aurora)
        XCTAssertEqual(AmbientStyle.migrated("nonsense"), AmbientStyle.none)
        XCTAssertEqual(AmbientStyle.migrated(nil), AmbientStyle.none)
        XCTAssertTrue(AmbientStyle.allCases.count >= 10)
    }

    func testDefaultDarkPlayIsToneDownNotAWhiteSlab() {
        let t = GlassTheme.defaultDark
        XCTAssertTrue(t.accentIsNeutral)
        XCTAssertLessThan(rgb(t.playFill).count, 4)
        var a: CGFloat = 0, w: CGFloat = 0
        _ = UIColor(t.playFill).getWhite(&w, alpha: &a)
        XCTAssertLessThan(Double(a), 0.5, "Default Dark Play should be a translucent frosted pill")
    }

    func testPlayInkStaysLegibleInEveryTheme() {
        for id in ThemeID.allCases {
            let t = GlassTheme.base(for: id, systemScheme: .dark)
            guard !t.accentIsNeutral else { continue }
            let fill = GlassTheme.luminance(of: t.accent)
            let ink = GlassTheme.luminance(of: t.playInk)
            XCTAssertGreaterThan(abs(fill - ink), 0.35, "\(id)")
        }
    }

    func testLuminanceBounds() {
        XCTAssertEqual(GlassTheme.luminance(of: .white), 1, accuracy: 0.01)
        XCTAssertEqual(GlassTheme.luminance(of: .black), 0, accuracy: 0.01)
    }
}
