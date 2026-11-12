import SwiftUI

/// Continuation §F2: the horizontal safe areas beside a landscape page. Pages sit inside the safe
/// area; full-bleed artwork (Discover's hero, the detail backdrop) draws this far past the page's
/// edges so it reaches the physical edges of the screen instead of leaving background strips.
struct HorizontalBleed: Equatable {
    var leading: CGFloat
    var trailing: CGFloat

    static let zero = HorizontalBleed(leading: 0, trailing: 0)

    var total: CGFloat { leading + trailing }
    /// Symmetric amount for clip shapes, which do not mirror in right-to-left layouts.
    var symmetric: CGFloat { max(leading, trailing) }

    /// Portrait pages already span the full width.
    static func resolve(isLandscape: Bool, safeLeading: CGFloat, safeTrailing: CGFloat) -> HorizontalBleed {
        guard isLandscape else { return .zero }
        return HorizontalBleed(leading: max(safeLeading, 0), trailing: max(safeTrailing, 0))
    }

    /// A scroll view's clip, widened sideways by the bleed and exact at the top and bottom, so
    /// artwork reaches the screen edges while rows still stop at the page's own top and bottom.
    static func clipRect(_ rect: CGRect, bleed: CGFloat) -> CGRect {
        let b = max(bleed, 0)
        return CGRect(x: rect.minX - b, y: rect.minY, width: rect.width + b * 2, height: rect.height)
    }
}

struct HorizontalBleedClip: Shape {
    var bleed: CGFloat
    func path(in rect: CGRect) -> Path { Path(HorizontalBleed.clipRect(rect, bleed: bleed)) }
}

private struct PageBleedKey: EnvironmentKey { static let defaultValue = HorizontalBleed.zero }

extension EnvironmentValues {
    /// Horizontal safe areas beside the current page (zero in portrait). Set by the pager.
    var pageBleed: HorizontalBleed {
        get { self[PageBleedKey.self] }
        set { self[PageBleedKey.self] = newValue }
    }
}

/// Continuation §F3: how a title detail page is presented. Landscape uses a full-screen cover so the
/// page gets the whole width (a landscape sheet is a narrow portrait-sized card); portrait keeps the
/// sheet and its drag to dismiss. The style is chosen when nothing is presented and kept until the
/// page closes, so rotating with a detail open never dismisses or re-presents it.
enum DetailPresentation: Equatable {
    case sheet, fullScreen

    static func style(isLandscape: Bool) -> DetailPresentation { isLandscape ? .fullScreen : .sheet }

    /// The style to use after a change: only re-evaluated while nothing is on screen.
    static func next(current: DetailPresentation, isPresenting: Bool, isLandscape: Bool) -> DetailPresentation {
        isPresenting ? current : style(isLandscape: isLandscape)
    }
}

/// Continuation §F1: Discover's floating header. Portrait: search and the account button on one row,
/// the All/Movies/Series filter full width below. Landscape: one row with search leading (capped, so
/// it reads as a field rather than a banner), and the filter and account grouped at the trailing end.
/// The three views keep their identity in both arrangements, so search focus survives rotation.
struct DiscoverHeaderLayout: Layout {
    var isLandscape: Bool

    static let controlHeight: CGFloat = 48
    static let filterHeight: CGFloat = 36
    static let spacing: CGFloat = 10
    static let rowSpacing: CGFloat = 10
    static let groupSpacing: CGFloat = 12
    static let landscapeSearchMax: CGFloat = 440
    static let landscapeFilterMax: CGFloat = 276
    static let landscapeFilterMin: CGFloat = 200

    struct Frames: Equatable {
        var search: CGRect
        var account: CGRect
        var filter: CGRect
        var height: CGFloat
    }

    static func frames(width: CGFloat, isLandscape: Bool) -> Frames {
        let w = max(width, 0), h = controlHeight
        let account = CGRect(x: max(w - h, 0), y: 0, width: h, height: h)
        if isLandscape {
            let filterWidth = min(landscapeFilterMax, max(w * 0.34, landscapeFilterMin))
            let filter = CGRect(x: max(account.minX - groupSpacing - filterWidth, 0), y: (h - filterHeight) / 2,
                                width: filterWidth, height: filterHeight)
            let searchWidth = max(min(landscapeSearchMax, filter.minX - groupSpacing * 2), 0)
            return Frames(search: CGRect(x: 0, y: 0, width: searchWidth, height: h), account: account,
                          filter: filter, height: h)
        }
        let search = CGRect(x: 0, y: 0, width: max(account.minX - spacing, 0), height: h)
        let filter = CGRect(x: 0, y: h + rowSpacing, width: w, height: filterHeight)
        return Frames(search: search, account: account, filter: filter, height: filter.maxY)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 375, height: 0)).width
        return CGSize(width: width, height: Self.frames(width: width, isLandscape: isLandscape).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let f = Self.frames(width: bounds.width, isLandscape: isLandscape)
        let rects = [f.search, f.account, f.filter]
        for (index, subview) in subviews.enumerated() {
            let rect = index < rects.count ? rects[index] : .zero
            subview.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }
}
