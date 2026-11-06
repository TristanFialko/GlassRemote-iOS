import SwiftUI
import UIKit

// MARK: - Theme model
//
// One source of truth for appearance. Views never pick colours themselves: they read the active
// `GlassTheme` from the environment (set once at the app root) or use `Color.ink` for text, which
// flips with the window's light/dark scheme. Switching themes only changes environment values: no
// model, page or helper is recreated.

enum ThemeID: String, CaseIterable, Identifiable {
    case defaultDark, deepBlue, violet, amber, lightGlass, forest, crimson, ocean, glassWhite, adaptive, auto
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
        t.lensOpacity = isLight ? 0.22 : 0.30
        t.accentSurfaceOpacity = isLight ? 0.26 : 0.34
        t.rim = isLight ? .white : accent2
        t.glassTint = palette.glassTint(light: isLight)
        t.glassTintOpacity = isLight ? 0.28 : 0.24
        if !isLight {
            t.canvasMid = palette.canvasColor()
            t.glow = accent.opacity(0.20)
        } else {
            t.glow = accent.opacity(0.16)
        }
        return t
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
    /// Primary foreground: white in dark scheme, near-black in light scheme. Use instead of `.white`
    /// for text and icons (leave literal `Color.white` for content drawn over posters).
    static let ink = Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(white: 0.08, alpha: 1) : .white })
    /// The opposite of `ink`: for glyphs drawn on top of an `ink`-coloured fill.
    static let inkInverse = Color(UIColor { $0.userInterfaceStyle == .light ? .white : UIColor(white: 0.05, alpha: 1) })
}

// MARK: - Artwork palette (Adaptive)

/// Dominant hue of an artwork, stored raw (hue / saturation / brightness). Concrete colours are
/// generated per scheme so contrast stays acceptable and saturation is capped.
struct ArtworkPalette: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var secondaryHue: Double
    var isNeutral: Bool

    static let neutral = ArtworkPalette(hue: 0, saturation: 0, brightness: 0.8, secondaryHue: 0, isNeutral: true)

    func accentColor(light: Bool) -> Color {
        light ? Color(hue: hue, saturation: min(max(saturation, 0.5), 0.78), brightness: 0.62)
              : Color(hue: hue, saturation: min(max(saturation, 0.45), 0.72), brightness: min(max(brightness + 0.12, 0.66), 0.92))
    }
    func secondaryColor(light: Bool) -> Color {
        light ? Color(hue: secondaryHue, saturation: 0.45, brightness: 0.78)
              : Color(hue: secondaryHue, saturation: 0.40, brightness: 0.92)
    }
    func glassTint(light: Bool) -> Color {
        light ? Color(hue: hue, saturation: 0.18, brightness: 1.0) : Color(hue: hue, saturation: 0.55, brightness: 0.34)
    }
    /// A very dark wash of the hue: the canvas only hints at the artwork.
    func canvasColor() -> Color { Color(hue: hue, saturation: 0.60, brightness: 0.16) }
}

enum ArtworkPaletteExtractor {
    /// Downsamples to 32x32 and picks the hue bin with the most weight (weight = saturation x
    /// brightness, ignoring near-grey and near-black/white pixels). Runs off the main thread.
    /// Returns `.neutral` for greyscale artwork. Pure: no network, no state.
    static func extract(from image: UIImage) -> ArtworkPalette {
        guard let cg = image.cgImage else { return .neutral }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return .neutral }
        return palette(fromRGBA: pixels)
    }

    static func palette(fromRGBA pixels: [UInt8]) -> ArtworkPalette {
        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var sat = [Double](repeating: 0, count: bins)
        var bri = [Double](repeating: 0, count: bins)
        let count = pixels.count / 4
        for i in 0..<count {
            let r = Double(pixels[i * 4]) / 255, g = Double(pixels[i * 4 + 1]) / 255, b = Double(pixels[i * 4 + 2]) / 255
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            guard s > 0.22, v > 0.16, v < 0.98 else { continue }
            let w = Double(s) * Double(v)
            let bin = min(Int(Double(h) * Double(bins)), bins - 1)
            weight[bin] += w; sat[bin] += w * Double(s); bri[bin] += w * Double(v)
        }
        let total = weight.reduce(0, +)
        // Less than ~4 % of the image carries colour: treat as neutral (greyscale / monochrome art).
        guard total > Double(count) * 0.04, let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return .neutral }
        let hue = (Double(best) + 0.5) / Double(bins)
        let second = weight.indices.filter { idx in
            let d = abs(idx - best); return min(d, bins - d) >= 3
        }.max(by: { weight[$0] < weight[$1] })
        let secondHue = (second.map { weight[$0] > weight[best] * 0.25 ? (Double($0) + 0.5) / Double(bins) : nil } ?? nil)
            ?? (hue + 0.06).truncatingRemainder(dividingBy: 1)
        return ArtworkPalette(hue: hue, saturation: sat[best] / weight[best], brightness: bri[best] / weight[best],
                              secondaryHue: secondHue, isNeutral: false)
    }
}

