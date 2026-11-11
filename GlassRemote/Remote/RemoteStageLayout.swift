import SwiftUI

// Phase 8: the Remote page's compositions.
//
// Portrait stacks the controls in their declared order with the pad taking every spare point.
// Landscape is a three-column stage: device, mode and launcher on the leading side, the pad in the
// middle, navigation and volume on the trailing side. Both orientations use the SAME child views
// (switched with `AnyLayout`), so the pad, its gesture state and the input guard survive rotation.

/// Which column a Remote control occupies in the landscape stage. Portrait ignores it.
enum RemoteStageColumn: Int, Equatable {
    case leading, pad, trailing
}

struct RemoteStageSlot: LayoutValueKey {
    static let defaultValue: RemoteStageColumn = .leading
}

/// Anchors a control to the bottom of its landscape column (volume, navigation keys).
struct RemoteStageBottom: LayoutValueKey {
    static let defaultValue: Bool = false
}

extension View {
    /// Places this control in a landscape stage column; `bottom` pins it to the column's foot.
    func remoteStage(_ column: RemoteStageColumn, bottom: Bool = false) -> some View {
        layoutValue(key: RemoteStageSlot.self, value: column)
            .layoutValue(key: RemoteStageBottom.self, value: bottom)
    }
}

/// Pure layout decisions for the Remote page (unit tested in Phase8RemoteTests).
enum RemoteLayoutPolicy {
    enum Composition: Equatable {
        case androidPortrait, androidLandscape, samsungPortrait, samsungLandscape
    }

    static func composition(target: RemoteTarget, isLandscape: Bool) -> Composition {
        switch (target, isLandscape) {
        case (.android, false): return .androidPortrait
        case (.android, true): return .androidLandscape
        case (.samsung, false): return .samsungPortrait
        case (.samsung, true): return .samsungLandscape
        }
    }

    /// Short portrait screens (SE / mini class) get tighter gaps and a smaller minimum pad.
    static func isCompact(height: CGFloat) -> Bool { height < 620 }

    static func spacing(compact: Bool, isLandscape: Bool) -> CGFloat {
        isLandscape ? 10 : (compact ? 8 : 12)
    }

    /// The pad never shrinks below this; everything else is fixed height, so the pad is always the
    /// dominant control.
    static func padMinHeight(compact: Bool, isLandscape: Bool) -> CGFloat {
        isLandscape ? 200 : (compact ? 220 : 280)
    }

    /// D-pad diameter for the room the pad gets: as large as fits with space for the bezel,
    /// between 180 and 440 pt.
    static func dpadDiameter(for size: CGSize) -> CGFloat {
        let side = min(size.width, size.height) - 20
        return min(max(side, 180), 440)
    }

    /// Mode selector height: prominent in portrait, slimmer in the landscape column.
    static func selectorHeight(compact: Bool, isLandscape: Bool) -> CGFloat {
        isLandscape ? 40 : (compact ? 42 : 48)
    }

    /// Landscape column widths. Each is a share of the width with a usable minimum and a cap; on a
    /// very narrow window both shrink together so the pad always keeps at least 40 % of the width.
    static func columnWidths(for width: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        guard width > 0 else { return (0, 0) }
        let leading = min(max(width * 0.26, 180), 270)
        let trailing = min(max(width * 0.22, 160), 240)
        let limit = width * 0.6
        let sum = leading + trailing
        if sum > limit {
            let scale = limit / sum
            return (leading * scale, trailing * scale)
        }
        return (leading, trailing)
    }
}

/// The landscape stage. Children are routed to columns with `.remoteStage(...)`; the pad fills the
/// middle at full height, column children stack from the top, bottom-pinned ones from the foot.
struct RemoteStageLayout: Layout {
    var spacing: CGFloat = 10
    var columnSpacing: CGFloat = 14

    struct Frames: Equatable {
        var leading: [CGRect]
        var trailing: [CGRect]
        var pad: CGRect?
    }

    /// Pure frame computation (unit tested). Heights are each child's natural height at its column
    /// width; `bottom` flags mark children pinned to the column's foot.
    static func frames(width: CGFloat, height: CGFloat,
                       leading: [CGFloat], leadingBottom: [Bool],
                       trailing: [CGFloat], trailingBottom: [Bool],
                       hasPad: Bool, spacing: CGFloat, columnSpacing: CGFloat) -> Frames {
        let widths = RemoteLayoutPolicy.columnWidths(for: width)
        let leadingWidth: CGFloat = leading.isEmpty ? 0 : widths.leading
        let trailingWidth: CGFloat = trailing.isEmpty ? 0 : widths.trailing
        let trailingX: CGFloat = max(width - trailingWidth, 0)

        func stack(_ heights: [CGFloat], _ bottom: [Bool], x: CGFloat, w: CGFloat) -> [CGRect] {
            var rects = Array(repeating: CGRect.zero, count: heights.count)
            var y: CGFloat = 0
            for i in heights.indices where !(i < bottom.count && bottom[i]) {
                rects[i] = CGRect(x: x, y: y, width: w, height: heights[i])
                y += heights[i] + spacing
            }
            var foot: CGFloat = height
            for i in heights.indices.reversed() where i < bottom.count && bottom[i] {
                foot -= heights[i]
                rects[i] = CGRect(x: x, y: foot, width: w, height: heights[i])
                foot -= spacing
            }
            return rects
        }

        var pad: CGRect?
        if hasPad {
            let x: CGFloat = leadingWidth > 0 ? leadingWidth + columnSpacing : 0
            let right: CGFloat = trailingWidth > 0 ? trailingX - columnSpacing : width
            pad = CGRect(x: x, y: 0, width: max(right - x, 0), height: max(height, 0))
        }
        return Frames(leading: stack(leading, leadingBottom, x: 0, w: leadingWidth),
                      trailing: stack(trailing, trailingBottom, x: trailingX, w: trailingWidth),
                      pad: pad)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 700, height: proposal.height ?? 360)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = RemoteLayoutPolicy.columnWidths(for: bounds.width)
        var leadingIndex: [Int] = []
        var trailingIndex: [Int] = []
        var padIndex: [Int] = []
        for (i, view) in subviews.enumerated() {
            switch view[RemoteStageSlot.self] {
            case .leading: leadingIndex.append(i)
            case .trailing: trailingIndex.append(i)
            case .pad: padIndex.append(i)
            }
        }
        func heights(_ indices: [Int], width: CGFloat) -> [CGFloat] {
            indices.map { subviews[$0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        }
        func bottoms(_ indices: [Int]) -> [Bool] { indices.map { subviews[$0][RemoteStageBottom.self] } }

        let frames = Self.frames(width: bounds.width, height: bounds.height,
                                 leading: heights(leadingIndex, width: widths.leading),
                                 leadingBottom: bottoms(leadingIndex),
                                 trailing: heights(trailingIndex, width: widths.trailing),
                                 trailingBottom: bottoms(trailingIndex),
                                 hasPad: !padIndex.isEmpty, spacing: spacing, columnSpacing: columnSpacing)

        func place(_ index: Int, _ rect: CGRect) {
            subviews[index].place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
        for (n, i) in leadingIndex.enumerated() { place(i, frames.leading[n]) }
        for (n, i) in trailingIndex.enumerated() { place(i, frames.trailing[n]) }
        if let pad = frames.pad {
            for i in padIndex { place(i, pad) }
        }
    }
}
