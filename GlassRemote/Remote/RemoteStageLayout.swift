import SwiftUI

// Phase 8: the Remote page's compositions.
//
// Portrait stacks the controls in their declared order with the pad taking every spare point.
// Landscape (Phase 9 gap fix) is a console built around the pad rather than the portrait stack split
// into columns:
//
//   ┌ status ──────────────── mode (over the pad) ──────────────── device · power ┐
//   │ key │                                                               │ key │
//   │ rail│                       trackpad / D-pad                        │ rail│
//   │     │                                                               │     │
//   │     │  volume deck, exactly under the pad                           │     │
//   └─────┴───────────────────────────────────────────────────────────────┴─────┘
//
// A slim bar across the top holds the status pill, the Mouse / D-pad selector centred over the pad,
// and the device switch with power. Narrow key rails sit under each thumb, their keys centred on the
// rail. The pad takes the whole middle (about three quarters of the stage width) and the volume deck
// runs along its foot. Both orientations use the SAME child views (switched with `AnyLayout`), so the
// pad, its gesture state, a held key and the input guard survive rotation.

/// Where a Remote control sits on the landscape stage. Portrait ignores it.
enum RemoteStageColumn: Int, Equatable {
    /// Top bar: the status pill (leading), the mode selector (centred over the pad) and the device
    /// switch with power (trailing).
    case topLeading, topCenter, topTrailing
    /// Key rails beside the pad. Each child is a key group; the groups stack and centre on the rail.
    case leading, trailing
    case pad
    /// Floats over the top of the pad (the Samsung link banner, shown only while the pad is disabled).
    case overPad
    /// The volume deck along the pad's foot.
    case deck
    /// Continuation §D: a page-swipe area in a rail's free space (leading first).
    case gap
}

struct RemoteStageSlot: LayoutValueKey {
    static let defaultValue: RemoteStageColumn = .leading
}

extension View {
    /// Places this control on the landscape stage.
    func remoteStage(_ column: RemoteStageColumn) -> some View {
        layoutValue(key: RemoteStageSlot.self, value: column)
    }
}

/// Pure layout decisions for the Remote page (unit tested in Phase8RemoteTests and
/// RemoteLandscapeLayoutTests).
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

    /// Padding around the Remote's controls inside its page (both orientations).
    static let stageInsets = EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16)

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

    /// Mode selector height: prominent in portrait, slimmer in the landscape top bar.
    static func selectorHeight(compact: Bool, isLandscape: Bool) -> CGFloat {
        isLandscape ? 40 : (compact ? 42 : 48)
    }

    /// Gap between a landscape key rail and the pad.
    static let stageColumnSpacing: CGFloat = 14
    /// Phase 9 §1.2: the narrowest the landscape pad may get.
    static let landscapePadMinWidth: CGFloat = 200
    /// Corner radius shared by every central touch surface (mouse pad, D-pad bezel, Samsung pad).
    static let padCornerRadius: CGFloat = 36

    // MARK: Landscape stage

    /// Height of the landscape top bar (the status pill, the switch and power are all 44 pt).
    static let topBarHeight: CGFloat = 44
    /// The status pill's widest size in the top bar.
    static let statusMaxWidth: CGFloat = 260
    /// Gap between key groups on one rail (inside a group the keys are 10 pt apart).
    static let railGroupSpacing: CGFloat = 16
    /// Inset of the banner that floats over the pad.
    static let overPadInset: CGFloat = 10

    /// Width of each landscape key rail: a tenth of the stage, between a comfortable key (58 pt) and
    /// 72 pt, so the pad keeps the rest.
    static func railWidth(stageWidth: CGFloat) -> CGFloat {
        min(max(stageWidth * 0.1, 58), 72)
    }

    /// The landscape pad's width: everything between the two rails. Both rails are always reserved,
    /// so it depends only on the stage width, never on the target.
    static func landscapePadWidth(stageWidth: CGFloat) -> CGFloat {
        max(stageWidth - 2 * (railWidth(stageWidth: stageWidth) + stageColumnSpacing), 0)
    }

    /// The Mouse / D-pad selector's width, centred over the pad in the top bar.
    static func modeBarWidth(stageWidth: CGFloat) -> CGFloat {
        min(max(landscapePadWidth(stageWidth: stageWidth) * 0.32, 132), 172)
    }

    /// The status pill's width in the top bar: up to the mode selector's slot (reserved for both
    /// targets, so the bar does not jump when the device changes) and at most `statusMaxWidth`.
    static func statusWidth(stageWidth: CGFloat, spacing: CGFloat = 10) -> CGFloat {
        let room = stageWidth / 2 - modeBarWidth(stageWidth: stageWidth) / 2 - spacing
        return max(min(room, statusMaxWidth), 0)
    }

    /// Height under the top bar: rails, pad and deck share it.
    static func landscapeBandHeight(stageHeight: CGFloat, spacing: CGFloat = 10) -> CGFloat {
        max(stageHeight - topBarHeight - spacing, 0)
    }

    /// Rail key height: full size on every current iPhone, a little shorter on a very short stage so
    /// four keys still fit beside the pad.
    static func railKeyHeight(stageHeight: CGFloat) -> CGFloat {
        stageHeight >= 320 ? 52 : 46
    }

    // MARK: Continuation §C3 volume sizing

    /// Portrait track heights (thumb = height - 10).
    static let portraitVolumeThickness: CGFloat = 60
    static let compactVolumeThickness: CGFloat = 56
    /// Landscape deck height, and the least it may become on a very short stage.
    static let landscapeVolumeThickness: CGFloat = 66
    static let landscapeVolumeMinThickness: CGFloat = 56
    /// The landscape deck is never shorter than this (it spans the pad's width).
    static let landscapeVolumeMinLength: CGFloat = 300

    static func volumeThickness(compact: Bool) -> CGFloat {
        compact ? compactVolumeThickness : portraitVolumeThickness
    }

    /// The deck's height for a landscape pad column `stageHeight` tall: full size while the pad keeps
    /// its minimum height above it, then it gives way (to 56 pt) before the pad does.
    static func volumeDeckHeight(stageHeight: CGFloat, spacing: CGFloat = 10) -> CGFloat {
        let room = stageHeight - padMinHeight(compact: false, isLandscape: true) - spacing
        return min(max(room, landscapeVolumeMinThickness), landscapeVolumeThickness)
    }

    /// The deck's height on a whole landscape stage (under the top bar).
    static func landscapeDeckHeight(stageHeight: CGFloat, spacing: CGFloat = 10) -> CGFloat {
        volumeDeckHeight(stageHeight: landscapeBandHeight(stageHeight: stageHeight, spacing: spacing), spacing: spacing)
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

    /// "No apps", "1 app", "9 apps" (the Apps key's VoiceOver value).
    static func appCountLabel(_ count: Int) -> String {
        switch count {
        case ..<1: return "No apps"
        case 1: return "1 app"
        default: return "\(count) apps"
        }
    }
}

