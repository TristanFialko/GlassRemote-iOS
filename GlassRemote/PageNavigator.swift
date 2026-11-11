import SwiftUI

/// Shared page state. Anything (the Remote's search button, Apps, ...) can ask for a page here;
/// `RootPagerView` owns the presentation. Changing pages only changes which page is visible (a short
/// opacity fade, v5 §2): every page stays alive, so it never touches the connection, helpers or
/// polling, and never sends TV input.
@MainActor
final class PageNavigator: ObservableObject {
    @Published var page: AppPage = .landing {
        didSet { if page != oldValue { searchFocus.pageChanged(to: page) } }
    }
    /// v5 §2: Now Playing is presented over the current page (opened from the mini-player), not a
    /// dock page. The dock stays visible above it; choosing any dock item closes it.
    @Published private(set) var playerPresented = false
    /// Phase 7.4: the page the pager has finished sliding to (reported by RootPagerView's
    /// PageSettleObserver). Not published: nothing renders from it.
    private(set) var settledPage: AppPage?
    /// Bumped only when Discover should focus its search field now (see SearchFocusPolicy).
    @Published private(set) var searchFocusFire = 0
    private var searchFocus = SearchFocusPolicy(page: .landing)
    /// Phase 8: a Profile sub-page another page asked for (the Remote menu, Samsung set-up).
    /// ProfilePage opens it and clears it. Settings live only in Profile now.
    @Published var pendingProfileRoute: ProfileRoute?

    func openProfile(_ route: ProfileRoute? = nil) {
        pendingProfileRoute = route
        go(.profile)
    }

    /// Dock and rail selection. Closes Now Playing first; choosing the page that is already
    /// underneath the player simply closes the player.
    func go(_ target: AppPage, haptic: Bool = true) {
        let wasPresented = playerPresented
        if wasPresented { closePlayer(haptic: false) }
        guard target != page else {
            if wasPresented && haptic { Haptics.soft() }
            return
        }
        if haptic { Haptics.soft() }
        withAnimation(TabSwitchPolicy.adaptiveAnimation) { page = target }
    }

    /// The mini-player (or the Remote page's Now Playing card) opens the full player.
    func openPlayer(haptic: Bool = true) {
        guard !playerPresented else { return }
        if haptic { Haptics.soft() }
        withAnimation(NowPlayingPresentation.adaptiveAnimation) { playerPresented = true }
    }

    func closePlayer(haptic: Bool = true) {
        guard playerPresented else { return }
        if haptic { Haptics.soft() }
        withAnimation(NowPlayingPresentation.adaptiveAnimation) { playerPresented = false }
    }

    /// Remote page's Search shortcut: open Discover and focus its search field.
    /// The keyboard comes up only once Discover has finished sliding in and its field is mounted;
    /// no fixed delay. Repeated taps make one request; navigating away or backgrounding cancels it.
    func openSearch() {
        searchFocus.request()
        go(.discover)
        fireSearchFocusIfReady()
    }

    /// The pager's slide reached `settled`. A report for an earlier target is ignored.
    func pageSettled(_ settled: AppPage) {
        guard settled == page else { return }
        settledPage = settled
        searchFocus.pageSettled(settled)
        fireSearchFocusIfReady()
    }

    func searchFieldMounted(_ mounted: Bool) {
        searchFocus.setFieldMounted(mounted)
        fireSearchFocusIfReady()
    }

    func sceneActiveChanged(_ active: Bool) {
        searchFocus.setSceneActive(active)
    }

    private func fireSearchFocusIfReady() {
        if searchFocus.consumeIfReady() { searchFocusFire &+= 1 }
    }
}

/// Phase 7.4: pure state machine for the Remote's Search shortcut (unit tested). Focus fires once per
/// request, only when Discover is the target page, the slide has finished, the field is mounted and the
/// app is active. Leaving Discover or going to the background cancels a pending request, so a stale
/// request can never steal focus later.
struct SearchFocusPolicy: Equatable {
    private(set) var pending = false
    private(set) var page: AppPage
    private(set) var settled: AppPage?
    private(set) var fieldMounted = false
    private(set) var sceneActive = true

    init(page: AppPage) { self.page = page }

    mutating func request() { pending = true }

    mutating func pageChanged(to newPage: AppPage) {
        page = newPage
        settled = nil                         // moving: not settled until the pager says so
        if newPage != .discover { pending = false }
    }

    mutating func pageSettled(_ settledPage: AppPage) {
        if settledPage == page { settled = settledPage }
    }

