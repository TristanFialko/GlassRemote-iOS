import XCTest
@testable import GlassRemote

// Phase 7 Discover tests: search ranking and the search cache, the artwork-orientation preference,
// hero sizing and artwork choice, and the richer catalogue parsing used by the hero.
// Layout, the zoom transition and motion need a device; see PHASE-7-NOTES.md.

private func media(_ id: String, _ name: String, year: String = "", kind: MediaTitle.Kind = .movie,
                   poster: String? = nil, background: String? = nil) -> MediaTitle {
    MediaTitle(id: id, kind: kind, name: name, year: year, posterURL: poster.flatMap(URL.init(string:)),
               rating: "", backgroundURL: background.flatMap(URL.init(string:)))
}

final class Phase7SearchRankingTests: XCTestCase {
    func testExactMatchBeatsPopularPrefixAndUnrelatedTitles() {
        let list = [media("1", "The Matrix"), media("2", "Dune: Part Two"), media("3", "Dune Drifter"), media("4", "Dune")]
        let ranked = SearchRanking.rank(list, query: "dune")
        XCTAssertEqual(ranked.first?.id, "4")
        XCTAssertEqual(ranked.last?.id, "1")
    }

    func testPrefixBeatsAWordInsideALongerTitle() {
        let list = [media("1", "Escape from Alien Planet"), media("2", "Alien: Romulus")]
        XCTAssertEqual(SearchRanking.rank(list, query: "alien").first?.id, "2")
    }

    func testYearsInTitlesAndInQueries() {
        let list = [media("1", "Blade Runner", year: "1982"), media("2", "Blade Runner 2049", year: "2017")]
        XCTAssertEqual(SearchRanking.rank(list, query: "blade runner 2049").first?.id, "2")
        XCTAssertEqual(SearchRanking.rank(list, query: "Blade Runner").first?.id, "1")
        let dunes = [media("a", "Dune", year: "1984"), media("b", "Dune", year: "2021")]
        XCTAssertEqual(SearchRanking.rank(dunes, query: "dune 2021").first?.id, "b")
        XCTAssertEqual(SearchRanking.rank(dunes, query: "dune").first?.id, "a")
    }

    func testParseSplitsOnlyATrailingYear() {
        XCTAssertEqual(SearchRanking.parse("Dune 2021"), SearchRanking.Query(text: "dune", year: "2021"))
        XCTAssertEqual(SearchRanking.parse("Blade Runner 2049"), SearchRanking.Query(text: "blade runner", year: "2049"))
        XCTAssertEqual(SearchRanking.parse("2012"), SearchRanking.Query(text: "2012", year: nil))
        XCTAssertEqual(SearchRanking.parse("  The Matrix  "), SearchRanking.Query(text: "matrix", year: nil))
        XCTAssertEqual(SearchRanking.parse("Ocean's 11"), SearchRanking.Query(text: "ocean s 11", year: nil))
    }

    func testSimilarityBounds() {
        XCTAssertEqual(SearchRanking.similarity("night", "night"), 1)
        XCTAssertEqual(SearchRanking.similarity("", ""), 0)
        XCTAssertEqual(SearchRanking.similarity("ab", "xy"), 0)
        let partial = SearchRanking.similarity("night", "nacht")
        XCTAssertGreaterThan(partial, 0)
        XCTAssertLessThan(partial, 1)
    }

    func testEqualScoresKeepTheCatalogueOrder() {
        let filler = (0..<22).map { media("f\($0)", "Filler \($0)") }
        let ranked = SearchRanking.rank(filler + [media("x", "Alien"), media("y", "Alien")], query: "alien")
        XCTAssertEqual(ranked.prefix(2).map(\.id), ["x", "y"])
        XCTAssertEqual(ranked.count, 24)
    }

    func testTopResultNeedsAConfidentMatch() {
        let movies = SearchRanking.rank([media("1", "Interstellar"), media("2", "Inception")], query: "inception")
        XCTAssertEqual(SearchRanking.topResult([movies, []], query: "inception")?.id, "2")
        XCTAssertEqual(SearchRanking.topResult([[media("3", "Inception")]], query: "incep")?.id, "3")
        XCTAssertNil(SearchRanking.topResult([[media("4", "Arrival")]], query: "inception"))
        XCTAssertNil(SearchRanking.topResult([], query: "inception"))
    }
}

final class Phase7SearchCacheTests: XCTestCase {
    func testHitsUseTheNormalisedQueryAndExpire() {
        var cache = SearchCache(limit: 4, lifetime: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        cache.store([media("1", "Dune")], for: "Dune", now: start)
        XCTAssertEqual(cache.value(for: "  dune ", now: start.addingTimeInterval(5))?.map(\.id), ["1"])
        XCTAssertEqual(cache.value(for: "DUNE", now: start)?.count, 1)
        XCTAssertNil(cache.value(for: "dun", now: start))
        XCTAssertNil(cache.value(for: "dune", now: start.addingTimeInterval(61)))
    }

    func testLimitDropsTheLeastRecentlyStoredQuery() {
        var cache = SearchCache(limit: 2, lifetime: 600)
        let now = Date()
        cache.store([media("1", "One")], for: "one", now: now)
        cache.store([media("2", "Two")], for: "two", now: now)
        cache.store([media("3", "Three")], for: "three", now: now)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.value(for: "one", now: now))
        cache.store([media("2", "Two")], for: "two", now: now)
        cache.store([media("4", "Four")], for: "four", now: now)
        XCTAssertNil(cache.value(for: "three", now: now))
        XCTAssertNotNil(cache.value(for: "two", now: now))
        XCTAssertNotNil(cache.value(for: "four", now: now))
        cache.store([], for: "   ", now: now)
        XCTAssertEqual(cache.count, 2)
    }
}

