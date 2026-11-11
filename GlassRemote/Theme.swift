import SwiftUI
import UIKit

// MARK: - Theme model
//
// One source of truth for appearance. Views never pick colours themselves: they read the active
// `GlassTheme` from the environment (set once at the app root) or use `Color.ink` for text, which
// flips with the window's light/dark scheme. Switching themes only changes environment values: no
// model, page or helper is recreated.

enum ThemeID: String, CaseIterable, Identifiable {
    case defaultDark, deepBlue, violet, amber, lightGlass, forest, crimson, ocean, glassWhite,
         synthwave, rosewood, graphite, glacier, adaptive, auto
    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultDark: return "Default Dark"
        case .deepBlue: return "Deep Blue"
        case .violet: return "Violet"
        case .amber: return "Amber"
        case .lightGlass: return "Light Glass"
        case .forest: return "Forest"
        case .crimson: return "Crimson"
        case .ocean: return "Ocean"
        case .glassWhite: return "Glass White"
        case .synthwave: return "Synthwave"
        case .rosewood: return "Rosewood"
        case .graphite: return "Graphite"
        case .glacier: return "Glacier"
        case .adaptive: return "Adaptive"
        case .auto: return "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .defaultDark: return "OLED black, charcoal glass"
        case .deepBlue: return "Navy glass, electric blue"
        case .violet: return "Rich purple glass"
        case .amber: return "Warm, cinematic"
        case .lightGlass: return "Frosted, cool highlights"
        case .forest: return "Deep green, emerald"
        case .crimson: return "Black and red"
        case .ocean: return "Teal and cyan"
        case .glassWhite: return "Minimal, neutral"
        case .synthwave: return "Neon magenta and cyan"
        case .rosewood: return "Rose gold on plum"
        case .graphite: return "Graphite and champagne"
        case .glacier: return "Icy light, deep teal"
        case .adaptive: return "Accents from artwork"
        case .auto: return "Follows iOS Light / Dark"
        }
    }
}

struct GlassTheme: Equatable {
    var id: ThemeID
    var isLight: Bool
    /// Canvas gradient (top, middle, bottom) and the soft glow behind the controls.
    var canvasTop: Color
    var canvasMid: Color
    var canvasBottom: Color
    var glow: Color
    /// Tint inside ordinary glass and how strong it is.
    var glassTint: Color
    var glassTintOpacity: Double
    /// Accent (selected states, progress, focus) and a secondary accent for highlights.
    var accent: Color
    var accent2: Color
    /// How strongly the accent tints a selected glass lens / accent surface.
    var lensOpacity: Double
    var accentSurfaceOpacity: Double
    /// Base colour of rim highlights and borders.
    var rim: Color

    var scheme: ColorScheme? { id == .auto ? nil : (isLight ? .light : .dark) }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    // Dark base shared by the coloured dark themes.
    private static func dark(_ id: ThemeID, top: UInt32, mid: UInt32, bottom: UInt32, glow: UInt32, glowOpacity: Double = 0.30,
                             tint: UInt32, tintOpacity: Double, accent: UInt32, accent2: UInt32) -> GlassTheme {
        GlassTheme(id: id, isLight: false,
                   canvasTop: rgb(top), canvasMid: rgb(mid), canvasBottom: rgb(bottom), glow: rgb(glow).opacity(glowOpacity),
                   glassTint: rgb(tint), glassTintOpacity: tintOpacity,
                   accent: rgb(accent), accent2: rgb(accent2), lensOpacity: 0.34, accentSurfaceOpacity: 0.40,
                   rim: rgb(accent2))
    }

    static let defaultDark = GlassTheme(
        id: .defaultDark, isLight: false,
        canvasTop: Color(white: 0.035), canvasMid: Color(white: 0.075), canvasBottom: .black,
        glow: Color(white: 0.11).opacity(0.7),
        glassTint: Color(white: 0.09), glassTintOpacity: 0.20,
        accent: Color(white: 0.92), accent2: Color(white: 0.70),
        lensOpacity: 0.10, accentSurfaceOpacity: 0.10, rim: .white)

    static let deepBlue = dark(.deepBlue, top: 0x010A18, mid: 0x06234A, bottom: 0x010612, glow: 0x1E6BFF,
                               tint: 0x0F3C82, tintOpacity: 0.30, accent: 0x2A8CFF, accent2: 0x4FD0FF)
    static let violet = dark(.violet, top: 0x080312, mid: 0x25104A, bottom: 0x05020C, glow: 0x8B3DFF,
                             tint: 0x3A1478, tintOpacity: 0.30, accent: 0xA45CFF, accent2: 0xC9A0FF)
    static let amber = dark(.amber, top: 0x0A0502, mid: 0x2B160A, bottom: 0x060301, glow: 0xFF8A1F,
                            tint: 0x6B3A0C, tintOpacity: 0.30, accent: 0xFF9A1F, accent2: 0xFFC247)
    static let forest = dark(.forest, top: 0x010805, mid: 0x0B2C1B, bottom: 0x010603, glow: 0x1FBF6A,
                             tint: 0x0F5530, tintOpacity: 0.30, accent: 0x2DD47A, accent2: 0x7DF0B0)
    static let crimson = dark(.crimson, top: 0x090203, mid: 0x30070D, bottom: 0x050102, glow: 0xE11D48,
                              tint: 0x7A0F23, tintOpacity: 0.30, accent: 0xF0324F, accent2: 0xFF7A8E)
    static let ocean = dark(.ocean, top: 0x00100F, mid: 0x04343A, bottom: 0x000A0B, glow: 0x14C2D6,
                            tint: 0x0A5B66, tintOpacity: 0.30, accent: 0x18C9DC, accent2: 0x5BE3D0)
    // Phase 8 themes: each has its own hue family, accent pair and canvas, not a recolour of another.
    static let synthwave = dark(.synthwave, top: 0x0B0218, mid: 0x2A0A45, bottom: 0x05010D, glow: 0xFF2BD6, glowOpacity: 0.26,
                                tint: 0x3B0F5E, tintOpacity: 0.32, accent: 0xFF3FD8, accent2: 0x3FE0FF)
    static let rosewood = dark(.rosewood, top: 0x0E0507, mid: 0x3A1820, bottom: 0x070203, glow: 0xE8A08C, glowOpacity: 0.24,
                               tint: 0x5A2430, tintOpacity: 0.30, accent: 0xF2A48F, accent2: 0xFFD3B8)
    static let graphite = dark(.graphite, top: 0x0C0D0F, mid: 0x1C1F24, bottom: 0x050607, glow: 0xC9A46A, glowOpacity: 0.18,
                               tint: 0x2A2D33, tintOpacity: 0.26, accent: 0xD9B27A, accent2: 0xF0D9AE)

