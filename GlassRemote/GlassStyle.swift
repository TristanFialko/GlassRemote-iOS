import SwiftUI
import UIKit

/// Themed glass styling shared by the app's surfaces. Every colour comes from the active
/// `GlassTheme` (environment), so a theme change restyles every surface at once.
///
/// iOS 26+ uses Apple's real glass material, tinted by the theme; earlier systems get a
/// material-based fallback built from the same tokens.
///
/// Light-theme visibility: glass over a pale canvas has little to separate it, so light themes add a
/// hairline edge and a soft contact shadow (tokens in `Theme.swift`). Dark themes get neither, so
/// their look is unchanged. The structure is the same in every theme (the tokens are simply clear in
/// dark), so switching themes never rebuilds a view's subtree.
extension View {
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, elevated: Bool = false, accent: Bool = false) -> some View {
        modifier(ThemedGlassSurface(shape: shape, interactive: interactive, elevated: elevated, accent: accent))
    }

    /// Large floating bars (the page dock, transport bar, search field). `edge: false` is for bars
    /// that draw their own outline (the scrub selectors).
    func glassBar<S: Shape>(_ shape: S, interactive: Bool = true, edge: Bool = true) -> some View {
        modifier(ThemedGlassBar(shape: shape, interactive: interactive, drawsEdge: edge))
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

    /// One look for a disabled control in every theme: dimmed, but never invisible on pale glass.
    func controlDisabled(_ disabled: Bool) -> some View {
        modifier(DisabledLook(disabled: disabled))
    }
}

