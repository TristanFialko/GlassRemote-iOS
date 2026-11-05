import SwiftUI
import UIKit

/// In-memory + URLCache-backed image loader for remote artwork (posters, backdrops).
/// Used by Discover and Player. Nothing is written to disk by this type itself; `URLCache`
/// handles HTTP caching. Requests are https-only and de-duplicated per URL.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        memory.countLimit = 120
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        guard url.scheme == "https" else { return nil }
        if let hit = cached(url) { return hit }
        if let task = inFlight[url] { return await task.value }
        let session = self.session
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// AsyncImage-like view backed by `ArtworkCache`. Shows `placeholder` until (or unless) it loads.
struct CachedArtwork<Placeholder: View>: View {
    let url: URL?
    /// Tried only when `url` is missing or fails to load.
    var fallbackURL: URL? = nil
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: [url, fallbackURL]) {
            image = nil
            for candidate in [url, fallbackURL].compactMap({ $0 }) {
                if let hit = ArtworkCache.shared.cached(candidate) { image = hit; return }
                if let loaded = await ArtworkCache.shared.image(for: candidate) {
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.25)) { image = loaded }
                    return
                }
            }
        }
    }
}

/// Pure title matching for Player artwork (unit tested).
enum PlayerArtworkMatcher {
    struct Query: Equatable {
        var names: [String]          // search candidates, best first
        // A release year is split off only when it is clearly one: bracketed, or the last of two
        // year-like numbers ("Blade Runner 2049 2017"). A lone "2012" or "Blade Runner 2049" stays in the name.
        var year: String?
        if let regex = try? NSRegularExpression(pattern: #"[\(\[]?\b(19|20)\d{2}\b[\)\]]?"#) {
            let ns = title as NSString
            let found = regex.matches(in: title, range: NSRange(location: 0, length: ns.length))
            if let last = found.last, last.range.location > 1 {
                let text = ns.substring(with: last.range)
                let bracketed = text.hasPrefix("(") || text.hasPrefix("[")
                if bracketed || found.count >= 2 {
                    year = text.trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
                    title = ns.substring(to: last.range.location)
                }
            }
        }
        var names: [String] = []
        func add(_ value: String) {
            let v = value.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·|,.")).trimmingCharacters(in: .whitespaces)
            if v.count >= 2, !names.contains(where: { normalise($0) == normalise(v) }) { names.append(v) }
        }
        if let r = title.range(of: episodeMarker, options: .regularExpression) {
            episodic = true
            add(String(title[..<r.lowerBound]))           // "Show Name S01E05 Episode" -> "Show Name"
        }
        add(title)
        for separator in [" - ", " – ", " — ", " | "] {
            if let r = title.range(of: separator) { add(String(title[..<r.lowerBound])) }   // "Show - Episode title"
        }
        return Query(names: names, year: year, looksEpisodic: episodic)
    }

    /// Picks a catalogue title whose name equals one of the candidate names. Never a fuzzy guess: no
    /// exact match means no poster (the Player then shows the app icon).
    static func best(from titles: [StremioTitle], for query: Query) -> StremioTitle? {
        for name in query.names {
            let wanted = normalise(name)
            let matches = titles.filter { normalise($0.name) == wanted && $0.posterURL != nil }
            guard !matches.isEmpty else { continue }
            if let year = query.year, let exact = matches.first(where: { $0.year.hasPrefix(year) }) { return exact }
            // Episodic playback -> the series poster; otherwise a movie wins ties. Catalogue order
            // (popularity) breaks the rest.
            let preferred: StremioTitle.Kind = query.looksEpisodic ? .series : .movie
            return matches.first(where: { $0.kind == preferred }) ?? matches.first
        }
        return nil
    }
}

/// Poster for what the TV box is playing. Previously this only worked when playback had been
/// started from Discover (a remembered hint); Stremio's media session carries no artwork, so for
/// anything started in Stremio itself the poster is now looked up by the session's title in
/// Cinemeta, matched by exact normalised name, and cached.
@MainActor
final class PlayerArtworkStore: ObservableObject {
    static let shared = PlayerArtworkStore()

    struct Hint: Equatable { var title: String; var posterURL: URL? }
    @Published private(set) var hint: Hint?
    @Published private(set) var resolved: [String: URL] = [:]
    private var misses: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private static let cacheKey = "glassRemote.playerPosterCache.v1"
    private static let cacheLimit = 120

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] ?? [:]
        resolved = stored.compactMapValues { URL(string: $0) }.filter { $0.value.scheme == "https" }
    }

    func remember(title: String, posterURL: URL?) { hint = Hint(title: title, posterURL: posterURL) }

    /// Poster for the current session: the Discover hint when it matches, else a resolved/cached one.
    func posterURL(forSessionTitle title: String) -> URL? {
        if let hint, let url = hint.posterURL, Self.matches(session: title, hint: hint.title) { return url }
        return resolved[PlayerArtworkMatcher.normalise(title)]
    }

    /// Looks the title up (once; failures retry after five minutes). Safe to call on every change.
    func resolve(sessionTitle: String, subtitle: String) async {
        let key = PlayerArtworkMatcher.normalise(sessionTitle)
        guard key.count >= 2, resolved[key] == nil else { return }
        if let hint, let url = hint.posterURL, Self.matches(session: sessionTitle, hint: hint.title) { _ = url; return }
        if let failed = misses[key], Date().timeIntervalSince(failed) < 300 { return }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key); defer { inFlight.remove(key) }

        let query = PlayerArtworkMatcher.query(title: sessionTitle, subtitle: subtitle)
        for name in query.names.prefix(3) {
            guard let found = try? await StremioCatalog.search(name), !Task.isCancelled else { continue }
            if let match = PlayerArtworkMatcher.best(from: found, for: query), let url = match.posterURL {
                resolved[key] = url
                persist()
                return
            }
        }
        misses[key] = Date()
    }

    private func persist() {
        let trimmed = resolved.count > Self.cacheLimit ? Dictionary(uniqueKeysWithValues: Array(resolved).suffix(Self.cacheLimit)) : resolved
        UserDefaults.standard.set(trimmed.mapValues(\.absoluteString), forKey: Self.cacheKey)
    }

    nonisolated static func matches(session: String, hint: String) -> Bool {
        let a = PlayerArtworkMatcher.normalise(session), b = PlayerArtworkMatcher.normalise(hint)
        guard a.count >= 3, b.count >= 3 else { return false }
        return a == b || a.hasPrefix(b + " ") || b.hasPrefix(a + " ")
    }
}


extension ArtworkCache {
    /// Average colour of an image (drawn into 1x1), for ambient lighting behind artwork.
    nonisolated static func averageColor(of image: UIImage) -> Color? {
        guard let cg = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