    static let lightGlass = GlassTheme(
        id: .lightGlass, isLight: true,
        canvasTop: rgb(0xF4F7FD), canvasMid: rgb(0xDDE6F6), canvasBottom: rgb(0xC9D5EC),
        glow: rgb(0xFFFFFF).opacity(0.7),
        glassTint: rgb(0xFFFFFF), glassTintOpacity: 0.28,
        accent: rgb(0x3F78D8), accent2: rgb(0x7FB0F0), lensOpacity: 0.20, accentSurfaceOpacity: 0.24, rim: .white)

    static let glassWhite = GlassTheme(
        id: .glassWhite, isLight: true,
        canvasTop: rgb(0xFAFAFB), canvasMid: rgb(0xEEEEF1), canvasBottom: rgb(0xE0E0E5),
        glow: rgb(0xFFFFFF).opacity(0.85),
        glassTint: rgb(0xFFFFFF), glassTintOpacity: 0.40,
        accent: rgb(0x6B6B75), accent2: rgb(0x9A9AA3), lensOpacity: 0.12, accentSurfaceOpacity: 0.14, rim: .white)

    static let glacier = GlassTheme(
        id: .glacier, isLight: true,
        canvasTop: rgb(0xEEF8FB), canvasMid: rgb(0xD3ECF3), canvasBottom: rgb(0xB8DCE8),
        glow: rgb(0xFFFFFF).opacity(0.75),
        glassTint: rgb(0xF4FCFF), glassTintOpacity: 0.30,
        accent: rgb(0x0E8FB0), accent2: rgb(0x5CC8DE), lensOpacity: 0.20, accentSurfaceOpacity: 0.24, rim: .white)

    static func base(for id: ThemeID, systemScheme: ColorScheme) -> GlassTheme {
        switch id {
        case .defaultDark: return defaultDark
        case .deepBlue: return deepBlue
        case .violet: return violet
        case .amber: return amber
        case .lightGlass: return lightGlass
        case .forest: return forest
        case .crimson: return crimson
        case .ocean: return ocean
        case .glassWhite: return glassWhite
        case .synthwave: return synthwave
        case .rosewood: return rosewood
        case .graphite: return graphite
        case .glacier: return glacier
        case .adaptive: var t = defaultDark; t.id = .adaptive; return t
        case .auto:
            var t = systemScheme == .light ? lightGlass : defaultDark
            t.id = .auto
            return t
        }
    }

    /// Adaptive: the default dark/light base with accents (and only a trace of canvas tint) taken from
    /// the shared artwork palette. A neutral palette leaves the base untouched.
    func adapted(to palette: ArtworkPalette) -> GlassTheme {
        guard !palette.isNeutral else { return self }
        var t = self
        let accent = palette.accentColor(light: isLight)
        let accent2 = palette.secondaryColor(light: isLight)
        t.accent = accent; t.accent2 = accent2
        let k = palette.intensity
        t.lensOpacity = (isLight ? 0.22 : 0.30) * k
        t.accentSurfaceOpacity = (isLight ? 0.26 : 0.34) * k
        t.rim = isLight ? .white : accent2
        t.glassTint = palette.glassTint(light: isLight)
        t.glassTintOpacity = (isLight ? 0.28 : 0.24) * k
        if !isLight {
            t.canvasMid = palette.canvasColor()
            t.glow = accent.opacity(0.20 * k)
        } else {
            t.glow = accent.opacity(0.16 * k)
        }
        return t
    }
}


// MARK: - Contrast tokens
//
// Surfaces and text pick their separation from these tokens, never from the accent. That keeps the
// dock, selectors and controls legible whatever Adaptive extracts from artwork, and it is the single
// place to tune light-theme visibility. Dark themes keep their existing look: every token that was
// not needed there is clear or very faint.

extension GlassTheme {
    /// Hairline that keeps a glass surface visible against its own canvas.
    var edge: Color { isLight ? Color(white: 0.10).opacity(0.20) : rim.opacity(0.22) }
    /// Stronger hairline for surfaces that sit over busy content (the dock).
    var edgeStrong: Color { isLight ? Color(white: 0.10).opacity(0.30) : rim.opacity(0.34) }
    /// Soft contact shadow that separates bright glass from a bright canvas. Dark themes need none.
    var separationShadow: Color { isLight ? Color.black.opacity(0.11) : .clear }

