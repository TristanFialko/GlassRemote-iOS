import SwiftUI

/// Shared page state. Anything (the Remote's search button, Apps, ...) can ask for a page here;
/// `RootPagerView` owns the animation. Changing pages only moves an offset: it never touches the
/// connection, helpers or polling, and never sends TV input.
@MainActor
final class PageNavigator: ObservableObject {
    @Published var page: AppPage = .landing
    /// Bumped to ask Discover to focus its search field (keyboard appears).
    @Published private(set) var searchFocusToken = 0

    func go(_ target: AppPage, haptic: Bool = true) {
        guard target != page else { return }
        if haptic { Haptics.soft() }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { page = target }
    }

    /// Remote page's Search shortcut: open Discover and focus its search field.
    func openSearch() {
        go(.discover)
        searchFocusToken += 1
    }
}

/// Geometry of the floating page dock. Everything is derived from the real bottom safe-area inset
/// (measured by `RootPagerView`), so the dock sits correctly on every iPhone, with or without a home
/// indicator, and pages keep exactly the clearance it needs.
enum DockMetrics {
    /// Dock height (was 64): a slightly more substantial bar with a larger lens.
    static let height: CGFloat = 70
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
