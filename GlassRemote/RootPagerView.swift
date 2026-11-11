import SwiftUI
import UIKit

/// Hosts the three pages side by side and keeps ALL of them alive. Switching pages only moves an
/// offset: nothing is torn down or recreated, so ADB, the HID helpers, media polling and the
/// Remote page's touch state are never affected by navigation. Navigation sends no TV input.
///
/// Gesture policy (one UIKit pan recogniser, `PagerPan`, replaces the old SwiftUI drag):
/// - It FAILS at the start of any drag that is not horizontal-dominant, so a vertical swipe can never
///   page and never competes with the Discover scroll view (previously a SwiftUI DragGesture ran
///   alongside every scroll and re-evaluated this view on every frame).
/// - It ignores touches that begin on the dock (the dock scrubs by itself).
/// - Remote: the page itself never pages (the trackpad / D-pad own the touch). Only the two thin
///   edge strips in the page's side padding start a page swipe.
/// - Discover / Player: a horizontal-dominant swipe anywhere changes page, EXCEPT one that begins
///   inside a horizontal scroll view (a carousel), which scrolls the carousel instead.
///
/// Landscape (Phase 6): the dock becomes a vertical glass rail on the leading edge and pages sit
/// beside it. Rotation only changes values (padding, alignment, the dock's axis); the pages are the
/// same views, so rotating never rebuilds a page or touches the connection. Touches that land on
/// the rail never start a page swipe.
///
/// Continuation §D: landscape pages run vertically, matching the rail: Remote at the top, Player,
/// Discover, Profile at the bottom. A clearly vertical swipe moves to the adjacent page; rail taps stay
/// the rail's. The strip switches between an HStack and a VStack layout with `AnyLayout`, which keeps
/// every page's identity, so rotating never recreates a page. Portrait (and RTL portrait) is unchanged.
struct RootPagerView: View {
    @StateObject private var navigator = PageNavigator()
    /// Live finger travel along the pager's axis while a page swipe is in progress (0 otherwise).
    @State private var dragTravel: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection

