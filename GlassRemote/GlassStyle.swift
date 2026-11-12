import SwiftUI
import UIKit

/// Themed glass styling shared by the app's surfaces. Every colour comes from the active
/// `GlassTheme` (environment), so a theme change restyles every surface at once.
///
/// Phase 9: the deployment target is iOS 26, so every surface is Apple's native Liquid Glass
/// (`glassEffect`), tinted by the theme. The Phase 5 to 8 material fallbacks are gone. Native glass
/// already lenses its backdrop at the rim; controls that need a visible optical response (the scrub
/// selector bubble, the volume thumb) add the bounded refraction lens from
/// `DesignSystem/Refraction.swift` to the content directly beneath them (PHASE-7-NOTES.md, Phase 9 §0).
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

    /// Lets two glass shapes in one `GlassGroup` morph into each other.
    func glassMorph(_ id: String, in namespace: Namespace.ID) -> some View {
        glassEffectID(id, in: namespace)
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

    func body(content: Content) -> some View {
        let glass = Glass.regular.tint(tint)
        return content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
            .overlay { shape.stroke(theme.controlEdge, lineWidth: 0.8).allowsHitTesting(false) }
            .shadow(color: theme.separationShadow, radius: elevated ? 10 : 7, y: elevated ? 5 : 3)
    }
}

private struct ThemedGlassBar<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let drawsEdge: Bool
    @Environment(\.glassTheme) private var theme

    func body(content: Content) -> some View {
        // Untinted for the neutral themes (the glass itself carries the look); a light wash for coloured ones.
        let tint = theme.id == .defaultDark || theme.isLight ? Color.clear : theme.glassTint.opacity(theme.glassTintOpacity * 0.5)
        let glass = Glass.regular.tint(tint)
        return content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
            .overlay { shape.stroke(drawsEdge ? theme.controlEdge : .clear, lineWidth: 0.8).allowsHitTesting(false) }
            .shadow(color: drawsEdge ? theme.separationShadow : .clear, radius: 8, y: 3)
    }
}

