import SwiftUI
import UIKit

/// Volume slider, v5 §5: a thin line, like the system Now Playing volume.
///
/// No refractive thumb and no glass lens: a slim track whose fill thickens while held, a speaker
/// glyph on the leading side and, on the trailing side, the real 0–100 % only when the output's level
/// is read back (`VolumeScale.readsLevel`). Key routes are relative, so they show a speaker glyph and
/// no number; with no route the track is empty (no invented level), dimmed and says why. The whole
/// row is the touch target (never below 44 pt).
///
/// Now Playing (`.nowPlaying`) draws it as Apple Music does: a neutral gradient fill, a knob that
/// appears under the finger, and (when `onMute` is given) the leading speaker as a mute button that
/// bounces when the command was sent and shakes when it was not.
///
/// Behaviour kept: dragging is relative (like Control Centre), so a touch alone never jumps the
/// volume; within 1.5 % of an end snaps to the end; the value is 0...1 and the model maps it to the
/// target's raw scale. Haptics mark real levels but are rate limited (`VolumeHapticThrottle`), so a
/// fast sweep never buzzes; TV readings and programmatic updates never tick.
struct GlassVolumeSlider: View {
    @Binding var value: Double
    /// The current target's real range: drives the readout, the haptic steps, the mute/minimum
    /// distinction, the VoiceOver increments and the unavailable state.
    var scale: VolumeScale = .samsungAbsolute(.standard)
    /// Height of the control's touch area (never below 44 pt). The visible track stays thin.
    var thickness: CGFloat = RemoteLayoutPolicy.portraitVolumeThickness
    /// `.nowPlaying` draws the row as Apple Music does: a neutral fill and quiet speaker glyphs
    /// instead of the accent fill.
    var appearance: Appearance = .standard
    /// Tells the model a finger is on the slider, so TV readings never move the level mid-drag.
    var onDragChange: (Bool) -> Void = { _ in }
    /// Short reason shown and spoken while no route is available (e.g. "Connect the TV box").
    var unavailableReason: String? = nil
    /// Now Playing: makes the leading speaker a mute button. Returns whether the command was sent.
    var onMute: (() -> Bool)? = nil

