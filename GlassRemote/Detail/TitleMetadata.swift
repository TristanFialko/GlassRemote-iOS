import Foundation

/// Cinemeta /meta for the detail page (Phase 7).
///
/// Stremio-style metadata publishes credits in more than one shape: plain name lists ("director",
/// "writer", "cast", either arrays or comma-separated text) and, from Cinemeta, an "app_extras" block
/// with character names, portrait photos and the certification. Nuvio reads the same fields
/// (NuvioMedia/NuvioTV MetaResponseDto: app_extras, trailerStreams, trailers, writer/writers, country,
/// awards, language, logo, released). Every field here is optional and decoded leniently, so one odd
/// value never drops the page; sections without data are simply not shown.
extension CinemetaCatalog {
    struct Episode: Identifiable, Hashable {
        let id: String
        let season: Int
        let number: Int
        let title: String
        let released: Date?
        /// Phase 7 extras for the episode list (empty when the source omits them).
        var overview: String = ""
        var thumbnail: URL? = nil
    }

    /// A credited person. `character` and `photo` exist only when the source publishes them.
    struct Person: Identifiable, Hashable {
        let name: String
        var character: String = ""
        var photo: URL? = nil
        var id: String { name + "|" + character }

        /// "Keanu Reeves" -> "KR"; shown while a portrait loads or when there is none.
        var initials: String {
            let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
            let picks: [Substring?] = [words.first, words.count > 1 ? words.last : nil]
            return picks.compactMap { $0?.first }.map { String($0) }.joined().uppercased()
        }
    }

    /// A YouTube trailer reference (the only trailer source Stremio metadata publishes).
    struct Trailer: Identifiable, Hashable {
        let youTubeID: String
        var title: String = "Trailer"
        var id: String { youTubeID }
        /// YouTube's public still. "hqdefault" is 4:3 with letterbox bars top and bottom, which a 16:9
        /// fill crop removes, and it is sharper than the true-16:9 "mqdefault".
        var thumbnail: URL? { URL(string: "https://i.ytimg.com/vi/\(youTubeID)/hqdefault.jpg") }
    }

    struct Detail: Equatable {
        var overview = ""
        var runtime = ""
        var genres: [String] = []
        var cast: [String] = []
        var directors: [String] = []
        var background: URL?
        var episodes: [Episode] = []
        // Phase 7
        var name = ""
        var poster: URL? = nil
        var logo: URL? = nil
        var releaseInfo = ""
        var released: Date? = nil
        var imdbRating = ""
        var certification = ""
        var writers: [String] = []
        var castMembers: [Person] = []
        var country = ""
        var language = ""
        var awards = ""
        var status = ""
        var trailers: [Trailer] = []

        var seasons: [Int] { Array(Set(episodes.map(\.season))).filter { $0 > 0 }.sorted() }
        /// Portrait-photo cast when the source has it, otherwise names only.
        var people: [Person] { castMembers.isEmpty ? cast.map { Person(name: $0) } : castMembers }
    }

    // MARK: Lenient decoding

    private struct MetaResponse: Decodable { let meta: FullMeta? }

    private struct FullMeta: Decodable {
        let name, description, runtime, background, poster, logo, releaseInfo, released, imdbRating,
            country, language, awards, status: MetaText?
        let genres, genre, cast, director, writer, writers: MetaList?
        let videos: MetaArray<Video>?
        let trailers: MetaArray<TrailerRef>?
        let trailerStreams: MetaArray<TrailerRef>?
        // JSON key as published by Cinemeta.
        let app_extras: Lossy<Extras>?
    }

    private struct Video: Decodable {
        let id: String
        let season: Int?
        let episode: Int?
        let number: Int?
        let title, name, released, overview, description, thumbnail: String?
    }

    private struct TrailerRef: Decodable {
        let source, ytId, title, name, type: String?
    }

    private struct Extras: Decodable {
        let cast, directors, writers: MetaArray<Credit>?
        let certification, certificationLocal: MetaText?
    }

    private struct Credit: Decodable {
        let name: String
        let character, photo: String?
    }