/// The landscape stage. Children are routed with `.remoteStage(...)`.
struct RemoteStageLayout: Layout {
    var spacing: CGFloat = 10
    var columnSpacing: CGFloat = RemoteLayoutPolicy.stageColumnSpacing

    /// Continuation §D: a free rail area shorter than this is not offered as a page-swipe area.
    static let swipeAreaMinHeight: CGFloat = 44

    struct Frames: Equatable {
        var topLeading: CGRect?
        var topCenter: CGRect?
        var topTrailing: CGRect?
        /// One rect per key group, centred together on the rail.
        var leading: [CGRect]
        var trailing: [CGRect]
        var pad: CGRect?
        var overPad: [CGRect]
        /// The volume deck, exactly under the pad.
        var deck: CGRect?
        /// Continuation §D: free rail space under the keys. Nil when too short to swipe on.
        var leadingGap: CGRect?
        var trailingGap: CGRect?
    }

    /// Pure frame computation (unit tested). `leading` / `trailing` are each key group's natural
    /// height at the rail width; `overPad` the floating children's heights; `topTrailingWidth` the
    /// natural width of the device switch with power. Both rails are always reserved, so the pad and
    /// the deck depend only on the stage size.
    static func frames(width: CGFloat, height: CGFloat,
                       topBar: Bool = true, topTrailingWidth: CGFloat = 0,
                       leading: [CGFloat], trailing: [CGFloat], overPad: [CGFloat] = [],
                       hasPad: Bool = true, deck: Bool = true,
                       spacing: CGFloat = 10,
                       columnSpacing: CGFloat = RemoteLayoutPolicy.stageColumnSpacing) -> Frames {
        let railWidth = RemoteLayoutPolicy.railWidth(stageWidth: width)
        let padX = railWidth + columnSpacing
        let padWidth = max(width - 2 * padX, 0)
        let barHeight: CGFloat = topBar ? RemoteLayoutPolicy.topBarHeight : 0
        let bandTop: CGFloat = topBar ? barHeight + spacing : 0
        let band = max(height - bandTop, 0)

        var topLeading: CGRect?
        var topCenter: CGRect?
        var topTrailing: CGRect?
        if topBar {
            let status = RemoteLayoutPolicy.statusWidth(stageWidth: width, spacing: spacing)
            let mode = RemoteLayoutPolicy.modeBarWidth(stageWidth: width)
            topLeading = CGRect(x: 0, y: 0, width: status, height: barHeight)
            topCenter = CGRect(x: padX + (padWidth - mode) / 2, y: 0, width: mode, height: barHeight)
            let trailingWidth = min(max(topTrailingWidth, 0), width)
            topTrailing = CGRect(x: width - trailingWidth, y: 0, width: trailingWidth, height: barHeight)
        }

        let deckHeight: CGFloat = deck ? RemoteLayoutPolicy.volumeDeckHeight(stageHeight: band, spacing: spacing) : 0
        let padHeight: CGFloat = deck ? max(band - deckHeight - spacing, 0) : band
        let padRect = CGRect(x: padX, y: bandTop, width: padWidth, height: padHeight)
        let deckRect: CGRect? = deck
            ? CGRect(x: padX, y: max(height - deckHeight, bandTop), width: padWidth, height: deckHeight)
            : nil

        var floating: [CGRect] = []
        let inset = RemoteLayoutPolicy.overPadInset
        var floatY = padRect.minY + inset
        for h in overPad {
            floating.append(CGRect(x: padRect.minX + inset, y: floatY, width: max(padRect.width - inset * 2, 0), height: h))
            floatY += h + spacing
        }

        func rail(_ heights: [CGFloat], x: CGFloat) -> (rects: [CGRect], gap: CGRect?) {
            let groupGap = RemoteLayoutPolicy.railGroupSpacing
            let total = heights.reduce(0, +) + groupGap * CGFloat(max(heights.count - 1, 0))
            var y = bandTop + max((band - total) / 2, 0)
            var rects: [CGRect] = []
            for h in heights {
                rects.append(CGRect(x: x, y: y, width: railWidth, height: h))
                y += h + groupGap
            }
            let top = rects.last.map { $0.maxY + spacing } ?? bandTop
            let gap: CGRect? = height - top >= swipeAreaMinHeight
                ? CGRect(x: x, y: top, width: railWidth, height: height - top) : nil
            return (rects, gap)
        }
        let left = rail(leading, x: 0)
        let right = rail(trailing, x: max(width - railWidth, 0))

        return Frames(topLeading: topLeading, topCenter: topCenter, topTrailing: topTrailing,
                      leading: left.rects, trailing: right.rects,
                      pad: hasPad ? padRect : nil, overPad: floating, deck: deckRect,
                      leadingGap: left.gap, trailingGap: right.gap)
    }