    /// Under-glass wash for ordinary controls (segmented bars, search). Light themes get a faint
    /// ink tint so a white bar is not white-on-white; dark themes are unchanged.
    var controlScrim: Color { isLight ? Color(white: 0.10).opacity(0.045) : .clear }

    // Dock: its own polarity-opposed scrim guarantees label contrast over any page content.
    var dockScrim: Color { isLight ? Color.white.opacity(0.58) : Color.black.opacity(0.40) }
    var dockInk: Color { isLight ? Color(white: 0.08) : .white }
    var dockInkInactive: Color { isLight ? Color(white: 0.08).opacity(0.62) : Color.white.opacity(0.70) }

    /// Accent used to tint selected lenses. Adaptive clamps its luminance so a very bright artwork
    /// colour can never wash out the selected label; fixed themes use their accent unchanged.
    var lensTint: Color {
        guard id == .adaptive else { return accent }
        return ColorMath.clamped(accent, maxLuminance: isLight ? 0.30 : 0.36)
    }
    /// Selected-lens fill and edge: obvious on light surfaces, a faint rim on dark ones.
    var lensFill: Color { isLight ? lensTint.opacity(0.14) : .clear }
    var lensEdge: Color { isLight ? lensTint.opacity(0.55) : rim.opacity(0.18) }

    /// Outline drawn on ordinary glass: light themes only (dark glass already carries its own rim).
    var controlEdge: Color { isLight ? edge : .clear }
    /// Outline of the dock: always present, faint on dark.
    var dockEdge: Color { isLight ? edgeStrong : rim.opacity(0.16) }
}

