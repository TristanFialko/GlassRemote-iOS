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
struct RootPagerView: View {
    @StateObject private var navigator = PageNavigator()
    /// Live horizontal finger travel while a page swipe is in progress (0 otherwise).
    @State private var dragX: CGFloat = 0
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
            let landscape = LayoutContext.resolve(verticalSizeClass: verticalSizeClass, size: geo.size).isLandscape
            let clearance = landscape ? DockMetrics.landscapeBottomClearance : DockMetrics.clearance(safeBottom: safeBottom)
            let leading: CGFloat = landscape ? DockMetrics.railClearance(safeLeading: safeLeading) : 0
            let context = LayoutContext(isLandscape: landscape,
                                        size: CGSize(width: max(width - leading, 0), height: geo.size.height))
            let travel = AppPage.resisted(dragX, on: page)
            // The rail never grows past the visible height (the keyboard can shrink it in landscape).
            let railLength = min(DockMetrics.railLength(count: AppPage.allCases.count), max(geo.size.height - 8, 120))

            ZStack(alignment: landscape ? .leading : .bottom) {
                HStack(spacing: 0) {
                    ForEach(AppPage.allCases) { item in
                        let depth = PageDepth.distance(of: item, current: page, travel: travel, width: width)
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
                .frame(width: width * CGFloat(AppPage.allCases.count), alignment: .leading)
                .offset(x: -CGFloat(page.rawValue) * width + travel)
                .frame(width: width, alignment: .leading)
                .animation(spring, value: page)
                .clipShape(HorizontalClip())

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
            .environment(\.layoutContext, context)
            .background {
                PagerPan(
                    page: page,
                    edgeWidth: edgeWidth,
                    dockZone: landscape ? 0 : DockMetrics.topFromScreenBottom(safeBottom: safeBottom) + 8,
                    railZone: landscape ? DockMetrics.railZone(safeLeading: safeLeading) : 0,
                    rightToLeft: layoutDirection == .rightToLeft,
                    onChanged: { dragX = $0 },
                    onEnded: { translation, predicted in
                        let target = AppPage.target(from: page, translation: translation, predicted: predicted, width: width)
                        if target != page { Haptics.soft() }
                        withAnimation(spring) { navigator.page = target; dragX = 0 }
                    },
                    onCancelled: { withAnimation(spring) { dragX = 0 } }
                )
            }
        }
        .background { AmbientBackdrop() }
        .environmentObject(navigator)
        .onChange(of: navigator.page) { ThemeStore.shared.pageChanged($0) }
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
        private var startedInHorizontalScroller = false

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let translation = pan.translation(in: view).x
            switch pan.state {
            case .began, .changed:
                onChanged(translation)
            case .ended:
                // Where a flick would carry the page (the same idea as SwiftUI's predictedEndTranslation).
                onEnded(translation, translation + pan.velocity(in: view).x * 0.25)
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
            guard PagerGesturePolicy.acceptsTouch(on: page, x: point.x, width: host.bounds.width, edgeWidth: edgeWidth) else { return false }
            startedInHorizontalScroller = Self.enclosingHorizontalScroller(of: touch.view) != nil
            return true
        }

        // Decided when the drag would begin: only a clearly horizontal drag, never from a carousel.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let t = pan.translation(in: view)
            guard PagerGesturePolicy.isHorizontalDominant(dx: t.x, dy: t.y) else { return false }   // vertical: never a page swipe
            if startedInHorizontalScroller { return false }                                         // the carousel owns it
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
                Image(systemName: item.symbol(selected: selected)).scaledFont(vertical ? 20 : 22, .semibold)
                Text(item.title).scaledFont(vertical ? 9.5 : 10.5, .semibold).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? theme.dockInk : theme.dockInkInactive)
            .accessibilityLabel(item.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}

/// Clips the page strip horizontally only (neighbouring pages stay hidden) and lets content extend
/// vertically, so Discover's hero can run under the status bar.
struct HorizontalClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - 2000, width: rect.width, height: rect.height + 4000))
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
