import SwiftUI

/// Press feedback for glass controls: the surface dips slightly and brightens while held and springs
/// back on release. Purely visual; the action fires on the normal button timing.
struct GlassPressStyle: ButtonStyle {
    var scale: CGFloat = 0.965
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// Capsule glass button used by Profile, Discover and detail pages. `prominent` fills it with the
/// theme accent for the primary action of a screen.
struct GlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.glassTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(15, .semibold)
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.white : Color.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background {
                if prominent { Capsule().fill(theme.accent.opacity(isEnabled ? 0.92 : 0.4)) }
            }
            .glassSurface(Capsule(), interactive: true)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// Rounded glass card used to group content on Profile and detail pages.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Section title used across Discover, detail and Profile pages.
struct GlassSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).scaledFont(19, .bold).foregroundStyle(Color.ink)
            if let subtitle { Text(subtitle).scaledFont(13).foregroundStyle(Color.inkAlpha(0.6)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The dock's light (Phase 7). A specular reflection along the rim that is brightest above the glass
/// bubble and slides with it, plus a soft depth shade on the far edge like light passing through
/// thick glass. Static gradients only: it re-renders when the bubble moves (driven by the same spring
/// as the bubble) and never runs a continuous animation, so it costs nothing at rest.
struct DockSheen: View {
    let progress: CGFloat
    let vertical: Bool
    let active: Bool
    let light: Bool

    var body: some View {
        let centre = ScrubGeometry.sheenCentre(progress: progress)
        let strength: Double = (light ? 0.55 : 0.34) * (active ? 1.3 : 1)
        let along: (UnitPoint, UnitPoint) = vertical ? (.top, .bottom) : (.leading, .trailing)
        let across: (UnitPoint, UnitPoint) = vertical ? (.leading, .trailing) : (.top, .bottom)
        ZStack {
            Capsule()
                .strokeBorder(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0), location: max(0, centre - 0.42)),
                        .init(color: .white.opacity(strength), location: centre),
                        .init(color: .white.opacity(0), location: min(1, centre + 0.42)),
                    ], startPoint: along.0, endPoint: along.1),
                    lineWidth: 1.2)
                .mask(LinearGradient(colors: [.white, .white.opacity(0.1)], startPoint: across.0, endPoint: across.1))
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(light ? 0.10 : 0.06), .clear, .black.opacity(light ? 0.04 : 0.12)],
                                     startPoint: across.0, endPoint: across.1))
        }
        .animation(nil, value: light)
    }
}