/// Small colour maths shared by the palette and the contrast tokens (pure; unit tested).
enum ColorMath {
    /// HSV (all 0...1) to sRGB.
    static func rgb(hue h: Double, saturation s: Double, value v: Double) -> (r: Double, g: Double, b: Double) {
        let hh = (h - h.rounded(.down)) * 6
        let i = Int(hh) % 6
        let f = hh - Double(Int(hh))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func hsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// WCAG relative luminance of an sRGB colour.
    static func luminance(r: Double, g: Double, b: Double) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The colour of this hue whose luminance is `target`. Saturation is eased off first when the hue
    /// cannot get that bright at full value (pure blue tops out at ~7 % luminance), so a dark-theme
    /// accent turns periwinkle rather than staying murky. Perceptually even across hues.
    static func color(hue: Double, saturation: Double, luminance target: Double) -> (r: Double, g: Double, b: Double) {
        var s = min(max(saturation, 0), 1)
        for _ in 0..<16 {
            let top = rgb(hue: hue, saturation: s, value: 1)
            if luminance(r: top.r, g: top.g, b: top.b) >= target || s <= 0.02 { break }
            s *= 0.88
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<22 {
            let mid = (lo + hi) / 2
            let c = rgb(hue: hue, saturation: s, value: mid)
            if luminance(r: c.r, g: c.g, b: c.b) < target { lo = mid } else { hi = mid }
        }
        return rgb(hue: hue, saturation: s, value: hi)
    }

    /// `color` with its luminance reduced to at most `maxLuminance` (unchanged when already darker).
    static func clamped(_ color: Color, maxLuminance: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let l = luminance(r: Double(r), g: Double(g), b: Double(b))
        guard l > maxLuminance, l > 0 else { return color }
        let parts = Self.hsv(r: Double(r), g: Double(g), b: Double(b))
        let c = Self.color(hue: parts.h, saturation: parts.s, luminance: maxLuminance)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

// MARK: - Primary action (Play) colours

extension GlassTheme {
    /// Rough perceived brightness of a colour, 0...1 (sRGB weights, no linearisation).
    static func luminance(of color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
        return Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
    }

    /// True when the accent is a grey (Default Dark, Glass White, Auto, Adaptive with no artwork).
    var accentIsNeutral: Bool {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        guard UIColor(accent).getHue(&h, saturation: &s, brightness: &v, alpha: &a) else { return true }
        return s < 0.15
    }

    /// Phase 8: Play's fill. Neutral dark themes get a quiet frosted pill instead of a solid white slab;
    /// neutral light themes a soft graphite pill; coloured themes keep their accent.
    var playFill: Color {
        if accentIsNeutral { return isLight ? Color(white: 0.16).opacity(0.88) : Color.white.opacity(0.16) }
        return accent.opacity(0.92)
    }

    /// Text and glyph colour on `playFill`: dark on bright accents, white otherwise.
    var playInk: Color {
        if accentIsNeutral { return .white }
        return GlassTheme.luminance(of: accent) > 0.6 ? Color(white: 0.06) : .white
    }
}

private struct GlassThemeKey: EnvironmentKey { static let defaultValue = GlassTheme.defaultDark }
extension EnvironmentValues {
    var glassTheme: GlassTheme {
        get { self[GlassThemeKey.self] }
        set { self[GlassThemeKey.self] = newValue }
    }
}

extension Color {
    /// Very faint foreground used for tertiary labels and decorative metadata.
    /// Lifted more aggressively in light appearance so it remains visible on pale glass.
    static func inkFaint(_ a: Double) -> Color {
        Color(UIColor { trait in
            let alpha: Double
            if trait.userInterfaceStyle == .light {
                alpha = a + (1 - a) * 0.48
                return UIColor(white: 0.10, alpha: CGFloat(min(1, max(0, alpha))))
            }
            return UIColor(white: 1, alpha: CGFloat(min(1, max(0, a))))
        })
    }

    /// Primary foreground: white in dark scheme, near-black in light scheme. Use instead of `.white`
    /// for text and icons (leave literal `Color.white` for content drawn over posters).
    static let ink = Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(white: 0.08, alpha: 1) : .white })
    /// The opposite of `ink`: for glyphs drawn on top of an `ink`-coloured fill.
    static let inkInverse = Color(UIColor { $0.userInterfaceStyle == .light ? .white : UIColor(white: 0.05, alpha: 1) })

    /// Secondary / tertiary foreground. Identical to `ink.opacity(a)` in dark scheme. In light scheme
    /// the opacity of text-weight values (0.4 to 0.99) is lifted 30 % of the way to opaque, so captions and
    /// inactive icons keep roughly 4.5:1 against pale glass instead of fading into it.
    static func inkAlpha(_ a: Double) -> Color {
        Color(UIColor { trait in
            if trait.userInterfaceStyle == .light {
                let lifted = (a >= 0.4 && a < 1) ? a + (1 - a) * 0.30 : a
                return UIColor(white: 0.08, alpha: CGFloat(lifted))
            }
            return UIColor(white: 1, alpha: CGFloat(a))
        })
    }
}

// MARK: - Artwork palette (Adaptive)

/// Dominant colours of an artwork, stored raw (hue / saturation / brightness). Concrete colours are
/// generated per scheme by matching a target *luminance*, not a fixed brightness, so a yellow, a blue
/// and a red poster all produce accents of the same visual weight, and saturation is compressed so a
/// loud poster never makes the whole interface neon.
struct ArtworkPalette: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var secondaryHue: Double
    var isNeutral: Bool
    /// Share (0...1) of the centre-weighted image that carries real colour. Mostly-monochrome art
    /// has a low value and gets a quieter accent.
    var coverage: Double = 1
    /// Mean brightness of the whole image (0 = black, 1 = white).
    var meanBrightness: Double = 0.5
    /// Saturation of the secondary hue's region.
    var secondarySaturation: Double = 0.5
    /// Blend amount of the artwork tint (0 = neutral, 1 = fully applied).
    var strength: Double = 1

    static let neutral = ArtworkPalette(hue: 0, saturation: 0, brightness: 0.8, secondaryHue: 0, isNeutral: true, strength: 0)

    /// Smoothly interpolates between palettes using the shortest path around the hue wheel.
    /// This is used when artwork changes so the interface fades instead of snapping.
    func mixed(to other: ArtworkPalette, _ amount: Double) -> ArtworkPalette {
        let t = min(max(amount, 0), 1)
        func hueMix(_ a: Double, _ b: Double) -> Double {
            var delta = b - a
            if delta > 0.5 { delta -= 1 }
            if delta < -0.5 { delta += 1 }
            let value = (a + delta * t).truncatingRemainder(dividingBy: 1)
            return value < 0 ? value + 1 : value
        }
        return ArtworkPalette(
            hue: hueMix(hue, other.hue),
            saturation: saturation + (other.saturation - saturation) * t,
            brightness: brightness + (other.brightness - brightness) * t,
            secondaryHue: hueMix(secondaryHue, other.secondaryHue),
            isNeutral: t >= 1 ? other.isNeutral : (t <= 0 ? isNeutral : false),
            coverage: coverage + (other.coverage - coverage) * t,
            meanBrightness: meanBrightness + (other.meanBrightness - meanBrightness) * t,
            secondarySaturation: secondarySaturation + (other.secondarySaturation - secondarySaturation) * t,
            strength: strength + (other.strength - strength) * t
        )
    }

    /// 0.6...1: how strongly the palette is allowed to tint the interface.
    var intensity: Double { 0.6 + 0.4 * min(1, coverage * 4) }

    /// Source saturation compressed into a calm range (0.30 ... 0.74).
    private var calmSaturation: Double { (0.30 + 0.44 * min(max(saturation, 0), 1)) * (0.80 + 0.20 * min(1, coverage * 4)) }

    private func tone(hue: Double, saturation: Double, luminance: Double) -> Color {
        let c = ColorMath.color(hue: hue, saturation: saturation, luminance: luminance)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Accent: luminance 0.36 on dark (reads as text on the dark canvas, and white labels stay legible
    /// over it), 0.17 on light (about 5:1 against the pale canvas).
    func accentColor(light: Bool) -> Color {
        tone(hue: hue, saturation: calmSaturation, luminance: light ? 0.17 : 0.36)
    }

    /// Secondary accent: lighter and softer, from the second distinct hue when the artwork has one.
    func secondaryColor(light: Bool) -> Color {
        let s = min(max(secondarySaturation * 0.8, 0.25), 0.55)
        return tone(hue: secondaryHue, saturation: s, luminance: light ? 0.30 : 0.55)
    }

    func glassTint(light: Bool) -> Color {
        light ? Color(hue: hue, saturation: 0.18, brightness: 1.0)
              : Color(hue: hue, saturation: 0.42 + 0.16 * min(1, coverage * 4), brightness: 0.34)
    }

    /// A very dark wash of the hue: the canvas only hints at the artwork. Dark artwork gets a touch
    /// less so the page does not turn muddy.
    func canvasColor() -> Color {
        Color(hue: hue, saturation: 0.60, brightness: 0.13 + 0.05 * min(1, meanBrightness * 2))
    }

    /// True when `other` is close enough that recolouring the interface would be noise, not change.
    func isSimilar(to other: ArtworkPalette) -> Bool {
        guard isNeutral == other.isNeutral else { return false }
        if isNeutral { return true }
        let d = abs(hue - other.hue)
        return min(d, 1 - d) < 0.02 && abs(saturation - other.saturation) < 0.06 && abs(brightness - other.brightness) < 0.08
    }
}

enum ArtworkPaletteExtractor {
    /// Edge of the square the artwork is reduced to before analysis.
    static let sampleSide = 48

    /// Downsamples to 48x48 and analyses it. Runs off the main thread. Returns `.neutral` for
    /// greyscale artwork. Pure: no network, no state.
    static func extract(from image: UIImage) -> ArtworkPalette {
        guard let cg = image.cgImage else { return .neutral }
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return .neutral }
        return palette(fromRGBA: pixels)
    }

    /// Weighted hue histogram.
    ///  - Centre-weighted: posters carry borders, letterboxing and credits at the edges, which say
    ///    nothing about the picture, so edge pixels count for a quarter of centre pixels.
    ///  - A pixel's weight is area x saturation x (0.3 + 0.7 x brightness): vivid regions beat dull
    ///    ones, yet dark but tinted artwork still registers (brightness floor 0.14).
    ///  - Near-grey, near-black and blown-out pixels are ignored.
    ///  - Weight is shared with the two neighbouring bins, so a hue sitting on a bin boundary is not
    ///    split into two weak bins, and the final hue is the circular mean of the winning bins.
    ///  - The secondary hue is the best bin at least three bins (45 degrees) away, if it carries at
    ///    least a quarter of the primary's weight.
    /// `pixels` is RGBA, row-major; a square image gets the centre weighting, anything else is uniform.
    static func palette(fromRGBA pixels: [UInt8]) -> ArtworkPalette {
        let bins = 24
        let count = pixels.count / 4
        guard count > 0 else { return .neutral }
        let side = Int(Double(count).squareRoot().rounded())
        let square = side * side == count

        var weight = [Double](repeating: 0, count: bins)
        var sat = [Double](repeating: 0, count: bins)
        var bri = [Double](repeating: 0, count: bins)
        var sinSum = [Double](repeating: 0, count: bins)
        var cosSum = [Double](repeating: 0, count: bins)
        var totalMass = 0.0, colouredMass = 0.0, brightnessSum = 0.0

        for i in 0..<count {
            let alpha = Double(pixels[i * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[i * 4]) / 255 / alpha, g = Double(pixels[i * 4 + 1]) / 255 / alpha, b = Double(pixels[i * 4 + 2]) / 255 / alpha
            let c = ColorMath.hsv(r: min(r, 1), g: min(g, 1), b: min(b, 1))

            var position = 1.0
            if square {
                let nx = (Double(i % side) + 0.5) / Double(side) * 2 - 1
                let ny = (Double(i / side) + 0.5) / Double(side) * 2 - 1
                position = max(0.25, 1 - 0.75 * (nx * nx + ny * ny) / 1.4)
            }
            totalMass += position
            brightnessSum += c.v * position

            guard c.s > 0.22, c.v > 0.14, c.v < 0.99 else { continue }
            let w = position * c.s * (0.30 + 0.70 * c.v)
            colouredMass += position
            let bin = min(Int(c.h * Double(bins)), bins - 1)
            let angle = c.h * 2 * Double.pi
            for (offset, share) in [(-1, 0.25), (0, 1.0), (1, 0.25)] {
                let target = (bin + offset + bins) % bins
                weight[target] += w * share
                sat[target] += w * share * c.s
                bri[target] += w * share * c.v
                sinSum[target] += w * share * sin(angle)
                cosSum[target] += w * share * cos(angle)
            }
        }

        let coverage = totalMass > 0 ? colouredMass / totalMass : 0
        let mean = totalMass > 0 ? brightnessSum / totalMass : 0
        // Less than ~5 % of the picture carries colour: greyscale / monochrome art.
        guard coverage > 0.05, let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return .neutral }

        func hue(around bin: Int) -> Double {
            var s = 0.0, c = 0.0
            for offset in -1...1 {
                let idx = (bin + offset + bins) % bins
                s += sinSum[idx]; c += cosSum[idx]
            }
            var h = atan2(s, c) / (2 * Double.pi)
            if h < 0 { h += 1 }
            return h
        }

        let primaryHue = hue(around: best)
        let second = weight.indices.filter { idx in
            let d = abs(idx - best); return min(d, bins - d) >= 3
        }.max(by: { weight[$0] < weight[$1] })

        var secondaryHue = (primaryHue + 0.07).truncatingRemainder(dividingBy: 1)
        var secondarySat = sat[best] / weight[best]
        if let second, weight[second] > weight[best] * 0.25 {
            secondaryHue = hue(around: second)
            secondarySat = sat[second] / weight[second]
        }
        return ArtworkPalette(hue: primaryHue, saturation: sat[best] / weight[best], brightness: bri[best] / weight[best],
                              secondaryHue: secondaryHue, isNeutral: false,
                              coverage: coverage, meanBrightness: mean, secondarySaturation: secondarySat)
    }
}

// MARK: - Store

enum AmbientStyle: String, CaseIterable, Identifiable {
    case none, blue, violet, ember, teal, aurora, dusk, nebula, prism, mist
    var id: String { rawValue }

    /// Phase 8 removed "Mountains"; a stored value migrates to Dusk (the closest warm sky). Unknown → Off.
    static func migrated(_ raw: String?) -> AmbientStyle {
        guard let raw else { return .none }
        if raw == "mountains" { return .dusk }
        return AmbientStyle(rawValue: raw) ?? .none
    }
    var title: String {
        switch self {
        case .none: return "Off"
        case .blue: return "Blue flow"
        case .violet: return "Violet flow"
        case .ember: return "Ember"
        case .teal: return "Teal"
        case .aurora: return "Aurora"
        case .dusk: return "Dusk"
        case .nebula: return "Nebula"
        case .prism: return "Prism"
        case .mist: return "Mist"
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let themeKey = "glassRemote.theme"
    private static let ambientKey = "glassRemote.ambient"

    @Published var selected: ThemeID {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.themeKey)
            if selected == .adaptive { recompute(immediate: true) }
        }
    }
    @Published var ambient: AmbientStyle {
        didSet { UserDefaults.standard.set(ambient.rawValue, forKey: Self.ambientKey) }
    }
    /// The ONE shared Adaptive palette. Pages only submit artwork; none derives its own colours.
    @Published private(set) var palette: ArtworkPalette = .neutral

    private var sources: [AppPage: URL] = [:]
    private var page: AppPage = .remote
    private var cache: [URL: ArtworkPalette] = [:]
    private var task: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    init() {
        selected = ThemeID(rawValue: UserDefaults.standard.string(forKey: Self.themeKey) ?? "") ?? .defaultDark
        let storedAmbient = UserDefaults.standard.string(forKey: Self.ambientKey)
        ambient = AmbientStyle.migrated(storedAmbient)
        if let storedAmbient, storedAmbient != ambient.rawValue {
            UserDefaults.standard.set(ambient.rawValue, forKey: Self.ambientKey)
        }
    }

    func theme(systemScheme: ColorScheme) -> GlassTheme {
        let base = GlassTheme.base(for: selected, systemScheme: systemScheme)
        return selected == .adaptive ? base.adapted(to: palette) : base
    }

    /// A page tells the store which artwork it is currently showing (nil = none).
    func submitArtwork(_ url: URL?, for page: AppPage) {
        guard sources[page] != url else { return }
        sources[page] = url
        recompute()
    }

    func pageChanged(_ page: AppPage) {
        guard self.page != page else { return }
        self.page = page
        recompute()
    }

    /// Discover and Player prefer their own artwork; Remote follows what is playing, else Discover.
    private var activeURL: URL? {
        switch page {
        case .discover: return sources[.discover] ?? sources[.player]
        case .player, .remote, .profile: return sources[.player] ?? sources[.discover]
        }
    }

    /// Delays (seconds) before a change of artwork recolours the UI. A short settle absorbs rapid
    /// changes (a hero image loading, a page swipe passing through); a longer grace stops the
    /// interface flashing to neutral while a page simply has no artwork for a moment.
    static let settleDelay: TimeInterval = 0.25
    static let neutralGrace: TimeInterval = 1.5

    private func recompute(immediate: Bool = false) {
        guard selected == .adaptive else { return }
        task?.cancel()
        guard let url = activeURL else { settle(.neutral, after: immediate ? 0 : Self.neutralGrace); return }
        if let hit = cache[url] { settle(hit, after: immediate ? 0 : Self.settleDelay); return }
        task = Task { [weak self] in
            guard let image = await ArtworkCache.shared.image(for: url), !Task.isCancelled else { return }
            // Pixel work off the main thread; the result is cached per URL so an image is never processed twice.
            let result = await Task.detached(priority: .utility) { ArtworkPaletteExtractor.extract(from: image) }.value
            guard !Task.isCancelled, let self else { return }
            self.cache[url] = result
            if self.activeURL == url { self.settle(result, after: immediate ? 0 : Self.settleDelay) }
        }
    }

    private func settle(_ new: ArtworkPalette, after delay: TimeInterval) {
        settleTask?.cancel()
        guard !palette.isSimilar(to: new) else { return }
        if delay <= 0 { commit(new); return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.commit(new)
        }
    }

    private func commit(_ new: ArtworkPalette) {
        guard new != palette else { return }
        withAnimation(.easeInOut(duration: 0.8)) { palette = new }
    }
}

/// Applies the active theme to everything below it. The app's models live above this view, so a
/// theme change cannot touch ADB, helpers or playback state.
struct ThemedRoot<Content: View>: View {
    @ObservedObject private var store = ThemeStore.shared
    @Environment(\.colorScheme) private var systemScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let theme = store.theme(systemScheme: systemScheme)
        content()
            .environment(\.glassTheme, theme)
            .preferredColorScheme(theme.scheme)
            .tint(theme.accent)
    }
}

extension View {
    /// For sheets: same scheme as the app, canvas behind, theme inherited from the environment.
    func themedSheet() -> some View { modifier(ThemedSheetModifier()) }
}

private struct ThemedSheetModifier: ViewModifier {
    @Environment(\.glassTheme) private var theme
    func body(content: Content) -> some View {
        content.preferredColorScheme(theme.scheme).tint(theme.accent)
    }
}

// MARK: - Ambient backgrounds (optional, drawn, no image assets)

struct AmbientArtwork: View {
    let style: AmbientStyle
    @Environment(\.glassTheme) private var theme

