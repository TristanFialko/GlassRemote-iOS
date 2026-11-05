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
                Color(white: elevated ? 0.12 : 0.09)
                    .opacity(elevated ? 0.12 : 0.20)
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

// MARK: - v0.4 glass helpers

extension View {
    /// Large floating bars (the page dock, transport bar). Untinted regular glass on iOS 26 so
    /// refraction and the specular edge carry the look; heavier material fallback before that.
    @ViewBuilder
    func glassBar<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.legacyBar(shape)
        }
        #else
        self.legacyBar(shape)
        #endif
    }

    /// The selected-item "lens" inside a bar: clear, lightly lifted glass.
    @ViewBuilder
    func glassLens<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.clear.tint(Color.white.opacity(0.10)).interactive(), in: shape)
        } else {
            self.legacyLens(shape)
        }
        #else
        self.legacyLens(shape)
        #endif
    }

    /// Lets two glass shapes in one `GlassGroup` morph into each other on iOS 26. No-op earlier.
    @ViewBuilder
    func glassMorph(_ id: String, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    fileprivate func legacyBar<S: Shape>(_ shape: S) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(Color.black.opacity(0.18))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03), Color.white.opacity(0.10)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay { shape.stroke(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08), Color.white.opacity(0.30)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1) }
            .shadow(color: .black.opacity(0.45), radius: 16, y: 9)
    }

    fileprivate func legacyLens<S: Shape>(_ shape: S) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(Color.white.opacity(0.16))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay { shape.stroke(Color.white.opacity(0.45), lineWidth: 0.8) }
    }
}

/// Records that a scrub bar is being touched, so the page-swipe gesture (which runs alongside every
/// child gesture) ignores the same finger. Touched from the main thread only.
final class ScrubTouch: @unchecked Sendable {
    static let shared = ScrubTouch()
    private var last = Date.distantPast
    func touch() { last = Date() }
    var isActive: Bool { Date().timeIntervalSince(last) < 0.4 }
}

/// A glass bar with a glass "bubble" that follows your finger. Used by the page dock, the device
/// selector and the Discover filter.
///
/// Why the labels are NOT inside the glass container: native glass refracts whatever is rendered
/// beneath it inside the same container, which warped the labels and drew ghost copies of them at
/// the bar's edges. The container now holds only the bar and the bubble; labels sit above it and
/// are never sampled.
///
/// Touch: pressing or sliding along the bar moves the bubble live (it grows slightly while a finger
/// is down) and selects the segment under the finger as it crosses it, with a haptic tick.
struct GlassScrubSelector<Value: Hashable, Label: View>: View {
    let values: [Value]
    @Binding var selection: Value
    var height: CGFloat = 40
    var inset: CGFloat = 4
    var haptic: Bool = true
    @ViewBuilder var label: (Value, Bool) -> Label

    @Namespace private var ns
    @State private var fingerX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let seg = (geo.size.width - inset * 2) / CGFloat(count)
            let index = values.firstIndex(of: selection) ?? 0
            let restX = inset + seg * CGFloat(index)
            let lensX = fingerX.map { min(max($0 - seg / 2, inset), geo.size.width - inset - seg) } ?? restX
            let dragging = fingerX != nil

            ZStack(alignment: .leading) {
                // Glass only: bar + bubble. Nothing else may live in this container.
                GlassGroup(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Color.clear.glassBar(Capsule()).glassMorph("bar", in: ns)
                        Color.clear
                            .frame(width: seg, height: height - inset * 2)
                            .glassLens(Capsule())
                            .glassMorph("lens", in: ns)
                            .scaleEffect(dragging ? 1.12 : 1)
                            .offset(x: lensX)
                            .animation(dragging ? .interactiveSpring(response: 0.18, dampingFraction: 0.85)
                                                : .spring(response: 0.38, dampingFraction: 0.80), value: lensX)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
                    }
                }

                // Labels above the glass, untouched by refraction.
                HStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { offset, value in
                        label(value, offset == index)
                            .frame(width: seg, height: height)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(offset == index ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { choose(value) }
                    }
                }
                .padding(.horizontal, inset)
                .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        ScrubTouch.shared.touch()
                        fingerX = drag.location.x
                        let i = min(max(Int((drag.location.x - inset) / seg), 0), count - 1)
                        if values[i] != selection { choose(values[i]) }
                    }
                    .onEnded { _ in fingerX = nil }
            )
        }
        .frame(height: height)
    }

    private func choose(_ value: Value) {
        guard value != selection else { return }
        if haptic { Haptics.soft() }
        selection = value
    }
}

/// Text (+ optional symbol) segmented control built on `GlassScrubSelector`.
struct GlassSegmented<Value: Hashable>: View {
    struct Item { let value: Value; let title: String; let symbol: String? }
    let items: [Item]
    @Binding var selection: Value
    var height: CGFloat = 40

    var body: some View {
        GlassScrubSelector(values: items.map(\.value), selection: $selection, height: height) { value, selected in
            let item = items.first { $0.value == value }
            HStack(spacing: 5) {
                if let symbol = item?.symbol { Image(systemName: symbol).scaledFont(13, .semibold) }
                Text(item?.title ?? "").scaledFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.68))
        }
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
    /// The one place a button press gives haptic feedback; actions themselves stay silent.
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed && haptic { Haptics.soft() }
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
                    Image(systemName: "circle.grid.cross").scaledFont(15, .semibold)
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
            Haptics.soft()
            action()
        } label: {
            HStack(spacing: 7) {
                icon()
                Text(title).scaledFont(14, .semibold)
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
