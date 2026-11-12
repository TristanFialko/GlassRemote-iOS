import SwiftUI
import UIKit
import XCTest
@testable import GlassRemote

/// Now Playing's adaptive background: colour extraction from the artwork and the legibility
/// adjustment of the palette (NowPlayingPalette.swift, PlayerBackdropPolicy).
final class NowPlayingPaletteTests: XCTestCase {

    private func pixels(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int, alpha: UInt8 = 255) -> [UInt8] {
        Array(repeating: [r, g, b, alpha], count: count).flatMap { $0 }
    }

    private func solidImage(_ colour: UIColor, size: CGSize = CGSize(width: 60, height: 90)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            colour.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
    }

    private func assertLegible(_ palette: NowPlayingPalette, light: Bool, _ label: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        for tone in PlayerBackdropPolicy.meshColors(palette, light: light) {
            XCTAssertGreaterThanOrEqual(PlayerBackdropPolicy.inkContrast(over: tone, light: light),
                                        PlayerBackdropPolicy.minimumContrast, "\(label), light \(light)",
                                        file: file, line: line)
        }
    }

    // MARK: Extraction

    func testASolidImageGivesItsOwnColour() throws {
        let image = solidImage(UIColor(red: 0.20, green: 0.45, blue: 0.80, alpha: 1))
        let swatches = NowPlayingPaletteExtractor.swatches(from: image)
        let only = try XCTUnwrap(swatches.first)
        XCTAssertEqual(swatches.count, 1)
        XCTAssertEqual(only.share, 1, accuracy: 0.001)
        XCTAssertEqual(only.r, 0.20, accuracy: 0.03)
        XCTAssertEqual(only.g, 0.45, accuracy: 0.03)
        XCTAssertEqual(only.b, 0.80, accuracy: 0.03)
    }

    func testSwatchesAreOrderedByProminence() {
        let swatches = NowPlayingPaletteExtractor.swatches(rgba: pixels(30, 60, 200, count: 250) + pixels(200, 30, 40, count: 750))
        XCTAssertEqual(swatches.count, 2)
        XCTAssertGreaterThan(swatches[0].r, swatches[0].b, "the red field covers most of the picture")
        XCTAssertEqual(swatches[0].share, 0.75, accuracy: 0.001)
        XCTAssertGreaterThan(swatches[1].b, swatches[1].r)
        XCTAssertEqual(swatches[1].share, 0.25, accuracy: 0.001)
    }

    func testSpecksAndTransparencyAreIgnored() {
        let specks = NowPlayingPaletteExtractor.swatches(rgba: pixels(40, 180, 60, count: 995) + pixels(230, 20, 200, count: 5))
        XCTAssertEqual(specks.count, 1, "a 0.5 % speck is noise, not a colour of the artwork")

        let cutout = NowPlayingPaletteExtractor.swatches(rgba: pixels(200, 30, 40, count: 100) + pixels(0, 0, 0, count: 300, alpha: 0))
        XCTAssertEqual(cutout.count, 1)
        XCTAssertEqual(cutout.first?.share ?? 0, 1, accuracy: 0.001, "shares count opaque pixels only")

        XCTAssertTrue(NowPlayingPaletteExtractor.swatches(rgba: []).isEmpty)
        XCTAssertTrue(NowPlayingPaletteExtractor.swatches(rgba: pixels(0, 0, 0, count: 20, alpha: 0)).isEmpty)
        XCTAssertNil(NowPlayingPalette.make(swatches: [], light: false), "no colour read: the caller uses the fallback")
    }

    func testNearIdenticalShadesAreOneColour() {
        let swatches = NowPlayingPaletteExtractor.swatches(rgba: pixels(184, 30, 36, count: 500) + pixels(196, 34, 40, count: 500))
        XCTAssertEqual(swatches.count, 1)
    }

