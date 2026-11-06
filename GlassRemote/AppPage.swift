import SwiftUI
import UIKit

/// The three primary pages. Order here is the swipe order. Remote is the default landing page.
enum AppPage: Int, CaseIterable, Identifiable {
    case remote, player, discover

    var id: Int { rawValue }
    static let landing: AppPage = .remote

    var title: String {
        switch self {
        case .remote: return "Remote"
        case .player: return "Player"
        case .discover: return "Discover"
        }
    }

    /// `appletvremote.gen4` ships with SF Symbols 4 (iOS 16, this app's deployment target). The
    /// runtime check keeps an unexpected OS from showing an empty icon: it falls back to gen2.
    static let remoteSymbols: (fill: String, outline: String) = {
        for pair in [("appletvremote.gen4.fill", "appletvremote.gen4"), ("appletvremote.gen2.fill", "appletvremote.gen2")]
        where UIImage(systemName: pair.0) != nil && UIImage(systemName: pair.1) != nil { return pair }
        return ("dot.radiowaves.left.and.right", "dot.radiowaves.left.and.right")
    }()
    static var remoteSymbol: String { remoteSymbols.fill }

    /// The Player's media-player symbol. `play.circle` replaces the old `play.rectangle.fill`, which at
    /// dock size read as a wide thin slab with a tiny triangle. The circle has the same optical weight
    /// as the Remote glyph, stays recognisable at 22 pt, and its outline / filled pair makes the selected
    /// state obvious in every theme. Every other place that showed the old symbol uses `playerSymbol`.
    static let playerSymbolFilled = "play.circle.fill"
    static let playerSymbolOutline = "play.circle"
    static var playerSymbol: String { playerSymbolFilled }

    /// Filled glyph for the selected dock item, outline for the others (Discover's magnifier has no
    /// filled form, so it keeps one symbol and the lens carries the state).
    func symbol(selected: Bool) -> String {
        switch self {
        case .remote: return selected ? AppPage.remoteSymbols.fill : AppPage.remoteSymbols.outline
        case .player: return selected ? AppPage.playerSymbolFilled : AppPage.playerSymbolOutline
        case .discover: return "magnifyingglass"
        }
    }

    var symbol: String { symbol(selected: true) }

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