    private let edgeWidth: CGFloat = 16
    private var page: AppPage { navigator.page }
    private var spring: Animation { Motion.resolve(Motion.page, reduceMotion: reduceMotion) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let safeBottom = geo.safeAreaInsets.bottom
            let safeLeading = geo.safeAreaInsets.leading
            let safeTrailing = geo.safeAreaInsets.trailing
            let landscape = LayoutContext.resolve(verticalSizeClass: verticalSizeClass, size: geo.size).isLandscape
            let safeTop = geo.safeAreaInsets.top
            // Continuation §D: side by side in portrait, top to bottom in landscape.
            let axis = PagerAxis.resolve(isLandscape: landscape)
            let pageGap = PagerAxis.pageGap(axis, safeTop: safeTop, safeBottom: safeBottom)
            let pageStride = PagerAxis.pageStride(axis, size: geo.size, safeTop: safeTop, safeBottom: safeBottom)
            let pageCount = CGFloat(AppPage.allCases.count)
            let strip = axis == .vertical ? AnyLayout(VStackLayout(spacing: pageGap)) : AnyLayout(HStackLayout(spacing: 0))
            let stripAlignment: Alignment = axis == .vertical ? .top : .leading
            let clearance = landscape ? DockMetrics.landscapeBottomClearance : DockMetrics.clearance(safeBottom: safeBottom)
            let leading: CGFloat = landscape ? DockMetrics.railClearance(safeLeading: safeLeading) : 0
            let context = LayoutContext(isLandscape: landscape,
                                        size: CGSize(width: max(width - leading, 0), height: geo.size.height))
            let travel = AppPage.resisted(dragTravel, on: page)
            // The rail never grows past the visible height (the keyboard can shrink it in landscape).
            let railLength = min(DockMetrics.railLength(count: AppPage.allCases.count), max(geo.size.height - 8, 120))

            ZStack(alignment: landscape ? .leading : .bottom) {
                strip {
                    ForEach(AppPage.allCases) { item in
                        let depth = PageDepth.distance(of: item, current: page, travel: travel, width: pageStride)
                        content(for: item, clearance: clearance)
                            // Landscape: pages sit beside the rail. Only a value changes on rotation, never
                            // the view, so every page (and the Remote's touch state) stays alive.
                            .padding(.leading, leading)
                            .frame(width: width, height: geo.size.height)
                            .scaleEffect(PageDepth.scale(depth, reduceMotion: reduceMotion))
                            .opacity(PageDepth.opacity(depth, reduceMotion: reduceMotion))
                            .allowsHitTesting(item == page)
                            .accessibilityHidden(item != page)
                    }
                }
                .frame(width: axis == .vertical ? width : width * pageCount,
                       height: axis == .vertical ? pageStride * pageCount - pageGap : geo.size.height,
                       alignment: stripAlignment)
                .offset(axis.stripOffset(page: page, travel: travel, stride: pageStride))
                // Phase 7.4: reports when the slide has actually finished (Discover's search focus waits for it).
                .modifier(PageSettleObserver(page: page) { navigator.pageSettled($0) })
                .frame(width: width, height: geo.size.height, alignment: stripAlignment)
                .animation(spring, value: page)
                .clipShape(PagerClip(axis: axis, safeTop: safeTop, safeBottom: safeBottom))

                if landscape {
                    // The dock stands on end as a glass rail on the leading edge, vertically centred.
                    PageDock(axis: .vertical)
                        .frame(height: railLength)
                        .padding(.leading, DockMetrics.railGap)
                        .offset(x: -DockMetrics.railDrop(safeLeading: safeLeading))
                        .transition(.opacity)
                } else {
                    PageDock()
                        .padding(.horizontal, DockMetrics.sideInset)
                        .padding(.bottom, DockMetrics.baseGap)
                        // Sinks into the bottom safe area by a measured amount (never into the indicator).
                        .offset(y: DockMetrics.drop(safeBottom: safeBottom))
                        .transition(.opacity)
                }
            }
            .environment(\.dockClearance, clearance)
            .environment(\.railClearance, leading)
            // Continuation §F2: the safe areas beside a landscape page, for full-bleed artwork.
            .environment(\.pageBleed, HorizontalBleed.resolve(isLandscape: landscape, safeLeading: safeLeading,
                                                               safeTrailing: safeTrailing))
            .environment(\.layoutContext, context)
            // §G2: pages with their own backdrop align it to this window canvas (no seams).
            .environment(\.windowCanvasSize, BackdropAlignment.canvasSize(size: geo.size, insets: geo.safeAreaInsets))
            .background {
                PagerPan(
                    page: page,
                    axis: axis,
                    edgeWidth: edgeWidth,
                    dockZone: landscape ? 0 : DockMetrics.topFromScreenBottom(safeBottom: safeBottom) + 8,
                    railZone: landscape ? DockMetrics.railZone(safeLeading: safeLeading) : 0,
                    rightToLeft: layoutDirection == .rightToLeft,
                    onChanged: { dragTravel = $0 },
                    onEnded: { translation, predicted in
                        let target = AppPage.target(from: page, translation: translation, predicted: predicted, width: pageStride)
                        if target != page { Haptics.soft() }
                        withAnimation(spring) { navigator.page = target; dragTravel = 0 }
                    },
                    onCancelled: { withAnimation(spring) { dragTravel = 0 } }
                )
            }
        }
        .background { AmbientBackdrop() }
        .environmentObject(navigator)
        .onChange(of: navigator.page) { _, page in ThemeStore.shared.pageChanged(page) }
        // Continuation §D: rotating mid-swipe drops the swipe; travel never carries across axes.
        .onChange(of: verticalSizeClass) { _, _ in dragTravel = 0 }
    }

    @ViewBuilder
    private func content(for item: AppPage, clearance: CGFloat) -> some View {
        switch item {
        case .remote: RemoteView().padding(.bottom, clearance)
        case .player: PlayerPage()
        case .discover: DiscoverPage()
        case .profile: ProfilePage()
        }
    }
}

// MARK: - Page-swipe recogniser

/// Pure decisions of the page-swipe recogniser (unit tested).
enum PagerGesturePolicy {
    /// A page swipe must be clearly horizontal at the moment it would begin.
    static let dominance: CGFloat = 1.4

    static func isHorizontalDominant(dx: CGFloat, dy: CGFloat) -> Bool { abs(dx) > abs(dy) * dominance }

    /// Continuation §D: the landscape (vertical) counterpart, with the same dominance.
    static func isVerticalDominant(dx: CGFloat, dy: CGFloat) -> Bool { abs(dy) > abs(dx) * dominance }

