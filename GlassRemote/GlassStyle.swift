import SwiftUI
import UIKit

/// Themed glass styling shared by the app's surfaces. Every colour comes from the active
/// `GlassTheme` (environment), so a theme change restyles every surface at once.
///
/// iOS 26+ uses Apple's real glass material, tinted by the theme; earlier systems get a
/// material-based fallback built from the same tokens.
extension View {
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, elevated: Bool = false, accent: Bool = false) -> some View {
        modifier(ThemedGlassSurface(shape: shape, interactive: interactive, elevated: elevated, accent: accent))
    }

    /// Large floating bars (the page dock, transport bar).
    func glassBar<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        modifier(ThemedGlassBar(shape: shape, interactive: interactive))
    }

    /// The selected-item "lens" inside a bar, tinted with the accent.
    func glassLens<S: Shape>(_ shape: S) -> some View {
        modifier(ThemedGlassLens(shape: shape))
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
}

private struct ThemedGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let elevated: Bool
    let accent: Bool
    @Environment(\.glassTheme) private var theme

    private var tint: Color {
        if accent { return theme.accent.opacity(theme.accentSurfaceOpacity) }
        return theme.glassTint.opacity(theme.glassTintOpacity * (elevated ? 0.6 : 1))
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let glass = Glass.regular.tint(tint)
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        let light = theme.isLight
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(light ? Color.white.opacity(elevated || accent ? 0.30 : 0.42) : Color.black.opacity(elevated || accent ? 0.13 : 0.26))
                    shape.fill(tint)
                    shape.fill(LinearGradient(colors: [Color.white.opacity(light ? 0.5 : (elevated || accent ? 0.24 : 0.16)), Color.white.opacity(0.025), Color.white.opacity(0.075)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay {
                shape.stroke(LinearGradient(colors: [theme.rim.opacity(light ? 0.95 : 0.46), theme.rim.opacity(0.11), theme.rim.opacity(0.025), theme.rim.opacity(light ? 0.6 : 0.24)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
            }
            .shadow(color: .black.opacity(light ? 0.14 : 0.40), radius: elevated ? 12 : 8, y: elevated ? 7 : 4)
    }
}

private struct ThemedGlassBar<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.glassTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Untinted for the neutral themes (refraction carries the look); a light wash for coloured ones.
            let tint = theme.id == .defaultDark || theme.isLight ? Color.clear : theme.glassTint.opacity(theme.glassTintOpacity * 0.5)
            let glass = Glass.regular.tint(tint)
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        let light = theme.isLight
        return content
            .background {
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(light ? Color.white.opacity(0.35) : Color.black.opacity(0.18))
                    shape.fill(theme.glassTint.opacity(theme.glassTintOpacity * 0.5))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(light ? 0.5 : 0.22), Color.white.opacity(0.03), Color.white.opacity(light ? 0.25 : 0.10)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay { shape.stroke(LinearGradient(colors: [theme.rim.opacity(light ? 1 : 0.55), theme.rim.opacity(0.08), theme.rim.opacity(light ? 0.7 : 0.30)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1) }
            .shadow(color: .black.opacity(light ? 0.16 : 0.45), radius: 16, y: 9)
    }
}

private struct ThemedGlassLens<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.glassTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(Glass.clear.tint(theme.accent.opacity(theme.lensOpacity)).interactive(), in: shape)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(theme.accent.opacity(theme.isLight ? 0.18 : max(theme.lensOpacity, 0.16)))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(theme.isLight ? 0.55 : 0.30), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay { shape.stroke(theme.rim.opacity(theme.isLight ? 0.9 : 0.45), lineWidth: 0.8) }
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
            .foregroundStyle(selected ? Color.ink : Color.ink.opacity(0.68))
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

/// Full-width Mouse / D-pad selector. Behaves like the page dock's glass bar, but swipes follow the
/// page convention: swipe LEFT for D-pad, swipe RIGHT for Mouse. A tap picks the tapped half.
/// The gesture lives only on this bar; the trackpad / D-pad surface below is a separate view and is
/// never touched by it.
struct ModeSelector: View {
    @Binding var isMouse: Bool
    /// Height of each segment. The Android remote uses a compact value so the pad gets the room.
    var segmentHeight: CGFloat = 38
    @Namespace private var ns
    @State private var fired = false
    @State private var nudge: CGFloat = 0
    private let inset: CGFloat = 4
    private let swipeDistance: CGFloat = 22

    var body: some View {
        let height = segmentHeight + inset * 2
        GeometryReader { geo in
            let seg = (geo.size.width - inset * 2) / 2
            ZStack(alignment: .leading) {
                GlassGroup(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Color.clear.glassBar(Capsule(), interactive: true).glassMorph("bar", in: ns)
                        Color.clear
                            .frame(width: seg, height: segmentHeight)
                            .glassLens(Capsule())
                            .glassMorph("lens", in: ns)
                            .offset(x: inset + (isMouse ? 0 : seg) + nudge)
                            .animation(.spring(response: 0.38, dampingFraction: 0.80), value: isMouse)
                            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: nudge)
                    }
                }
                HStack(spacing: 0) {
                    label(true).frame(width: seg, height: height)
                    label(false).frame(width: seg, height: height)
                }
                .padding(.horizontal, inset)
                .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        ScrubTouch.shared.touch()
                        let dx = drag.translation.width, dy = drag.translation.height
                        // The bar leans a little toward the swipe, then commits once past the threshold.
                        nudge = abs(dx) > abs(dy) ? min(max(dx * 0.12, -8), 8) : 0
                        if !fired, abs(dx) >= swipeDistance, abs(dx) > abs(dy) * 1.2 {
                            fired = true
                            set(mouse: dx > 0)
                        }
                    }
                    .onEnded { drag in
                        defer { fired = false; nudge = 0 }
                        // A tap (little movement): choose the half that was tapped.
                        if !fired, abs(drag.translation.width) < 10, abs(drag.translation.height) < 10 {
                            set(mouse: drag.location.x < geo.size.width / 2)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mouse or D-pad")
            .accessibilityValue(isMouse ? "Mouse" : "D-pad")
            .accessibilityAdjustableAction { direction in
                set(mouse: direction == .decrement)   // swipe up/increment -> D-pad, matching page order
            }
        }
        .frame(height: height)
    }

    private func set(mouse: Bool) {
        guard mouse != isMouse else { return }
        Haptics.soft()
        isMouse = mouse
    }

    @ViewBuilder
    private func label(_ mouse: Bool) -> some View {
        let selected = mouse == isMouse
        HStack(spacing: 7) {
            if mouse { MouseGlyph(color: selected ? Color.ink : Color.ink.opacity(0.72)) }
            else { Image(systemName: "circle.grid.cross").scaledFont(15, .semibold) }
            Text(mouse ? "Mouse" : "D-pad").scaledFont(14, .semibold)
        }
        .foregroundStyle(selected ? Color.ink : Color.ink.opacity(0.72))
    }
}

/// The themed canvas: a gradient with a soft glow behind the controls, plus an optional ambient picture.
struct AmbientBackdrop: View {
    @Environment(\.glassTheme) private var theme
    @ObservedObject private var store = ThemeStore.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.canvasTop, theme.canvasMid, theme.canvasBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [theme.glow, .clear], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 520)
            if store.ambient != .none {
                AmbientArtwork(style: store.ambient).transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The one button used for every key on both remotes (Android navigation, Samsung keys), so the
/// two remotes share icon size, weight, height and glass treatment.
struct RemoteKeyButton<Icon: View>: View {
    let label: String
    var enabled = true
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    static var height: CGFloat { 48 }

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .glassSurface(Capsule(), interactive: enabled)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(label)
    }
}

extension RemoteKeyButton where Icon == AnyView {
    /// SF Symbol key at the shared size and weight.
    init(symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.enabled = enabled
        self.action = action
        self.icon = { AnyView(Image(systemName: symbol).scaledFont(19, .medium)) }
    }
}
