import SwiftUI

// Phase 6: shared layout and glass geometry. Everything here is pure (no TV, ADB or model access),
// so rotating or resizing only re-arranges views; it never touches the connection or input state.

// MARK: - Layout context

/// Orientation facts every page can read. `RootPagerView` resolves it once from the vertical size
/// class, not from its geometry: the keyboard shrinks the geometry in portrait and must never flip a
/// page into its landscape layout.
struct LayoutContext: Equatable {
    var isLandscape: Bool
    /// Room a page gets (after the landscape rail).
    var size: CGSize

    static let portrait = LayoutContext(isLandscape: false, size: CGSize(width: 393, height: 852))

    static func resolve(verticalSizeClass: UserInterfaceSizeClass?, size: CGSize) -> LayoutContext {
        if let sizeClass = verticalSizeClass {
            return LayoutContext(isLandscape: sizeClass == .compact, size: size)
        }
        return LayoutContext(isLandscape: size.width > size.height, size: size)
    }
}

private struct LayoutContextKey: EnvironmentKey {
    static let defaultValue = LayoutContext.portrait
}

extension EnvironmentValues {
    /// Set by `RootPagerView` for every page.
    var layoutContext: LayoutContext {
        get { self[LayoutContextKey.self] }
        set { self[LayoutContextKey.self] = newValue }
    }
}

// MARK: - Landscape rail

/// In landscape the page dock stands on end as a rail along the leading edge, so pages keep their
/// full height. The same glass selector drives both (see `GlassScrubSelector(axis:)`).
extension DockMetrics {
    static let railWidth: CGFloat = 64
    static let railSegment: CGFloat = 62
    static let railInset: CGFloat = 6
    /// v5 §2: the landscape Now Playing tile under the rail (artwork side, gap above the bottom edge).
    static let railTileArtwork: CGFloat = 44
    static let railMiniBottom: CGFloat = 8
    /// Gap between the rail and the leading safe-area edge, before the drop below.
    static let railGap: CGFloat = 6
    /// Space pages keep between the rail and their content.
    static let railBreathing: CGFloat = 12
    /// Bottom space pages keep in landscape, where nothing floats at the bottom.
    static let landscapeBottomClearance: CGFloat = 8

    /// How far the rail sinks into the leading safe area (the sensor-housing side): 20 % of the
    /// inset, at most 12 pt, so it sits close to the edge without ever reaching the cut-out.
    static func railDrop(safeLeading: CGFloat) -> CGFloat { min(max(safeLeading * 0.2, 0), 12) }

    static func railLength(count: Int) -> CGFloat { CGFloat(max(count, 1)) * railSegment + railInset * 2 }

    /// v5 §2: whether the Now Playing tile fits below a vertically centred rail of `count` items in a
    /// window `height` tall, without touching it.
    static func railTileFits(height: CGFloat, count: Int) -> Bool {
        (height - railLength(count: count)) / 2 >= railWidth + railMiniBottom + 4
    }

    /// Leading space a page keeps clear of the rail, measured from the leading safe-area edge.
    static func railClearance(safeLeading: CGFloat) -> CGFloat {
        railGap - railDrop(safeLeading: safeLeading) + railWidth + railBreathing
    }

    /// Strip, measured from the physical leading edge of the screen, whose touches belong to the
    /// rail and never to the page-swipe recogniser.
    static func railZone(safeLeading: CGFloat) -> CGFloat {
        max(safeLeading, 0) + railGap - railDrop(safeLeading: safeLeading) + railWidth + 8
    }
}

// MARK: - Page depth

// MARK: - Scrub selector geometry

/// Pure maths behind `GlassScrubSelector` (unit tested). `offset` is the lens's leading (or top)
/// edge along the bar; `length` is the bar's length along its axis.
enum ScrubGeometry {
    static func segment(length: CGFloat, inset: CGFloat, count: Int) -> CGFloat {
        max(length - inset * 2, 0) / CGFloat(max(count, 1))
    }

    /// Keeps the lens inside the bar.
    static func clamp(_ offset: CGFloat, inset: CGFloat, length: CGFloat, segment: CGFloat) -> CGFloat {
        min(max(offset, inset), max(length - inset - segment, inset))
    }

    /// The segment under the lens's centre: selection flips as the centre crosses a midpoint.
    static func index(forOffset offset: CGFloat, inset: CGFloat, segment: CGFloat, count: Int) -> Int {
        guard segment > 0, count > 0 else { return 0 }
        let centre = offset + segment / 2
        return min(max(Int((centre - inset) / segment), 0), count - 1)
    }

    /// 0 with the lens on the first segment, 1 on the last: steers the specular highlight.
    static func progress(offset: CGFloat, inset: CGFloat, length: CGFloat, segment: CGFloat) -> CGFloat {
        let travel = length - inset * 2 - segment
        guard travel > 0 else { return 0.5 }
        return min(max((offset - inset) / travel, 0), 1)
    }

    /// Liquid stretch along the bar from the finger's speed (pt/s): 1 at rest, at most 1.16.
    static func stretch(speed: CGFloat) -> CGFloat { 1 + min(abs(speed) / 2400, 1) * 0.16 }

