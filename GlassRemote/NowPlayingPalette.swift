import SwiftUI
import UIKit

// Now Playing's adaptive background, Apple Music style: a colour wash made from the artwork's
// prominent colours, not an enlarged or blurred copy of the picture.
//
// 1. `NowPlayingPaletteExtractor` reduces the artwork to 32 x 48 px, buckets the pixels into a 12-bit
//    histogram and clusters the occupied buckets (weighted k-means in OKLab, deterministic seeding).
//    Near-identical clusters are merged and specks under 1.5 % dropped. Runs once per artwork, off the
//    main thread, in `PlayerBackdropStore`.
// 2. `NowPlayingPalette.make` picks four tones: the dominant colour (base), the most vivid colour
//    with a real presence (accent, so a small saturated highlight on dark art still shows), a third
//    colour (support) and a deepened base under the controls (foot). Every tone is clamped into the
//    theme's legible luminance band (`PlayerBackdropPolicy`), keeping its hue.
// 3. `NowPlayingWash` draws them as one 3 x 3 mesh gradient. Nothing is animated per frame.
//
// Pure and unit tested (NowPlayingPaletteTests).

/// One colour region of the artwork (sRGB, 0...1) and its share of the picture's opaque pixels.
struct ArtworkSwatch: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var share: Double
}

enum NowPlayingPaletteExtractor {
    static let sampleWidth = 32
    static let sampleHeight = 48
    static let maxSwatches = 5
    /// Regions smaller than this share are noise (credits, specks), not part of the palette.
    static let minimumShare = 0.015
    /// Clusters closer than this (OKLab distance) are one colour.
    static let mergeDistance = 0.06

    /// Swatches of an image, most prominent first. Empty when nothing could be read.
    static func swatches(from image: UIImage) -> [ArtworkSwatch] {
        guard let cg = image.cgImage else { return [] }
        let width = sampleWidth, height = sampleHeight
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drew ? swatches(rgba: pixels) : []
    }

    private struct Cluster {
        var lab: SIMD3<Double>
        var rgb: SIMD3<Double>
        var weight: Double
    }

