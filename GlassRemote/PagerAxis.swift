import CoreGraphics

/// Continuation §D: the direction the four pages run. Portrait keeps them side by side
/// (Remote → Player → Discover → Profile, mirrored in right-to-left layouts exactly as before);
/// landscape stacks them top to bottom in the same order, matching the vertical rail: Remote at the
/// top, Profile at the bottom. Only values change with the axis. The pager keeps the same page views,
/// so rotating never rebuilds a page and never touches the connection, the helpers or polling.
enum PagerAxis: Equatable {
    case horizontal, vertical

    static func resolve(isLandscape: Bool) -> PagerAxis { isLandscape ? .vertical : .horizontal }

    /// The part of a pan (translation or velocity) that moves pages along this axis.
    func component(_ point: CGPoint) -> CGFloat { self == .vertical ? point.y : point.x }

    /// A page swipe must be clearly along the axis at the moment it would begin.
    func isDominant(dx: CGFloat, dy: CGFloat) -> Bool {
        self == .vertical ? PagerGesturePolicy.isVerticalDominant(dx: dx, dy: dy)
                          : PagerGesturePolicy.isHorizontalDominant(dx: dx, dy: dy)
    }

    /// Space between neighbouring pages in the strip. Vertical pages keep the top and bottom safe
    /// areas between them, so a neighbour never shows in the status-bar or home-indicator zones.
    static func pageGap(_ axis: PagerAxis, safeTop: CGFloat, safeBottom: CGFloat) -> CGFloat {
        axis == .vertical ? max(safeTop, 0) + max(safeBottom, 0) : 0
    }

    /// Distance from one page to the next along the axis (also the paging threshold's reference).
    static func pageStride(_ axis: PagerAxis, size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> CGFloat {
        axis == .vertical ? size.height + pageGap(axis, safeTop: safeTop, safeBottom: safeBottom) : size.width
    }

    /// Offset of the page strip that shows `page`, plus the live finger travel. The horizontal case is
    /// the pre-§D formula unchanged, so portrait (and right-to-left portrait) behave exactly as before.
    func stripOffset(page: AppPage, travel: CGFloat, stride: CGFloat) -> CGSize {
        let main = -CGFloat(page.rawValue) * stride + travel
        return self == .vertical ? CGSize(width: 0, height: main) : CGSize(width: main, height: 0)
    }

    /// What of the strip stays visible, relative to the page frame `rect`. Horizontal: neighbours are
    /// cut at the sides, content may run under the status bar (Discover's hero). Vertical: neighbours are
    /// cut at the edges of the safe areas above and below, content may run sideways under the rail.
    static func clipRect(_ axis: PagerAxis, in rect: CGRect, safeTop: CGFloat, safeBottom: CGFloat) -> CGRect {
        switch axis {
        case .horizontal:
            return CGRect(x: rect.minX, y: rect.minY - 2000, width: rect.width, height: rect.height + 4000)
        case .vertical:
            let top = max(safeTop, 0), bottom = max(safeBottom, 0)
            return CGRect(x: rect.minX - 2000, y: rect.minY - top, width: rect.width + 4000,
                          height: rect.height + top + bottom)
        }
    }
}