    mutating func setFieldMounted(_ mounted: Bool) { fieldMounted = mounted }

    mutating func setSceneActive(_ active: Bool) {
        sceneActive = active
        if !active { pending = false }
    }

    /// True exactly once per request, when everything is ready.
    mutating func consumeIfReady() -> Bool {
        guard pending, page == .discover, settled == .discover, fieldMounted, sceneActive else { return false }
        pending = false
        return true
    }
}

/// Phase 7.4: iOS 16 has no animation completion, so the pager animates this modifier with the page
/// index and reports when the interpolated value reaches the target (the slide is visually finished).
/// With Reduce Motion (no animation) it reports on the same update.
struct PageSettleObserver: AnimatableModifier {
    var position: CGFloat
    let target: CGFloat
    let page: AppPage
    let onSettle: (AppPage) -> Void

    init(page: AppPage, onSettle: @escaping (AppPage) -> Void) {
        let index = CGFloat(page.rawValue)
        position = index
        target = index
        self.page = page
        self.onSettle = onSettle
    }

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        if PageSettlePolicy.isSettled(position: position, target: target) {
            let page = page, onSettle = onSettle
            DispatchQueue.main.async { onSettle(page) }   // out of the view update, not a delay
        }
        return content
    }
}

enum PageSettlePolicy {
    static let epsilon: CGFloat = 0.001
    static func isSettled(position: CGFloat, target: CGFloat) -> Bool { abs(position - target) < epsilon }
}

/// Geometry of the floating page dock. Everything is derived from the real bottom safe-area inset
/// (measured by `RootPagerView` with the keyboard ignored, so the dock never rides up with it), so the
/// dock sits correctly on every iPhone, with or without a home indicator, and pages keep exactly the
/// clearance it needs.
enum DockMetrics {
    /// v5 §2: a thinner, icon-only bar (was 70 with labels and a lens). Each item is a full-height,
    /// at least `minimumTouchTarget`-wide button, so the targets stay comfortable.
    static let height: CGFloat = 58
    /// Horizontal padding inside the dock capsule, before the first and after the last item.
    static let itemInset: CGFloat = 8
    /// Apple's minimum comfortable touch target.
    static let minimumTouchTarget: CGFloat = 44
    /// v5 §2: the compact Now Playing bar above the dock, and the gap between the two.
    static let miniPlayerHeight: CGFloat = 58
    static let miniPlayerGap: CGFloat = 8
    /// Gap between the dock's bottom edge and the bottom safe-area edge, before the drop below.
    static let baseGap: CGFloat = 4
    /// Space pages keep between their content and the dock's top edge.
    static let breathing: CGFloat = 14
    static let sideInset: CGFloat = 14

    /// How far the dock sinks into the bottom safe area (the home-indicator zone). 30 % of the inset,
    /// at most 10 pt: on a notched iPhone that is 10 pt, which still leaves the dock well clear of the
    /// indicator and within thumb reach; with no safe area (home-button iPhones) it is zero.
    static func drop(safeBottom: CGFloat) -> CGFloat { min(max(safeBottom * 0.30, 0), 10) }

    /// Space a page keeps clear at the bottom so no control is ever hidden behind the dock.
    static func clearance(safeBottom: CGFloat) -> CGFloat { height + baseGap - drop(safeBottom: safeBottom) + breathing }

    /// The same, plus the mini-player when it is showing above the dock.
    static func clearance(safeBottom: CGFloat, miniPlayer: Bool) -> CGFloat {
        clearance(safeBottom: safeBottom) + (miniPlayer ? miniPlayerHeight + miniPlayerGap : 0)
    }

    /// Width of one dock item for a dock `width` wide with `count` items.
    static func itemWidth(dockWidth width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(width - itemInset * 2, 0) / CGFloat(count)
    }

    /// Distance from the physical bottom edge of the screen up to the dock's top edge.
    static func topFromScreenBottom(safeBottom: CGFloat) -> CGFloat { safeBottom + baseGap - drop(safeBottom: safeBottom) + height }

    /// Value used until the pager has measured a real inset (previews, tests): a notched iPhone.
    static let defaultClearance: CGFloat = clearance(safeBottom: 34)
}

private struct DockClearanceKey: EnvironmentKey { static let defaultValue: CGFloat = DockMetrics.defaultClearance }
extension EnvironmentValues {
    /// Bottom space every page reserves for the dock. Set once by `RootPagerView`.
    var dockClearance: CGFloat {
        get { self[DockClearanceKey.self] }
        set { self[DockClearanceKey.self] = newValue }
    }
}
