import Foundation

/// Search relevance for Discover (pure, unit tested).
///
/// Cinemeta returns matches in its own popularity order. Ranking keeps that order only as a small
/// tie-breaker and puts title relevance first, so an exact match is never buried under a popular but
/// unrelated title: exact title > title starts with the query > whole-word match > substring > similarity.
/// A trailing year in the query ("dune 2021") boosts titles released that year.
enum SearchRanking {
    struct Query: Equatable {
        var text: String
        var year: String?
    }

    /// Same folding as Player artwork matching: accents, case, punctuation and a leading article are ignored.
    static func normalise(_ text: String) -> String { PlayerArtworkMatcher.normalise(text) }

    /// "Blade Runner 2049" keeps its full text; the trailing year is also offered separately.
    static func parse(_ raw: String) -> Query {
        var words = normalise(raw).split(separator: " ").map(String.init)
        var year: String?
        if words.count > 1, let last = words.last, last.range(of: #"^(19|20)[0-9]{2}$"#, options: .regularExpression) != nil {
            year = last
            words.removeLast()
        }
        return Query(text: words.joined(separator: " "), year: year)
    }

    /// Title-only relevance of a normalised name against a normalised query.
    static func textScore(_ name: String, _ query: String) -> Double {
        guard !query.isEmpty, !name.isEmpty else { return 0 }
        var score = similarity(name, query) * 200
        if name == query { score += 1000 }
        else if name.hasPrefix(query) { score += 600 }
        else if (" " + name + " ").contains(" " + query + " ") { score += 450 }
        else if name.contains(query) { score += 300 }
        return score
    }

    /// Relevance plus a small popularity bonus from the catalogue's own order (index 0 = most popular).
    static func score(name: String, year: String, query: Query, fullText: String, popularityIndex: Int) -> Double {
        let n = normalise(name)
        var best = textScore(n, fullText)
        if let y = query.year, !query.text.isEmpty {
            // "blade runner 2049": the year-less text only wins when the release year matches.
            let split = textScore(n, query.text)
            best = max(best, year.hasPrefix(y) ? split + 250 : split * 0.85)
        }
        return best + max(0, 60 - Double(popularityIndex) * 3)
    }

    /// Stable: equal scores keep the catalogue's popularity order.
    static func rank(_ titles: [MediaTitle], query raw: String) -> [MediaTitle] {
        let q = parse(raw)
        let full = normalise(raw)
        return titles.enumerated()
            .map { item in
                (index: item.offset, title: item.element,
                 score: score(name: item.element.name, year: item.element.year, query: q, fullText: full, popularityIndex: item.offset))
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.title)
    }

    /// One "Top result" card, only for a confident title match (exact or starts-with) among the ranked lists.
    static func topResult(_ ranked: [[MediaTitle]], query raw: String) -> MediaTitle? {
        let q = parse(raw)
        let full = normalise(raw)
        func value(_ t: MediaTitle) -> Double { score(name: t.name, year: t.year, query: q, fullText: full, popularityIndex: 0) }
        guard let best = ranked.compactMap(\.first).max(by: { value($0) < value($1) }), value(best) >= 660 else { return nil }
        return best
    }

    /// Dice coefficient over letter pairs: 1 for identical text, 0 for nothing in common.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        func pairs(_ s: String) -> [String: Int] {
            let c = Array(s.replacingOccurrences(of: " ", with: ""))
            guard c.count > 1 else { return c.isEmpty ? [:] : [String(c): 1] }
            var out: [String: Int] = [:]
            for i in 0..<(c.count - 1) { out[String(c[i...(i + 1)]), default: 0] += 1 }
            return out
        }
        let x = pairs(a), y = pairs(b)
        let total = x.values.reduce(0, +) + y.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let shared = x.reduce(0) { $0 + min($1.value, y[$1.key] ?? 0) }
        return Double(2 * shared) / Double(total)
    }
}

/// Recent search results kept in memory so a repeated or corrected query shows instantly.
/// Bounded (least recently stored entries are dropped) and short-lived, so results stay fresh.
struct SearchCache {
    var limit = 24
    var lifetime: TimeInterval = 600
    private var entries: [String: (titles: [MediaTitle], stored: Date)] = [:]
    private var order: [String] = []

    init(limit: Int = 24, lifetime: TimeInterval = 600) { self.limit = limit; self.lifetime = lifetime }

    static func key(_ query: String) -> String { SearchRanking.normalise(query) }

    var count: Int { entries.count }

    func value(for query: String, now: Date = Date()) -> [MediaTitle]? {
        guard let entry = entries[Self.key(query)], now.timeIntervalSince(entry.stored) < lifetime else { return nil }
        return entry.titles
    }

    mutating func store(_ titles: [MediaTitle], for query: String, now: Date = Date()) {
        let k = Self.key(query)
        guard !k.isEmpty else { return }
        entries[k] = (titles, now)
        order.removeAll { $0 == k }
        order.append(k)
        while order.count > limit { entries[order.removeFirst()] = nil }
    }
}