private struct DisabledLook: ViewModifier {
    let disabled: Bool
    @Environment(\.glassTheme) private var theme
    func body(content: Content) -> some View {
        content.opacity(disabled ? (theme.isLight ? 0.50 : 0.42) : 1)
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
                .overlay { shape.stroke(theme.controlEdge, lineWidth: 0.8).allowsHitTesting(false) }
                .shadow(color: theme.separationShadow, radius: elevated ? 10 : 7, y: elevated ? 5 : 3)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        let light = theme.isLight
        let rim: [Color] = light
            ? [theme.edgeStrong, theme.edge.opacity(0.6), theme.edge.opacity(0.5), theme.edge]
            : [theme.rim.opacity(0.46), theme.rim.opacity(0.11), theme.rim.opacity(0.025), theme.rim.opacity(0.24)]
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
                shape.stroke(LinearGradient(colors: rim, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
            }
            .shadow(color: .black.opacity(light ? 0.14 : 0.40), radius: elevated ? 12 : 8, y: elevated ? 7 : 4)
    }
}

private struct ThemedGlassBar<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let drawsEdge: Bool
    @Environment(\.glassTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Untinted for the neutral themes (refraction carries the look); a light wash for coloured ones.
            let tint = theme.id == .defaultDark || theme.isLight ? Color.clear : theme.glassTint.opacity(theme.glassTintOpacity * 0.5)
            let glass = Glass.regular.tint(tint)
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
                .overlay { shape.stroke(drawsEdge ? theme.controlEdge : .clear, lineWidth: 0.8).allowsHitTesting(false) }
                .shadow(color: drawsEdge ? theme.separationShadow : .clear, radius: 8, y: 3)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        let light = theme.isLight
        let rim: [Color] = light
            ? (drawsEdge ? [theme.edgeStrong, theme.edge.opacity(0.5), theme.edge] : [.clear, .clear])
            : [theme.rim.opacity(0.55), theme.rim.opacity(0.08), theme.rim.opacity(0.30)]
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
            .overlay { shape.stroke(LinearGradient(colors: rim, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1) }
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
            // Fill and edge make the selected state obvious on pale glass; both are clear/faint on dark themes.
            content
                .background { shape.fill(theme.lensFill) }
                .glassEffect(Glass.clear.tint(theme.lensTint.opacity(theme.lensOpacity)).interactive(), in: shape)
                .overlay { shape.stroke(theme.lensEdge, lineWidth: 0.8).allowsHitTesting(false) }
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
                    shape.fill(theme.lensTint.opacity(theme.isLight ? 0.18 : max(theme.lensOpacity, 0.16)))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(theme.isLight ? 0.55 : 0.30), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay { shape.stroke(theme.isLight ? theme.lensEdge : theme.rim.opacity(0.45), lineWidth: 0.8) }
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

/// Which contrast rules a scrub selector follows.
enum ScrubSelectorRole {
    /// Segmented controls and the Mouse / D-pad selector: ordinary glass.
    case control
    /// The page dock: floats over arbitrary page content, so it gets its own polarity-opposed scrim,
    /// ink colours and a stronger edge that never depend on the accent.
    case dock
}

/// A glass bar with a glass "bubble" that follows your finger. Used by the page dock, the device
/// selector, the Mouse / D-pad selector and the Discover filter.
///
/// Why the labels are NOT inside the glass container: native glass refracts whatever is rendered
/// beneath it inside the same container, which warped the labels and drew ghost copies of them at
/// the bar's edges. The container now holds only the bar and the bubble; labels sit above it and
/// are never sampled. The contrast scrim and outline are likewise drawn outside the container.
///
/// Touch: the bubble is dragged, not teleported. A touch inside the selected segment grabs the bubble
/// where it is (no jump); a touch elsewhere picks it up under the finger. While the finger is down
/// the bubble follows it (clamped to the bar) and grows slightly; the selection changes the moment
/// the bubble's centre crosses the midpoint between two segments, with one soft haptic tick. On
/// release the bubble settles into the selected segment with a spring.
struct GlassScrubSelector<Value: Hashable, Label: View>: View {
    let values: [Value]
    @Binding var selection: Value
    var height: CGFloat = 40
    var inset: CGFloat = 4
    var haptic: Bool = true
    var role: ScrubSelectorRole = .control
    @ViewBuilder var label: (Value, Bool) -> Label

    @Environment(\.glassTheme) private var theme
    @Namespace private var ns
    @State private var drag: Drag?

    /// `grab` is where in the bubble the finger holds it; `lensX` is the bubble's leading edge.
    private struct Drag { var grab: CGFloat; var lensX: CGFloat }

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let seg = (geo.size.width - inset * 2) / CGFloat(count)
            let index = values.firstIndex(of: selection) ?? 0
            let restX = inset + seg * CGFloat(index)
            let lensX = drag?.lensX ?? restX
            let dragging = drag != nil
            let maxLensX = geo.size.width - inset - seg
            let scrim = role == .dock ? theme.dockScrim : theme.controlScrim
            let outline = role == .dock ? theme.dockEdge : theme.controlEdge

            ZStack(alignment: .leading) {
                // Contrast underlay (outside the glass container): guarantees the labels a backdrop.
                Capsule().fill(scrim)
                    .shadow(color: theme.separationShadow, radius: 8, y: 3)
                    .allowsHitTesting(false)

                // Glass only: bar + bubble. Nothing else may live in this container.
                GlassGroup(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Color.clear.glassBar(Capsule(), edge: false).glassMorph("bar", in: ns)
                        Color.clear
                            .frame(width: seg, height: height - inset * 2)
                            .glassLens(Capsule())
                            .glassMorph("lens", in: ns)
                            .scaleEffect(dragging ? 1.10 : 1)
                            .offset(x: lensX)
                            .animation(dragging ? .interactiveSpring(response: 0.16, dampingFraction: 0.86)
                                                : .spring(response: 0.38, dampingFraction: 0.80), value: lensX)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
                    }
                }

                Capsule().stroke(outline, lineWidth: 0.9).allowsHitTesting(false)

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
                    .onChanged { value in
                        ScrubTouch.shared.touch()
                        let x = value.location.x
                        var state: Drag
                        if let current = drag {
                            state = current
                        } else {
                            // First contact: grab the bubble in place if the finger is on it, else pick it up under the finger.
                            let onSelected = x >= restX && x <= restX + seg
                            let start = onSelected ? restX : min(max(x - seg / 2, inset), maxLensX)
                            state = Drag(grab: x - start, lensX: start)
                        }
                        state.lensX = min(max(x - state.grab, inset), maxLensX)
                        drag = state
                        // Selection follows the bubble's centre: it flips as the bubble crosses a midpoint.
                        let centre = state.lensX + seg / 2
                        let i = min(max(Int((centre - inset) / seg), 0), count - 1)
                        if values[i] != selection { choose(values[i]) }
                    }
                    .onEnded { _ in drag = nil }
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
            .foregroundStyle(selected ? Color.ink : Color.inkAlpha(0.68))
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

/// Full-width Mouse / D-pad selector. It IS the page dock's scrub selector (same code, same feel):
/// drag the glass lens between the two halves, or tap a half. The lens follows the finger, the mode
/// flips as the lens crosses the middle, and it settles on release.
///
/// Direction: the lens moves WITH the finger, like the dock. Mouse is the left half, so dragging
/// left lands on Mouse and dragging right lands on D-pad.
///
/// Gesture separation: the gesture lives only on this bar. The trackpad / D-pad below is a separate
/// view with its own recognisers and is never touched by it; the page pager ignores touches that
/// begin here (see `ScrubTouch`, and the Remote page's edge-only rule in `RootPagerView`).
struct ModeSelector: View {
    @Binding var isMouse: Bool
    /// Height of each segment. The Android remote uses a compact value so the pad gets the room.
    var segmentHeight: CGFloat = 38
    private let inset: CGFloat = 4

    var body: some View {
        GlassScrubSelector(
            values: [true, false],
            selection: Binding(get: { isMouse }, set: { newValue in
                withAnimation(.easeInOut(duration: 0.18)) { isMouse = newValue }
            }),
            height: segmentHeight + inset * 2,
            inset: inset
        ) { mouse, selected in
            HStack(spacing: 7) {
                if mouse { MouseGlyph(color: selected ? Color.ink : Color.inkAlpha(0.72)) }
                else { Image(systemName: "circle.grid.cross").scaledFont(15, .semibold) }
                Text(mouse ? "Mouse" : "D-pad").scaledFont(14, .semibold)
            }
            .foregroundStyle(selected ? Color.ink : Color.inkAlpha(0.72))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mouse or D-pad")
        .accessibilityValue(isMouse ? "Mouse" : "D-pad")
        .accessibilityAdjustableAction { direction in
            // Swipe up / increment moves to D-pad, matching page order.
            let wantMouse = direction == .decrement
            guard wantMouse != isMouse else { return }
            Haptics.soft()
            withAnimation(.easeInOut(duration: 0.18)) { isMouse = wantMouse }
        }
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
        .controlDisabled(!enabled)
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