    /// Where along the bar (0...1) the dock's reflected highlight sits. It follows the bubble but
    /// travels less than it, like a reflection on a curved surface.
    static func sheenCentre(progress: CGFloat) -> CGFloat { 0.12 + min(max(progress, 0), 1) * 0.76 }
}

// MARK: - Remote page, landscape

/// Marks the Remote page's pad (trackpad / D-pad, or the Samsung panel) for `RemoteLandscapeLayout`.
struct RemotePadSlot: LayoutValueKey { static let defaultValue = false }
/// Marks controls that sit at the bottom of the landscape control column (navigation keys, volume).
struct RemoteBottomSlot: LayoutValueKey { static let defaultValue = false }

/// Landscape arrangement of the Remote page: a control column beside a full-height pad. Used through
/// `AnyLayout` (portrait keeps the Phase 5 `VStackLayout`), so rotating re-arranges the SAME views
/// instead of rebuilding them: the trackpad, its recognisers, a held button and the mouse session
/// all survive rotation.
struct RemoteLandscapeLayout: Layout {
    var spacing: CGFloat = 8
    var columnSpacing: CGFloat = 14
    var maxColumnWidth: CGFloat = 340
    var padMinHeight: CGFloat = 200
    var padMaxHeight: CGFloat? = nil

    struct Frames: Equatable {
        var column: [CGRect]
        var pad: CGRect?
        var size: CGSize
    }

    static func columnWidth(for width: CGFloat, maxColumnWidth: CGFloat) -> CGFloat {
        max(min(maxColumnWidth, width * 0.46), 0)
    }

    /// Pure geometry (unit tested). `heights` are the column views' heights in order; `bottom` marks
    /// the ones anchored to the bottom of the column. `height == nil` means the page is scrolling.
    static func frames(width: CGFloat, height: CGFloat?, heights: [CGFloat], bottom: [Bool], hasPad: Bool,
                       spacing: CGFloat, columnSpacing: CGFloat, maxColumnWidth: CGFloat,
                       padMinHeight: CGFloat, padMaxHeight: CGFloat?) -> Frames {
        let colWidth = hasPad ? columnWidth(for: width, maxColumnWidth: maxColumnWidth) : width
        let gaps = CGFloat(max(heights.count - 1, 0)) * spacing
        let natural = heights.reduce(0, +) + gaps
        let total = height ?? max(natural, hasPad ? padMinHeight : 0)
        func anchored(_ i: Int) -> Bool { i < bottom.count && bottom[i] }

        var rects = Array(repeating: CGRect.zero, count: heights.count)
        var y: CGFloat = 0
        for i in heights.indices where !anchored(i) {
            rects[i] = CGRect(x: 0, y: y, width: colWidth, height: heights[i])
            y += heights[i] + spacing
        }
        var bottomY = max(total, natural)
        for i in heights.indices.reversed() where anchored(i) {
            bottomY -= heights[i]
            rects[i] = CGRect(x: 0, y: bottomY, width: colWidth, height: heights[i])
            bottomY -= spacing
        }

        var pad: CGRect?
        if hasPad {
            let x = colWidth + columnSpacing
            var padHeight = max(total, padMinHeight)
            if let cap = padMaxHeight { padHeight = min(padHeight, max(cap, padMinHeight)) }
            pad = CGRect(x: x, y: 0, width: max(width - x, 0), height: padHeight)
        }
        let reported = height ?? max(natural, pad?.height ?? 0)
        return Frames(column: rects, pad: pad, size: CGSize(width: width, height: reported))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 600
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        return compute(width: width, height: height, subviews: subviews).frames.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = compute(width: bounds.width, height: bounds.height, subviews: subviews)
        for (n, i) in result.columnIndices.enumerated() {
            let r = result.frames.column[n]
            subviews[i].place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: r.width, height: r.height))
        }
        if let padIndex = result.padIndex, let r = result.frames.pad {
            subviews[padIndex].place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), anchor: .topLeading,
                                     proposal: ProposedViewSize(width: r.width, height: r.height))
        }
    }

    private func compute(width: CGFloat, height: CGFloat?, subviews: Subviews)
        -> (frames: Frames, padIndex: Int?, columnIndices: [Int]) {
        let padIndex = subviews.firstIndex { $0[RemotePadSlot.self] }
        let columnIndices = subviews.indices.filter { $0 != padIndex }
        let colWidth = padIndex == nil ? width : Self.columnWidth(for: width, maxColumnWidth: maxColumnWidth)
        let heights = columnIndices.map { subviews[$0].sizeThatFits(ProposedViewSize(width: colWidth, height: nil)).height }
        let bottom = columnIndices.map { subviews[$0][RemoteBottomSlot.self] }
        let frames = Self.frames(width: width, height: height, heights: heights, bottom: bottom, hasPad: padIndex != nil,
                                 spacing: spacing, columnSpacing: columnSpacing, maxColumnWidth: maxColumnWidth,
                                 padMinHeight: padMinHeight, padMaxHeight: padMaxHeight)
        return (frames, padIndex, columnIndices)
    }
}
