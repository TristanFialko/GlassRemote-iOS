import Foundation

/// One movie or series from a catalogue.
struct MediaTitle: Identifiable, Hashable {
    enum Kind: String { case movie, series }
    let id: String           // IMDb id such as "tt0133093"
    let kind: Kind
    let name: String
    let year: String
    let posterURL: URL?
    let rating: String
    var backgroundURL: URL? = nil
    /// Catalogue extras used by the Discover hero (empty when a source omits them).
    var overview: String = ""
    var genres: [String] = []
    var logoURL: URL? = nil

    /// Used only when Cinemeta supplies no poster (Metahub image host). Not verified from this build environment (no network); if it
    /// has no image either, the placeholder is shown.
    var fallbackPosterURL: URL? {
        guard id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://images.metahub.space/poster/medium/\(id)/img")
    }
}

/// ISO-8601 helper shared by catalogue and account parsing.
enum DateParsing {
    static func iso(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Catalogue and metadata from Cinemeta, the metadata addon Nuvio installs by default (Nuvio is a
/// Stremio-addon-protocol client). NOT a Nuvio API: it is the public addon protocol. Search against Cinemeta
/// (`https://v3-cinemeta.strem.io/catalog/<type>/top/search=<query>.json`, the standard
/// Stremio addon-catalog protocol). This runs on the iPhone over the internet and does not
/// touch the TV box. It has NOT been exercised from this build environment (no network):
/// verify on device. The decoder tolerates missing fields.
enum CinemetaCatalog {
    static let base = "https://v3-cinemeta.strem.io"

    /// Percent-encodes a query for use as a path segment ("search=<query>").
    static func encode(_ query: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func searchURL(kind: MediaTitle.Kind, query: String) -> URL? {
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
        let description: LossyText?
        let genres: LossyStrings?
        let genre: LossyStrings?
        let logo: LossyText?
    }

    /// Optional extras are decoded leniently: one odd field must not drop the whole row.
    private struct LossyText: Decodable {
        let value: String?
        init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(String.self) }
    }
    private struct LossyStrings: Decodable {
        let values: [String]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            values = (try? c.decode([String].self)) ?? ((try? c.decode(String.self)).map { [$0] } ?? [])
        }
    }

    private static func https(_ text: String?) -> URL? {
        text.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    static func parse(_ data: Data, kind: MediaTitle.Kind) -> [MediaTitle] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.metas ?? []).compactMap { meta in
            guard let id = meta.id, let name = meta.name, !name.isEmpty else { return nil }
            return MediaTitle(id: id, kind: kind, name: name, year: meta.releaseInfo ?? "",
                                posterURL: https(meta.poster), rating: meta.imdbRating ?? "",
                                backgroundURL: https(meta.background),
                                overview: (meta.description?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                genres: meta.genres?.values ?? meta.genre?.values ?? [],
                                logoURL: https(meta.logo?.value))
        }
    }

    private static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Movies and series are requested in parallel; cancelling the calling task cancels both requests.
    static func search(_ query: String, session: URLSession = .shared) async throws -> [MediaTitle] {
        guard let movieURL = searchURL(kind: .movie, query: query),
              let seriesURL = searchURL(kind: .series, query: query) else { return [] }
        async let movies = fetch(movieURL, session: session)
        async let series = fetch(seriesURL, session: session)
        return parse(try await movies, kind: .movie) + parse(try await series, kind: .series)
    }

    // MARK: Browse (Cinemeta catalogues: "top" = popular, "imdbRating" = top rated)

    static let genres = ["Action", "Comedy", "Drama", "Sci-Fi", "Thriller", "Horror", "Animation", "Documentary",
                         "Crime", "Romance", "Adventure", "Fantasy", "Mystery", "Family"]

    /// Cinemeta sort catalogues: "top" (popular), "imdbRating" (top rated), "year" (newest).
    static let sortCatalogs: [(id: String, title: String)] = [("top", "Popular"), ("imdbRating", "Top rated"), ("year", "Newest")]

    /// Addon-protocol extras go in the path: `/catalog/movie/top/genre=Action&skip=100.json`.
    static func browseURL(kind: MediaTitle.Kind, catalog: String, genre: String? = nil, skip: Int = 0) -> URL? {
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

    static func browse(kind: MediaTitle.Kind, catalog: String = "top", genre: String? = nil, skip: Int = 0, session: URLSession = .shared) async throws -> [MediaTitle] {
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

    static func detailURL(kind: MediaTitle.Kind, id: String) -> URL? {
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
                           released: DateParsing.iso(v.released))
        }.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        return detail
    }

    static func detail(kind: MediaTitle.Kind, id: String, session: URLSession = .shared) async throws -> Detail? {
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
    var kind: MediaTitle.Kind
    var catalog: String
    var genre: String?
    var id: String { "\(kind.rawValue)/\(catalog)/\(genre ?? "-")" }

    var title: String {
        let noun = kind == .movie ? "movies" : "series"
        if let genre { return catalog == "top" ? "\(genre) \(noun)" : "\(sortTitle) \(genre) \(noun)" }
        return "\(sortTitle) \(noun)"
    }
    var sortTitle: String { CinemetaCatalog.sortCatalogs.first { $0.id == catalog }?.title ?? "Popular" }
}

/// One horizontal carousel on the Discover home.
struct DiscoverRow: Identifiable, Equatable {
    enum Phase: Equatable { case idle, loading, loaded, failed }
    let source: CatalogSource
    var items: [MediaTitle] = []
    var phase: Phase = .idle
    var id: String { source.id }
    var title: String { source.title }
    var kind: MediaTitle.Kind { source.kind }
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
    @Published private(set) var movies: [MediaTitle] = []
    @Published private(set) var series: [MediaTitle] = []
    @Published private(set) var rows: [DiscoverRow] = DiscoverModel.makeRows()
    private var task: Task<Void, Never>?
    private var cache = SearchCache()

    /// Popular, top rated and newest first, then every genre. Genre rows are only requested when
    /// they scroll into view, so the page can be long without being expensive.
    static func makeRows() -> [DiscoverRow] {
        var list: [DiscoverRow] = []
        for catalog in ["top", "imdbRating", "year"] {
            for kind in [MediaTitle.Kind.movie, .series] { list.append(DiscoverRow(source: CatalogSource(kind: kind, catalog: catalog, genre: nil))) }
        }
        for genre in CinemetaCatalog.genres {
            for kind in [MediaTitle.Kind.movie, .series] { list.append(DiscoverRow(source: CatalogSource(kind: kind, catalog: "top", genre: genre))) }
        }
        return list
    }

    var visibleMovies: [MediaTitle] { filter == .series ? [] : movies }
    var visibleSeries: [MediaTitle] { filter == .movies ? [] : series }
    var visibleRows: [DiscoverRow] { rows.filter { filter == .all || ($0.kind == .movie) == (filter == .movies) } }
    /// Hero titles: popular movies and series that have real backdrop artwork, alternated. Nothing is invented.
    var featuredPool: [MediaTitle] {
        let pools = rows.filter { $0.source.catalog == "top" && $0.source.genre == nil
            && (filter == .all || ($0.kind == .movie) == (filter == .movies)) }
            .map { row in row.items.filter { $0.backgroundURL != nil } }
        return DiscoverHeroLayout.interleave(pools)
    }
    var featured: MediaTitle? { featuredPool.first }
    /// One confident title match shown above the grids.
    var topResult: MediaTitle? { SearchRanking.topResult([visibleMovies, visibleSeries], query: query) }
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
        let items = try? await CinemetaCatalog.browse(kind: source.kind, catalog: source.catalog, genre: source.genre)
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

    /// Live search. A cached query shows at once; otherwise a short debounce, and each keystroke cancels
    /// the request in flight. The previous results stay on screen while the next ones load.
    func queryChanged() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { movies = []; series = []; phase = .idle; return }
        if let hit = cache.value(for: text) { apply(hit, for: text); return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    var hasResults: Bool { !movies.isEmpty || !series.isEmpty }

    private func apply(_ found: [MediaTitle], for text: String) {
        movies = SearchRanking.rank(found.filter { $0.kind == .movie }, query: text)
        series = SearchRanking.rank(found.filter { $0.kind == .series }, query: text)
        phase = found.isEmpty ? .empty : .results
    }

    func retrySearch() { queryChanged() }

    private func run(_ text: String) async {
        phase = .searching
        do {
            let found = try await CinemetaCatalog.search(text)
            // A stale response (the text changed meanwhile) is dropped even if it was not cancelled in time.
            guard !Task.isCancelled, text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            cache.store(found, for: text)
            apply(found, for: text)
            if !found.isEmpty {
                recents = RecentSearches.adding(recents, text)
                UserDefaults.standard.set(recents, forKey: RecentSearches.key)
            }
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            phase = .failed("Couldn't reach the catalogue. Check your internet connection.")
        }
    }
}


/// Resolves id -> name/poster/background/year/rating through Cinemeta `/meta`, with an in-memory cache,
/// so watch-progress rows (which carry only ids) can be shown with artwork.
actor CinemetaMetaCache {
    static let shared = CinemetaMetaCache()
    private var cache: [String: MediaTitle] = [:]
    private var misses: [String: Date] = [:]

    private struct Response: Decodable { let meta: Meta? }
    private struct Meta: Decodable {
        let id: String?, name: String?, poster: String?, background: String?, releaseInfo: String?, year: String?, imdbRating: String?
    }

    func title(kind: MediaTitle.Kind, id: String, session: URLSession = .shared) async -> MediaTitle? {
        let key = "\(kind.rawValue)/\(id)"
        if let hit = cache[key] { return hit }
        if let miss = misses[key], Date().timeIntervalSince(miss) < 300 { return nil }
        guard let url = CinemetaCatalog.detailURL(kind: kind, id: id),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let meta = (try? JSONDecoder().decode(Response.self, from: data))?.meta,
              let name = meta.name, !name.isEmpty else { misses[key] = Date(); return nil }
        func https(_ t: String?) -> URL? { t.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
        let value = MediaTitle(id: id, kind: kind, name: name, year: meta.releaseInfo ?? meta.year ?? "",
                               posterURL: https(meta.poster), rating: meta.imdbRating ?? "", backgroundURL: https(meta.background))
        cache[key] = value
        return value
    }
}