    var body: some View {
        ZStack {
            switch style {
            case .none: EmptyView()
            case .blue: flow([Color(red: 0.1, green: 0.4, blue: 1), Color(red: 0.2, green: 0.8, blue: 1)], bg: Color(red: 0.01, green: 0.05, blue: 0.15))
            case .violet: flow([Color(red: 0.6, green: 0.2, blue: 1), Color(red: 1, green: 0.4, blue: 0.9)], bg: Color(red: 0.05, green: 0.01, blue: 0.12))
            case .ember: flow([Color(red: 1, green: 0.4, blue: 0.05), Color(red: 1, green: 0.75, blue: 0.2)], bg: Color(red: 0.1, green: 0.03, blue: 0.01))
            case .teal: flow([Color(red: 0.0, green: 0.7, blue: 0.7), Color(red: 0.3, green: 0.95, blue: 0.8)], bg: Color(red: 0.0, green: 0.07, blue: 0.08))
            case .aurora: aurora
            case .dusk: dusk
            case .nebula: nebula
            case .prism: prism
            case .mist: mist
            }
        }
        // A scrim keeps text and glass legible whatever the picture does.
        .overlay((theme.isLight ? Color.white.opacity(0.55) : Color.black.opacity(0.38)))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .drawingGroup()
    }

