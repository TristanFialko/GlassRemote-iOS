import SwiftUI

/// Volume slider: a glass track, a theme-tinted fill, a native glass thumb riding the fill edge (Phase 9:
/// it refracts the fill, glyph and readout beneath it) and a live step readout.
///
/// Behaviour is unchanged from Phase 5: dragging is relative (like Apple's Control Centre slider), so
/// a touch on its own never jumps the volume; within 1.5 % of an end snaps to the end; the value is
/// 0...1 and callers map it to remote commands (routing is untouched). A soft haptic marks each of
/// the 20 steps, only while the finger is down, so TV echoes never buzz.
struct GlassVolumeSlider: View {
    @Binding var value: Double
    /// False when the TV's calibrated minimum is above 0: the floor is then NOT mute, so the
    /// "speaker.slash" glyph must not show at 0 %.
    var floorIsMute: Bool = true
    /// Tells the model a finger is on the slider, so TV readings never move the thumb mid-drag.
    var onDragChange: (Bool) -> Void = { _ in }

    @Environment(\.glassTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart: Double?

    private let height: CGFloat = 58
    private let steps = 20

    private var step: Int { Int((value * Double(steps)).rounded()) }
    private var dragging: Bool { dragStart != nil }

    /// Icon follows the quantised 20-step value, so it can't flicker between frames.
    private var symbolName: String {
        if value <= 0 { return floorIsMute ? "speaker.slash.fill" : "speaker.fill" }
        switch step {
        case 0: return "speaker.fill"
        case 1...6: return "speaker.wave.1.fill"
        case 7...13: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private var readout: String {
        if value <= 0 { return floorIsMute ? "Mute" : "Min" }
        return "\(step)"
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clamped = CGFloat(min(max(value, 0), 1))
            let thumb = VolumeSliderGeometry.thumbDiameter(height: height)
            let fillWidth = VolumeSliderGeometry.fillWidth(value: clamped, width: width, thumb: thumb)
            let settle: Animation? = dragging || reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)

            let thumbScale: CGFloat = dragging && !reduceMotion ? 1.08 : 1
            let thumbRect = VolumeSliderGeometry.thumbRect(fillWidth: fillWidth, thumb: thumb, scale: thumbScale)

            ZStack(alignment: .leading) {
                // Everything under the thumb: fill, glyph and readout. Phase 9: the thumb's bounded
                // refraction lens bends exactly this layer, inside the thumb's circle and nowhere else.
                ZStack(alignment: .leading) {
                    // Fill: theme gradient with a specular sheen along the top edge.
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [theme.accent.opacity(0.92), theme.accent2.opacity(0.86)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0)],
                                                     startPoint: .top, endPoint: .center))
                        )
                        .frame(width: fillWidth)
                        .opacity(value <= 0 ? 0 : 1)

                    // Speaker glyph on the leading end.
                    Image(systemName: symbolName)
                        .scaledFont(19, .semibold)
                        .foregroundStyle(Color.ink)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 30, alignment: .leading)
                        .padding(.leading, 20)

                    // Step readout on the trailing end; fades while the thumb passes over it.
                    Text(readout)
                        .scaledFont(13, .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.inkAlpha(0.78))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .opacity(fillWidth > width - 76 ? 0 : 1)
                        .animation(.easeOut(duration: 0.15), value: fillWidth > width - 76)
                }
                .frame(width: width, height: height, alignment: .leading)
                .refractiveLens(thumbRect, cornerRadius: thumbRect.width / 2, style: .thumb)
                .animation(settle, value: value)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: dragging)

                // Glass thumb on the fill edge: native clear Liquid Glass over the refracted layer.
                Color.clear
                    .frame(width: thumb, height: thumb)
                    .glassEffect(Glass.clear.tint(Color.white.opacity(dragging ? 0.12 : 0.06)), in: Circle())
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.70), Color.white.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: .black.opacity(0.30), radius: dragging ? 8 : 5, y: dragging ? 4 : 2)
                    .scaleEffect(thumbScale)
                    .offset(x: VolumeSliderGeometry.thumbX(fillWidth: fillWidth, thumb: thumb))
                    .animation(settle, value: value)
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: dragging)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStart == nil { dragStart = value; onDragChange(true) }
                        let start = dragStart ?? value
                        let proposed = start + Double(drag.translation.width / width)
                        // Within 1.5 % of an end counts as the end, so 0 % and 100 % are always reachable.
                        value = VolumeCalibration.magnet(min(max(proposed, 0), 1))
                    }
                    .onEnded { _ in dragStart = nil; onDragChange(false) }
            )
            .onChange(of: step) { _, _ in if dragging { Haptics.soft() } }
        }
        .frame(height: height)
        .glassSurface(Capsule(style: .continuous), interactive: true, elevated: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(value <= 0 ? (floorIsMute ? "Muted" : "Minimum") : "\(step) of \(steps)")
        .accessibilityHint("Swipe up or down to adjust the TV volume")
        .accessibilityAdjustableAction { direction in
            let delta = 1.0 / Double(steps)
            switch direction {
            case .increment: value = VolumeCalibration.magnet(min(value + delta, 1), margin: 0.001)
            case .decrement: value = VolumeCalibration.magnet(max(value - delta, 0), margin: 0.001)
            @unknown default: break
            }
        }
    }
}

/// Pure geometry for the volume slider (unit tested).
enum VolumeSliderGeometry {
    static let inset: CGFloat = 5

    static func thumbDiameter(height: CGFloat) -> CGFloat { max(height - inset * 2, 0) }

    /// The fill always reaches past the thumb, so the thumb sits on the fill's edge, and 0 shows no
    /// fill. Never wider than the track.
    static func fillWidth(value: CGFloat, width: CGFloat, thumb: CGFloat) -> CGFloat {
        let v = min(max(value, 0), 1)
        guard v > 0, width > 0 else { return 0 }
        let minimum = thumb + inset * 2
        return min(max(width * v, minimum), width)
    }

    /// Leading edge of the thumb: it rides the fill's edge and never leaves the track.
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