private struct ThemedGlassLens<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.glassTheme) private var theme

    func body(content: Content) -> some View {
        // Fill and edge make the selected state obvious on pale glass; both are clear/faint on dark themes.
        content
            .background { shape.fill(theme.lensFill) }
            .glassEffect(Glass.clear.tint(theme.lensTint.opacity(theme.lensOpacity)).interactive(), in: shape)
            .overlay { shape.stroke(theme.lensEdge, lineWidth: 0.8).allowsHitTesting(false) }
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
///
/// Phase 6: the bubble is a lens. Labels under it are drawn again, magnified about its centre, so an
/// icon swells as the bubble passes over it (half of each while it crosses between two). The bubble
/// stretches along the bar with the finger's speed and relaxes when the finger stops. Native Liquid
/// Glass (iOS 26) refracts and lights itself; before iOS 26 the material bubble gets drawn light: a rim
/// highlight that follows its position, a faint chromatic fringe and a sheen. `axis: .vertical` stands
/// the whole control on end for the landscape page rail; touch rules are identical on both axes.
///
/// Phase 9 recovery §2: `commitOnRelease` (the page dock) keeps the moving bubble but commits only on
/// release: while the finger is down the bubble and the highlighted icon follow it and nothing is
/// navigated; lifting commits the segment under the bubble's centre (even the current one, which the
/// dock uses to close the full player), and lifting well away from the bar cancels
/// (`ScrubGeometry.releaseCommits`). The refraction is clipped to the bar (`ScrubGeometry.boundedLens`).
struct GlassScrubSelector<Value: Hashable, Label: View>: View {
    let values: [Value]
    @Binding var selection: Value
    /// Thickness of the bar: its height when horizontal, its width when vertical.
    var height: CGFloat = 40
    var inset: CGFloat = 4
    var haptic: Bool = true
    var role: ScrubSelectorRole = .control
    var axis: Axis = .horizontal
    /// Release-to-commit instead of live selection (see the type's documentation).
    var commitOnRelease: Bool = false
    @ViewBuilder var label: (Value, Bool) -> Label

    @Environment(\.glassTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    @State private var drag: Drag?

    /// `grab`: where along the bubble the finger holds it. `offset`: the bubble's leading (or top) edge.
    /// `speed`: smoothed finger speed along the bar in pt/s.
    private struct Drag {
        var grab: CGFloat
        var offset: CGFloat
        var location: CGFloat
        var time: Date
        var speed: CGFloat = 0
        /// Release-to-commit only: the segment currently under the bubble's centre.
        var hover: Int = -1
    }

    private var vertical: Bool { axis == .vertical }

    var body: some View {
        GeometryReader { geo in
            let length: CGFloat = vertical ? geo.size.height : geo.size.width
            let thickness: CGFloat = vertical ? geo.size.width : geo.size.height
            let count: Int = max(values.count, 1)
            let seg: CGFloat = ScrubGeometry.segment(length: length, inset: inset, count: count)
            let index: Int = values.firstIndex(of: selection) ?? 0
            let rest: CGFloat = inset + seg * CGFloat(index)
            let offset: CGFloat = drag?.offset ?? rest
            let dragging: Bool = drag != nil
            let stretch: CGFloat = reduceMotion ? 1 : ScrubGeometry.stretch(speed: drag?.speed ?? 0)
            let scale = ScrubGeometry.lensScale(dragging: dragging, speed: drag?.speed ?? 0, reduceMotion: reduceMotion)
            let along: CGFloat = scale.along
            let across: CGFloat = scale.across
            let lensSize: CGSize = vertical ? CGSize(width: thickness - inset * 2, height: seg)
                                            : CGSize(width: seg, height: thickness - inset * 2)
            let lensOffset: CGSize = vertical ? CGSize(width: 0, height: offset) : CGSize(width: offset, height: 0)
            let lens = LensFrame(size: lensSize, offset: lensOffset,
                                 scaleX: vertical ? across : along, scaleY: vertical ? along : across)
            let bar = CGRect(x: 0, y: 0, width: vertical ? thickness : length, height: vertical ? length : thickness)
            let lensRect: CGRect = ScrubGeometry.boundedLens(
                ScrubGeometry.lensRect(offset: offset, segment: seg, thickness: thickness, inset: inset,
                                       vertical: vertical, along: along, across: across),
                in: bar)
            // Release-to-commit: the icon under the moving bubble is highlighted; the committed one otherwise.
            let highlighted: Int = commitOnRelease ? (drag.map { $0.hover >= 0 ? $0.hover : index } ?? index) : index
            let progress: CGFloat = ScrubGeometry.progress(offset: offset, inset: inset, length: length, segment: seg)
            let scrim: Color = role == .dock ? theme.dockScrim : theme.controlScrim
            let outline: Color = role == .dock ? theme.dockEdge : theme.controlEdge
            let alignment: Alignment = vertical ? .top : .leading

            ZStack(alignment: alignment) {
                // Contrast underlay (outside the glass container): guarantees the labels a backdrop.
                Capsule().fill(scrim)
                    .shadow(color: theme.separationShadow, radius: 8, y: 3)
                    .allowsHitTesting(false)

                // Glass only: bar + bubble. Nothing else may live in this container.
                GlassGroup(spacing: 10) {
                    ZStack(alignment: alignment) {
                        Color.clear.glassBar(Capsule(), edge: false).glassMorph("bar", in: ns)
                        Color.clear
                            .frame(width: lens.size.width, height: lens.size.height)
                            .glassLens(Capsule())
                            .glassMorph("lens", in: ns)
                            .lensPlacement(lens)
                    }
                }

                Capsule().stroke(outline, lineWidth: 0.9).allowsHitTesting(false)

                // Phase 7 dock light: a rim reflection that slides with the bubble plus an inner depth
                // shade. There is no magnification; the glass bubble itself carries the selection.
                if role == .dock {
                    DockSheen(progress: progress, vertical: vertical, active: dragging, light: theme.isLight)
                        .allowsHitTesting(false)
                }

                // Labels sit above the glass container (native glass sampling them drew ghost copies). Phase 9:
                // the bubble bends only the labels it covers, through the bounded refraction lens.
                labels(highlighted: highlighted, selected: index, thickness: thickness, seg: seg)
                    .refractiveLens(lensRect, cornerRadius: .infinity, style: .selector)
            }
            .modifier(LensMotion(offset: offset, dragging: dragging, stretch: stretch))
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        ScrubTouch.shared.touch()
                        let p: CGFloat = vertical ? value.location.y : value.location.x
                        let now = Date()
                        var state: Drag
                        if let current = drag {
                            state = current
                            let dt = CGFloat(now.timeIntervalSince(current.time))
                            if dt > 0.004 { state.speed = current.speed * 0.6 + (p - current.location) / dt * 0.4 }
                        } else {
                            // First contact: grab the bubble in place if the finger is on it, else pick it up under the finger.
                            let onSelected = p >= rest && p <= rest + seg
                            let start = onSelected ? rest : ScrubGeometry.clamp(p - seg / 2, inset: inset, length: length, segment: seg)
                            state = Drag(grab: p - start, offset: start, location: p, time: now)
                            state.hover = index
                        }
                        state.offset = ScrubGeometry.clamp(p - state.grab, inset: inset, length: length, segment: seg)
                        state.location = p
                        state.time = now
                        let i = ScrubGeometry.index(forOffset: state.offset, inset: inset, segment: seg, count: count)
                        if commitOnRelease {
                            // The bubble and highlight follow the finger; nothing is committed until release.
                            if i != state.hover {
                                state.hover = i
                                if haptic { Haptics.soft() }
                            }
                            drag = state
                        } else {
                            drag = state
                            // Selection follows the bubble's centre: it flips as the bubble crosses a midpoint.
                            if i < values.count, values[i] != selection { choose(values[i]) }
                        }
                        if abs(state.speed) > 1 { relaxStretch(after: now) }
                    }
                    .onEnded { value in
                        guard commitOnRelease, let ended = drag else { drag = nil; return }
                        drag = nil
                        let cross: CGFloat = vertical ? value.location.x : value.location.y
                        guard ScrubGeometry.releaseCommits(cross: cross, thickness: thickness) else { return }
                        let i = ScrubGeometry.index(forOffset: ended.offset, inset: inset, segment: seg, count: count)
                        if i < values.count { commit(values[i]) }
                    }
            )
        }
        .frame(width: vertical ? height : nil, height: vertical ? nil : height)
        // Phase 7.1: a page swipe never starts on a selector (see PagerExclusion.swift).
        .background { PagerExclusionZone() }
    }

    private func labels(highlighted: Int, selected: Int, thickness: CGFloat, seg: CGFloat) -> some View {
        let stack: AnyLayout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return stack {
            ForEach(Array(values.enumerated()), id: \.offset) { offset, value in
                label(value, offset == highlighted)
                    .frame(width: vertical ? thickness : seg, height: vertical ? seg : thickness)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(offset == selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { commitOnRelease ? commit(value) : choose(value) }
            }
        }
        .padding(vertical ? Edge.Set.vertical : Edge.Set.horizontal, inset)
        .allowsHitTesting(false)
    }

    /// The finger can stop without lifting: once events stop arriving, the stretch relaxes.
    private func relaxStretch(after stamp: Date) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: InteractionTiming.lensIdleNanos)
            guard var current = drag, current.time == stamp, current.speed != 0 else { return }
            current.speed = 0
            drag = current
        }
    }

    private func choose(_ value: Value) {
        guard value != selection else { return }
        if haptic { Haptics.soft() }
        selection = value
    }

    /// Release-to-commit: always reports the value, even the current one, so the owner decides what a
    /// repeat means (the dock closes the full player over the page that is already selected).
    private func commit(_ value: Value) {
        selection = value
    }
}