    private func flow(_ colors: [Color], bg: Color) -> some View {
        GeometryReader { geo in
            ZStack {
                bg
                FlowCurve(phase: 0).stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), lineWidth: 46)
                    .blur(radius: 26).opacity(0.85)
                FlowCurve(phase: 0.35).stroke(LinearGradient(colors: colors.reversed(), startPoint: .leading, endPoint: .trailing), lineWidth: 16)
                    .blur(radius: 10).opacity(0.7)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var aurora: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.01, green: 0.03, blue: 0.1), Color(red: 0.02, green: 0.1, blue: 0.12)], startPoint: .top, endPoint: .bottom)
                FlowCurve(phase: 0.1).stroke(LinearGradient(colors: [Color.green, Color.teal, Color.purple.opacity(0.7)], startPoint: .leading, endPoint: .trailing), lineWidth: 70)
                    .blur(radius: 34).opacity(0.75).offset(y: -geo.size.height * 0.18)
                FlowCurve(phase: 0.55).stroke(LinearGradient(colors: [Color.mint, Color.cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing), lineWidth: 26)
                    .blur(radius: 16).opacity(0.6).offset(y: -geo.size.height * 0.10)
            }
        }
    }

    // Phase 8 backgrounds: all drawn and static (no timers, nothing renders while idle).
    private var dusk: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.06, green: 0.05, blue: 0.20), Color(red: 0.42, green: 0.14, blue: 0.32),
                                        Color(red: 0.95, green: 0.45, blue: 0.30)], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.76, blue: 0.46).opacity(0.9), .clear],
                                         center: .center, startRadius: 0, endRadius: geo.size.width * 0.45))
                    .frame(width: geo.size.width * 0.9, height: geo.size.width * 0.9)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.92)
                FlowCurve(phase: 0.7)
                    .stroke(LinearGradient(colors: [Color.pink.opacity(0.6), Color.orange.opacity(0.5)], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 30)
                    .blur(radius: 22).opacity(0.6)
            }
        }
    }

    private var nebula: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(red: 0.03, green: 0.01, blue: 0.08)
                blob(Color(red: 0.55, green: 0.15, blue: 0.95), size: w * 1.1).position(x: w * 0.2, y: h * 0.3)
                blob(Color(red: 1.0, green: 0.3, blue: 0.6), size: w * 0.9).position(x: w * 0.85, y: h * 0.55)
                blob(Color(red: 0.2, green: 0.5, blue: 1.0), size: w * 0.8).position(x: w * 0.4, y: h * 0.85)
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.75), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }

    private var prism: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.05)
            ForEach(0..<4, id: \.self) { i in
                FlowCurve(phase: Double(i) * 0.22)
                    .stroke(LinearGradient(colors: prismColors(i), startPoint: .leading, endPoint: .trailing), lineWidth: 10)
                    .blur(radius: 7).opacity(0.75)
            }
        }
    }

    private func prismColors(_ i: Int) -> [Color] {
        let all: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
        return [all[i % all.count], all[(i + 2) % all.count], all[(i + 4) % all.count]]
    }

    private var mist: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.72, green: 0.80, blue: 0.90), Color(red: 0.50, green: 0.60, blue: 0.72)],
                               startPoint: .top, endPoint: .bottom)
                FlowCurve(phase: 0.2).stroke(Color.white.opacity(0.7), lineWidth: 80).blur(radius: 40).offset(y: -geo.size.height * 0.1)
                FlowCurve(phase: 0.6).stroke(Color.white.opacity(0.5), lineWidth: 50).blur(radius: 30)
            }
        }
    }
}

