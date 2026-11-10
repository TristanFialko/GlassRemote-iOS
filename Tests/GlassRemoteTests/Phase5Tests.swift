import XCTest
@testable import GlassRemote

/// Phase 5: the Discover hero's meta line.
final class Phase5Tests: XCTestCase {

    func testHeroMetaJoinsKindAndYearWithOneEvenSeparator() {
        XCTAssertEqual(DiscoverMetaLine.separator, " · ")
        XCTAssertEqual(DiscoverMetaLine.kindAndYear(.movie, year: "2026"), "Movie · 2026")
        XCTAssertEqual(DiscoverMetaLine.kindAndYear(.series, year: "2019–2023"), "Series · 2019–2023")
    }

    func testHeroMetaLeavesNoDanglingDotWithoutAYear() {
        XCTAssertEqual(DiscoverMetaLine.kindAndYear(.movie, year: ""), "Movie")
        XCTAssertEqual(DiscoverMetaLine.kindAndYear(.series, year: "  \n"), "Series")
    }

    func testHeroMetaTrimsTheYear() {
        XCTAssertEqual(DiscoverMetaLine.kindAndYear(.movie, year: " 1999 "), "Movie · 1999")
    }
}