    func testAPosterGivesItsFieldAndItsHighlights() throws {
        let swatches = NowPlayingPaletteExtractor.swatches(from: Self.redPoster())
        let first = try XCTUnwrap(swatches.first)
        XCTAssertGreaterThan(first.r, 2 * first.g, "the red field is the dominant colour")
        XCTAssertTrue(swatches.contains { $0.r > 0.85 && $0.g > 0.5 }, "the pale shapes are part of the palette: \(swatches)")
        XCTAssertLessThanOrEqual(swatches.count, NowPlayingPaletteExtractor.maxSwatches)
        XCTAssertEqual(swatches.map(\.share), swatches.map(\.share).sorted(by: >), "most prominent first")
    }

    // MARK: Palette

    func testAccentIsTheMostVividDistinctColour() throws {
        let brown = ArtworkSwatch(r: 0.45, g: 0.30, b: 0.20, share: 0.6)
        let grey = ArtworkSwatch(r: 0.5, g: 0.5, b: 0.5, share: 0.25)
        let orange = ArtworkSwatch(r: 1.0, g: 0.55, b: 0.05, share: 0.1)
        let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: [brown, grey, orange], light: false))
        XCTAssertEqual(palette.accent.hsv.h, NowPlayingPalette.Tone(orange).hsv.h, accuracy: 0.03)
    }

    func testABrightPosterIsDarkenedUnderWhiteInkAndKeptPaleUnderDarkInk() throws {
        let cream = ArtworkSwatch(r: 0.97, g: 0.96, b: 0.92, share: 0.6)
        let yellow = ArtworkSwatch(r: 0.98, g: 0.85, b: 0.30, share: 0.3)
        for light in [false, true] {
            let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: [cream, yellow], light: light))
            assertLegible(palette, light: light, "bright")
        }
        let dark = try XCTUnwrap(NowPlayingPalette.make(swatches: [cream, yellow], light: false))
        XCTAssertLessThanOrEqual(dark.base.luminance, PlayerBackdropPolicy.darkMaxLuminance + 0.001)
        XCTAssertLessThan(dark.accent.hsv.h, NowPlayingPalette.Tone(yellow).hsv.h, "darkened yellow leans gold, not olive")
        let light = try XCTUnwrap(NowPlayingPalette.make(swatches: [cream, yellow], light: true))
        XCTAssertGreaterThanOrEqual(light.base.luminance, PlayerBackdropPolicy.lightMinLuminance - 0.001)
    }

    func testAPaleColourlessPosterTakesItsWashFromItsColours() throws {
        // Seen in the CI render: a cream field darkened under white ink became a muddy grey.
        let swatches = NowPlayingPaletteExtractor.swatches(rgba: pixels(245, 238, 215, count: 600)
            + pixels(250, 214, 80, count: 300) + pixels(190, 120, 60, count: 100))
        let dark = try XCTUnwrap(NowPlayingPalette.make(swatches: swatches, light: false))
        XCTAssertGreaterThan(dark.base.hsv.s, 0.3, "the field keeps the poster's colour, not grey")
        XCTAssertLessThanOrEqual(dark.base.luminance, PlayerBackdropPolicy.darkMaxLuminance + 0.001)
        let light = try XCTUnwrap(NowPlayingPalette.make(swatches: swatches, light: true))
        XCTAssertGreaterThanOrEqual(light.base.luminance, PlayerBackdropPolicy.lightMinLuminance - 0.001)
    }

    func testADarkPosterKeepsItsSaturatedAccent() throws {
        let night = ArtworkSwatch(r: 0.03, g: 0.03, b: 0.04, share: 0.9)
        let cyan = ArtworkSwatch(r: 0.0, g: 0.75, b: 0.9, share: 0.08)
        let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: [night, cyan], light: false))
        XCTAssertGreaterThanOrEqual(palette.base.luminance, PlayerBackdropPolicy.darkMinLuminance - 0.001,
                                    "near-black artwork still gives a coloured, not an empty, wash")
        XCTAssertEqual(palette.accent.hsv.h, NowPlayingPalette.Tone(cyan).hsv.h, accuracy: 0.03, "the small cyan highlight leads")
        XCTAssertGreaterThan(palette.accent.hsv.s, palette.base.hsv.s)
        for light in [false, true] {
            let adjusted = try XCTUnwrap(NowPlayingPalette.make(swatches: [night, cyan], light: light))
            assertLegible(adjusted, light: light, "dark")
        }
    }

    func testHighlySaturatedColoursAreTamed() throws {
        for (r, g, b) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 1.0, 0.0), (1.0, 0.0, 1.0)] {
            for light in [false, true] {
                let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: [ArtworkSwatch(r: r, g: g, b: b, share: 1)], light: light))
                let cap = light ? PlayerBackdropPolicy.lightMaxSaturation : PlayerBackdropPolicy.darkMaxSaturation
                for tone in palette.tones {
                    XCTAssertLessThanOrEqual(tone.hsv.s, cap + 0.01, "(\(r), \(g), \(b)) light \(light)")
                }
                assertLegible(palette, light: light, "saturated (\(r), \(g), \(b))")
            }
        }
    }

    func testEveryHueSaturationAndBrightnessStaysLegible() throws {
        for step in 0..<12 {
            let hue = Double(step) / 12
            for saturation in [0.0, 0.5, 1.0] {
                for value in [0.1, 0.5, 1.0] {
                    let c = ColorMath.rgb(hue: hue, saturation: saturation, value: value)
                    let opposite = ColorMath.rgb(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 1, value: 1)
                    let swatches = [ArtworkSwatch(r: c.r, g: c.g, b: c.b, share: 0.7),
                                    ArtworkSwatch(r: opposite.r, g: opposite.g, b: opposite.b, share: 0.2)]
                    for light in [false, true] {
                        let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: swatches, light: light))
                        assertLegible(palette, light: light, "h \(hue) s \(saturation) v \(value)")
                    }
                }
            }
        }
    }

    func testSingleColourArtStillGetsAWash() throws {
        for light in [false, true] {
            let palette = try XCTUnwrap(NowPlayingPalette.make(swatches: [ArtworkSwatch(r: 0.2, g: 0.4, b: 0.7, share: 1)], light: light))
            XCTAssertGreaterThan(palette.base.distance(to: palette.accent), 0.02, "a neighbouring tone, not one flat colour")
        }
    }

    // MARK: No artwork

    func testFallbackFollowsTheThemeAccentOrUsesTheHousePalette() {
        let teal = NowPlayingPalette.Tone(r: 0.1, g: 0.6, b: 0.6)
        let themed = NowPlayingPalette.fallback(accent: teal, secondary: nil, light: false)
        XCTAssertEqual(themed.base.hsv.h, teal.hsv.h, accuracy: 0.03, "a coloured theme tints the wash")

        let grey = NowPlayingPalette.Tone(r: 0.92, g: 0.92, b: 0.92)
        for accent in [grey, nil] {
            let house = NowPlayingPalette.fallback(accent: accent, secondary: nil, light: false)
            XCTAssertEqual(house.base, NowPlayingPalette.adjust(NowPlayingPalette.houseBase, light: false, role: .field),
                           "a neutral theme gets a deliberate colour, not a grey, empty-looking background")
        }
        for light in [false, true] {
            assertLegible(NowPlayingPalette.fallback(accent: teal, secondary: nil, light: light), light: light, "fallback teal")
            assertLegible(NowPlayingPalette.fallback(accent: grey, secondary: nil, light: light), light: light, "fallback house")
        }
    }

    // MARK: Fixtures

    /// The stand-in poster used by the rendered screens: bold shapes on a red field.
    static func redPoster() -> UIImage {
        let size = CGSize(width: 600, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colours = [UIColor(red: 0.72, green: 0.08, blue: 0.12, alpha: 1).cgColor,
                           UIColor(red: 0.30, green: 0.02, blue: 0.06, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(red: 0.98, green: 0.90, blue: 0.62, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 330, y: 470, width: 220, height: 220))
            UIColor(white: 1, alpha: 0.92).setFill()
            cg.fillEllipse(in: CGRect(x: 60, y: 120, width: 200, height: 200))
            UIColor(red: 0.96, green: 0.62, blue: 0.70, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 190, y: 250, width: 240, height: 320))
        }
    }
}
