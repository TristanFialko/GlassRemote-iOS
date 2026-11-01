import SwiftUI

/// Horizontal take on Apple's Control Centre volume slider.
///
/// The capsule is the glass surface itself. Volume is the bright fill growing from the left,
/// and the speaker glyph sits inside the capsule (leading edge). Where the fill passes under
/// the glyph it flips to a dark tint, so the icon stays legible on both sides of the fill edge.
///
/// Dragging is relative (like Apple's): the fill moves by the finger's travel, so a touch on its
/// own never jumps the volume. Value is 0...1; callers map it to remote commands.
struct GlassVolumeSlider: View {
    @Binding var value: Double

    @State private var dragStart: Double?

    private let height: CGFloat = 58
    private let steps = 20

    private var step: Int { Int((value * Double(steps)).rounded()) }

    /// Icon follows the quantised 20-step value, so it can't flicker between frames.
    private var symbolName: String {
        switch step {
        case 0: return "speaker.slash.fill"
        case 1...6: return "speaker.wave.1.fill"
        case 7...13: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fillWidth = width * CGFloat(min(max(value, 0), 1))

            ZStack(alignment: .leading) {
                // Fill: flat right edge, left end follows the capsule via the clip below.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.92), Color.white.opacity(0.80)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: fillWidth)
                    .animation(dragStart == nil ? .easeOut(duration: 0.18) : nil, value: value)

                // Glyph on the unfilled glass: white.
                glyph(Color.white.opacity(0.92))

                // Same glyph, dark, revealed only where the fill is underneath it.
                glyph(Color.black.opacity(0.72))
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: fillWidth)
                            .animation(dragStart == nil ? .easeOut(duration: 0.18) : nil, value: value)
                    }
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStart == nil { dragStart = value }
                        let start = dragStart ?? value
                        let proposed = start + Double(drag.translation.width / width)
                        value = min(max(proposed, 0), 1)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: height)
        .glassSurface(Capsule(), interactive: true, elevated: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(step) of \(steps)")
        .accessibilityHint("Swipe up or down to adjust the TV volume")
        .accessibilityAdjustableAction { direction in
            let delta = 1.0 / Double(steps)
            switch direction {
            case .increment: value = min(value + delta, 1)
            case .decrement: value = max(value - delta, 0)
            @unknown default: break
            }
        }
    }

    private func glyph(_ color: Color) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(color)
            .modifier(SymbolSwap())
            .frame(width: 30, alignment: .leading)
            .padding(.leading, 20)
    }
}

/// Smooth symbol replace on iOS 17+, plain swap on iOS 16 (the project's deployment target).
private struct SymbolSwap: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}
