import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 9 continuation §A: Apps folder refinements (no close button, search, fixed 3 × 3 grid with
/// scaling tiles, faster motion, cached catalogue).
final class Phase9FolderRefinementTests: XCTestCase {

    private let screens: [(CGSize, Bool)] = [
        (CGSize(width: 320, height: 568), false),   // iPhone SE (1st generation)
        (CGSize(width: 375, height: 667), false),
        (CGSize(width: 393, height: 852), false),
        (CGSize(width: 440, height: 956), false),
        (CGSize(width: 568, height: 320), true),
        (CGSize(width: 667, height: 375), true),
        (CGSize(width: 700, height: 340), true),
        (CGSize(width: 852, height: 393), true),
        (CGSize(width: 956, height: 440), true)
    ]

    private func anchor(for size: CGSize, landscape: Bool) -> CGRect {
        landscape ? CGRect(x: 0, y: size.height - 70, width: 170, height: 58)
                  : CGRect(x: size.width / 2 - 30, y: size.height - 120, width: 60, height: 58)
    }

    // MARK: A3 grid

    func testGridIsAlwaysThreeColumnsAndFitsEveryScreen() {
        for (size, landscape) in screens {
            for count in [0, 1, 8, 9, 12, 40] {
                for banner in [false, true] {
                    let label = "\(size) landscape=\(landscape) apps=\(count) banner=\(banner)"
                    let p = AppsFolderLayout.placement(container: size, anchor: anchor(for: size, landscape: landscape),
                                                       isLandscape: landscape, appCount: count, showsBanner: banner)
                    XCTAssertEqual(AppsFolderLayout.columns(folderWidth: p.frame.width), 3, label)
                    XCTAssertEqual(AppLauncherPolicy.columns(for: p.frame.width), 3, label)
                    XCTAssertLessThanOrEqual(p.metrics.gridWidth, p.frame.width - AppsFolderLayout.inset * 2 + 0.001, label)
                    XCTAssertGreaterThanOrEqual(p.metrics.tileSide, 44 - 0.001, "tiles stay touchable: \(label)")
                    XCTAssertLessThanOrEqual(p.metrics.scale, 1, label)
                    XCTAssertEqual(p.metrics.columnWidth * 3, p.metrics.gridWidth, accuracy: 0.001, label)
                    assertInsideMargins(p.frame, size, label)
                }
            }
        }
    }

    func testNineAppsFitWithoutScrollingAndExtraRowsScroll() {
        let size = CGSize(width: 393, height: 852)
        let key = anchor(for: size, landscape: false)
        let nine = AppsFolderLayout.placement(container: size, anchor: key, isLandscape: false, appCount: 9, showsBanner: false)
        let twelve = AppsFolderLayout.placement(container: size, anchor: key, isLandscape: false, appCount: 12, showsBanner: false)
        XCTAssertFalse(nine.scrolls)
        XCTAssertEqual(nine.metrics.scale, 1)
        XCTAssertTrue(twelve.scrolls, "a fourth row scrolls instead of growing the folder")
        XCTAssertEqual(twelve.frame.height, nine.frame.height)
        XCTAssertEqual(AppsFolderLayout.rows(appCount: 12), 4)
        XCTAssertEqual(AppsFolderLayout.rows(appCount: 0), 1)
    }

    func testShortScreensScaleTilesBeforeTheGridChanges() {
        let landscape = AppsFolderLayout.placement(container: CGSize(width: 700, height: 340),
                                                   anchor: CGRect(x: 0, y: 270, width: 180, height: 58),
                                                   isLandscape: true, appCount: 9, showsBanner: false)
        XCTAssertLessThan(landscape.metrics.scale, 1)
        XCTAssertGreaterThanOrEqual(landscape.metrics.scale, AppsFolderLayout.minimumScale)
        XCTAssertFalse(landscape.scrolls, "three rows still fit once the tiles shrink")

        let tiny = AppsFolderLayout.placement(container: CGSize(width: 568, height: 320),
                                              anchor: CGRect(x: 0, y: 250, width: 170, height: 58),
                                              isLandscape: true, appCount: 24, showsBanner: true)
        XCTAssertEqual(tiny.metrics.scale, AppsFolderLayout.minimumScale, accuracy: 0.0001)
        XCTAssertTrue(tiny.scrolls)
        XCTAssertEqual(tiny.frame.height, AppsFolderLayout.heightCap(container: CGSize(width: 568, height: 320), isLandscape: true))
    }

    func testRotationMidTransitionRecomputesAValidFrame() {
        var folder = AppsFolderState()
        let g = folder.open()!
        let portrait = AppsFolderLayout.frame(container: CGSize(width: 393, height: 852),
                                              anchor: anchor(for: CGSize(width: 393, height: 852), landscape: false),
                                              isLandscape: false, appCount: 12, showsBanner: false)
        // The device rotates before the open animation finishes: the frame follows the new
        // container and anchor; the lifecycle is untouched and still settles.
        let landscape = AppsFolderLayout.frame(container: CGSize(width: 852, height: 393),
                                               anchor: anchor(for: CGSize(width: 852, height: 393), landscape: true),
                                               isLandscape: true, appCount: 12, showsBanner: false)
        assertInsideMargins(portrait, CGSize(width: 393, height: 852), "portrait")
        assertInsideMargins(landscape, CGSize(width: 852, height: 393), "landscape")
        folder.settle(g)
        XCTAssertEqual(folder.phase, .open)
    }

    // MARK: A1 dismissal without a close button

    func testThereIsNoCloseButtonButEveryInputCanDismiss() {
        XCTAssertEqual(Set(AppsFolderState.DismissReason.allCases),
                       [.outsideTap, .swipe, .escape, .launched, .contextChanged])
        XCTAssertFalse(AppsFolderInteraction.touchDismissals.isEmpty)
        XCTAssertTrue(AppsFolderInteraction.keyboardDismissals.contains(.escape))
        XCTAssertTrue(AppsFolderInteraction.voiceOverDismissals.contains(.escape))
        for reason in AppsFolderState.DismissReason.allCases {
            var folder = AppsFolderState()
            folder.settle(folder.open()!)
            folder.settle(folder.dismiss(reason)!)
            XCTAssertEqual(folder.phase, .closed, "\(reason)")
            XCTAssertFalse(folder.highlightsSource, "\(reason)")
            XCTAssertEqual(folder.lastDismissal, reason)
        }
    }

    func testRapidTapsNeverStrandTheFolderOrItsHighlight() {
        var folder = AppsFolderState()
        var pending: [Int] = []
        for i in 0..<12 {
            if i.isMultiple(of: 2) { if let g = folder.open() { pending.append(g) } }
            else { if let g = folder.dismiss(.outsideTap) { pending.append(g) } }
        }
        // Completions arrive late and out of order: only the latest one counts.
        for g in pending.shuffled() { folder.settle(g) }
        XCTAssertEqual(folder.phase, .closed)
        XCTAssertFalse(folder.highlightsSource)
        XCTAssertNotNil(folder.open())
        XCTAssertTrue(folder.highlightsSource, "highlighted only while visible")
        folder.reset()
        XCTAssertFalse(folder.highlightsSource)
    }

    // MARK: A2 search

    private let apps = [
        TVApp(name: "Netflix", package: "com.netflix.ninja", asset: "netflix"),
        TVApp(name: "Disney+", package: "com.disney.disneyplus", asset: "disney"),
        TVApp(name: "Pokémon TV", package: "com.pokemon.pokemontv", asset: "pokemon"),
        TVApp(name: "YouTube", package: "com.google.android.youtube.tv", asset: "youtube"),
        TVApp(name: "YouTube Kids", package: "com.google.android.youtube.tvkids", asset: "youtubekids")
    ]

    func testSearchIsCaseAndDiacriticInsensitiveWithFavouritesFirst() {
        let favs = ["com.google.android.youtube.tvkids"]
        XCTAssertEqual(AppLauncherPolicy.visible(apps, favourites: favs, query: "POKEMON").map(\.package),
                       ["com.pokemon.pokemontv"])
        XCTAssertEqual(AppLauncherPolicy.visible(apps, favourites: favs, query: "youtube").map(\.package),
                       ["com.google.android.youtube.tvkids", "com.google.android.youtube.tv"])
        XCTAssertEqual(AppLauncherPolicy.visible(apps, favourites: favs, query: "   ").count, apps.count)
        XCTAssertEqual(AppLauncherPolicy.visible(apps, favourites: favs, query: "").first?.package,
                       "com.google.android.youtube.tvkids")
        XCTAssertEqual(AppLauncherPolicy.visible(apps, favourites: favs, query: "you").map(\.package),
                       AppLauncherPolicy.filtered(AppLauncherPolicy.ordered(apps, favourites: favs), query: "you").map(\.package))
    }

    func testEmptyStatesAndClearing() {
        XCTAssertEqual(AppLauncherPolicy.emptyMessage(visibleCount: 0, query: ""), "No apps")
        XCTAssertEqual(AppLauncherPolicy.emptyMessage(visibleCount: 0, query: " zz "), "No apps match “zz”")
        XCTAssertNil(AppLauncherPolicy.emptyMessage(visibleCount: 3, query: "you"))
        // Clearing the query restores the whole catalogue.
        XCTAssertTrue(AppLauncherPolicy.visible(apps, favourites: [], query: "zz").isEmpty)
        XCTAssertEqual(AppLauncherPolicy.visible(apps, favourites: [], query: "").count, apps.count)
    }

    func testSearchNeverLaunchesOrDismissesByAccident() {
        XCTAssertEqual(AppsFolderInteraction.outsideTap(searchFocused: true), .endSearch)
        XCTAssertEqual(AppsFolderInteraction.outsideTap(searchFocused: false), .dismiss)
        XCTAssertFalse(AppsFolderInteraction.submitLaunchesFirstMatch)
        var folder = AppsFolderState()
        _ = folder.open()
        XCTAssertFalse(folder.acceptsLaunch, "a tile tapped while the folder is still opening does nothing")
    }

    // MARK: A4 motion

    func testFolderMotionIsFasterAndHonoursReduceMotion() {
        XCTAssertLessThan(AppsFolderMotion.openResponse, AppsFolderMotion.previousOpenResponse)
        XCTAssertLessThan(AppsFolderMotion.closeResponse, AppsFolderMotion.previousCloseResponse)
        XCTAssertLessThan(AppsFolderMotion.closeResponse, AppsFolderMotion.openResponse)
        XCTAssertLessThan(AppsFolderMotion.openDamping, 1, "the open keeps a tactile spring")
        XCTAssertGreaterThan(AppsFolderMotion.closeDamping, AppsFolderMotion.openDamping, "the close does not bounce")
        XCTAssertTrue(AppsFolderMotion.morphs(reduceMotion: false))
        XCTAssertFalse(AppsFolderMotion.morphs(reduceMotion: true), "Reduce Motion cross-fades in place")
        XCTAssertEqual(AppsFolderMotion.contentScale(expanded: false, reduceMotion: true), 1)
        XCTAssertEqual(AppsFolderMotion.contentScale(expanded: false, reduceMotion: false),
                       AppsFolderMotion.collapsedContentScale)
        XCTAssertEqual(AppsFolderMotion.contentScale(expanded: true, reduceMotion: false), 1)
        XCTAssertLessThan(AppsFolderMotion.reducedDuration, 0.2)
    }

    private func assertInsideMargins(_ frame: CGRect, _ container: CGSize, _ label: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let m = AppsFolderLayout.margin - 0.001
        XCTAssertGreaterThanOrEqual(frame.minX, m, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, m, label, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, container.width - m, label, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, container.height - m, label, file: file, line: line)
    }
}
