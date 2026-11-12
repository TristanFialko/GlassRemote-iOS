import SwiftUI

/// The keys on the D-pad and the ADB key names they send (unchanged from Phase 5).
enum DpadKey: String, CaseIterable {
    case up = "UP", right = "RIGHT", down = "DOWN", left = "LEFT", ok = "OK"

    static let arrows: [DpadKey] = [.up, .right, .down, .left]

    /// Direction in screen degrees (0 = right, 90 = down). Unused for OK.
    var angle: Double {
        switch self {
        case .up: return -90
        case .right: return 0
        case .down: return 90
        case .left: return 180
        case .ok: return 0
        }
    }

    var vector: CGVector {
        guard self != .ok else { return .zero }
        let a = angle * .pi / 180
        return CGVector(dx: cos(a), dy: sin(a))
    }

    var symbol: String {
        switch self {
        case .up: return "chevron.up"
        case .right: return "chevron.right"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .ok: return "circle.fill"
        }
    }

    var label: String {
        switch self {
        case .up: return "Up"
        case .right: return "Right"
        case .down: return "Down"
        case .left: return "Left"
        case .ok: return "Select"
        }
    }
}

/// The Remote tab's directional pad, built like one piece of glass: a domed disc with four
/// directional wedges around a raised OK "pebble".
///
/// Touch: every key keeps `RepeatKey`'s behaviour (tap = one press, hold = accelerating repeat, a
/// small drag cancels so the pad's swipe gesture can take over). Each arrow owns a quarter of the visible
/// disc (Phase 7.2), so a touch anywhere on the ring goes to the nearest arrow, the centre belongs to OK,
/// and the square's corners outside the disc are inactive. `DpadHitPolicy` is the single rule for this. Decorative layers never take touches, and nothing here waits on an animation.
struct GlassDpad: View {
    let size: CGFloat
    let onKey: (String) -> Void

    /// Proportions as fractions of the pad's diameter.
    enum Metrics {
        static let pebble: CGFloat = 0.36      // visible OK button (Phase 8: slimmer, so the arrows breathe)
        static let okHit: CGFloat = 0.42       // OK touch area (slightly larger than the pebble)
        static let groove: CGFloat = 0.48      // engraved ring around OK
        static let glyphRadius: CGFloat = 0.36 // chevrons sit midway between the groove and the rim
    }

