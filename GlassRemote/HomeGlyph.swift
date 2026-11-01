import SwiftUI

/// Minimal house: one outlined silhouette, a square body under a triangular roof with small eaves.
/// No dividing line, no door, no chimney. Corners are softened by the round-joined stroke in `HomeGlyph`.
struct HouseShape: Shape {
    /// Pulls the drawing in from the frame so a round-joined stroke stays inside it.
    var inset: CGFloat = 0

    func path(in fullRect: CGRect) -> Path {
        let rect = fullRect.insetBy(dx: inset, dy: inset)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addLine(to: p(1, 0.47))
        path.addLine(to: p(0.88, 0.47))
        path.addLine(to: p(0.88, 1))
        path.addLine(to: p(0.12, 1))
        path.addLine(to: p(0.12, 0.47))
        path.addLine(to: p(0, 0.47))
        path.closeSubpath()
        return path
    }
}

struct HomeGlyph: View {
    var color: Color = .white
    private let lineWidth: CGFloat = 1.9

    var body: some View {
        HouseShape(inset: lineWidth / 2)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: 21, height: 20)
    }
}