/// Where the scrub selector's bubble is, shared by every layer that has to sit exactly on it.
private struct LensFrame {
    var size: CGSize
    var offset: CGSize
    var scaleX: CGFloat
    var scaleY: CGFloat
}

private extension View {
    func lensPlacement(_ lens: LensFrame) -> some View {
        scaleEffect(x: lens.scaleX, y: lens.scaleY).offset(lens.offset)
    }
}


/// One set of curves for every layer that follows the bubble, so glass, light, masks and the
/// dock sheen always move together.
private struct LensMotion: ViewModifier {
    let offset: CGFloat
    let dragging: Bool
    let stretch: CGFloat

    func body(content: Content) -> some View {
        content
            .animation(dragging ? Motion.tracking : Motion.adaptive(Motion.lensSettle), value: offset)
            .animation(Motion.unlessReduced(Motion.lensLift, reduceMotion: UIAccessibility.isReduceMotionEnabled), value: dragging)
            .animation(Motion.unlessReduced(Motion.lensStretch, reduceMotion: UIAccessibility.isReduceMotionEnabled), value: stretch)
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

/// Groups nearby glass elements so Liquid Glass renders them in one pass and blends their silhouettes.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) { content() }
    }
}

struct PressStyle: ButtonStyle {
    /// The one place a button press gives haptic feedback; actions themselves stay silent.
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.adaptive(configuration.isPressed ? Motion.press : Motion.snappy), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
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
    /// Phase 7.3: true while a finger is on the selector, false on lift or cancellation (GestureState
    /// resets itself), so the Remote can keep that touch away from the pad. See RemoteInputGuard.
    var onTouchChange: ((Bool) -> Void)?
    private let inset: CGFloat = 4
    @GestureState private var touching = false
    @Environment(\.glassTheme) private var theme

