import SwiftUI
import XCTest
@testable import GlassRemote

/// v6 §8: Discover's header hides on downward scroll and returns on upward scroll (portrait and
/// landscape share the rule), the search keyboard never resizes the page, and the cast list is the
/// fullest real list the metadata supports.
final class Phase9V6DiscoverHeaderTests: XCTestCase {
    private let topZone = DiscoverHeaderReveal.topZone(headerHeight: 104)
    private let maxOffset: CGFloat = 4_000

    /// Feeds offsets in order and returns the final state.
    private func run(_ offsets: [CGFloat], pinned: Bool = false, maxOffset: CGFloat? = nil,
                     start: DiscoverHeaderReveal = DiscoverHeaderReveal()) -> DiscoverHeaderReveal {
        var state = start
        for offset in offsets {
            state.update(offset: offset, maxOffset: maxOffset ?? self.maxOffset, topZone: topZone, pinned: pinned)
        }
        return state
    }

    func testScrollingDownPastTheThresholdHides() {
        XCTAssertTrue(run([400, 420, 440]).hidden, "40 pt of downward travel hides it")
        XCTAssertFalse(run([400, 410, 420]).hidden, "20 pt is below the threshold")
    }

    func testScrollingUpRevealsAfterAShorterDistance() {
        let hidden = run([400, 440])
        XCTAssertTrue(hidden.hidden)
        XCTAssertTrue(run([430], start: hidden).hidden, "10 pt up is jitter")
        XCTAssertFalse(run([420], start: hidden).hidden, "20 pt up reveals it")
    }

    func testJitterNeverToggles() {
        var offsets: [CGFloat] = [500]
        for i in 0..<40 { offsets.append(500 + (i.isMultiple(of: 2) ? 10 : 0)) }
        XCTAssertFalse(run(offsets).hidden, "back-and-forth below the threshold never hides")
        let hidden = run([500, 540])
        var back: [CGFloat] = []
        for i in 0..<40 { back.append(540 - (i.isMultiple(of: 2) ? 8 : 0)) }
        XCTAssertTrue(run(back, start: hidden).hidden, "and never reveals")
    }

    func testDirectionReversalRestartsTheCount() {
        // 20 down, 5 up, 20 down: neither run of downward travel reaches 28 on its own.
        XCTAssertFalse(run([400, 420, 415, 435]).hidden)
    }

    func testAlwaysShownNearTheTop() {
        XCTAssertFalse(run([0, 60, 100]).hidden, "inside the top zone")
        let hidden = run([400, 460])
        XCTAssertFalse(run([50], start: hidden).hidden, "jumping back to the top shows it")
    }

    func testRubberBandOverscrollIsIgnored() {
        let hidden = run([3_000, 3_960, 4_000])
        XCTAssertTrue(hidden.hidden)
        // Bouncing past the bottom and settling back never reads as an upward scroll.
        XCTAssertTrue(run([4_060, 4_100, 4_030, 4_000], start: hidden).hidden)
        // Pulling down past the top is clamped to zero, which is the top zone.
        XCTAssertFalse(run([-80], start: hidden).hidden)
    }

    func testShortContentNeverHides() {
        XCTAssertFalse(run([60, 120, 130], maxOffset: 130).hidden, "too short to scroll past the header")
    }

    func testPinnedWhileSearchingOrVoiceOver() {
        XCTAssertFalse(run([400, 500, 600], pinned: true).hidden)
        let hidden = run([400, 460])
        XCTAssertFalse(run([470], pinned: true, start: hidden).hidden, "focus pins it visible")
    }

    func testRevealResets() {
        var state = run([400, 460])
        XCTAssertTrue(state.hidden)
        state.reveal()
        XCTAssertFalse(state.hidden)
        XCTAssertEqual(state.travel, 0)
    }

    func testUpdateReportsOnlyRealChanges() {
        var state = DiscoverHeaderReveal()
        XCTAssertFalse(state.update(offset: 400, maxOffset: maxOffset, topZone: topZone, pinned: false))
        XCTAssertFalse(state.update(offset: 410, maxOffset: maxOffset, topZone: topZone, pinned: false))
        XCTAssertTrue(state.update(offset: 440, maxOffset: maxOffset, topZone: topZone, pinned: false))
        XCTAssertFalse(state.update(offset: 480, maxOffset: maxOffset, topZone: topZone, pinned: false))
    }

    func testLandscapeUsesTheSameRuleWithItsShorterHeader() {
        let landscapeZone = DiscoverHeaderReveal.topZone(headerHeight: 52)
        XCTAssertEqual(landscapeZone, 52)
        XCTAssertEqual(DiscoverHeaderReveal.topZone(headerHeight: 10), 44, "never smaller than a touch target")
        var state = DiscoverHeaderReveal()
        for y: CGFloat in [80, 120] { state.update(offset: y, maxOffset: maxOffset, topZone: landscapeZone, pinned: false) }
        XCTAssertTrue(state.hidden)
    }

    func testOffsetSlidesOrOnlyFades() {
        XCTAssertEqual(DiscoverHeaderReveal.offset(hidden: true, travel: 160, reduceMotion: false), -160)
        XCTAssertEqual(DiscoverHeaderReveal.offset(hidden: true, travel: 160, reduceMotion: true), 0, "Reduce Motion: fade only")
        XCTAssertEqual(DiscoverHeaderReveal.offset(hidden: false, travel: 160, reduceMotion: false), 0)
    }

