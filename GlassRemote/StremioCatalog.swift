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
    var backgroundURL: URL? = nil

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
        let background: String?
        let releaseInfo: String?
        let imdbRating: String?
    }

    private static func https(_ text: String?) -> URL? {
        text.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    static func parse(_ data: Data, kind: StremioTitle.Kind) -> [StremioTitle] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.metas ?? []).compactMap { meta in
            guard let id = meta.id, let name = meta.name, !name.isEmpty else { return nil }
            return StremioTitle(id: id, kind: kind, name: name, year: meta.releaseInfo ?? "",
                                posterURL: https(meta.poster), rating: meta.imdbRating ?? "",
                                backgroundURL: https(meta.background))
        }
    }

    private static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    static func search(_ query: String, session: URLSession = .shared) async throws -> [StremioTitle] {
        var all: [StremioTitle] = []
        for kind in [StremioTitle.Kind.movie, .series] {
            guard let url = searchURL(kind: kind, query: query) else { return [] }
            all += parse(try await fetch(url, session: session), kind: kind)
        }
        return all
    }

    // MARK: Browse (Cinemeta catalogues: "top" = popular, "imdbRating" = top rated)

    static let genres = ["Action", "Comedy", "Drama", "Sci-Fi", "Thriller", "Horror", "Animation", "Documentary",
                         "Crime", "Romance", "Adventure", "Fantasy", "Mystery", "Family"]

    /// Cinemeta sort catalogues: "top" (popular), "imdbRating" (top rated), "year" (newest).
    static let sortCatalogs: [(id: String, title: String)] = [("top", "Popular"), ("imdbRating", "Top rated"), ("year", "Newest")]

    /// Addon-protocol extras go in the path: `/catalog/movie/top/genre=Action&skip=100.json`.
    static func browseURL(kind: StremioTitle.Kind, catalog: String, genre: String? = nil, skip: Int = 0) -> URL? {
        guard catalog.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil, skip >= 0 else { return nil }
        var extras: [String] = []
        if let genre {
            let g = encode(genre)
            guard !g.isEmpty else { return nil }
            extras.append("genre=\(g)")
        }
        if skip > 0 { extras.append("skip=\(skip)") }
        let tail = extras.isEmpty ? "" : "/" + extras.joined(separator: "&")
        return URL(string: "\(base)/catalog/\(kind.rawValue)/\(catalog)\(tail).json")
    }

    static func browse(kind: StremioTitle.Kind, catalog: String = "top", genre: String? = nil, skip: Int = 0, session: URLSession = .shared) async throws -> [StremioTitle] {
        guard let url = browseURL(kind: kind, catalog: catalog, genre: genre, skip: skip) else { return [] }
        return parse(try await fetch(url, session: session), kind: kind)
    }

    // MARK: Detail (Cinemeta /meta)

    struct Episode: Identifiable, Hashable {
        let id: String          // video id "tt…:season:episode"
        let season: Int
        let number: Int
        let title: String
        let released: Date?
    }

    struct Detail: Equatable {
        var overview = ""
        var runtime = ""
        var genres: [String] = []
        var cast: [String] = []
        var directors: [String] = []
        var background: URL?
        var episodes: [Episode] = []
        var seasons: [Int] { Array(Set(episodes.map(\.season))).filter { $0 > 0 }.sorted() }
    }

    private struct MetaResponse: Decodable { let meta: FullMeta? }
    private struct FullMeta: Decodable {
        let description: String?
        let runtime: String?
        let genres: [String]?
        let cast: [String]?
        let director: [String]?
        let background: String?
        let videos: [Video]?
    }
    private struct Video: Decodable {
        let id: String?
        let season: Int?
        let episode: Int?
        let number: Int?
        let title: String?
        let name: String?
        let released: String?
    }

    static func detailURL(kind: StremioTitle.Kind, id: String) -> URL? {
        guard id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "\(base)/meta/\(kind.rawValue)/\(id).json")
    }

    static func parseDetail(_ data: Data) -> Detail? {
        guard let meta = (try? JSONDecoder().decode(MetaResponse.self, from: data))?.meta else { return nil }
        var detail = Detail()
        detail.overview = meta.description ?? ""
        detail.runtime = meta.runtime ?? ""
        detail.genres = meta.genres ?? []
        detail.cast = meta.cast ?? []
        detail.directors = meta.director ?? []
        detail.background = https(meta.background)
        detail.episodes = (meta.videos ?? []).compactMap { v in
            guard let id = v.id, let season = v.season, let number = v.episode ?? v.number else { return nil }
            return Episode(id: id, season: season, number: number, title: v.title ?? v.name ?? "",
                           released: StremioAccountParser.iso(v.released))
        }.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        return detail
    }

    static func detail(kind: StremioTitle.Kind, id: String, session: URLSession = .shared) async throws -> Detail? {
        guard let url = detailURL(kind: kind, id: id) else { return nil }
        return parseDetail(try await fetch(url, session: session))
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

/// A catalogue slice: which Cinemeta catalogue, optionally one genre. Shared by the home carousels
/// and the See All collection page so neither needs its own implementation per category.
struct CatalogSource: Hashable, Identifiable {
    var kind: StremioTitle.Kind
    var catalog: String
    var genre: String?
    var id: String { "\(kind.rawValue)/\(catalog)/\(genre ?? "-")" }

    var title: String {
        let noun = kind == .movie ? "movies" : "series"
        if let genre { return catalog == "top" ? "\(genre) \(noun)" : "\(sortTitle) \(genre) \(noun)" }
        return "\(sortTitle) \(noun)"
    }
    var sortTitle: String { StremioCatalog.sortCatalogs.first { $0.id == catalog }?.title ?? "Popular" }
}

/// One horizontal carousel on the Discover home.
struct DiscoverRow: Identifiable, Equatable {
    enum Phase: Equatable { case idle, loading, loaded, failed }
    let source: CatalogSource
    var items: [StremioTitle] = []
    var phase: Phase = .idle
    var id: String { source.id }
    var title: String { source.title }
    var kind: StremioTitle.Kind { source.kind }
}

@MainActor
final class DiscoverModel: ObservableObject {
    enum Phase: Equatable { case idle, searching, results, empty, failed(String) }
    enum Filter: String, CaseIterable { case all, movies, series }

    /// Filtering is local: changing it never re-requests the catalogue.
    @Published var filter: Filter = .all
    @Published private(set) var recents: [String] = UserDefaults.standard.stringArray(forKey: RecentSearches.key) ?? []
    @Published var query = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var movies: [StremioTitle] = []
    @Published private(set) var series: [StremioTitle] = []
    @Published private(set) var rows: [DiscoverRow] = DiscoverModel.makeRows()
    private var task: Task<Void, Never>?

    /// Popular, top rated and newest first, then every genre. Genre rows are only requested when
    /// they scroll into view, so the page can be long without being expensive.
    static func makeRows() -> [DiscoverRow] {
        var list: [DiscoverRow] = []
        for catalog in ["top", "imdbRating", "year"] {
            for kind in [StremioTitle.Kind.movie, .series] { list.append(DiscoverRow(source: CatalogSource(kind: kind, catalog: catalog, genre: nil))) }
        }
        for genre in StremioCatalog.genres {
            for kind in [StremioTitle.Kind.movie, .series] { list.append(DiscoverRow(source: CatalogSource(kind: kind, catalog: "top", genre: genre))) }
        }
        return list
    }

    var visibleMovies: [StremioTitle] { filter == .series ? [] : movies }
    var visibleSeries: [StremioTitle] { filter == .movies ? [] : series }
    var visibleRows: [DiscoverRow] { rows.filter { filter == .all || ($0.kind == .movie) == (filter == .movies) } }
    /// Featured: the first popular title that has real backdrop artwork. Nothing is invented.
    var featured: StremioTitle? {
        let pool = rows.first { $0.source.catalog == "top" && $0.source.genre == nil && (filter == .all || ($0.kind == .movie) == (filter == .movies)) }
        return pool?.items.first { $0.backgroundURL != nil }
    }
    var isSearching: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }

    func useRecent(_ text: String) { query = text; queryChanged() }
    func clearRecents() { recents = []; UserDefaults.standard.removeObject(forKey: RecentSearches.key) }

    /// Search suggestions while typing: remembered searches that contain the text.
    var suggestions: [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return [] }
        return recents.filter { $0.lowercased().contains(text) && $0.lowercased() != text }
    }

    // MARK: Rows

    /// The two popular rows feed the Featured hero, so they load up front; the rest load on demand.
    func loadHomeIfNeeded() async {
        await withTaskGroup(of: Void.self) { group in
            for id in ["movie/top/-", "series/top/-"] { group.addTask { await self.loadRowIfNeeded(id) } }
        }
    }

    func loadRowIfNeeded(_ id: String) async {
        guard let i = rows.firstIndex(where: { $0.id == id }), rows[i].phase == .idle else { return }
        rows[i].phase = .loading
        let source = rows[i].source
        let items = try? await StremioCatalog.browse(kind: source.kind, catalog: source.catalog, genre: source.genre)
        guard let j = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[j].items = items ?? []
        rows[j].phase = (items?.isEmpty == false) ? .loaded : .failed
    }

    func retryRow(_ id: String) async {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].phase = .idle
        await loadRowIfNeeded(id)
    }

    // MARK: Search

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

    func retrySearch() { queryChanged() }

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
