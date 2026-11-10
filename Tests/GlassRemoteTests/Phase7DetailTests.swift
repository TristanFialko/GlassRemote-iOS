import XCTest
@testable import GlassRemote

/// Phase 7 detail page: Stremio/Nuvio meta parsing (app_extras cast, writers, certification,
/// trailerStreams), the facts line, credits, "more like this" and the pure layout rules.
final class Phase7DetailParsingTests: XCTestCase {
    private func parse(_ json: String) -> CinemetaCatalog.Detail? { CinemetaCatalog.parseDetail(Data(json.utf8)) }

    func testAppExtrasCastKeepsCharactersAndOnlyHTTPSPortraits() {
        let detail = parse(#"""
        {"meta":{"name":"Inception","cast":["Leonardo DiCaprio"],
          "app_extras":{"cast":[{"name":"Leonardo DiCaprio","character":"Cobb","photo":"https://img.example/a.jpg"},
                                {"name":"Elliot Page","character":"Ariadne","photo":"http://img.example/b.jpg"},
                                {"name":"  ","character":"Nobody"},
                                {"name":"Leonardo DiCaprio","character":"Cobb"},
                                42],
                        "directors":[{"name":"Christopher Nolan"}],
                        "writers":[{"name":"Christopher Nolan"}],
                        "certificationLocal":"PG-13"}}}
        """#)
        XCTAssertEqual(detail?.name, "Inception")
        XCTAssertEqual(detail?.castMembers.map(\.name), ["Leonardo DiCaprio", "Elliot Page"])
        XCTAssertEqual(detail?.castMembers.first?.character, "Cobb")
        XCTAssertEqual(detail?.castMembers.first?.photo?.absoluteString, "https://img.example/a.jpg")
        XCTAssertNil(detail?.castMembers.last?.photo, "plain http portraits are dropped")
        XCTAssertEqual(detail?.people.count, 2, "portraits win over the plain cast list")
        XCTAssertEqual(detail?.directors, ["Christopher Nolan"])
        XCTAssertEqual(detail?.writers, ["Christopher Nolan"])
        XCTAssertEqual(detail?.certification, "PG-13")
    }

    func testTopLevelCreditsWinAndAcceptCommaStringsAndNumbers() {
        let detail = parse(#"""
        {"meta":{"director":"Lana Wachowski, Lilly Wachowski","writer":["Lana Wachowski"],"imdbRating":8.7,
          "cast":["Keanu Reeves","keanu reeves"," Carrie-Anne Moss "],"genre":["Sci-Fi","Action"],
          "app_extras":{"directors":[{"name":"Someone Else"}],"certification":"R","certificationLocal":"16"}}}
        """#)
        XCTAssertEqual(detail?.directors, ["Lana Wachowski", "Lilly Wachowski"])
        XCTAssertEqual(detail?.writers, ["Lana Wachowski"])
        XCTAssertEqual(detail?.imdbRating, "8.7")
        XCTAssertEqual(detail?.cast, ["Keanu Reeves", "Carrie-Anne Moss"], "trimmed and de-duplicated")
        XCTAssertEqual(detail?.people.map(\.name), ["Keanu Reeves", "Carrie-Anne Moss"])
        XCTAssertEqual(detail?.genres, ["Sci-Fi", "Action"], "falls back to the singular genre key")
        XCTAssertEqual(detail?.certification, "R", "certification is preferred over certificationLocal")
    }

    func testTrailerStreamsFirstDeduplicatedAndInvalidIDsDropped() {
        let detail = parse(#"""
        {"meta":{"trailerStreams":[{"ytId":"abcdef123","title":"Official Trailer"}],
          "trailers":[{"source":"abcdef123","type":"Trailer"},{"source":"bad id!"},{"source":"zyxwvu987","type":"Teaser"},"oops"]}}
        """#)
        XCTAssertEqual(detail?.trailers.map(\.youTubeID), ["abcdef123", "zyxwvu987"])
        XCTAssertEqual(detail?.trailers.map(\.title), ["Official Trailer", "Teaser"])
        XCTAssertEqual(detail?.trailers.first?.thumbnail?.absoluteString, "https://i.ytimg.com/vi/abcdef123/hqdefault.jpg")
    }

    func testEpisodesSkipBrokenVideosAndAreSorted() {
        let detail = parse(#"""
        {"meta":{"videos":[
          {"id":"tt1:2:1","season":2,"episode":1,"name":"Second"},
          {"id":"tt1:1:2","season":1,"number":2,"title":"Two","overview":"  Hello  ","thumbnail":"https://t.example/2.jpg"},
          {"id":"no-season"},
          "garbage",
          {"id":"tt1:1:1","season":1,"episode":1,"released":"2010-07-16T00:00:00.000Z"}]}}
        """#)
        XCTAssertEqual(detail?.episodes.map(\.id), ["tt1:1:1", "tt1:1:2", "tt1:2:1"])
        XCTAssertEqual(detail?.seasons, [1, 2])
        XCTAssertEqual(detail?.episodes[1].overview, "Hello")
        XCTAssertEqual(detail?.episodes[1].thumbnail?.absoluteString, "https://t.example/2.jpg")
        XCTAssertEqual(detail?.episodes[2].title, "Second")
        XCTAssertNotNil(detail?.episodes[0].released)
    }

    func testNonObjectMetaIsNil() {
        XCTAssertNil(parse(#"{"meta":"nope"}"#))
        XCTAssertNil(parse(#"{}"#))
        XCTAssertNil(parse("not json"))
    }

    func testDetailURLOnlyForIMDbIDs() {
        XCTAssertEqual(CinemetaCatalog.detailURL(kind: .movie, id: "tt0133093")?.absoluteString.hasSuffix("/meta/movie/tt0133093.json"), true)
        XCTAssertNil(CinemetaCatalog.detailURL(kind: .series, id: "kitsu:123"))
        XCTAssertNil(CinemetaCatalog.detailURL(kind: .movie, id: "tt12/../x"))
    }

    func testYouTubeIDValidation() {
        XCTAssertEqual(CinemetaCatalog.youTubeID(" dQw4w9WgXcQ "), "dQw4w9WgXcQ")
        XCTAssertNil(CinemetaCatalog.youTubeID("https://youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(CinemetaCatalog.youTubeID("abc"))
        XCTAssertNil(CinemetaCatalog.youTubeID(nil))
    }

    func testPersonInitials() {
        XCTAssertEqual(CinemetaCatalog.Person(name: "Keanu Reeves").initials, "KR")
        XCTAssertEqual(CinemetaCatalog.Person(name: "Samuel L. Jackson").initials, "SJ")
        XCTAssertEqual(CinemetaCatalog.Person(name: "Cher").initials, "C")
        XCTAssertEqual(CinemetaCatalog.Person(name: "").initials, "")
    }
}

final class Phase7DetailFactsTests: XCTestCase {
    private func title(_ kind: MediaTitle.Kind = .movie, id: String = "tt0000001", genres: [String] = []) -> MediaTitle {
        var t = MediaTitle(id: id, kind: kind, name: "T", year: "1999", posterURL: nil, rating: "7.1")
        t.genres = genres
        return t
    }

    func testRuntimeFormatting() {
        XCTAssertEqual(DetailFacts.runtime("136 min"), "2h 16m")
        XCTAssertEqual(DetailFacts.runtime("45 min"), "45m")
        XCTAssertEqual(DetailFacts.runtime("120 min"), "2h")
        XCTAssertEqual(DetailFacts.runtime(" 1h 30m "), "1h 30m")
        XCTAssertEqual(DetailFacts.runtime(""), "")
    }

    func testFactsFallBackToTheCatalogueCard() {
        let facts = DetailFacts(title: title(genres: ["Drama", "Crime", "Thriller", "Mystery"]), detail: nil)
        XCTAssertEqual(facts.year, "1999")
        XCTAssertEqual(facts.rating, "7.1")
        XCTAssertEqual(facts.line, ["1999"])
        XCTAssertEqual(facts.genres, ["Drama", "Crime", "Thriller"])
    }

    func testFactsPreferDetailAndCountSeasonsForSeriesOnly() {
        var detail = CinemetaCatalog.Detail()
        detail.releaseInfo = "2008–2013"
        detail.runtime = "49 min"
        detail.imdbRating = "9.5"
        detail.certification = "TV-MA"
        detail.episodes = (1...5).map { CinemetaCatalog.Episode(id: "e\($0)", season: $0, number: 1, title: "", released: nil) }
        let series = DetailFacts(title: title(.series), detail: detail)
        XCTAssertEqual(series.line, ["2008–2013", "49m", "5 Seasons"])
        XCTAssertEqual(series.rating, "9.5")
        XCTAssertEqual(series.certification, "TV-MA")
        detail.episodes = [CinemetaCatalog.Episode(id: "e", season: 1, number: 1, title: "", released: nil)]
        XCTAssertEqual(DetailFacts(title: title(.series), detail: detail).seasons, "1 Season")
        XCTAssertEqual(DetailFacts(title: title(.movie), detail: detail).seasons, "")
    }

    func testCreditLabelsAndEmptyValuesLeftOut() {
        XCTAssertEqual(DetailCredit.list(nil), [])
        var detail = CinemetaCatalog.Detail()
        detail.directors = ["A", "B"]
        detail.writers = ["C"]
        detail.status = "Ended"
        detail.released = Date(timeIntervalSince1970: 1_279_238_400)
        let labels = DetailCredit.list(detail).map(\.label)
        XCTAssertEqual(labels, ["Directors", "Writer", "Released", "Status"])
        XCTAssertEqual(DetailCredit.list(detail).first?.value, "A, B")
    }

    func testSimilarGenreUsesCatalogueSpelling() {
        XCTAssertEqual(TitleDetailModel.similarGenre(["sci-fi"], fallback: []), "Sci-Fi")
        XCTAssertEqual(TitleDetailModel.similarGenre(["Made Up", "drama"], fallback: []), "Drama")
        XCTAssertEqual(TitleDetailModel.similarGenre([], fallback: ["Comedy"]), "Comedy")
        XCTAssertNil(TitleDetailModel.similarGenre(["Made Up"], fallback: ["Comedy"]), "detail genres win over the fallback")
    }

    func testSimilarExcludesSelfDeduplicatesAndLimits() {
        let items = ["tt1", "tt2", "tt2", "tt3", "tt4"].map { title(id: $0) }
        XCTAssertEqual(TitleDetailModel.similar(items, excluding: "tt1", limit: 2).map(\.id), ["tt2", "tt3"])
        XCTAssertEqual(TitleDetailModel.similar(items, excluding: "tt9").map(\.id), ["tt1", "tt2", "tt3", "tt4"])
    }
}

@MainActor
final class Phase7DetailLayoutTests: XCTestCase {
    func testHeroHeightPortraitAndLandscape() {
        XCTAssertEqual(DetailLayout.heroHeight(size: CGSize(width: 390, height: 844), isLandscape: false), 436.8, accuracy: 0.01)
        XCTAssertEqual(DetailLayout.heroHeight(size: CGSize(width: 320, height: 500), isLandscape: false), 380, accuracy: 0.01)
        XCTAssertEqual(DetailLayout.heroHeight(size: CGSize(width: 844, height: 390), isLandscape: true), 335.4, accuracy: 0.01)
        XCTAssertEqual(DetailLayout.heroHeight(size: CGSize(width: 667, height: 300), isLandscape: true), 300, accuracy: 0.01)
        XCTAssertEqual(DetailLayout.heroHeight(size: CGSize(width: 1366, height: 1000), isLandscape: true), 640, accuracy: 0.01)
    }

    func testPosterWidth() {
        XCTAssertEqual(DetailLayout.posterWidth(isLandscape: false, heroHeight: 500), 104)
        XCTAssertEqual(DetailLayout.posterWidth(isLandscape: true, heroHeight: 335.4), 134.16, accuracy: 0.01)
        XCTAssertEqual(DetailLayout.posterWidth(isLandscape: true, heroHeight: 1000), 180)
        XCTAssertEqual(DetailLayout.posterWidth(isLandscape: true, heroHeight: 100), 110)
    }

    func testArtworkPrefersBackdropThenBlurredPoster() {
        let poster = URL(string: "https://img.example/p.jpg")
        let backdrop = URL(string: "https://img.example/b.jpg")
        var title = MediaTitle(id: "tt1", kind: .movie, name: "T", year: "", posterURL: poster, rating: "")
        XCTAssertEqual(DetailLayout.artwork(detail: nil, title: title), .init(primary: poster, fallback: title.fallbackPosterURL, isPoster: true))
        var detail = CinemetaCatalog.Detail()
        detail.background = backdrop
        XCTAssertEqual(DetailLayout.artwork(detail: detail, title: title), .init(primary: backdrop, fallback: nil, isPoster: false))
        title.backgroundURL = URL(string: "https://img.example/card.jpg")
        XCTAssertEqual(DetailLayout.artwork(detail: detail, title: title).primary, title.backgroundURL)
        XCTAssertEqual(DetailLayout.artwork(detail: detail, title: title).fallback, backdrop)
    }

    func testOverviewToggleOnlyForLongText() {
        XCTAssertFalse(DetailOverview.isLong(String(repeating: "a", count: 180), lines: 4))
        XCTAssertTrue(DetailOverview.isLong(String(repeating: "a", count: 181), lines: 4))
    }
}
