import XCTest
@testable import GlassRemote

final class StremioCatalogTests: XCTestCase {
    func testSearchParsingKeepsVerifiedArtworkAndMetadata() throws {
        let json = Data(#"{"metas":[{"id":"tt0133093","name":"The Matrix","releaseInfo":"1999","poster":"https://images.example/poster.jpg","background":"https://images.example/backdrop.jpg","imdbRating":"8.7","description":"A hacker discovers a simulated reality.","genre":["Action","Sci-Fi"]}]}"#.utf8)
        let result = StremioCatalog.parse(json, kind: .movie)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "The Matrix")
        XCTAssertEqual(result[0].genres, ["Action", "Sci-Fi"])
        XCTAssertEqual(result[0].backgroundURL?.scheme, "https")
    }

    func testMetadataURLsOnlyAcceptIMDbIDs() {
        XCTAssertNotNil(StremioCatalog.metadataURL(kind: .movie, id: "tt0133093"))
        XCTAssertNil(StremioCatalog.metadataURL(kind: .movie, id: "not-a-title"))
    }
}
