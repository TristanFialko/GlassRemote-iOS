import SwiftUI

// Phase 8: the Remote page's compositions.
//
// Portrait stacks the controls in their declared order with the pad taking every spare point.
// Landscape is a three-column stage: device, mode and launcher on the leading side, the pad in the
// middle, navigation on the trailing side. Continuation §C3: volume has its own deck along the foot
// of the pad and trailing column, so it is long and prominent instead of a leftover narrow column. Both orientations use the SAME child views
// (switched with `AnyLayout`), so the pad, its gesture state and the input guard survive rotation.

/// Which column a Remote control occupies in the landscape stage. Portrait ignores it.
enum RemoteStageColumn: Int, Equatable {
    /// `deck`: the landscape volume deck, under the pad and the trailing column.
    /// `gap`: continuation §D, a page-swipe area in a side column's free space (leading first).
    case leading, pad, trailing, deck, gap
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

    /// Gap between a landscape column and the pad.
    static let stageColumnSpacing: CGFloat = 14
    /// Phase 9 §1.2: the narrowest the landscape pad may get. The columns give way first.
    static let landscapePadMinWidth: CGFloat = 200
    /// Corner radius shared by every central touch surface (mouse pad, D-pad bezel, Samsung pad).
    static let padCornerRadius: CGFloat = 36

    // MARK: Continuation §C3 volume sizing

    /// Portrait track heights (thumb = height - 10).
    static let portraitVolumeThickness: CGFloat = 60
    static let compactVolumeThickness: CGFloat = 56
    /// Landscape deck height, and the least it may become on a very short stage.
    static let landscapeVolumeThickness: CGFloat = 66
    static let landscapeVolumeMinThickness: CGFloat = 56
    /// The landscape deck is never shorter than this (it spans the pad and the trailing column).
    static let landscapeVolumeMinLength: CGFloat = 300

    static func volumeThickness(compact: Bool) -> CGFloat {
        compact ? compactVolumeThickness : portraitVolumeThickness
    }

    /// The deck's height on a landscape stage: full size while the pad keeps its minimum height above
    /// it, then it gives way (to 56 pt) before the pad does.
    static func volumeDeckHeight(stageHeight: CGFloat, spacing: CGFloat = 10) -> CGFloat {
        let room = stageHeight - padMinHeight(compact: false, isLandscape: true) - spacing
        return min(max(room, landscapeVolumeMinThickness), landscapeVolumeThickness)
    }

    /// Landscape column widths. Each is a share of the width with a usable minimum and a cap. The
    /// pad always keeps at least `landscapePadMinWidth` and 38 % of the width (never less than 40 %
    /// left to the columns' combined cap of 60 %); on a narrow window both columns shrink together.
    static func columnWidths(for width: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        guard width > 0 else { return (0, 0) }
        let leading = min(max(width * 0.27, 176), 280)
        let trailing = min(max(width * 0.23, 156), 252)
        let padFloor = max(landscapePadMinWidth, width * 0.38)
        let limit = max(min(width - padFloor - stageColumnSpacing * 2, width * 0.6), 0)
        let sum = leading + trailing
        if sum > limit {
            let scale = limit / sum
            return (leading * scale, trailing * scale)
        }
        return (leading, trailing)
    }

    /// How much of the device name the status pill can show at a width.
    enum PillStyle: Equatable {
        /// "Android TV", status and the menu chevron.
        case full
        /// "Android", status and the chevron.
        case short
        /// "Android" and status; the whole pill is still the menu.
        case compact
    }

    static func pillStyle(width: CGFloat) -> PillStyle {
        if width >= 180 { return .full }
        return width >= 150 ? .short : .compact
    }

    /// Width the landscape Apps card needs for `previews` overlapping icons plus its one-line text.
    static func launcherCardRequiredWidth(previews: Int) -> CGFloat {
        let padding: CGFloat = 24
        let text: CGFloat = 58
        guard previews > 0 else { return padding + text }
        return padding + 34 + CGFloat(previews - 1) * 24 + 10 + text
    }

    /// Preview icons on the Apps card: as many as fit (up to 3) without wrapping the text.
    static func launcherPreviewCount(cardWidth: CGFloat) -> Int {
        for n in stride(from: 3, through: 1, by: -1) where launcherCardRequiredWidth(previews: n) <= cardWidth {
            return n
        }
        return 0
    }

    /// "No apps", "1 app", "9 apps".
    static func appCountLabel(_ count: Int) -> String {
        switch count {
        case ..<1: return "No apps"
        case 1: return "1 app"
        default: return "\(count) apps"
        }
    }
}

/// The landscape stage. Children are routed to columns with `.remoteStage(...)`; the pad fills the
/// middle at full height, column children stack from the top, bottom-pinned ones from the foot.
struct RemoteStageLayout: Layout {
    var spacing: CGFloat = 10
    var columnSpacing: CGFloat = RemoteLayoutPolicy.stageColumnSpacing
    /// Phase 9 §1.2: reserve both columns even when one is empty, so the pad's frame depends only
    /// on the stage size. The Android and Samsung pads are then identical in the same size class.
    var reservesColumns: Bool = true

    /// Continuation §D: a free column area shorter than this is not offered as a page-swipe area.
    static let swipeAreaMinHeight: CGFloat = 44

    struct Frames: Equatable {
        var leading: [CGRect]
        var trailing: [CGRect]
        var pad: CGRect?
        /// Continuation §C3: the volume deck, under the pad and the trailing column.
        var deck: CGRect? = nil
        /// Continuation §D: free space in the leading and trailing columns (between their top and
        /// bottom-pinned children, one spacing clear of both). Nil when too short to swipe on.
        var leadingGap: CGRect? = nil
        var trailingGap: CGRect? = nil
    }