    /// Text or a number ("imdbRating": 7.4), trimmed; anything else is empty.
    private struct MetaText: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                value = s.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let n = try? c.decode(Double.self) {
                value = (n.rounded() == n && abs(n) < 1e9) ? String(Int(n)) : String(n)
            } else {
                value = ""
            }
        }
    }

    /// A list of names, or one comma-separated string.
    private struct MetaList: Decodable {
        let values: [String]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let list = try? c.decode([MetaText].self) {
                values = list.map(\.value)
            } else if let text = try? c.decode(String.self) {
                values = text.split(separator: ",").map { String($0) }
            } else {
                values = []
            }
        }
    }

    /// An array whose broken elements are skipped (and which is empty when the value isn't an array).
    private struct MetaArray<Element: Decodable>: Decodable {
        let items: [Element]
        init(from decoder: Decoder) throws {
            let list = (try? decoder.singleValueContainer().decode([Lossy<Element>].self)) ?? []
            items = list.compactMap(\.value)
        }
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    // MARK: Detail (Cinemeta /meta)

    static func detailURL(kind: MediaTitle.Kind, id: String) -> URL? {
        guard id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "\(base)/meta/\(kind.rawValue)/\(id).json")
    }

    static func parseDetail(_ data: Data) -> Detail? {
        guard let meta = (try? JSONDecoder().decode(MetaResponse.self, from: data))?.meta else { return nil }
        let extras = meta.app_extras?.value
        var detail = Detail()
        detail.name = string(meta.name)
        detail.overview = string(meta.description)
        detail.runtime = string(meta.runtime)
        detail.genres = first(clean(meta.genres?.values ?? [], limit: 8), clean(meta.genre?.values ?? [], limit: 8))
        detail.cast = clean(meta.cast?.values ?? [])
        detail.directors = first(clean(meta.director?.values ?? [], limit: 6),
                                 clean((extras?.directors?.items ?? []).map(\.name), limit: 6))
        detail.writers = first(clean(meta.writer?.values ?? [], limit: 8), clean(meta.writers?.values ?? [], limit: 8),
                               clean((extras?.writers?.items ?? []).map(\.name), limit: 8))
        detail.castMembers = people(extras?.cast?.items ?? [])
        detail.background = https(string(meta.background))
        detail.poster = https(string(meta.poster))
        detail.logo = https(string(meta.logo))
        detail.releaseInfo = string(meta.releaseInfo)
        detail.released = DateParsing.iso(meta.released?.value)
        detail.imdbRating = string(meta.imdbRating)
        detail.country = string(meta.country)
        detail.language = string(meta.language)
        detail.awards = string(meta.awards)
        detail.status = string(meta.status)
        let certification = string(extras?.certification)
        detail.certification = certification.isEmpty ? string(extras?.certificationLocal) : certification
        detail.trailers = trailers((meta.trailerStreams?.items ?? []) + (meta.trailers?.items ?? []))
        detail.episodes = (meta.videos?.items ?? []).compactMap { v in
            guard let season = v.season, let number = v.episode ?? v.number else { return nil }
            return Episode(id: v.id, season: season, number: number, title: v.title ?? v.name ?? "",
                           released: DateParsing.iso(v.released),
                           overview: (v.overview ?? v.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           thumbnail: https(v.thumbnail))
        }.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        return detail
    }

    static func detail(kind: MediaTitle.Kind, id: String, session: URLSession = .shared) async throws -> Detail? {
        guard let url = detailURL(kind: kind, id: id) else { return nil }
        return parseDetail(try await fetch(url, session: session))
    }

    /// A YouTube video id as published by Stremio metadata, or nil for anything else.
    static func youTubeID(_ raw: String?) -> String? {
        guard let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              id.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    private static func string(_ value: MetaText?) -> String { value?.value ?? "" }

    private static func first(_ lists: [String]...) -> [String] { lists.first { !$0.isEmpty } ?? [] }

    /// Trimmed, non-empty, de-duplicated (case-insensitively), in source order.
    private static func clean(_ names: [String], limit: Int = 40) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
            if out.count == limit { break }
        }
        return out
    }

    private static func people(_ credits: [Credit], limit: Int = 40) -> [Person] {
        var seen = Set<String>()
        var out: [Person] = []
        for credit in credits {
            let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let character = (credit.character ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased() + "|" + character.lowercased()).inserted else { continue }
            out.append(Person(name: name, character: character, photo: https(credit.photo)))
            if out.count == limit { break }
        }
        return out
    }

    /// "trailerStreams" first (it carries titles), then the older "trailers" list; one entry per video.
    private static func trailers(_ refs: [TrailerRef], limit: Int = 8) -> [Trailer] {
        var seen = Set<String>()
        var out: [Trailer] = []
        for ref in refs {
            guard let id = youTubeID(ref.ytId ?? ref.source), seen.insert(id).inserted else { continue }
            let label = [ref.title, ref.name, ref.type]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            out.append(Trailer(youTubeID: id, title: label ?? "Trailer"))
            if out.count == limit { break }
        }
        return out
    }
}
