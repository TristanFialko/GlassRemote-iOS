import SwiftUI
import UIKit

/// Smoked native Liquid Glass styling shared by the app's interactive surfaces.
///
/// iOS 26+ uses Apple's real glass material, with a restrained smoke tint so refraction,
/// highlights and depth remain visible. Earlier systems get a material-based fallback.
extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(
        _ shape: S,
        interactive: Bool = false,
        elevated: Bool = false,
        accent: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let smoke = Glass.regular.tint(
                Color(white: elevated ? 0.10 : 0.075)
                    .opacity(elevated ? 0.22 : 0.32)
            )
            self.glassEffect(interactive ? smoke.interactive() : smoke, in: shape)
        } else {
            self.legacyGlass(shape, elevated: elevated || accent)
        }
        #else
        self.legacyGlass(shape, elevated: elevated || accent)
        #endif
    }

    fileprivate func legacyGlass<S: Shape>(_ shape: S, elevated: Bool) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.black.opacity(elevated ? 0.13 : 0.26))
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(elevated ? 0.24 : 0.16),
                                Color.white.opacity(0.025),
                                Color.white.opacity(0.075)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            Color.white.opacity(0.11),
                            Color.white.opacity(0.025),
                            Color.white.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
            }
            .shadow(color: .black.opacity(0.40), radius: elevated ? 12 : 8, y: elevated ? 7 : 4)
    }
}

/// Groups nearby glass elements so native Liquid Glass can blend their silhouettes.
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
            .onChange(of: configuration.isPressed) { pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }
}

/// Full-width Mouse / D-pad selector. The shell and selected segment are both glass.
struct ModeSelector: View {
    @Binding var isMouse: Bool
    @Namespace private var pill

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 0) {
                segment("Mouse", selected: isMouse, action: { isMouse = true }) { MouseGlyph(color: isMouse ? .white : Color.white.opacity(0.72)) }
                segment("D-pad", selected: !isMouse, action: { isMouse = false }) {
                    Image(systemName: "circle.grid.cross").font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .glassSurface(Capsule(), interactive: true)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isMouse)
        }
    }

    private func segment<Icon: View>(_ title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                icon()
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.72))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.clear)
                        .glassSurface(Capsule(), interactive: true, elevated: true)
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

/// Softly lifted charcoal canvas: brighter behind the controls, still near-black at the edges.
struct AmbientBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color.black
                RadialGradient(
                    colors: [
                        Color(white: 0.105),
                        Color(white: 0.068),
                        Color(white: 0.045),
                        .black
                    ],
                    center: UnitPoint(x: 0.5, y: 0.48),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.78
                )
                LinearGradient(
                    colors: [Color(white: 0.035), .clear, Color.black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(white: 0.052).opacity(0.72), .clear],
                    center: UnitPoint(x: 0.5, y: 0.80),
                    startRadius: 0,
                    endRadius: w * 0.90
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