    /// Swatches of 8-bit premultiplied RGBA pixels, most prominent first. Pixels under half
    /// opacity are ignored.
    static func swatches(rgba pixels: [UInt8], maxCount: Int = NowPlayingPaletteExtractor.maxSwatches) -> [ArtworkSwatch] {
        // A 12-bit histogram (4 bits per channel): a few hundred occupied bins instead of every pixel.
        var bins: [Int: SIMD4<Double>] = [:]
        var total = 0.0
        var i = 0
        while i + 3 < pixels.count {
            let alpha = Double(pixels[i + 3]) / 255
            if alpha > 0.5 {
                let r = min(Double(pixels[i]) / 255 / alpha, 1)
                let g = min(Double(pixels[i + 1]) / 255 / alpha, 1)
                let b = min(Double(pixels[i + 2]) / 255 / alpha, 1)
                let key = (Int(r * 15.999) << 8) | (Int(g * 15.999) << 4) | Int(b * 15.999)
                bins[key, default: SIMD4<Double>(0, 0, 0, 0)] += SIMD4<Double>(r, g, b, 1)
                total += 1
            }
            i += 4
        }
        guard total > 0, maxCount > 0 else { return [] }

        // Sorted keys keep the clustering deterministic.
        let points: [Cluster] = bins.keys.sorted().map { key in
            let sum = bins[key] ?? SIMD4<Double>(0, 0, 0, 1)
            let rgb = SIMD3<Double>(sum.x, sum.y, sum.z) / max(sum.w, 1)
            return Cluster(lab: oklab(rgb), rgb: rgb, weight: sum.w / total)
        }

        // Seeding: the heaviest bin, then repeatedly the bin with the most weight far from every centre.
        let k = min(maxCount + 2, points.count)
        var centres: [SIMD3<Double>] = []
        if let heaviest = points.max(by: { $0.weight < $1.weight }) { centres.append(heaviest.lab) }
        while centres.count < k {
            var best = 0.0
            var pick: SIMD3<Double>?
            for point in points {
                let d = centres.map { distanceSquared($0, point.lab) }.min() ?? 0
                if point.weight * d > best { best = point.weight * d; pick = point.lab }
            }
            guard let next = pick, best > 1e-9 else { break }
            centres.append(next)
        }

        // Weighted Lloyd iterations.
        var assignment = [Int](repeating: 0, count: points.count)
        for _ in 0..<12 {
            for (index, point) in points.enumerated() { assignment[index] = nearest(point.lab, in: centres) }
            var sums = [SIMD3<Double>](repeating: SIMD3<Double>(0, 0, 0), count: centres.count)
            var weights = [Double](repeating: 0, count: centres.count)
            for (index, point) in points.enumerated() {
                sums[assignment[index]] += point.lab * point.weight
                weights[assignment[index]] += point.weight
            }
            var moved = false
            for c in centres.indices where weights[c] > 0 {
                let next = sums[c] / weights[c]
                if distanceSquared(next, centres[c]) > 1e-10 { moved = true }
                centres[c] = next
            }
            if !moved { break }
        }
        for (index, point) in points.enumerated() { assignment[index] = nearest(point.lab, in: centres) }

        var clusters = centres.map { Cluster(lab: $0, rgb: SIMD3<Double>(0, 0, 0), weight: 0) }
        for (index, point) in points.enumerated() {
            clusters[assignment[index]].rgb += point.rgb * point.weight
            clusters[assignment[index]].weight += point.weight
        }
        clusters = clusters.filter { $0.weight > 0 }.map { (cluster: Cluster) -> Cluster in
            var c = cluster
            c.rgb /= cluster.weight
            return c
        }

        // Merge clusters that are really one colour, heaviest first.
        clusters.sort { $0.weight > $1.weight }
        var merged: [Cluster] = []
        for cluster in clusters {
            if let j = merged.firstIndex(where: { distanceSquared($0.lab, cluster.lab) < mergeDistance * mergeDistance }) {
                let w = merged[j].weight + cluster.weight
                merged[j].lab = (merged[j].lab * merged[j].weight + cluster.lab * cluster.weight) / w
                merged[j].rgb = (merged[j].rgb * merged[j].weight + cluster.rgb * cluster.weight) / w
                merged[j].weight = w
            } else {
                merged.append(cluster)
            }
        }
        merged.sort { $0.weight > $1.weight }
        return merged
            .filter { $0.weight >= minimumShare }
            .prefix(maxCount)
            .map { ArtworkSwatch(r: min(max($0.rgb.x, 0), 1), g: min(max($0.rgb.y, 0), 1),
                                 b: min(max($0.rgb.z, 0), 1), share: $0.weight) }
    }

    /// sRGB (0...1) to OKLab: distances there match how different two colours look.
    static func oklab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let r = PlayerBackdropPolicy.linear(rgb.x)
        let g = PlayerBackdropPolicy.linear(rgb.y)
        let b = PlayerBackdropPolicy.linear(rgb.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return SIMD3<Double>(lightness, a, bb)
    }

    static func distanceSquared(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d * d).sum()
    }

    private static func nearest(_ lab: SIMD3<Double>, in centres: [SIMD3<Double>]) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, centre) in centres.enumerated() {
            let d = distanceSquared(centre, lab)
            if d < bestDistance { bestDistance = d; best = index }
        }
        return best
    }
}

/// The background's four tones, already clamped so the page's ink stays legible over them.
struct NowPlayingPalette: Equatable {
    struct Tone: Equatable, Sendable {
        var r: Double
        var g: Double
        var b: Double
    }

    enum Role { case field, glow, foot }

    /// The artwork's dominant colour: most of the screen.
    var base: Tone
    /// Its most vivid prominent colour: the glow at the top.
    var accent: Tone
    /// A third colour of the artwork, or a neighbour of the base when it has none.
    var support: Tone
    /// Under the controls: the base, deepened (dark themes) or softened (light themes).
    var foot: Tone

    var tones: [Tone] { [base, accent, support, foot] }