    /// The pad's frame on a stage of this size (unit tested): it depends only on the stage size,
    /// never on the target or the keys.
    static func padRect(width: CGFloat, height: CGFloat,
                        spacing: CGFloat = RemoteLayoutPolicy.spacing(compact: false, isLandscape: true)) -> CGRect {
        frames(width: width, height: height, leading: [], trailing: [], spacing: spacing).pad ?? .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 700, height: proposal.height ?? 360)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let railWidth = RemoteLayoutPolicy.railWidth(stageWidth: bounds.width)
        var slots: [RemoteStageColumn: [Int]] = [:]
        for (i, view) in subviews.enumerated() {
            slots[view[RemoteStageSlot.self], default: []].append(i)
        }
        func indices(_ column: RemoteStageColumn) -> [Int] { slots[column] ?? [] }
        func heights(_ list: [Int], width: CGFloat) -> [CGFloat] {
            list.map { subviews[$0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        }
        let topTrailingWidth = indices(.topTrailing)
            .map { subviews[$0].sizeThatFits(.unspecified).width }
            .max() ?? 0
        let hasTop = !(indices(.topLeading) + indices(.topCenter) + indices(.topTrailing)).isEmpty
        let padWidth = RemoteLayoutPolicy.landscapePadWidth(stageWidth: bounds.width)
        let floatWidth = max(padWidth - RemoteLayoutPolicy.overPadInset * 2, 0)

        let frames = Self.frames(width: bounds.width, height: bounds.height,
                                 topBar: hasTop, topTrailingWidth: topTrailingWidth,
                                 leading: heights(indices(.leading), width: railWidth),
                                 trailing: heights(indices(.trailing), width: railWidth),
                                 overPad: heights(indices(.overPad), width: floatWidth),
                                 hasPad: !indices(.pad).isEmpty, deck: !indices(.deck).isEmpty,
                                 spacing: spacing, columnSpacing: columnSpacing)

        func place(_ index: Int, _ rect: CGRect) {
            subviews[index].place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
        /// Top-bar children keep their own height (the selector is 40 pt in a 44 pt bar): centred.
        func placeCentred(_ index: Int, _ rect: CGRect) {
            subviews[index].place(at: CGPoint(x: bounds.minX + rect.midX, y: bounds.minY + rect.midY),
                                  anchor: .center,
                                  proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
        let hidden = CGRect(x: 0, y: 0, width: 0, height: 0)
        for i in indices(.topLeading) { placeCentred(i, frames.topLeading ?? hidden) }
        for i in indices(.topCenter) { placeCentred(i, frames.topCenter ?? hidden) }
        for i in indices(.topTrailing) { placeCentred(i, frames.topTrailing ?? hidden) }
        for (n, i) in indices(.leading).enumerated() { place(i, frames.leading[n]) }
        for (n, i) in indices(.trailing).enumerated() { place(i, frames.trailing[n]) }
        for i in indices(.pad) { place(i, frames.pad ?? hidden) }
        for (n, i) in indices(.overPad).enumerated() { place(i, frames.overPad[n]) }
        for i in indices(.deck) { place(i, frames.deck ?? hidden) }
        // §D: swipe areas take the free rail space (leading first); without one they are zero-sized.
        let gaps: [CGRect?] = [frames.leadingGap, frames.trailingGap]
        for (n, i) in indices(.gap).enumerated() {
            place(i, (n < gaps.count ? gaps[n] : nil) ?? hidden)
        }
    }
}