// MARK: - Store

enum AmbientStyle: String, CaseIterable, Identifiable {
    case none, blue, violet, ember, teal, aurora, mountains
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Off"
        case .blue: return "Blue flow"
        case .violet: return "Violet flow"
        case .ember: return "Ember"
        case .teal: return "Teal"
        case .aurora: return "Aurora"
        case .mountains: return "Mountains"
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
            if selected == .adaptive { recompute() }
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

    init() {
        selected = ThemeID(rawValue: UserDefaults.standard.string(forKey: Self.themeKey) ?? "") ?? .defaultDark
        ambient = AmbientStyle(rawValue: UserDefaults.standard.string(forKey: Self.ambientKey) ?? "") ?? .none
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
        case .player, .remote: return sources[.player] ?? sources[.discover]
        }
    }

    private func recompute() {
        guard selected == .adaptive else { return }
        task?.cancel()
        guard let url = activeURL else { apply(.neutral); return }
        if let hit = cache[url] { apply(hit); return }
        task = Task { [weak self] in
            guard let image = await ArtworkCache.shared.image(for: url), !Task.isCancelled else { return }
            // Pixel work off the main thread; the result is cached per URL so an image is never processed twice.
            let result = await Task.detached(priority: .utility) { ArtworkPaletteExtractor.extract(from: image) }.value
            guard !Task.isCancelled, let self else { return }
            self.cache[url] = result
            if self.activeURL == url { self.apply(result) }
        }
    }

    private func apply(_ new: ArtworkPalette) {
        guard new != palette else { return }
        withAnimation(.easeInOut(duration: 0.9)) { palette = new }
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
            case .mountains: mountains
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

    private var mountains: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.08, green: 0.1, blue: 0.3), Color(red: 0.85, green: 0.4, blue: 0.3), Color(red: 1, green: 0.7, blue: 0.4)],
                               startPoint: .top, endPoint: .bottom)
                MountainShape(seed: 0).fill(Color(red: 0.2, green: 0.22, blue: 0.4)).frame(height: geo.size.height * 0.42).opacity(0.9)
                MountainShape(seed: 1).fill(Color(red: 0.08, green: 0.08, blue: 0.18)).frame(height: geo.size.height * 0.3)
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

private struct MountainShape: Shape {
    let seed: Int
    func path(in rect: CGRect) -> Path {
        let peaks: [CGFloat] = seed == 0 ? [0, 0.35, 0.2, 0.7, 0.45, 1.0, 0.5, 0.8, 0.3, 0.55, 0] : [0, 0.2, 0.45, 0.25, 0.6, 0.3, 0.4, 0.15, 0]
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height))
        let step = rect.width / CGFloat(max(peaks.count - 1, 1))
        for (i, h) in peaks.enumerated() { p.addLine(to: CGPoint(x: CGFloat(i) * step, y: rect.height * (1 - h))) }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
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
    private let coloured: [ThemeID] = [.defaultDark, .deepBlue, .violet, .amber, .lightGlass, .forest, .crimson, .ocean, .glassWhite]

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

                Text("Dynamic").scaledFont(15, .semibold).foregroundStyle(Color.ink.opacity(0.6))
                LazyVGrid(columns: columns, spacing: 16) {
                    card(.adaptive)
                    card(.auto)
                }

                ambientSection
                Text("Adaptive takes its accents from the artwork on screen. Auto follows the iPhone's Light or Dark setting.")
                    .scaledFont(11).foregroundStyle(Color.ink.opacity(0.5))
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
                        Text(id.subtitle).scaledFont(11).foregroundStyle(Color.ink.opacity(0.55)).lineLimit(1)
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
            Text("Ambient background").scaledFont(15, .semibold).foregroundStyle(Color.ink.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AmbientStyle.allCases) { style in
                        let on = store.ambient == style
                        Button { withAnimation(.easeInOut(duration: 0.35)) { store.ambient = style }; Haptics.soft() } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ink.opacity(0.08))
                                    if style == .none { Image(systemName: "slash.circle").scaledFont(20, .light).foregroundStyle(Color.ink.opacity(0.5)) }
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
                    .scaledFont(11).foregroundStyle(Color.ink.opacity(0.5))
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
