import SwiftUI
import UIKit

/// v5 §2: the three dock pages, in dock order. Remote is the default landing page.
///
/// Now Playing is no longer a page or a dock tab. It opens from the mini-player that sits above the
/// dock while a session is genuinely active (`PageNavigator.playerPresented`, `MiniPlayerPolicy`).
/// There is no swipe paging between these pages any more: the dock (or the landscape rail) is the
/// only way to switch, and a switch is a short opacity fade (`TabSwitchPolicy`).
enum AppPage: Int, CaseIterable, Identifiable {
    case remote, discover, profile

    var id: Int { rawValue }
    static let landing: AppPage = .remote

    var title: String {
        switch self {
        case .remote: return "Remote"
        case .discover: return "Discover"
        case .profile: return "Profile"
        }
    }

    /// `appletvremote.gen4` ships with SF Symbols 4 (iOS 16). The runtime check keeps an unexpected OS
    /// from showing an empty icon: it falls back to gen2.
    static let remoteSymbols: (fill: String, outline: String) = {
        for pair in [("appletvremote.gen4.fill", "appletvremote.gen4"), ("appletvremote.gen2.fill", "appletvremote.gen2")]
        where UIImage(systemName: pair.0) != nil && UIImage(systemName: pair.1) != nil { return pair }
        return ("dot.radiowaves.left.and.right", "dot.radiowaves.left.and.right")
    }()
    static var remoteSymbol: String { remoteSymbols.fill }

    /// The media-player symbol, used where the app refers to Now Playing (the player's no-artwork
    /// fallback). It is no longer a dock item.
    static let playerSymbolFilled = "play.circle.fill"
    static let playerSymbolOutline = "play.circle"
    static var playerSymbol: String { playerSymbolFilled }

    /// Filled glyph for the selected dock item, outline for the others (Discover's magnifier has no
    /// filled form, so it keeps one symbol and the accent colour carries the state).
    func symbol(selected: Bool) -> String {
        switch self {
        case .remote: return selected ? AppPage.remoteSymbols.fill : AppPage.remoteSymbols.outline
        case .discover: return "magnifyingglass"
        case .profile: return selected ? "person.crop.circle.fill" : "person.crop.circle"
        }
    }

    var symbol: String { symbol(selected: true) }
}
