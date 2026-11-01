import SwiftUI

/// Outlined mouse: a tall capsule with a single button split from the top. Stroke weight
/// matches the semibold SF Symbols beside it in the mode selector.
struct MouseGlyph: View {
    var color: Color = .white
    private let lineWidth: CGFloat = 1.8

    var body: some View {
        ZStack {
            Capsule()
                .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth))
            MouseSplit(inset: lineWidth / 2)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .frame(width: 14, height: 19)
    }
}

private struct MouseSplit: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.40))
        return path
    }
}
