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

enum DockMetrics {
    static let height: CGFloat = 64
    /// Space pages keep clear at the bottom so controls are never hidden behind the floating dock.
    static let clearance: CGFloat = 84
}