    enum Appearance: Equatable { case standard, nowPlaying }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glassTheme) private var theme
    @State private var dragStart: Double?
    @State private var tickStep: Int?
    @State private var haptics = VolumeHapticThrottle()
    @State private var muteSent = 0
    @State private var muteFailures = 0

    private var dragging: Bool { dragStart != nil }
    private var available: Bool { scale.isAvailable }
    private var percent: Int { scale.percent(forFraction: value) }
    private var large: Bool { thickness >= 64 }
    private var quiet: Bool { appearance == .nowPlaying }
    private var readout: VolumeRowReadout { .resolve(scale: scale, fraction: value, reason: unavailableReason) }
    private var reduced: Bool { reduceMotion || MotionPreference.reduced }

    private var leadingSymbol: String {
        guard available else { return "speaker.slash" }
        // Key routes have no level to show: one plain speaker, like Apple Music's quiet end.
        guard scale.readsLevel else { return "speaker.fill" }
        // Apple Music keeps one quiet speaker here; mute and minimum still show their own glyph.
        if quiet, onMute == nil, percent > 0 { return "speaker.fill" }
        return VolumeReadout.symbol(percent: percent, floorIsMute: scale.floorIsMute)
    }

    var body: some View {
        HStack(spacing: quiet ? ThinVolumeMetrics.nowPlayingSpacing : ThinVolumeMetrics.spacing) {
            leading
            HStack(spacing: quiet ? ThinVolumeMetrics.nowPlayingSpacing : ThinVolumeMetrics.spacing) {
                track
                trailing
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint(available ? "Swipe up or down to change the volume"
                                         : "Choose where volume goes in Connection settings")
            .accessibilityAdjustableAction { direction in
                guard available else { return }
                switch direction {
                case .increment: value = scale.adjusted(value, up: true)
                case .decrement: value = scale.adjusted(value, up: false)
                @unknown default: break
                }
            }
        }
        .padding(.horizontal, quiet ? 0 : 4)
        .frame(height: ThinVolumeMetrics.controlHeight(thickness))
        .onChange(of: value) { _, newValue in
            let step = scale.step(forFraction: newValue)
            if haptics.shouldTick(previousStep: tickStep, newStep: step, steps: scale.steps, userInitiated: dragging) {
                Haptics.soft()
            }
            if dragging { tickStep = step }
        }
        .onChange(of: available) { _, isAvailable in
            // The route dropped mid-drag: release the finger so readings are accepted again.
            if !isAvailable, dragStart != nil { endDrag() }
        }
    }

    // MARK: Leading speaker / mute

    @ViewBuilder
    private var leading: some View {
        if quiet, let onMute {
            Button { mute(onMute) } label: {
                Image(systemName: leadingSymbol)
                    .scaledFont(14, .semibold)
                    .foregroundStyle(Color.inkAlpha(available ? 0.85 : 0.4))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: reduced ? 0 : muteSent)
                    .frame(width: ThinVolumeMetrics.muteDisc, height: ThinVolumeMetrics.muteDisc)
                    .background { Circle().fill(Color.inkAlpha(available ? 0.12 : 0.06)) }
                    .modifier(VolumeShake(phase: CGFloat(muteFailures)))
                    .frame(height: ThinVolumeMetrics.minimumTouchTarget)
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(MuteButtonStyle())
            .disabled(!available)
            .animation(Motion.unlessReduced(Motion.snappy, reduceMotion: reduceMotion), value: leadingSymbol)
            .accessibilityLabel("Mute")
            .accessibilityHint(available ? "Mutes or unmutes the sound" : readoutReason)
        } else {
            Image(systemName: leadingSymbol)
                .scaledFont(large ? 17 : (quiet ? 13 : 15), .semibold)
                .foregroundStyle(Color.inkAlpha(available ? (quiet ? 0.6 : 0.75) : 0.4))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: quiet ? 18 : 24)
                .accessibilityHidden(true)
        }
    }

    private func mute(_ send: () -> Bool) {
        // `RemoteModel.volume` gives the soft haptic itself, only when the command was handed over.
        if send() {
            muteSent += 1
        } else {
            withAnimation(Motion.unlessReduced(Motion.release, reduceMotion: reduceMotion)) { muteFailures += 1 }
            UIAccessibility.post(notification: .announcement, argument: "Mute not sent. \(readoutReason)")
        }
    }

    private var readoutReason: String {
        if case .unavailable(let reason) = readout { return reason }
        return unavailableReason ?? VolumeRowReadout.defaultReason
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = ThinVolumeMetrics.trackHeight(dragging: dragging && !reduceMotion, large: large)
            let fill = readout.showsFill ? ThinVolumeMetrics.fillWidth(value: value, width: width) : 0
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.inkAlpha(available ? 0.16 : 0.10))
                Capsule(style: .continuous)
                    .fill(fillStyle)
                    .frame(width: fill)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .leading) { knob(fill: fill, width: width) }
            .frame(width: width, height: geo.size.height)   // centred in the full-height touch area
            .contentShape(Rectangle())
            // Follows the finger with the tracking spring; settles after a reading or an increment.
            .animation(Motion.unlessReduced(dragging ? Motion.tracking : Motion.settle, reduceMotion: reduceMotion), value: value)
            .animation(Motion.unlessReduced(Motion.pressBounce, reduceMotion: reduceMotion), value: dragging)
            .gesture(drag(width: width), including: available ? .all : .none)
        }
    }

    private var fillStyle: AnyShapeStyle {
        guard available else { return AnyShapeStyle(Color.inkAlpha(0.28)) }
        guard quiet else { return AnyShapeStyle(theme.accent) }
        // A soft gradient towards the level's end; brighter while held.
        return AnyShapeStyle(LinearGradient(colors: [Color.inkAlpha(dragging ? 0.82 : 0.66), Color.inkAlpha(dragging ? 1 : 0.92)],
                                            startPoint: .leading, endPoint: .trailing))
    }

    /// Now Playing: a knob rises under the finger while dragging, so a relative route still shows
    /// where the slider is being moved. Hidden at rest, like Apple Music.
    @ViewBuilder
    private func knob(fill: CGFloat, width: CGFloat) -> some View {
        if quiet, readout.showsFill {
            let diameter = ThinVolumeMetrics.knobDiameter
            Circle()
                .fill(Color.ink)
                .frame(width: diameter, height: diameter)
                .shadow(color: Color.black.opacity(0.28), radius: 5, y: 2)
                .scaleEffect(dragging ? 1 : (reduced ? 1 : 0.3))
                .opacity(dragging ? 1 : 0)
                .offset(x: ThinVolumeMetrics.knobOffset(fill: fill, width: width))
                .allowsHitTesting(false)
        }
    }

    // MARK: Trailing readout

    @ViewBuilder
    private var trailing: some View {
        switch readout {
        case .level(let shown):
            Text(VolumeReadout.text(percent: shown))
                .scaledFont(large ? 14 : 13, .semibold)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(shown)))
                .foregroundStyle(Color.inkAlpha(0.7))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: quiet ? 38 : 40, alignment: .trailing)
                .animation(Motion.unlessReduced(Motion.snappy, reduceMotion: reduceMotion), value: shown)
        case .relative:
            Image(systemName: "speaker.wave.3.fill")
                .scaledFont(quiet ? 13 : (large ? 16 : 14), .semibold)
                .foregroundStyle(Color.inkAlpha(0.6))
                .frame(minWidth: quiet ? 24 : 40, alignment: .trailing)
        case .unavailable(let reason):
            Text(reason)
                .scaledFont(quiet ? 12 : 13, .semibold)
                .foregroundStyle(Color.inkAlpha(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
    }

    private var accessibilityValueText: String {
        switch readout {
        case .level(let shown): return VolumeReadout.accessibilityValue(percent: shown, floorIsMute: scale.floorIsMute)
        case .relative: return "Level not reported, slider at \(percent) percent"
        case .unavailable(let reason): return "Unavailable, \(reason)"
        }
    }

    // MARK: Drag

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart == nil {
                    dragStart = value
                    tickStep = scale.step(forFraction: value)
                    onDragChange(true)
                }
                let start = dragStart ?? value
                let proposed = start + Double(drag.translation.width / width)
                // Within 1.5 % of an end counts as the end, so 0 % and 100 % are always reachable.
                value = VolumeCalibration.magnet(min(max(proposed, 0), 1))
            }
            .onEnded { _ in endDrag() }
    }

    private func endDrag() {
        dragStart = nil
        tickStep = nil
        haptics.reset()
        onDragChange(false)
    }
}