    @Environment(\.glassTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit: DpadKey?

    var body: some View {
        ZStack {
            disc
            ForEach(DpadKey.arrows, id: \.self) { arrowKey($0) }
            okKey
        }
        .frame(width: size, height: size)
    }

    private var press: Animation { Motion.resolve(Motion.snappy, reduceMotion: reduceMotion) }

    private func setLit(_ key: DpadKey, _ down: Bool) {
        if down { lit = key } else if lit == key { lit = nil }
    }

    // MARK: - Disc

    private var disc: some View {
        let light = theme.isLight
        return ZStack {
            Color.clear.glassSurface(Circle(), elevated: true)
            // Dome: a soft top light falling away to a slightly shaded lower edge.
            Circle().fill(RadialGradient(colors: [Color.white.opacity(light ? 0.34 : 0.11), .clear],
                                         center: UnitPoint(x: 0.5, y: 0.08), startRadius: 2, endRadius: size * 0.75))
            Circle().fill(LinearGradient(colors: [.clear, Color.black.opacity(light ? 0.04 : 0.16)],
                                         startPoint: .center, endPoint: .bottom))
            // Phase 8: a shallow basin falling towards the OK groove gives the disc real depth.
            Circle().fill(RadialGradient(colors: [Color.black.opacity(light ? 0.07 : 0.24), .clear],
                                         center: .center, startRadius: size * Metrics.groove * 0.5, endRadius: size * 0.42))
            // A faint theme tint in the lower rim, like light passing through coloured glass.
            Circle().fill(RadialGradient(colors: [.clear, theme.accent.opacity(light ? 0.05 : 0.10)],
                                         center: UnitPoint(x: 0.5, y: 0.2), startRadius: size * 0.3, endRadius: size * 0.6))
            // Four fine seams on the diagonals separate the directions without boxing them in.
            DpadSeams(inner: Metrics.groove + 0.04, outer: 0.93)
                .stroke(Color.ink.opacity(light ? 0.10 : 0.09), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            // Engraved groove around OK: a dark cut with a light lip under it.
            Circle().stroke(Color.black.opacity(light ? 0.10 : 0.38), lineWidth: 1.5)
                .frame(width: size * Metrics.groove, height: size * Metrics.groove)
            Circle().stroke(Color.white.opacity(light ? 0.55 : 0.08), lineWidth: 1)
                .frame(width: size * Metrics.groove + 3, height: size * Metrics.groove + 3)
                .offset(y: 1)
            // Rim: bright where the light hits the top, dark underneath.
            Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(light ? 0.8 : 0.36), Color.white.opacity(0.05),
                                                          Color.black.opacity(light ? 0.10 : 0.45)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(light ? 0.14 : 0.45), radius: 16, y: 9)
        .shadow(color: theme.accent.opacity(light ? 0.08 : 0.16), radius: 30, y: 16)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Arrows

    private func arrowKey(_ key: DpadKey) -> some View {
        let v = key.vector
        let isLit = lit == key
        let glyph = min(24, max(17, size * 0.062))
        // Phase 7.2: the hit area is this arrow's quarter of the visible disc (a sector meeting at the
        // centre, radius = the pad's radius). It never leaves the pad's frame, so the Mouse / D-pad selector
        // above can't fire Up, and it matches DpadHitPolicy exactly. OK sits on top and owns the centre.
        return RepeatKey(hitShape: DpadWedge(angle: key.angle, inner: 0, outer: 1),
                         onFire: { onKey(key.rawValue) },
                         onPressChange: { setLit(key, $0) }) {
            ZStack {
                // Light pooling in the pressed wedge, strongest towards the rim.
                DpadWedge(angle: key.angle, inner: Metrics.groove + 0.02, outer: 0.97)
                    .fill(RadialGradient(colors: [theme.accent.opacity(theme.isLight ? 0.26 : 0.34), theme.accent.opacity(0)],
                                         center: UnitPoint(x: 0.5 + v.dx * 0.46, y: 0.5 + v.dy * 0.46),
                                         startRadius: 0, endRadius: size * 0.36))
                    .opacity(isLit ? 1 : 0)
                DpadRimArc(angle: key.angle, span: 56, radius: 0.955)
                    .stroke(theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(isLit ? 1 : 0)
                Image(systemName: key.symbol)
                    .scaledFont(glyph, .semibold)
                    .foregroundStyle(isLit ? theme.accent : Color.ink.opacity(0.88))
                    .offset(x: v.dx * size * Metrics.glyphRadius, y: v.dy * size * Metrics.glyphRadius)
            }
            .frame(width: size, height: size)
            .animation(press, value: isLit)
        }
        .accessibilityLabel(key.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onKey(key.rawValue) }
    }

    // MARK: - OK

    private var okKey: some View {
        let isLit = lit == .ok
        let pebble = size * Metrics.pebble
        let light = theme.isLight
        // OK never auto-repeats (audit BUG-009): holding it must not become a stream of Enter presses.
        // A true long-press needs key-down/key-up in the UHID keyboard helper, which it does not have.
        return RepeatKey(hitShape: Circle(), repeats: false,
                         onFire: { onKey(DpadKey.ok.rawValue) },
                         onPressChange: { setLit(.ok, $0) }) {
            ZStack {
                Color.clear.glassSurface(Circle(), interactive: true, elevated: true, accent: true)
                // Phase 8: a gentle top-lit theme body so OK reads as the pad's focal point.
                Circle().fill(LinearGradient(colors: [theme.accent.opacity(light ? 0.10 : 0.16), theme.accent2.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom))
                // Specular cap: the top of the pebble catches the light.
                Ellipse()
                    .fill(LinearGradient(colors: [Color.white.opacity(light ? 0.55 : 0.30), Color.white.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: pebble * 0.72, height: pebble * 0.42)
                    .offset(y: -pebble * 0.2)
                    .frame(width: pebble, height: pebble)
                    .clipShape(Circle())
                    .opacity(isLit ? 0.55 : 1)
                Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.04), Color.black.opacity(0.22)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                Text("OK")
                    .tracking(0.8)
                    .scaledFont(min(19, max(14, size * 0.052)), .semibold)
                    .foregroundStyle(Color.ink)
            }
            .frame(width: pebble, height: pebble)
            .scaleEffect(isLit && !reduceMotion ? 0.95 : 1)
            // Pressing pushes the pebble into the disc: its shadow tightens.
            .shadow(color: .black.opacity(isLit ? 0.22 : (light ? 0.18 : 0.42)), radius: isLit ? 3 : 9, y: isLit ? 1 : 6)
            .animation(press, value: isLit)
            .frame(width: size * Metrics.okHit, height: size * Metrics.okHit)
        }
        .accessibilityLabel(DpadKey.ok.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onKey(DpadKey.ok.rawValue) }
    }
}

// MARK: - Shapes

enum DpadGeometry {
    static func point(_ centre: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: centre.x + cos(a) * radius, y: centre.y + sin(a) * radius)
    }
}

/// A quarter of the pad centred on `angle` (screen degrees, 0 = right), between `inner` and `outer`
/// (fractions of the pad's radius). With `inner == 0` it is a slice meeting at the centre. Arcs are
/// built from points so the direction of travel never depends on the flipped coordinate system.
struct DpadWedge: Shape {
    var angle: Double
    var inner: CGFloat = 0
    var outer: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let steps = 24
        func at(_ i: Int) -> Double { angle - 45 + 90 * Double(i) / Double(steps) }
        var p = Path()
        p.move(to: inner > 0 ? DpadGeometry.point(c, r * inner, at(0)) : c)
        for i in 0...steps { p.addLine(to: DpadGeometry.point(c, r * outer, at(i))) }
        if inner > 0 {
            for i in stride(from: steps, through: 0, by: -1) { p.addLine(to: DpadGeometry.point(c, r * inner, at(i))) }
        }
        p.closeSubpath()
        return p
    }
}

/// Which key owns a touch on the pad (Phase 7.2). This is the rule the hit shapes implement:
/// - within the OK touch radius: OK;
/// - beyond the pad's radius (including the square's corners): nothing;
/// - otherwise the arrow whose axis is closest, using |dx| and |dy| from the centre.
/// Screen coordinates: +y is down. An exact diagonal tie goes to the horizontal arrow, so the answer is
/// always deterministic.
enum DpadHitPolicy {
    /// OK's touch radius as a fraction of the pad's radius (`Metrics.okHit` is a fraction of the diameter).
    static var okRadius: CGFloat { GlassDpad.Metrics.okHit }

    static func key(at point: CGPoint, in rect: CGRect) -> DpadKey? {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return nil }
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance > radius { return nil }
        if distance <= radius * okRadius { return .ok }
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .down : .up
    }
}

/// An open arc along the rim, used for the pressed wedge's light line.
struct DpadRimArc: Shape {
    var angle: Double
    var span: Double
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 * radius
        let steps = 20
        var p = Path()
        for i in 0...steps {
            let point = DpadGeometry.point(c, r, angle - span / 2 + span * Double(i) / Double(steps))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}

/// Four diagonal seams between the directions (visual only).
struct DpadSeams: Shape {
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for angle in [45.0, 135.0, 225.0, 315.0] {
            p.move(to: DpadGeometry.point(c, r * inner, angle))
            p.addLine(to: DpadGeometry.point(c, r * outer, angle))
        }
        return p
    }
}