final class Phase7DiscoverLayoutTests: XCTestCase {
    func testCardShapeFollowsTheArtworkPreference() {
        XCTAssertEqual(DiscoverCardShape.resolve(.automatic, usage: .catalog), .portrait)
        XCTAssertEqual(DiscoverCardShape.resolve(.automatic, usage: .progress), .landscape)
        XCTAssertEqual(DiscoverCardShape.resolve(.portrait, usage: .progress), .portrait)
        XCTAssertEqual(DiscoverCardShape.resolve(.landscape, usage: .catalog), .landscape)
    }

    func testHeroHeightAdaptsToOrientation() {
        XCTAssertEqual(DiscoverHeroLayout.height(width: 390, height: 844, isLandscape: false), 483.6, accuracy: 0.01)
        XCTAssertEqual(DiscoverHeroLayout.height(width: 430, height: 600, isLandscape: false), 420, accuracy: 0.01)
        XCTAssertEqual(DiscoverHeroLayout.height(width: 844, height: 390, isLandscape: true), 335.4, accuracy: 0.01)
        XCTAssertEqual(DiscoverHeroLayout.height(width: 1366, height: 1024, isLandscape: true), 560, accuracy: 0.01)
        XCTAssertEqual(DiscoverHeroLayout.height(width: 568, height: 280, isLandscape: true), 260, accuracy: 0.01)
    }

    func testHeroArtworkPrefersBackdropsAndFallsBack() {
        let wide = media("tt0133093", "The Matrix", poster: "https://img.example/p.jpg", background: "https://img.example/b.jpg")
        XCTAssertEqual(DiscoverHeroLayout.artwork(for: wide).primary?.absoluteString, "https://img.example/b.jpg")
        XCTAssertEqual(DiscoverHeroLayout.artwork(for: wide).fallback?.absoluteString, "https://img.example/p.jpg")
        let posterOnly = media("tt0133093", "The Matrix", poster: "https://img.example/p.jpg")
        XCTAssertEqual(DiscoverHeroLayout.artwork(for: posterOnly).primary?.absoluteString, "https://img.example/p.jpg")
        XCTAssertEqual(DiscoverHeroLayout.artwork(for: posterOnly).fallback, posterOnly.fallbackPosterURL)
        XCTAssertNil(DiscoverHeroLayout.artwork(for: media("local", "Home video")).primary)
    }

    func testInterleaveAlternatesDeduplicatesAndLimits() {
        let movies = [media("m1", "A"), media("m2", "B"), media("s1", "Shared")]
        let series = [media("s1", "Shared", kind: .series), media("s2", "C", kind: .series)]
        XCTAssertEqual(DiscoverHeroLayout.interleave([movies, series]).map(\.id), ["m1", "s1", "m2", "s2"])
        XCTAssertEqual(DiscoverHeroLayout.interleave([movies, series], limit: 3).map(\.id), ["m1", "s1", "m2"])
        XCTAssertTrue(DiscoverHeroLayout.interleave([]).isEmpty)
    }

    func testLandscapeMetricsUseTheExtraWidth() {
        let portrait = DiscoverMetrics(isLandscape: false)
        let landscape = DiscoverMetrics(isLandscape: true)
        XCTAssertEqual(portrait.poster, PosterCard.width)
        XCTAssertEqual(portrait.landscape, LandscapeCard.width)
        XCTAssertGreaterThan(landscape.poster, portrait.poster)
        XCTAssertGreaterThan(landscape.landscape, portrait.landscape)
        XCTAssertGreaterThan(landscape.spacing, portrait.spacing)
    }
}

final class Phase7CatalogParsingTests: XCTestCase {
    func testParsesHeroExtrasLenientlyAndSkipsBrokenEntries() {
        let json = #"""
        {"metas":[
          {"id":"tt1160419","name":"Dune","releaseInfo":"2021","poster":"https://images.example/dune.jpg","imdbRating":"8.0",
           "background":"https://images.example/dune-bg.jpg","logo":"https://images.example/dune-logo.png",
           "description":"  Paul Atreides leads nomadic tribes.  ","genres":["Science Fiction","Adventure"]},
          {"id":"tt0000001","name":"Plain HTTP","poster":"http://insecure.example/p.jpg","genre":"Drama","description":42},
          {"id":"tt0000002","name":""},
          {"name":"No id"}
        ]}
        """#
        let titles = CinemetaCatalog.parse(Data(json.utf8), kind: .movie)
        XCTAssertEqual(titles.map(\.id), ["tt1160419", "tt0000001"])
        let dune = titles[0]
        XCTAssertEqual(dune.year, "2021")
        XCTAssertEqual(dune.rating, "8.0")
        XCTAssertEqual(dune.overview, "Paul Atreides leads nomadic tribes.")
        XCTAssertEqual(dune.genres, ["Science Fiction", "Adventure"])
        XCTAssertEqual(dune.logoURL?.absoluteString, "https://images.example/dune-logo.png")
        XCTAssertEqual(dune.backgroundURL?.absoluteString, "https://images.example/dune-bg.jpg")
        let plain = titles[1]
        XCTAssertNil(plain.posterURL)
        XCTAssertEqual(plain.genres, ["Drama"])
        XCTAssertEqual(plain.overview, "")
        XCTAssertEqual(plain.kind, .movie)
    }

    func testRejectsNonCatalogueResponses() {
        XCTAssertTrue(CinemetaCatalog.parse(Data("not json".utf8), kind: .series).isEmpty)
        XCTAssertTrue(CinemetaCatalog.parse(Data(#"{"metas":null}"#.utf8), kind: .series).isEmpty)
    }
}
