import SwiftUI

/// Volume slider, Phase 9 continuation §C: one integrated piece of Liquid Glass.
///
/// The track is native clear glass with edge lighting and a recessed inner shade; the level is a
/// neutral luminous body inside it (adaptive ink tones, never the theme accent); the thumb is a
/// substantial clear-glass lens that sits inside the level's rounded end, so track, fill and thumb
/// read as one object. The readout is a real 0–100 % of the target's own range (`VolumeScale`).
///
/// Behaviour kept from Phase 5: dragging is relative (like Control Centre), so a touch alone never
/// jumps the volume; within 1.5 % of an end snaps to the end; the value is 0...1 and the model maps it
/// to the target's raw scale (routing is untouched). A soft haptic marks each real level the finger
/// moves through (`VolumeHapticPolicy`); TV readings and programmatic updates never tick.
struct GlassVolumeSlider: View {
    @Binding var value: Double
    /// The current target's real range: drives the percentage, the haptic steps, the mute/minimum
    /// distinction and the VoiceOver increments.
    var scale: VolumeScale = .samsungAbsolute(.standard)
    /// Track height. Landscape gives the slider its own deck, so it is taller there (RemoteLayoutPolicy).
    var thickness: CGFloat = RemoteLayoutPolicy.portraitVolumeThickness
    /// Tells the model a finger is on the slider, so TV readings never move the thumb mid-drag.
    var onDragChange: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragStart: Double?
    @State private var tickStep: Int?

    private var dragging: Bool { dragStart != nil }
    private var percent: Int { scale.percent(forFraction: value) }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = thickness
            let clamped = CGFloat(min(max(value, 0), 1))
            let thumb = VolumeSliderGeometry.thumbDiameter(height: height)
            let fillWidth = VolumeSliderGeometry.fillWidth(value: clamped, width: width, thumb: thumb)
            let settle: Animation? = dragging || reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)
            let press: Animation? = reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)

            let thumbScale: CGFloat = dragging && !reduceMotion ? 1.06 : 1
            let thumbRect = VolumeSliderGeometry.thumbRect(fillWidth: fillWidth, thumb: thumb, scale: thumbScale)
            let readoutHidden = fillWidth > width - VolumeSliderGeometry.readoutClearance

            ZStack(alignment: .leading) {
                // Everything under the thumb: recessed track shading, the level, glyph and readout.
                // The thumb's bounded refraction lens bends exactly this layer, inside its circle.
                ZStack(alignment: .leading) {
                    trackShade
                    level
                        .frame(width: fillWidth)
                        .opacity(value <= 0 ? 0 : 1)

                    Image(systemName: VolumeReadout.symbol(percent: percent, floorIsMute: scale.floorIsMute))
                        .scaledFont(height >= 64 ? 21 : 19, .semibold)
                        .foregroundStyle(Color.ink)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 30, alignment: .leading)
                        .padding(.leading, 20)

                    // Percentage on the trailing end; fades while the thumb passes over it.
                    Text(VolumeReadout.text(percent: percent))
                        .scaledFont(height >= 64 ? 15 : 13, .semibold)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(percent)))
                        .foregroundStyle(Color.inkAlpha(0.8))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .opacity(readoutHidden ? 0 : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: readoutHidden)
                }
                .frame(width: width, height: height, alignment: .leading)
                .refractiveLens(thumbRect, cornerRadius: thumbRect.width / 2, style: .thumb)
                .animation(settle, value: value)
                .animation(press, value: dragging)

                thumbView(diameter: thumb)
                    .scaleEffect(thumbScale)
                    .offset(x: VolumeSliderGeometry.thumbX(fillWidth: fillWidth, thumb: thumb))
                    .animation(settle, value: value)
                    .animation(press, value: dragging)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipShape(Capsule(style: .continuous))
            .overlay(edgeLight)
            .contentShape(Capsule(style: .continuous))
            .gesture(
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
                    .onEnded { _ in
                        dragStart = nil
                        tickStep = nil
                        onDragChange(false)
                    }
            )
            .onChange(of: value) { _, newValue in
                let step = scale.step(forFraction: newValue)
                if VolumeHapticPolicy.shouldTick(previousStep: tickStep, newStep: step, userInitiated: dragging) {
                    Haptics.soft()
                }
                if dragging { tickStep = step }
            }
        }
        .frame(height: thickness)
        .glassSurface(Capsule(style: .continuous), interactive: true, elevated: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(VolumeReadout.accessibilityValue(percent: percent, floorIsMute: scale.floorIsMute))
        .accessibilityHint("Swipe up or down to adjust the TV volume")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = scale.adjusted(value, up: true)
            case .decrement: value = scale.adjusted(value, up: false)
            @unknown default: break
            }
        }
    }

    // MARK: - Glass layers

    private var dark: Bool { colorScheme == .dark }

    /// Recessed track: light falls in from above, so the top of the channel is a touch darker.
    private var trackShade: some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(colors: [Color.black.opacity(dark ? 0.16 : 0.07), Color.black.opacity(0)],
                                 startPoint: .top, endPoint: .center))
    }

    /// The level: a neutral luminous body (ink tones adapt to light and dark), lit along its top edge
    /// and shaded at its foot, with no accent colour.
    private var level: some View {
        Capsule(style: .continuous)
            .fill(LinearGradient(colors: [Color.inkAlpha(dark ? 0.34 : 0.22), Color.inkAlpha(dark ? 0.18 : 0.12)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.22 : 0.42), Color.white.opacity(0)],
                                         startPoint: .top, endPoint: .center))
            )
            .overlay(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(dark ? 0.14 : 0.06)],
                                         startPoint: .center, endPoint: .bottom))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.42 : 0.7), Color.white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }

    /// Edge lighting on the whole track: a bright upper rim fading to a faint lower one.
    private var edgeLight: some View {
        Capsule(style: .continuous)
            .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.34 : 0.62), Color.white.opacity(0.03),
                                                  Color.white.opacity(dark ? 0.12 : 0.22)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .allowsHitTesting(false)
    }

    /// Clear-glass thumb: native Liquid Glass over the refracted layer, a specular highlight, a lit
    /// rim and a contact shadow that deepens while held.
    private func thumbView(diameter: CGFloat) -> some View {
        Color.clear
            .frame(width: diameter, height: diameter)
            .glassEffect(Glass.clear.tint(Color.white.opacity(dragging ? 0.10 : 0.05)), in: Circle())
            .overlay(
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(dark ? 0.42 : 0.6), Color.white.opacity(0)],
                                         center: UnitPoint(x: 0.34, y: 0.24), startRadius: 0,
                                         endRadius: diameter * 0.42))
                    .blendMode(.plusLighter)
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.14), Color.white.opacity(0.4)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(dark ? 0.22 : 0.10), lineWidth: 0.6)
                    .blur(radius: 0.8)
                    .padding(1.2)
            )
            .shadow(color: .black.opacity(dark ? 0.34 : 0.2), radius: dragging ? 9 : 6, y: dragging ? 4 : 2)
    }
}

/// Pure geometry for the volume slider (unit tested).
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
