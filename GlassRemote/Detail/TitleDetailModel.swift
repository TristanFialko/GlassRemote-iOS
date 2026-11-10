import Foundation

/// Facts shown under the detail title, in reading order (pure, unit tested). Empty values are left out.
struct DetailFacts: Equatable {
    var year = ""
    var runtime = ""
    var certification = ""
    var rating = ""
    var seasons = ""
    var genres: [String] = []

    init(title: MediaTitle, detail: CinemetaCatalog.Detail?) {
        let info = detail?.releaseInfo ?? ""
        year = info.isEmpty ? title.year : info
        runtime = Self.runtime(detail?.runtime ?? "")
        certification = detail?.certification ?? ""
        let imdb = detail?.imdbRating ?? ""
        rating = imdb.isEmpty ? title.rating : imdb
        if title.kind == .series, let count = detail?.seasons.count, count > 0 {
            seasons = count == 1 ? "1 Season" : "\(count) Seasons"
        }
        let listed = detail?.genres ?? []
        genres = Array((listed.isEmpty ? title.genres : listed).prefix(3))
    }

    /// "136 min" -> "2h 16m"; anything else is shown as published.
    static func runtime(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.range(of: #"^[0-9]+(?=\s*min)"#, options: .regularExpression),
              let minutes = Int(text[match]), minutes > 0 else { return text }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Year, runtime and season count for the compact header line.
    var line: [String] { [year, runtime, seasons].filter { !$0.isEmpty } }
}

/// One labelled credit or fact for the details grid (pure, unit tested).
struct DetailCredit: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }

    static func list(_ detail: CinemetaCatalog.Detail?) -> [DetailCredit] {
        guard let detail else { return [] }
        var out: [DetailCredit] = []
        func add(_ label: String, _ value: String) {
            if !value.isEmpty { out.append(DetailCredit(label: label, value: value)) }
        }
        add(detail.directors.count > 1 ? "Directors" : "Director", detail.directors.prefix(3).joined(separator: ", "))
        add(detail.writers.count > 1 ? "Writers" : "Writer", detail.writers.prefix(3).joined(separator: ", "))
        if let date = detail.released { add("Released", date.formatted(date: .long, time: .omitted)) }
        add("Status", detail.status)
        add("Country", detail.country)
        add("Language", detail.language)
        add("Awards", detail.awards)
        return out
    }
}

/// Loads one title's metadata and a "more like this" row for the detail page. Networking stays here;
/// the view only renders what this publishes.
@MainActor
final class TitleDetailModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, failed }

    let title: MediaTitle
    @Published private(set) var detail: CinemetaCatalog.Detail?
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var similar: [MediaTitle] = []
    @Published private(set) var similarGenre: String?

    init(title: MediaTitle) { self.title = title }

    var facts: DetailFacts { DetailFacts(title: title, detail: detail) }
    var credits: [DetailCredit] { DetailCredit.list(detail) }
    var displayName: String {
        let name = detail?.name ?? ""
        return name.isEmpty ? title.name : name
    }
    var overview: String {
        let text = detail?.overview ?? ""
        return text.isEmpty ? title.overview : text
    }
    var logoURL: URL? { detail?.logo ?? title.logoURL }

    func load() async {
        guard phase != .loaded else { return }
        phase = .loading
        let loaded = try? await CinemetaCatalog.detail(kind: title.kind, id: title.id)
        guard !Task.isCancelled else { return }
        detail = loaded ?? nil
        phase = detail == nil ? .failed : .loaded
        await loadSimilar()
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// Popular titles of the same kind in the title's first catalogue genre (real Cinemeta data;
    /// Cinemeta has no per-title recommendations endpoint).
    private func loadSimilar() async {
        guard similar.isEmpty, let genre = Self.similarGenre(detail?.genres ?? [], fallback: title.genres) else { return }
        let items = (try? await CinemetaCatalog.browse(kind: title.kind, catalog: "top", genre: genre)) ?? []
        guard !Task.isCancelled else { return }
        similarGenre = genre
        similar = Self.similar(items, excluding: title.id)
    }

    /// The first of the title's genres that Cinemeta can browse, spelled as the catalogue spells it.
    nonisolated static func similarGenre(_ genres: [String], fallback: [String]) -> String? {
        for genre in genres.isEmpty ? fallback : genres {
            if let known = CinemetaCatalog.genres.first(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) {
                return known
            }
        }
        return nil
    }

    nonisolated static func similar(_ items: [MediaTitle], excluding id: String, limit: Int = 20) -> [MediaTitle] {
        var seen: Set<String> = [id]
        return Array(items.filter { seen.insert($0.id).inserted }.prefix(limit))
    }
}
