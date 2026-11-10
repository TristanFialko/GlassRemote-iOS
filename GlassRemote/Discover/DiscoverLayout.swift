import SwiftUI

/// Card sizes for Discover. Landscape uses its extra width for slightly larger cards (and more of them
/// on screen) instead of stretching the portrait layout.
struct DiscoverMetrics: Equatable {
    let poster: CGFloat
    let landscape: CGFloat
    let spacing: CGFloat

    init(isLandscape: Bool) {
        poster = isLandscape ? 124 : PosterCard.width
        landscape = isLandscape ? 256 : LandscapeCard.width
        spacing = isLandscape ? 14 : 12
    }
}

/// Which card shape a Discover surface uses for the profile's artwork preference (unit tested).
enum DiscoverCardShape: Equatable {
    case portrait, landscape
    enum Usage { case catalog, progress }

    /// Automatic: posters for catalogues, wide backdrops for in-progress titles (where the progress bar
    /// and episode caption need the width).
    static func resolve(_ preference: PosterOrientation, usage: Usage) -> DiscoverCardShape {
        switch preference {
        case .portrait: return .portrait
        case .landscape: return .landscape
        case .automatic: return usage == .progress ? .landscape : .portrait
        }
    }
}

/// Hero sizing and artwork choice (pure, unit tested).
enum DiscoverHeroLayout {
    static let maxTitles = 6

    /// Full-bleed height including the area under the status bar and search bar.
    /// Portrait: a tall band a little taller than the width, capped so the first row still peeks in.
    /// Landscape: most of the screen height, with the text column on the left.
    static func height(width: CGFloat, height: CGFloat, isLandscape: Bool) -> CGFloat {
        if isLandscape { return min(max(height * 0.86, 260), 560) }
        return min(max(width * 1.24, 420), max(height * 0.68, 420))
    }

    /// Backdrops first (wide key art crops well around its centre); the poster only when there is no backdrop.
    static func artwork(for title: MediaTitle) -> (primary: URL?, fallback: URL?) {
        if let background = title.backgroundURL { return (background, title.posterURL ?? title.fallbackPosterURL) }
        return (title.posterURL, title.fallbackPosterURL)
    }

    /// Alternates the given lists (movies, series) without duplicates, so the hero isn't six films in a row.
    static func interleave(_ lists: [[MediaTitle]], limit: Int = maxTitles) -> [MediaTitle] {
        var out: [MediaTitle] = []
        var seen = Set<String>()
        let longest = lists.map(\.count).max() ?? 0
        for i in 0..<longest {
            for list in lists where i < list.count {
                if seen.insert(list[i].id).inserted { out.append(list[i]) }
                if out.count == limit { return out }
            }
        }
        return out
    }
}

/// Native card-to-detail zoom (iOS 18 matchedTransitionSource / navigationTransition). The card the user
/// tapped expands into the detail page and collapses back into it. Earlier systems keep the standard sheet.
struct DetailZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct DetailZoomDestination: ViewModifier {
    let id: String?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let id {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
