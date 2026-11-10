import XCTest
@testable import GlassRemote

final class AppPageTests: XCTestCase {
    func testLandscapePagingUsesOnePagePerIntent() {
        XCTAssertEqual(AppPage.target(from: .remote, translation: -260, predicted: -270, width: 800), .player)
        XCTAssertEqual(AppPage.target(from: .discover, translation: 280, predicted: 290, width: 800), .player)
    }

    func testPagingIsClampedAtEdges() {
        XCTAssertEqual(AppPage.target(from: .remote, translation: 900, predicted: 900, width: 800), .remote)
        XCTAssertEqual(AppPage.target(from: .apps, translation: -900, predicted: -900, width: 800), .apps)
    }
}
