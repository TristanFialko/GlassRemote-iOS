import SwiftUI

/// Satin smoked-graphite styling.
///
/// Surfaces are matte, hardware-like graphite: a flat vertical tone ramp, one even hairline edge and
/// a soft shadow. There are no diagonal specular streaks, no glow and no bright rims. Native Liquid
/// Glass (`glassEffect`, iOS 26+, Xcode 26+) is used sparingly, only where `accent` is true, with a
/// heavy graphite tint. Everything is static fill/stroke, so nothing here is costly on the pointer path.
extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, elevated: Bool = false, accent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if accent, #available(iOS 26.0, *) {
            let smoke = Glass.regular.tint(Color(white: 0.07).opacity(0.72))
            self.glassEffect(interactive ? smoke.interactive() : smoke, in: shape)
        } else {
            self.satinGraphite(shape, elevated: elevated || accent)
        }
        #else
        self.satinGraphite(shape, elevated: elevated || accent)
        #endif
    }

    fileprivate func satinGraphite<S: Shape>(_ shape: S, elevated: Bool) -> some View {
        self
            .background {
                ZStack {
                    // Matte graphite body: slightly lighter at the top, darker at the bottom.
                    shape.fill(
                        LinearGradient(
                            colors: [Color(white: elevated ? 0.19 : 0.14), Color(white: elevated ? 0.125 : 0.088)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Very soft satin falloff over the upper part only (vertical, not a streak).
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.035), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.45)
                        )
                    )
                }
            }
            .overlay {
                // One even, low-contrast edge. No gradient rim, no glow.
                shape.stroke(Color.white.opacity(elevated ? 0.12 : 0.09), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

/// Groups nearby glass shapes so native Liquid Glass can blend them (iOS 26+).
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width Mouse / D-pad selector. Each segment is exactly 50% of the container width.
struct ModeSelector: View {
    @Binding var isMouse: Bool
    @Namespace private var pill

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 0) {
                segment("Mouse", icon: "computermouse", selected: isMouse) { isMouse = true }
                segment("D-pad", icon: "circle.grid.cross", selected: !isMouse) { isMouse = false }
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .glassSurface(Capsule())
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isMouse)
        }
    }

    private func segment(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                if selected {
                    Color.clear
                        .glassSurface(Capsule(), interactive: true, elevated: true, accent: true)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}


/// Near-black canvas with a broad, very soft charcoal glow behind the central content, so the
/// graphite surfaces separate from the background. Static: it has no inputs and no state, so SwiftUI
/// never re-evaluates it while the pointer moves, and it is drawn once as plain gradients (no blur,
/// no material, no animation).
struct AmbientBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color.black
                // Broad charcoal body behind the middle of the layout (Now Playing -> control surface).
                RadialGradient(
                    colors: [Color(white: 0.095), Color(white: 0.055), Color(white: 0.02), .black],
                    center: UnitPoint(x: 0.5, y: 0.55),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.72
                )
                // Slight lift under the trackpad / D-pad area; wide and faint, not a visible spot.
                RadialGradient(
                    colors: [Color(white: 0.06), .clear],
                    center: UnitPoint(x: 0.5, y: 0.78),
                    startRadius: 0,
                    endRadius: w * 0.95
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