    /// Continuation §D: whether a touch at `point` may start a page swipe on `page` along `axis`.
    /// Portrait is unchanged (the Remote pages only from its edge strips). In landscape the Remote pages
    /// only from `swipeAreas`, the free space in its side columns; every other page from anywhere.
    static func acceptsTouch(on page: AppPage, at point: CGPoint, in size: CGSize, edgeWidth: CGFloat,
                             axis: PagerAxis, swipeAreas: [CGRect]) -> Bool {
        guard page == .remote else { return true }
        switch axis {
        case .horizontal: return acceptsTouch(on: page, x: point.x, width: size.width, edgeWidth: edgeWidth)
        case .vertical: return swipeAreas.contains { $0.contains(point) }
        }
    }

    /// Continuation §D: a page's own vertical scroll view that can actually scroll.
    static func isVerticalScroller(contentHeight: CGFloat, boundsHeight: CGFloat, insetTop: CGFloat,
                                   insetBottom: CGFloat, scrollEnabled: Bool) -> Bool {
        scrollEnabled && contentHeight + insetTop + insetBottom > boundsHeight + 1
    }

    /// Continuation §D: a vertical swipe that begins inside a scrolling page pages only when that
    /// scroll view is already at its end in the swipe's direction (pull down at the top for the page
    /// above, push up at the bottom for the page below). Anywhere else the scroll view keeps the drag.
    static func scrollerYieldsVerticalPage(dy: CGFloat, offsetY: CGFloat, contentHeight: CGFloat,
                                           boundsHeight: CGFloat, insetTop: CGFloat, insetBottom: CGFloat) -> Bool {
        let tolerance: CGFloat = 1
        if dy > 0 { return offsetY <= -insetTop + tolerance }
        if dy < 0 { return offsetY >= contentHeight + insetBottom - boundsHeight - tolerance }
        return false
    }

    /// Continuation §D: a swipe in progress when the axis flips (rotation) is cancelled, never carried over.
    static func cancelsOnAxisChange(active: Bool, from old: PagerAxis, to new: PagerAxis) -> Bool {
        active && old != new
    }

    /// Landscape: a touch that lands on the leading rail belongs to the rail (it scrubs by itself).
    /// `x` is measured from the left of the screen; in right-to-left layouts the rail is on the right.
    static func inRail(x: CGFloat, width: CGFloat, railZone: CGFloat, rightToLeft: Bool) -> Bool {
        guard railZone > 0 else { return false }
        return (rightToLeft ? width - x : x) < railZone
    }

    /// Extra room around a selector that still counts as the selector (fingers are wider than its edge).
    static let exclusionSlop: CGFloat = 6

    /// Phase 7.1: a touch inside (or just outside) any selector's frame never starts a page swipe.
    static func inExcludedZone(_ point: CGPoint, zones: [CGRect], slop: CGFloat = exclusionSlop) -> Bool {
        zones.contains { $0.insetBy(dx: -slop, dy: -slop).contains(point) }
    }

    /// Phase 7.3: only zones with a real size that are at least partly on screen count.
    static func visibleZones(_ zones: [CGRect], in bounds: CGRect) -> [CGRect] {
        zones.filter { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 && $0.intersects(bounds) }
    }

    /// Whether a touch that lands at `x` (of `width`) may start a page swipe on `page`.
    /// Remote pages only from its edge strips; the others anywhere.
    static func acceptsTouch(on page: AppPage, x: CGFloat, width: CGFloat, edgeWidth: CGFloat) -> Bool {
        page != .remote || x < edgeWidth || x > width - edgeWidth
    }

    /// Is this scroll view a carousel? It must be able to scroll sideways (content wider than itself)
    /// and have no vertical range. A page's own vertical scroll view is never a carousel: its content
    /// is not wider than it is, and it is taller than its frame.
    static func isHorizontalScroller(contentSize: CGSize, bounds: CGSize, scrollEnabled: Bool) -> Bool {
        scrollEnabled && contentSize.width > bounds.width + 1 && contentSize.height <= bounds.height + 1
    }
}