/// What the row shows beside the track (pure, unit tested). A number only when the output's real
/// level is read back; key routes are relative, so they get no number; with no route there is no
/// level at all, only the reason.
enum VolumeRowReadout: Equatable {
    case level(Int)
    case relative
    case unavailable(String)

    static let defaultReason = "Unavailable"

    static func resolve(scale: VolumeScale, fraction: Double, reason: String?) -> VolumeRowReadout {
        guard scale.isAvailable else {
            let text = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .unavailable(text.isEmpty ? defaultReason : text)
        }
        return scale.readsLevel ? .level(scale.percent(forFraction: fraction)) : .relative
    }

    /// No route: the track stays empty rather than showing a stale or invented position.
    var showsFill: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

/// The mute disc: dips on press and springs back. The haptic comes from the command, not the press.
private struct MuteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let reduced = UIAccessibility.isReduceMotionEnabled || MotionPreference.reduced
        return configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.adaptive(configuration.isPressed ? Motion.press : Motion.pressBounce), value: configuration.isPressed)
    }
}

/// A short horizontal shake; `phase` advances by one per shake and rests at whole numbers.
private struct VolumeShake: GeometryEffect {
    var travel: CGFloat = 4
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(phase * .pi * 3), y: 0))
    }
}

/// v5 §5 thin slider metrics (pure, unit tested in Phase9VolumeV5Tests).
enum ThinVolumeMetrics {
    static let minimumTouchTarget: CGFloat = 44
    static let restingTrack: CGFloat = 6
    static let heldTrack: CGFloat = 10
    static let spacing: CGFloat = 12
    /// Now Playing: gap between the mute disc, the track and the readout.
    static let nowPlayingSpacing: CGFloat = 12
    /// Now Playing: the mute button's visible disc (its touch area is the row's full height).
    static let muteDisc: CGFloat = 32
    /// Now Playing: the knob shown under the finger while dragging.
    static let knobDiameter: CGFloat = 20

    /// Leading edge of the knob: centred on the level's end, never past either end of the track.
    static func knobOffset(fill: CGFloat, width: CGFloat, diameter: CGFloat = ThinVolumeMetrics.knobDiameter) -> CGFloat {
        guard fill.isFinite, width > diameter else { return 0 }
        return min(max(fill - diameter / 2, 0), width - diameter)
    }

    static func trackHeight(dragging: Bool, large: Bool = false) -> CGFloat {
        (dragging ? heldTrack : restingTrack) + (large ? 2 : 0)
    }

    static func controlHeight(_ requested: CGFloat) -> CGFloat { max(requested, minimumTouchTarget) }

    static func fillWidth(value: Double, width: CGFloat) -> CGFloat {
        guard value.isFinite, width > 0 else { return 0 }
        return width * CGFloat(min(max(value, 0), 1))
    }
}

/// Retained geometry of the Phase 9 glass slider (unit tested). The v5 §5 slider draws with
/// `ThinVolumeMetrics`; the landscape deck and layout tests still size against `thumbDiameter`.
enum VolumeSliderGeometry {
    static let inset: CGFloat = 5
    /// The readout fades once the level reaches this close to the trailing end.
    static let readoutClearance: CGFloat = 84

    static func thumbDiameter(height: CGFloat) -> CGFloat { max(height - inset * 2, 0) }

    /// The level always reaches past the thumb, so the thumb sits inside its rounded end, and 0 shows
    /// no level. Never wider than the track.
    static func fillWidth(value: CGFloat, width: CGFloat, thumb: CGFloat) -> CGFloat {
        let v = min(max(value, 0), 1)
        guard v > 0, width > 0 else { return 0 }
        let minimum = thumb + inset * 2
        return min(max(width * v, minimum), width)
    }

    /// Leading edge of the thumb: it rides the level's end and never leaves the track.
    static func thumbX(fillWidth: CGFloat, thumb: CGFloat) -> CGFloat {
        max(fillWidth - thumb - inset, inset)
    }

    /// The thumb's on-screen circle (press scale applied about its centre), for the refraction lens.
    static func thumbRect(fillWidth: CGFloat, thumb: CGFloat, scale: CGFloat = 1) -> CGRect {
        let size = thumb * scale
        let centre = CGPoint(x: thumbX(fillWidth: fillWidth, thumb: thumb) + thumb / 2, y: inset + thumb / 2)
        return CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
    }
}
