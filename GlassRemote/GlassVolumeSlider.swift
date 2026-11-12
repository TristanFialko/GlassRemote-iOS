import SwiftUI

/// Volume slider, v5 §5: a thin accent line, like the system Now Playing volume.
///
/// No refractive thumb and no glass lens: a slim track whose accent fill thickens slightly while held,
/// the speaker glyph on the leading side and the real 0–100 % of the target's own range
/// (`VolumeScale`) on the trailing side. The whole row is the touch target (never below 44 pt).
///
/// Behaviour kept: dragging is relative (like Control Centre), so a touch alone never jumps the
/// volume; within 1.5 % of an end snaps to the end; the value is 0...1 and the model maps it to the
/// target's raw scale. Haptics mark real levels but are rate limited (`VolumeHapticThrottle`), so a
/// fast sweep never buzzes; TV readings and programmatic updates never tick. With no Samsung route
/// (`VolumeScale.unavailable`) the slider is disabled and says the soundbar is unavailable.
struct GlassVolumeSlider: View {
    @Binding var value: Double
    /// The current target's real range: drives the percentage, the haptic steps, the mute/minimum
    /// distinction, the VoiceOver increments and the unavailable state.
    var scale: VolumeScale = .samsungAbsolute(.standard)
    /// Height of the control's touch area (never below 44 pt). The visible track stays thin.
    var thickness: CGFloat = RemoteLayoutPolicy.portraitVolumeThickness
    /// Tells the model a finger is on the slider, so TV readings never move the level mid-drag.
    var onDragChange: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glassTheme) private var theme
    @State private var dragStart: Double?
    @State private var tickStep: Int?
    @State private var haptics = VolumeHapticThrottle()

    private var dragging: Bool { dragStart != nil }
    private var available: Bool { scale.isAvailable }
    private var percent: Int { scale.percent(forFraction: value) }
    private var large: Bool { thickness >= 64 }

    var body: some View {
        HStack(spacing: ThinVolumeMetrics.spacing) {
            Image(systemName: available ? VolumeReadout.symbol(percent: percent, floorIsMute: scale.floorIsMute)
                                        : "speaker.slash")
                .scaledFont(large ? 17 : 15, .semibold)
                .foregroundStyle(Color.inkAlpha(0.75))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24)

            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let track = ThinVolumeMetrics.trackHeight(dragging: dragging && !reduceMotion, large: large)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.inkAlpha(0.16))
                    Capsule(style: .continuous)
                        .fill(available ? theme.accent : Color.inkAlpha(0.28))
                        .frame(width: ThinVolumeMetrics.fillWidth(value: value, width: width))
                }
                .frame(width: width, height: track)
                .frame(width: width, height: geo.size.height)   // centred in the full-height touch area
                .contentShape(Rectangle())
                .animation(dragging ? nil : Motion.unlessReduced(Motion.settle, reduceMotion: reduceMotion), value: value)
                .animation(Motion.unlessReduced(Motion.pressBounce, reduceMotion: reduceMotion), value: dragging)
                .gesture(drag(width: width), including: available ? .all : .none)
            }

            Text(available ? VolumeReadout.text(percent: percent) : "Unavailable")
                .scaledFont(large ? 14 : 13, .semibold)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(percent)))
                .foregroundStyle(Color.inkAlpha(0.7))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .frame(height: ThinVolumeMetrics.controlHeight(thickness))
        .opacity(available ? 1 : 0.6)
        .onChange(of: value) { _, newValue in
            let step = scale.step(forFraction: newValue)
            if haptics.shouldTick(previousStep: tickStep, newStep: step, steps: scale.steps, userInitiated: dragging) {
                Haptics.soft()
            }
            if dragging { tickStep = step }
        }
        .onChange(of: available) { _, isAvailable in
            // The Samsung route dropped mid-drag: release the finger so readings are accepted again.
            if !isAvailable, dragStart != nil { endDrag() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(available ? VolumeReadout.accessibilityValue(percent: percent, floorIsMute: scale.floorIsMute)
                                      : "Soundbar unavailable")
        .accessibilityHint(available ? "Swipe up or down to adjust the TV volume"
                                     : "Connect the Samsung TV in Connection settings to control volume")
        .accessibilityAdjustableAction { direction in
            guard available else { return }
            switch direction {
            case .increment: value = scale.adjusted(value, up: true)
            case .decrement: value = scale.adjusted(value, up: false)
            @unknown default: break
            }
        }
    }

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

/// v5 §5 thin slider metrics (pure, unit tested in Phase9VolumeV5Tests).
enum ThinVolumeMetrics {
    static let minimumTouchTarget: CGFloat = 44
    static let restingTrack: CGFloat = 6
    static let heldTrack: CGFloat = 10
    static let spacing: CGFloat = 12

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