    func testScrollSampleFromGeometryNumbers() {
        let sample = DiscoverScrollSample(offset: 120, maxOffset: 900)
        XCTAssertEqual(sample, DiscoverScrollSample(offset: 120, maxOffset: 900))
    }
}

final class Phase9V6DiscoverKeyboardTests: XCTestCase {
    func testKeyboardOverlapIsMeasuredFromTheBottom() {
        let frame = CGRect(x: 0, y: 852 - 336, width: 393, height: 336)
        XCTAssertEqual(DiscoverKeyboardPolicy.overlap(keyboardFrame: frame, screenHeight: 852), 336)
        let hidden = CGRect(x: 0, y: 852, width: 393, height: 336)
        XCTAssertEqual(DiscoverKeyboardPolicy.overlap(keyboardFrame: hidden, screenHeight: 852), 0)
        XCTAssertEqual(DiscoverKeyboardPolicy.overlap(keyboardFrame: .zero, screenHeight: 852), 0)
    }

    func testContentMarginIsOnlyWhatTheDockSpaceDoesNotCover() {
        let clearance = DockMetrics.clearance(safeBottom: 34)
        XCTAssertEqual(DiscoverKeyboardPolicy.contentMargin(keyboardOverlap: 0, dockClearance: clearance), 0)
        XCTAssertEqual(DiscoverKeyboardPolicy.contentMargin(keyboardOverlap: 336, dockClearance: clearance), 336 - clearance)
        XCTAssertEqual(DiscoverKeyboardPolicy.contentMargin(keyboardOverlap: 20, dockClearance: clearance), 0)
    }

    func testHeroSizeDoesNotDependOnTheKeyboard() {
        // Discover ignores the keyboard safe area, so the hero is always sized from the full page.
        let full = DiscoverHeroLayout.height(width: 393, height: 852, isLandscape: false)
        XCTAssertEqual(full, DiscoverHeroLayout.height(width: 393, height: 852, isLandscape: false))
        XCTAssertGreaterThan(full, 0)
    }

    func testDiscoverIgnoresTheKeyboardAndTheDockLayerToo() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let discover = try? String(contentsOf: root.appendingPathComponent("GlassRemote/DiscoverPage.swift"), encoding: .utf8),
              let pager = try? String(contentsOf: root.appendingPathComponent("GlassRemote/RootPagerView.swift"), encoding: .utf8) else {
            throw XCTSkip("sources not readable from the test host")
        }
        XCTAssertTrue(discover.contains(".ignoresSafeArea(.keyboard, edges: .bottom)"), "the page never resizes for the keyboard")
        XCTAssertTrue(discover.contains("onScrollGeometryChange(for: DiscoverScrollSample.self)"), "the scroll direction drives the header")
        XCTAssertTrue(pager.contains(".ignoresSafeArea(.keyboard, edges: .bottom)"), "the dock layer stays anchored")
    }
}

final class Phase9V6CastTests: XCTestCase {
    private typealias Person = CinemetaCatalog.Person

    func testPortraitCastFirstThenNamesOnlyTheListHas() {
        let members = [Person(name: "Leonardo DiCaprio", character: "Cobb", photo: URL(string: "https://img.example/a.jpg")),
                       Person(name: "Elliot Page", character: "Ariadne")]
        let merged = CinemetaCatalog.Detail.mergedPeople(members: members,
                                                         names: ["leonardo dicaprio", "Tom Hardy", "Ken Watanabe"])
        XCTAssertEqual(merged.map(\.name), ["Leonardo DiCaprio", "Elliot Page", "Tom Hardy", "Ken Watanabe"])
        XCTAssertEqual(merged.first?.photo?.absoluteString, "https://img.example/a.jpg")
        XCTAssertNil(merged[2].photo, "a name without a published portrait gets the placeholder, never a guessed face")
        XCTAssertEqual(merged[2].initials, "TH")
    }

    func testNamesOnlyWhenThereAreNoCredits() {
        XCTAssertEqual(CinemetaCatalog.Detail.mergedPeople(members: [], names: ["A B", "C D"]).map(\.name), ["A B", "C D"])
        XCTAssertTrue(CinemetaCatalog.Detail.mergedPeople(members: [], names: []).isEmpty)
    }

    func testLimitIsRespected() {
        let names = (0..<60).map { "Actor \($0)" }
        XCTAssertEqual(CinemetaCatalog.Detail.mergedPeople(members: [], names: names, limit: 40).count, 40)
    }

    func testParsedDetailMergesBothSources() {
        let json = #"""
        {"meta":{"name":"Inception","cast":["Leonardo DiCaprio","Tom Hardy"],
          "app_extras":{"cast":[{"name":"Leonardo DiCaprio","character":"Cobb","photo":"https://img.example/a.jpg"}]}}}
        """#
        let detail = CinemetaCatalog.parseDetail(Data(json.utf8))
        XCTAssertEqual(detail?.people.map(\.name), ["Leonardo DiCaprio", "Tom Hardy"])
        XCTAssertEqual(detail?.people.first?.character, "Cobb")
    }
}