/// Attaches one `UIPanGestureRecognizer` to the hosting view (the same technique `TwoFingerScroll`
/// uses), so one-finger touches keep reaching SwiftUI untouched. It never cancels or delays touches
/// and runs alongside every other recogniser.
private struct PagerPan: UIViewRepresentable {
    let page: AppPage
    /// Continuation §D: horizontal in portrait, vertical in landscape.
    let axis: PagerAxis
    let edgeWidth: CGFloat
    /// Height from the bottom edge of the screen that belongs to the dock.
    let dockZone: CGFloat
    /// Landscape: width from the leading edge of the screen that belongs to the rail (0 in portrait).
    let railZone: CGFloat
    let rightToLeft: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PagerAnchorView {
        let view = PagerAnchorView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handle(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = coordinator
        view.recognizer = pan
        return view
    }

    func updateUIView(_ uiView: PagerAnchorView, context: Context) {
        if context.coordinator.axis != axis {
            // Rotation mid-swipe: the old swipe is cancelled (out of this view update), never re-aimed.
            if let pan = uiView.recognizer,
               PagerGesturePolicy.cancelsOnAxisChange(active: pan.state == .began || pan.state == .changed,
                                                      from: context.coordinator.axis, to: axis) {
                Task { @MainActor in Coordinator.cancel(pan) }
            }
            context.coordinator.axis = axis
        }
        context.coordinator.page = page
        context.coordinator.edgeWidth = edgeWidth
        context.coordinator.dockZone = dockZone
        context.coordinator.railZone = railZone
        context.coordinator.rightToLeft = rightToLeft
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled
    }

    static func dismantleUIView(_ uiView: PagerAnchorView, coordinator: Coordinator) { uiView.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var page: AppPage = .remote
        var edgeWidth: CGFloat = 16
        var dockZone: CGFloat = 90
        var railZone: CGFloat = 0
        var rightToLeft = false
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        var onCancelled: () -> Void = {}
        var axis: PagerAxis = .horizontal
        private var startedInHorizontalScroller = false
        /// Continuation §D: the vertical scroll view (if any) the current touch landed in.
        private weak var startScroller: UIScrollView?

        /// Ends a recogniser's current gesture (it reports `.cancelled`) without disabling it.
        static func cancel(_ recognizer: UIGestureRecognizer) {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let translation = axis.component(pan.translation(in: view))
            switch pan.state {
            case .began:
                // §D: at a scroll view's end the page takes the swipe; the scroll view does not also bounce.
                if axis == .vertical, let scroll = startScroller { Self.cancel(scroll.panGestureRecognizer) }
                onChanged(translation)
            case .changed:
                onChanged(translation)
            case .ended:
                // Where a flick would carry the page (the same idea as SwiftUI's predictedEndTranslation).
                onEnded(translation, translation + axis.component(pan.velocity(in: view)) * 0.25)
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }

        // Decided per touch, before any movement: dock touches and Remote's centre never reach the pager.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let host = gestureRecognizer.view else { return false }
            let point = touch.location(in: host)
            if point.y > host.bounds.height - dockZone { return false }
            if PagerGesturePolicy.inRail(x: point.x, width: host.bounds.width, railZone: railZone,
                                         rightToLeft: rightToLeft) { return false }
            // Phase 7.1: a touch that lands on a selector belongs to it, decided before any movement.
            if PagerGesturePolicy.inExcludedZone(point, zones: PagerExclusionRegistry.shared.frames(in: host)) { return false }
            // §D: the landscape Remote pages only from the free space in its side columns.
            let swipeAreas = (axis == .vertical && page == .remote) ? PagerSwipeAreaRegistry.shared.frames(in: host) : []
            guard PagerGesturePolicy.acceptsTouch(on: page, at: point, in: host.bounds.size, edgeWidth: edgeWidth,
                                                  axis: axis, swipeAreas: swipeAreas) else { return false }
            startedInHorizontalScroller = Self.enclosingHorizontalScroller(of: touch.view) != nil
            startScroller = axis == .vertical ? Self.enclosingVerticalScroller(of: touch.view) : nil
            return true
        }

        // Decided when the drag would begin: only a clearly horizontal drag, never from a carousel.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let t = pan.translation(in: view)
            guard axis.isDominant(dx: t.x, dy: t.y) else { return false }   // across the axis: never a page swipe
            switch axis {
            case .horizontal:
                if startedInHorizontalScroller { return false }             // the carousel owns it
            case .vertical:
                // §D: a scrolling page keeps its drag unless it is already at its end that way.
                if let scroll = startScroller {
                    if scroll.isDecelerating { return false }
                    let inset = scroll.adjustedContentInset
                    guard PagerGesturePolicy.scrollerYieldsVerticalPage(dy: t.y, offsetY: scroll.contentOffset.y,
                                                                        contentHeight: scroll.contentSize.height,
                                                                        boundsHeight: scroll.bounds.height,
                                                                        insetTop: inset.top, insetBottom: inset.bottom)
                    else { return false }
                }
            }
            if ScrubTouch.shared.isActive { return false }                                          // a selector owns it
            return true
        }

        // Never block, wait for, or cancel any other recogniser (scroll views, buttons, the trackpad).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        private static func enclosingHorizontalScroller(of view: UIView?) -> UIScrollView? {
            var current = view
            while let candidate = current {
                if let scroll = candidate as? UIScrollView,
                   PagerGesturePolicy.isHorizontalScroller(contentSize: scroll.contentSize, bounds: scroll.bounds.size,
                                                           scrollEnabled: scroll.isScrollEnabled) {
                    return scroll
                }
                current = candidate.superview
            }
            return nil
        }

