import SwiftUI

/// Minimal house: one solid silhouette, a square body under a triangular roof with small eaves.
/// No dividing line, no door, no chimney. Corners are softened by the stroke in `HomeGlyph`.
struct HouseShape: Shape {
    func path(in rect: CGRect) -> Path {
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
    private let inset: CGFloat = 1.5

    var body: some View {
        HouseShape()
            .inset(by: inset)
            .fill(color)
            .overlay {
                HouseShape()
                    .inset(by: inset)
                    .stroke(color, style: StrokeStyle(lineWidth: inset * 2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 21, height: 20)
    }
}