    /// 0...1, from the accent's hue: where the mesh's centre leans, so different artwork gives a
    /// differently shaped wash, not only different colours.
    var lean: Double { accent.hsv.h }

    /// Two colours closer than this (OKLab) count as the same one.
    static let distinctness = 0.08

    /// The palette for artwork, or nil when no colour could be read.
    static func make(swatches: [ArtworkSwatch], light: Bool) -> NowPlayingPalette? {
        guard let first = swatches.first else { return nil }
        let base = Tone(first)
        let rest = swatches.dropFirst().filter { Tone($0).distance(to: base) > distinctness }
        let accentSwatch = rest.max { vividness($0) < vividness($1) }
        let accent = accentSwatch.map { Tone($0) } ?? base.shifted(hue: 0.06, saturation: 1.25, value: 1.2)
        // The support colour is the one that adds most next to base and accent (a red poster's
        // yellow, not a third red).
        let others = rest.filter { $0 != accentSwatch }
        let supportSwatch = others.max { contribution($0, base: base, accent: accent) < contribution($1, base: base, accent: accent) }
        let support = supportSwatch.map { Tone($0) } ?? base.shifted(hue: -0.05, saturation: 0.9, value: 0.8)
        // A pale, colourless field (cream, white) darkens to grey under white ink; let the poster's
        // own colours carry the wash instead.
        if !light, base.luminance > 0.55, base.hsv.s < 0.2, accentSwatch != nil, accent.hsv.s >= 0.35 {
            return readable(base: accent, accent: accent.shifted(hue: -0.03, saturation: 1.1, value: 1.15),
                            support: supportSwatch.map { Tone($0) } ?? accent.shifted(hue: -0.05, saturation: 0.9, value: 0.8),
                            light: light)
        }
        return readable(base: base, accent: accent, support: support, light: light)
    }

    /// No artwork: a deliberate wash from the theme's accents, or GlassRemote's own deep blue
    /// palette when the accent is grey (a grey wash reads as an empty background).
    static func fallback(accent: Tone?, secondary: Tone?, light: Bool) -> NowPlayingPalette {
        guard let accent, accent.hsv.s >= 0.12 else {
            return readable(base: houseBase, accent: houseAccent, support: houseSupport, light: light)
        }
        var glow = accent.shifted(hue: 0.07, saturation: 1.1, value: 1.15)
        if let secondary, secondary.hsv.s >= 0.12, secondary.distance(to: accent) > distinctness { glow = secondary }
        return readable(base: accent.shifted(hue: 0, saturation: 0.85, value: 0.55), accent: glow,
                        support: accent.shifted(hue: -0.06, saturation: 0.9, value: 0.8), light: light)
    }

    static let houseBase = Tone(r: 0.10, g: 0.12, b: 0.30)
    static let houseAccent = Tone(r: 0.38, g: 0.30, b: 0.86)
    static let houseSupport = Tone(r: 0.06, g: 0.36, b: 0.44)

    static func readable(base: Tone, accent: Tone, support: Tone, light: Bool) -> NowPlayingPalette {
        NowPlayingPalette(base: adjust(base, light: light, role: .field),
                          accent: adjust(accent, light: light, role: .glow),
                          support: adjust(support, light: light, role: .field),
                          foot: adjust(base, light: light, role: .foot))
    }