        /// Continuation §D: the nearest enclosing scroll view that really scrolls vertically (a page's
        /// own scroll view; carousels have no vertical range and are skipped).
        private static func enclosingVerticalScroller(of view: UIView?) -> UIScrollView? {
            var current = view
            while let candidate = current {
                if let scroll = candidate as? UIScrollView {
                    let inset = scroll.adjustedContentInset
                    if PagerGesturePolicy.isVerticalScroller(contentHeight: scroll.contentSize.height,
                                                             boundsHeight: scroll.bounds.height,
                                                             insetTop: inset.top, insetBottom: inset.bottom,
                                                             scrollEnabled: scroll.isScrollEnabled) {
                        return scroll
                    }
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

/// Zero-interaction view that only attaches the recogniser to the hosting view.
private final class PagerAnchorView: UIView {
    var recognizer: UIPanGestureRecognizer?
    private weak var attachedTo: UIView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard window != nil, let recognizer, let host = hostView() else { return }
        host.addGestureRecognizer(recognizer)
        attachedTo = host
    }

    func detach() {
        if let recognizer { attachedTo?.removeGestureRecognizer(recognizer) }
        attachedTo = nil
    }

    private func hostView() -> UIView? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller.view }
            responder = current.next
        }
        return nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

// MARK: - Dock

/// Floating Liquid Glass page bar. Slide a finger along it and the glass bubble follows, switching
/// pages as it crosses each icon (like the YouTube bar). Tapping works the same way.
/// The icon / caption labels are drawn above the glass (see `GlassScrubSelector`). The dock follows
/// the `.dock` contrast rules: its own scrim, ink and edge from the theme, never the accent, so it
/// stays legible in light themes and over bright artwork.
/// In landscape the same dock runs vertically as the page rail (`axis: .vertical`).
struct PageDock: View {
    var axis: Axis = .horizontal
    @EnvironmentObject private var navigator: PageNavigator
    @Environment(\.glassTheme) private var theme

    var body: some View {
        let vertical = axis == .vertical
        GlassScrubSelector(
            values: AppPage.allCases,
            selection: Binding(get: { navigator.page }, set: { navigator.go($0, haptic: false) }),
            height: vertical ? DockMetrics.railWidth : DockMetrics.height,
            inset: vertical ? DockMetrics.railInset : 6,
            role: .dock,
            axis: axis
        ) { item, selected in
            VStack(spacing: vertical ? 3 : 4) {
                if item == .profile {
                    // §G3: the active profile's photo or initials instead of a generic glyph.
                    DockProfileAvatar(size: vertical ? 24 : 26, selected: selected)
                } else {
                    Image(systemName: item.symbol(selected: selected)).scaledFont(vertical ? 20 : 22, .semibold)
                }
                Text(item.title).scaledFont(vertical ? 9.5 : 10.5, .semibold).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? theme.dockInk : theme.dockInkInactive)
            .accessibilityLabel(item.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}

/// Clips the page strip along its axis only (neighbouring pages stay hidden). Portrait lets content
/// extend vertically, so Discover's hero can run under the status bar; landscape (§D) cuts neighbours
/// at the safe-area edges above and below and lets content run sideways under the rail.
struct PagerClip: Shape {
    var axis: PagerAxis
    var safeTop: CGFloat = 0
    var safeBottom: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(PagerAxis.clipRect(axis, in: rect, safeTop: safeTop, safeBottom: safeBottom))
    }
}

private struct RailClearanceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// Width reserved for the landscape glass rail on the leading edge (0 in portrait). Pages inset their
    /// content by it; Discover's hero artwork runs underneath the rail.
    var railClearance: CGFloat {
        get { self[RailClearanceKey.self] }
        set { self[RailClearanceKey.self] = newValue }
    }
}