    init(isMouse: Binding<Bool>, segmentHeight: CGFloat = 38, onTouchChange: ((Bool) -> Void)? = nil) {
        self._isMouse = isMouse
        self.segmentHeight = segmentHeight
        self.onTouchChange = onTouchChange
    }

    var body: some View {
        GlassScrubSelector(
            values: [true, false],
            selection: Binding(get: { isMouse }, set: { newValue in
                withAnimation(Motion.adaptive(Motion.snappy)) { isMouse = newValue }
            }),
            height: segmentHeight + inset * 2,
            inset: inset
        ) { mouse, selected in
            // v5 §6: icons only (no "Mouse" / "D-pad" captions); the selected half takes the theme
            // accent (v5 §9). The names stay available to VoiceOver below.
            let tint = ModeSelectorStyle.iconColor(selected: selected, accent: theme.accent)
            Group {
                if mouse { MouseGlyph(color: tint) }
                else { Image(systemName: "circle.grid.cross").scaledFont(17, .semibold) }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true }
        )
        .onChange(of: touching) { _, active in onTouchChange?(active) }
        .onDisappear { onTouchChange?(false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mouse or D-pad")
        .accessibilityValue(isMouse ? "Mouse" : "D-pad")
        .accessibilityHint("Swipe up or down to switch between the mouse trackpad and the D-pad")
        .accessibilityAdjustableAction { direction in
            // Swipe up / increment moves to D-pad, matching page order.
            let wantMouse = direction == .decrement
            guard wantMouse != isMouse else { return }
            Haptics.soft()
            withAnimation(Motion.adaptive(Motion.snappy)) { isMouse = wantMouse }
        }
    }
}

/// The themed canvas: a gradient with a soft glow behind the controls, plus an optional ambient picture.
struct AmbientBackdrop: View {
    var body: some View {
        AmbientCanvas()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// The backdrop's picture with no safe-area handling, so it can also be drawn at an exact size and
/// position (`ContinuousBackdrop`). Always laid out left-to-right: it is decoration, and every copy
/// must match the root one exactly.
struct AmbientCanvas: View {
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
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Continuation §G2: the backdrop for a page that needs its own opaque background (Profile and its
/// sub-pages, so a navigation push covers the page below). It draws the window-sized canvas shifted
/// onto the window origin and clipped to the page, so it lines up exactly with the root backdrop that
/// runs under the dock and the rail: no seam where the page meets the rail, and the picture stays put
/// while the page pages or scrolls. Without a known window size (outside the pager) it fills the page.
struct ContinuousBackdrop: View {
    @Environment(\.windowCanvasSize) private var canvas

    var body: some View {
        GeometryReader { geo in
            if let rect = BackdropAlignment.placement(pageFrame: geo.frame(in: .global), canvas: canvas) {
                AmbientCanvas()
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            } else {
                AmbientCanvas()
            }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Pure placement maths for `ContinuousBackdrop` (unit tested).
enum BackdropAlignment {
    /// The window canvas in the page's own coordinates; nil when the window size is unknown.
    static func placement(pageFrame: CGRect, canvas: CGSize) -> CGRect? {
        guard canvas.width > 0, canvas.height > 0, pageFrame.minX.isFinite, pageFrame.minY.isFinite else { return nil }
        return CGRect(x: -pageFrame.minX, y: -pageFrame.minY, width: canvas.width, height: canvas.height)
    }

    /// The whole window, measured from a view that respects the safe area: its size plus every inset.
    static func canvasSize(size: CGSize, insets: EdgeInsets) -> CGSize {
        CGSize(width: max(size.width + insets.leading + insets.trailing, 0),
               height: max(size.height + insets.top + insets.bottom, 0))
    }
}

private struct WindowCanvasSizeKey: EnvironmentKey { static let defaultValue: CGSize = .zero }

extension EnvironmentValues {
    /// Size of the window the root backdrop fills (zero outside the pager).
    var windowCanvasSize: CGSize {
        get { self[WindowCanvasSizeKey.self] }
        set { self[WindowCanvasSizeKey.self] = newValue }
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

/// v5 §6 / §9: the Mouse / D-pad selector shows icons only; the selected icon takes the theme accent.
enum ModeSelectorStyle {
    static let unselectedOpacity = 0.72

    static func iconColor(selected: Bool, accent: Color) -> Color {
        selected ? accent : Color.inkAlpha(unselectedOpacity)
    }
}