    /// Pure frame computation (unit tested). Heights are each child's natural height at its column
    /// width; `bottom` flags mark children pinned to the column's foot. With `deck`, the volume deck
    /// takes `volumeDeckHeight` along the foot of the pad and trailing column (the leading column keeps
    /// the full height), and the pad and trailing column end one spacing above it.
    static func frames(width: CGFloat, height: CGFloat,
                       leading: [CGFloat], leadingBottom: [Bool],
                       trailing: [CGFloat], trailingBottom: [Bool],
                       hasPad: Bool, spacing: CGFloat, columnSpacing: CGFloat,
                       reservesColumns: Bool = false, deck: Bool = false) -> Frames {
        let widths = RemoteLayoutPolicy.columnWidths(for: width)
        let leadingWidth: CGFloat = (leading.isEmpty && !reservesColumns) ? 0 : widths.leading
        let trailingWidth: CGFloat = (trailing.isEmpty && !reservesColumns) ? 0 : widths.trailing
        let trailingX: CGFloat = max(width - trailingWidth, 0)

        let deckHeight: CGFloat = deck ? RemoteLayoutPolicy.volumeDeckHeight(stageHeight: height, spacing: spacing) : 0
        let upper: CGFloat = deck ? max(height - deckHeight - spacing, 0) : height

        func stack(_ heights: [CGFloat], _ bottom: [Bool], x: CGFloat, w: CGFloat, foot columnFoot: CGFloat) -> [CGRect] {
            var rects = Array(repeating: CGRect.zero, count: heights.count)
            var y: CGFloat = 0
            for i in heights.indices where !(i < bottom.count && bottom[i]) {
                rects[i] = CGRect(x: x, y: y, width: w, height: heights[i])
                y += heights[i] + spacing
            }
            var foot: CGFloat = columnFoot
            for i in heights.indices.reversed() where i < bottom.count && bottom[i] {
                foot -= heights[i]
                rects[i] = CGRect(x: x, y: foot, width: w, height: heights[i])
                foot -= spacing
            }
            return rects
        }

        let middleX: CGFloat = leadingWidth > 0 ? leadingWidth + columnSpacing : 0
        var pad: CGRect?
        if hasPad {
            let right: CGFloat = trailingWidth > 0 ? trailingX - columnSpacing : width
            pad = CGRect(x: middleX, y: 0, width: max(right - middleX, 0), height: max(upper, 0))
        }
        let deckRect: CGRect? = deck
            ? CGRect(x: middleX, y: max(height - deckHeight, 0), width: max(width - middleX, 0), height: deckHeight)
            : nil
        func gap(_ rects: [CGRect], _ bottom: [Bool], x: CGFloat, w: CGFloat, foot columnFoot: CGFloat) -> CGRect? {
            guard w > 0 else { return nil }
            var top: CGFloat = 0
            var base: CGFloat = columnFoot
            for i in rects.indices {
                if i < bottom.count && bottom[i] { base = min(base, rects[i].minY - spacing) }
                else { top = max(top, rects[i].maxY + spacing) }
            }
            guard base - top >= RemoteStageLayout.swipeAreaMinHeight else { return nil }
            return CGRect(x: x, y: top, width: w, height: base - top)
        }
        let leadingRects = stack(leading, leadingBottom, x: 0, w: leadingWidth, foot: height)
        let trailingRects = stack(trailing, trailingBottom, x: trailingX, w: trailingWidth, foot: upper)
        return Frames(leading: leadingRects, trailing: trailingRects, pad: pad, deck: deckRect,
                      leadingGap: gap(leadingRects, leadingBottom, x: 0, w: leadingWidth, foot: height),
                      trailingGap: gap(trailingRects, trailingBottom, x: trailingX, w: trailingWidth, foot: upper))
    }

    /// The pad's frame on a stage of this size when both columns and the volume deck are reserved
    /// (unit tested): it depends only on the stage size, never on the target.
    static func padRect(width: CGFloat, height: CGFloat,
                        spacing: CGFloat = RemoteLayoutPolicy.spacing(compact: false, isLandscape: true),
                        columnSpacing: CGFloat = RemoteLayoutPolicy.stageColumnSpacing,
                        deck: Bool = true) -> CGRect {
        frames(width: width, height: height, leading: [], leadingBottom: [], trailing: [], trailingBottom: [],
               hasPad: true, spacing: spacing, columnSpacing: columnSpacing, reservesColumns: true,
               deck: deck).pad ?? .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 700, height: proposal.height ?? 360)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = RemoteLayoutPolicy.columnWidths(for: bounds.width)
        var leadingIndex: [Int] = []
        var trailingIndex: [Int] = []
        var padIndex: [Int] = []
        var deckIndex: [Int] = []
        var gapIndex: [Int] = []
        for (i, view) in subviews.enumerated() {
            switch view[RemoteStageSlot.self] {
            case .leading: leadingIndex.append(i)
            case .trailing: trailingIndex.append(i)
            case .pad: padIndex.append(i)
            case .deck: deckIndex.append(i)
            case .gap: gapIndex.append(i)
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
                                 hasPad: !padIndex.isEmpty, spacing: spacing, columnSpacing: columnSpacing,
                                 reservesColumns: reservesColumns, deck: !deckIndex.isEmpty)

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
        if let deck = frames.deck {
            for i in deckIndex { place(i, deck) }
        }
        // §D: swipe areas take the free column space (leading first); without one they are zero-sized.
        let gaps: [CGRect?] = [frames.leadingGap, frames.trailingGap]
        for (n, i) in gapIndex.enumerated() {
            place(i, (n < gaps.count ? gaps[n] : nil) ?? CGRect(x: 0, y: 0, width: 0, height: 0))
        }
    }
}
