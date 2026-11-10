import Foundation

/// Metadata returned by the Stremio/Cinemeta addon protocol.
struct StremioTitle: Identifiable, Hashable {
    enum Kind: String { case movie, series }
    let id: String
    let kind: Kind
    let name: String
    let year: String
    let posterURL: URL?
    let backgroundURL: URL?
    let rating: String
    let description: String
    let genres: [String]

    var metadataURL: URL? { StremioCatalog.metadataURL(kind: kind, id: id) }
}

enum StremioCatalog {
    static let base = "https://v3-cinemeta.strem.io"

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

    static func metadataURL(kind: StremioTitle.Kind, id: String) -> URL? {
        guard id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "\(base)/meta/\(kind.rawValue)/\(id).json")
    }

    private struct Response: Decodable { let metas: [Meta]? }
    private struct Meta: Decodable {
        let id: String?
        let name: String?
        let poster: String?
        let background: String?
        let releaseInfo: String?
        let imdbRating: String?
        let description: String?
        let genre: [String]?
    }

    private static func httpsURL(_ value: String?) -> URL? {
        value.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    private static func title(from meta: Meta, kind: StremioTitle.Kind) -> StremioTitle? {
        guard let id = meta.id, let name = meta.name, !name.isEmpty else { return nil }
        return StremioTitle(
            id: id,
            kind: kind,
            name: name,
            year: meta.releaseInfo ?? "",
            posterURL: httpsURL(meta.poster),
            backgroundURL: httpsURL(meta.background),
            rating: meta.imdbRating ?? "",
            description: meta.description ?? "",
            genres: meta.genre ?? []
        )
    }

    static func parse(_ data: Data, kind: StremioTitle.Kind) -> [StremioTitle] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.metas ?? []).compactMap { title(from: $0, kind: kind) }
    }

    static func search(_ query: String, session: URLSession = .shared) async throws -> [StremioTitle] {
        var all: [StremioTitle] = []
        for kind in [StremioTitle.Kind.movie, .series] {
            guard let url = searchURL(kind: kind, query: query) else { return [] }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            all += parse(data, kind: kind)
        }
        return all
    }

    /// Fetches the full Cinemeta record only after the user opens a title. This keeps search fast
    /// and gives the landscape detail view richer artwork/description without inventing fields.
    static func metadata(for title: StremioTitle, session: URLSession = .shared) async throws -> StremioTitle {
        guard let url = title.metadataURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let meta = try? JSONDecoder().decode(Meta.self, from: data),
              let hydrated = title(from: meta, kind: title.kind) else { throw URLError(.cannotParseResponse) }
        return hydrated
    }
}

@MainActor
final class DiscoverModel: ObservableObject {
    enum Phase: Equatable { case idle, searching, results, empty, failed(String) }

    @Published var query = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var movies: [StremioTitle] = []
    @Published private(set) var series: [StremioTitle] = []
    private var task: Task<Void, Never>?

    func queryChanged() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { movies = []; series = []; phase = .idle; return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
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
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            phase = .failed("Couldn't reach the catalog. Check your internet connection.")
        }
    }
}