private struct FlowCurve: Shape {
    var phase: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y0 = rect.height * (0.78 - phase * 0.3)
        p.move(to: CGPoint(x: -rect.width * 0.1, y: y0))
        p.addCurve(to: CGPoint(x: rect.width * 1.1, y: rect.height * (0.22 + phase * 0.2)),
                   control1: CGPoint(x: rect.width * 0.35, y: rect.height * (0.95 - phase * 0.2)),
                   control2: CGPoint(x: rect.width * 0.6, y: rect.height * (0.1 + phase * 0.3)))
        return p
    }
}

// MARK: - Theme picker

struct ThemePickerSheet: View {
    @ObservedObject private var store = ThemeStore.shared
    @Environment(\.glassTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let coloured: [ThemeID] = [.defaultDark, .deepBlue, .violet, .amber, .lightGlass, .forest, .crimson, .ocean, .glassWhite,
                                       .synthwave, .rosewood, .graphite, .glacier]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Themes").scaledFont(26, .bold)
                    Spacer()
                    Button("Done") { dismiss() }.scaledFont(16, .semibold)
                }
                .padding(.top, 22)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(coloured) { id in card(id) }
                }

                Text("Dynamic").scaledFont(15, .semibold).foregroundStyle(Color.inkAlpha(0.6))
                LazyVGrid(columns: columns, spacing: 16) {
                    card(.adaptive)
                    card(.auto)
                }

                ambientSection
                Text("Adaptive takes its accents from the artwork on screen. Auto follows the iPhone's Light or Dark setting.")
                    .scaledFont(11).foregroundStyle(Color.inkAlpha(0.5))
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
        }
        .foregroundStyle(Color.ink)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
    }

    private func card(_ id: ThemeID) -> some View {
        let preview = preview(for: id)
        let on = store.selected == id
        return Button {
            withAnimation(.easeInOut(duration: 0.35)) { store.selected = id }
            Haptics.soft()
        } label: {
            VStack(spacing: 8) {
                ThemePreview(theme: preview, split: id == .auto ? GlassTheme.lightGlass : nil, rainbow: id == .adaptive && store.palette.isNeutral)
                    .frame(height: 170)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(on ? theme.accent : Color.ink.opacity(0.14), lineWidth: on ? 2.5 : 0.8))
                HStack(spacing: 6) {
                    if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(id.title).scaledFont(14, .semibold)
                        Text(id.subtitle).scaledFont(11).foregroundStyle(Color.inkAlpha(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(PressStyle(haptic: false))
        .accessibilityLabel(id.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func preview(for id: ThemeID) -> GlassTheme {
        let base = GlassTheme.base(for: id, systemScheme: .dark)
        return id == .adaptive ? base.adapted(to: store.palette) : base
    }

    private var ambientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ambient background").scaledFont(15, .semibold).foregroundStyle(Color.inkAlpha(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AmbientStyle.allCases) { style in
                        let on = store.ambient == style
                        Button { withAnimation(.easeInOut(duration: 0.35)) { store.ambient = style }; Haptics.soft() } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ink.opacity(0.08))
                                    if style == .none { Image(systemName: "slash.circle").scaledFont(20, .light).foregroundStyle(Color.inkAlpha(0.5)) }
                                    else { AmbientArtwork(style: style).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
                                }
                                .frame(width: 74, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? theme.accent : Color.ink.opacity(0.14), lineWidth: on ? 2.5 : 0.8))
                                Text(style.title).scaledFont(11, .medium)
                            }
                        }
                        .buttonStyle(PressStyle(haptic: false))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if store.ambient != .none {
                Text("Drawn in-app, dimmed so text and glass stay readable. Posters are never covered.")
                    .scaledFont(11).foregroundStyle(Color.inkAlpha(0.5))
            }
        }
    }
}

