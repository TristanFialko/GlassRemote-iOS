import SwiftUI

/// The four primary pages. Order here is the swipe order. Remote is the default landing page.
enum AppPage: Int, CaseIterable, Identifiable {
    case remote, player, discover, apps

    var id: Int { rawValue }
    static let landing: AppPage = .remote

    var title: String {
        switch self {
        case .remote: return "Remote"
        case .player: return "Player"
        case .discover: return "Discover"
        case .apps: return "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .remote: return "dot.radiowaves.left.and.right"
        case .player: return "play.rectangle.fill"
        case .discover: return "magnifyingglass"
        case .apps: return "square.grid.2x2.fill"
        }
    }

    var accessibilityName: String { self == .apps ? "Apps and Controls" : title }

    /// Pure paging maths (unit tested). `translation` is the horizontal drag, `predicted` where it
    /// would coast to. A page changes on a deliberate drag past a third of the width or a flick.
    static func target(from page: AppPage, translation: CGFloat, predicted: CGFloat, width: CGFloat) -> AppPage {
        guard width > 0 else { return page }
        let threshold = width / 3
        var delta = 0
        if translation <= -threshold || predicted <= -width * 0.6 { delta = 1 }
        else if translation >= threshold || predicted >= width * 0.6 { delta = -1 }
        let index = min(max(page.rawValue + delta, 0), AppPage.allCases.count - 1)
        return AppPage(rawValue: index) ?? page
    }

    /// Dragging past the first or last page resists, like a native pager.
    static func resisted(_ translation: CGFloat, on page: AppPage) -> CGFloat {
        let pastStart = page == AppPage.allCases.first && translation > 0
        let pastEnd = page == AppPage.allCases.last && translation < 0
        return (pastStart || pastEnd) ? translation * 0.25 : translation
    }
}