    /// One colour moved into the theme's legible band, hue kept. Dark themes: never brighter than
    /// white ink allows (and never pure black, so black artwork still gives a coloured wash); light
    /// themes: pale enough for dark ink, saturation softened to a pastel.
    static func adjust(_ tone: Tone, light: Bool, role: Role) -> Tone {
        let policy = PlayerBackdropPolicy.self
        let hsv = tone.hsv
        let luminance = tone.luminance
        let saturation = min(hsv.s, light ? policy.lightMaxSaturation : policy.darkMaxSaturation)
        let target: Double
        if light {
            let lowest = role == .foot ? policy.lightFootLuminance : policy.lightMinLuminance
            target = min(max(luminance, lowest), policy.lightMaxLuminance)
        } else {
            switch role {
            case .field: target = min(max(luminance, policy.darkMinLuminance), policy.darkMaxLuminance)
            case .glow: target = min(max(luminance, policy.darkMinLuminance), policy.darkGlowLuminance)
            case .foot: target = min(max(luminance * 0.5, policy.darkMinLuminance), policy.darkFootLuminance)
            }
        }
        if abs(saturation - hsv.s) < 0.0001, abs(target - luminance) < 0.0005 { return tone }
        var hue = hsv.h
        if !light, saturation > 0.25, hue > 0.1, hue < 0.2, target < luminance {
            // A darkened yellow turns olive; easing it towards amber keeps it reading as gold.
            hue -= (hue - 0.1) * 0.5 * min(1, (luminance - target) / 0.3)
        }
        let c = ColorMath.color(hue: hue, saturation: saturation, luminance: target)
        return Tone(r: c.r, g: c.g, b: c.b)
    }

    /// Favours saturated, reasonably bright colours with a real share of the picture.
    static func vividness(_ swatch: ArtworkSwatch) -> Double {
        let hsv = ColorMath.hsv(r: swatch.r, g: swatch.g, b: swatch.b)
        return hsv.s * (0.25 + 0.75 * hsv.v) * swatch.share.squareRoot()
    }

    /// How much a colour adds beside the base and the accent: its presence times its difference
    /// from the nearer of the two.
    static func contribution(_ swatch: ArtworkSwatch, base: Tone, accent: Tone) -> Double {
        let tone = Tone(swatch)
        return swatch.share.squareRoot() * min(tone.distance(to: base), tone.distance(to: accent))
    }
}

extension NowPlayingPalette.Tone {
    init(_ swatch: ArtworkSwatch) {
        self.init(r: swatch.r, g: swatch.g, b: swatch.b)
    }

    /// sRGB components of a SwiftUI colour, or nil when it cannot be resolved.
    init?(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        self.init(r: min(max(Double(r), 0), 1), g: min(max(Double(g), 0), 1), b: min(max(Double(b), 0), 1))
    }

    var luminance: Double { ColorMath.luminance(r: r, g: g, b: b) }
    var hsv: (h: Double, s: Double, v: Double) { ColorMath.hsv(r: r, g: g, b: b) }
    var color: Color { Color(red: r, green: g, blue: b) }

    func distance(to other: Self) -> Double {
        NowPlayingPaletteExtractor.distanceSquared(NowPlayingPaletteExtractor.oklab(SIMD3<Double>(r, g, b)),
                                                   NowPlayingPaletteExtractor.oklab(SIMD3<Double>(other.r, other.g, other.b)))
            .squareRoot()
    }

    /// Straight sRGB mix (`t` 0 = self, 1 = other).
    func mixed(with other: Self, _ t: Double) -> Self {
        let k = min(max(t, 0), 1)
        return Self(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }

    /// A neighbour of this colour: hue turned by `hue`, saturation and value scaled.
    func shifted(hue: Double, saturation: Double, value: Double) -> Self {
        let hsv = self.hsv
        var h = (hsv.h + hue).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let c = ColorMath.rgb(hue: h, saturation: min(max(hsv.s * saturation, 0), 1), value: min(max(hsv.v * value, 0), 1))
        return Self(r: c.r, g: c.g, b: c.b)
    }
}

/// Now Playing's background: the palette as one mesh gradient covering the canvas. No image, no
/// blur, nothing animated per frame; a new palette cross-fades in (`PlayerBackdrop`).
struct NowPlayingWash: View {
    let palette: NowPlayingPalette
    let light: Bool

    var body: some View {
        let colors = PlayerBackdropPolicy.meshColors(palette, light: light).map(\.color)
        MeshGradient(width: 3, height: 3, points: PlayerBackdropPolicy.meshPoints(lean: palette.lean), colors: colors)
            .overlay {
                // Light themes: a faint sheen from the top gives the pastel wash some depth (it only
                // lightens, so dark ink keeps its contrast).
                if light {
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: .center)
                }
            }
    }
}