/// A miniature of the real Discover screen painted with a theme's own tokens.
struct ThemePreview: View {
    let theme: GlassTheme
    var split: GlassTheme? = nil
    var rainbow = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                phone(theme)
                if let split {
                    phone(split).mask(
                        Path { p in
                            p.move(to: CGPoint(x: geo.size.width, y: 0))
                            p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                            p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                            p.closeSubpath()
                        }
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func phone(_ t: GlassTheme) -> some View {
        let ink: Color = t.isLight ? Color(white: 0.1) : .white
        let accent: AnyShapeStyle = rainbow
            ? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
            : AnyShapeStyle(t.accent)
        return ZStack {
            LinearGradient(colors: [t.canvasTop, t.canvasMid, t.canvasBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [t.glow, .clear], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 120)
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Capsule().fill(t.glassTint.opacity(t.isLight ? 0.7 : 0.45)).frame(height: 13)
                        .overlay(Capsule().stroke(t.rim.opacity(t.isLight ? 0.9 : 0.3), lineWidth: 0.6))
                    Circle().fill(t.glassTint.opacity(0.55)).frame(width: 13, height: 13)
                }
                HStack(spacing: 0) {
                    Capsule().fill(accent).opacity(0.55).frame(height: 10)
                    Capsule().fill(Color.clear).frame(height: 10)
                    Capsule().fill(Color.clear).frame(height: 10)
                }
                .background(Capsule().fill(t.glassTint.opacity(t.isLight ? 0.6 : 0.4)))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [t.accent.opacity(0.55), t.accent2.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 50)
                    .overlay(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.85)).frame(width: 40, height: 4).padding(6)
                    }
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient(colors: [t.accent2.opacity(0.35 + Double(i) * 0.12), t.canvasMid], startPoint: .top, endPoint: .bottom))
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == 2 ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear)).opacity(i == 2 ? 0.55 : 1).frame(height: 14)
                    }
                }
                .background(Capsule().fill(t.glassTint.opacity(t.isLight ? 0.7 : 0.45)).overlay(Capsule().stroke(t.rim.opacity(t.isLight ? 0.9 : 0.3), lineWidth: 0.6)))
            }
            .padding(10)
        }
    }
}
