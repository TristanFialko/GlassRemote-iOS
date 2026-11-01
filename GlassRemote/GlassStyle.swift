import SwiftUI

/// Black smoked-glass styling.
///
/// On iOS 26 and later (when built with Xcode 26+) surfaces use Apple's native Liquid Glass
/// (`glassEffect`) with a dark smoke tint. On earlier systems, or when built with an older
/// SDK, they fall back to a dark material with silver edge highlights so the project always
/// compiles and still looks like glass.
extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, elevated: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let smoke = Glass.regular.tint(Color.black.opacity(elevated ? 0.12 : 0.38))
            self.glassEffect(interactive ? smoke.interactive() : smoke, in: shape)
        } else {
            self.legacyGlass(shape, elevated: elevated)
        }
        #else
        self.legacyGlass(shape, elevated: elevated)
        #endif
    }

    fileprivate func legacyGlass<S: Shape>(_ shape: S, elevated: Bool) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.black.opacity(elevated ? 0.18 : 0.46))
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(elevated ? 0.26 : 0.12), Color.white.opacity(0.015), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.06), Color.white.opacity(0.0), Color.white.opacity(0.26)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
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
