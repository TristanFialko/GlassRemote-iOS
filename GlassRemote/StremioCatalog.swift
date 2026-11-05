import Foundation

/// One movie or series from a Stremio catalog.
struct StremioTitle: Identifiable, Hashable {
    enum Kind: String { case movie, series }
    let id: String           // IMDb id such as "tt0133093"
    let kind: Kind
    let name: String
    let year: String
    let posterURL: URL?
    let rating: String

    /// Used only when Cinemeta supplies no poster. Metahub is the image host Stremio's own
    /// catalogue uses for these ids. Not verified from this build environment (no network); if it
    /// has no image either, the placeholder is shown.
    var fallbackPosterURL: URL? {
        guard id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://images.metahub.space/poster/medium/\(id)/img")
    }
}

/// Search against Cinemeta, Stremio's public official metadata addon
/// (`https://v3-cinemeta.strem.io/catalog/<type>/top/search=<query>.json`, the standard
/// Stremio addon-catalog protocol). This runs on the iPhone over the internet and does not
/// touch the TV box. It has NOT been exercised from this build environment (no network):
/// verify on device. The decoder tolerates missing fields.
enum StremioCatalog {
    static let base = "https://v3-cinemeta.strem.io"

    /// Percent-encodes a query for use as a path segment ("search=<query>").
    static func encode(_ query: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func searchURL(kind: StremioTitle.Kind, query: String) -> URL? {
        let q = encode(query)
        guard !q.isEmpty else { return nil }
        return URL(string: "\(base)/catalog/\(kind.rawValue)/top/search=\(q).json")
    }

    private struct Response: Decodable { let metas: [Meta]? }
    private struct Meta: Decodable {
        let id: String?
        let name: String?
        let poster: String?
        let releaseInfo: String?
        let imdbRating: String?
    }

    static func parse(_ data: Data, kind: StremioTitle.Kind) -> [StremioTitle] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.metas ?? []).compactMap { meta in
            guard let id = meta.id, let name = meta.name, !name.isEmpty else { return nil }
            let poster = meta.poster.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return StremioTitle(id: id, kind: kind, name: name,
                                year: meta.releaseInfo ?? "", posterURL: poster, rating: meta.imdbRating ?? "")
        }
    }

    static func search(_ query: String, session: URLSession = .shared) async throws -> [StremioTitle] {
        var all: [StremioTitle] = []
        for kind in [StremioTitle.Kind.movie, .series] {
            guard let url = searchURL(kind: kind, query: query) else { return [] }
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            all += parse(data, kind: kind)
        }
        return all
    }
}

/// Last few searches (local only). Pure helper so ordering and limits are testable.
enum RecentSearches {
    static let key = "glassRemote.recentSearches.v1"
    static let limit = 8

    static func adding(_ list: [String], _ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return list }
        return Array(([q] + list.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(limit))
    }
}

@MainActor
final class DiscoverModel: ObservableObject {
    enum Phase: Equatable { case idle, searching, results, empty, failed(String) }
    enum Filter: String, CaseIterable { case all, movies, series }

    /// Filtering is local: changing it never re-requests the catalogue.
    @Published var filter: Filter = .all
    @Published private(set) var recents: [String] = UserDefaults.standard.stringArray(forKey: RecentSearches.key) ?? []
    var visibleMovies: [StremioTitle] { filter == .series ? [] : movies }
    var visibleSeries: [StremioTitle] { filter == .movies ? [] : series }

    func useRecent(_ text: String) { query = text; queryChanged() }
    func clearRecents() { recents = []; UserDefaults.standard.removeObject(forKey: RecentSearches.key) }

    @Published var query = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var movies: [StremioTitle] = []
    @Published private(set) var series: [StremioTitle] = []
    private var task: Task<Void, Never>?

    /// Debounced; a new keystroke cancels the previous request.
    func queryChanged() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { movies = []; series = []; phase = .idle; return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    private func run(_ text: String) async {
        phase = .searching
        do {
            let found = try await StremioCatalog.search(text)
            guard !Task.isCancelled else { return }
            movies = found.filter { $0.kind == .movie }
            series = found.filter { $0.kind == .series }
            phase = found.isEmpty ? .empty : .results
            if !found.isEmpty {
                recents = RecentSearches.adding(recents, text)
                UserDefaults.standard.set(recents, forKey: RecentSearches.key)
            }
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            phase = .failed("Couldn't reach the Stremio catalog. Check your internet connection.")
        }
    }
}
