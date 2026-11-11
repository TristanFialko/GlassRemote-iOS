import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 9 §1–§2: icon-only Remote keys, the landscape Remote redesign and the expanding Apps folder.
final class Phase9RemoteTests: XCTestCase {

    // MARK: §1.1 icon-only keys

    func testNavigationKeysAreIconOnlyWithUniqueNamesAndSymbols() {
        XCTAssertFalse(RemoteNavKey.showsCaptions)
        let keys = RemoteNavKey.allCases
        XCTAssertEqual(Set(keys.map(\.title)).count, keys.count)
        XCTAssertEqual(Set(keys.map(\.symbol)).count, keys.count)
        for key in keys {
            XCTAssertFalse(key.title.isEmpty, "\(key) needs a VoiceOver name")
            XCTAssertFalse(key.hint.isEmpty, "\(key) needs a VoiceOver hint")
        }
        XCTAssertEqual(RemoteNavKey.apps.symbol, "square.grid.2x2.fill")
    }

    func testSamsungKeysCaptionOnlyTheChannelKeys() {
        XCTAssertEqual(SamsungRemoteLayout.caption(for: .channelUp), "Ch +")
        XCTAssertEqual(SamsungRemoteLayout.caption(for: .channelDown), "Ch \u{2212}")
        for key in SamsungKey.allCases where key != .channelUp && key != .channelDown {
            XCTAssertNil(SamsungRemoteLayout.caption(for: key), "\(key) should be icon-only")
        }
    }

    // MARK: §1.2 landscape stage

    func testLandscapePadNeverDropsBelowItsMinimum() {
        for width in [454, 520, 568, 620, 700, 760, 844, 932, 1100] as [CGFloat] {
            let c = RemoteLayoutPolicy.columnWidths(for: width)
            let pad = width - c.leading - c.trailing - RemoteLayoutPolicy.stageColumnSpacing * 2
            XCTAssertGreaterThanOrEqual(pad + 0.001, RemoteLayoutPolicy.landscapePadMinWidth, "width \(width)")
            XCTAssertLessThanOrEqual(c.leading + c.trailing, width * 0.6 + 0.001, "width \(width)")
            XCTAssertGreaterThan(c.leading, 0)
            XCTAssertGreaterThan(c.trailing, 0)
        }
    }

    func testAndroidAndSamsungPadsShareOneFrame() {
        for height in [300, 340, 380] as [CGFloat] {
            // Android: header, mode and the Apps card on the left; navigation on the right; volume in the deck.
            let android = RemoteStageLayout.frames(width: 812, height: height,
                                                   leading: [96, 40, 58], leadingBottom: [false, false, true],
                                                   trailing: [114], trailingBottom: [false],
                                                   hasPad: true, spacing: 10, columnSpacing: 14,
                                                   reservesColumns: true, deck: true)
            // Samsung: header and its navigation row; transport and the TV group; volume in the deck.
            let samsung = RemoteStageLayout.frames(width: 812, height: height,
                                                   leading: [96, 52], leadingBottom: [false, true],
                                                   trailing: [52, 52], trailingBottom: [false, true],
                                                   hasPad: true, spacing: 10, columnSpacing: 14,
                                                   reservesColumns: true, deck: true)
            XCTAssertEqual(android.pad, samsung.pad, "height \(height)")
            XCTAssertEqual(android.deck, samsung.deck, "height \(height)")
            // A sparse stage (one empty column) keeps the same pad when columns are reserved.
            let sparse = RemoteStageLayout.frames(width: 812, height: height,
                                                  leading: [96], leadingBottom: [false],
                                                  trailing: [], trailingBottom: [],
                                                  hasPad: true, spacing: 10, columnSpacing: 14,
                                                  reservesColumns: true, deck: true)
            XCTAssertEqual(sparse.pad, android.pad)
            XCTAssertEqual(RemoteStageLayout.padRect(width: 812, height: height), android.pad)
        }
    }

    func testStatusPillShortensBeforeItTruncates() {
        XCTAssertEqual(RemoteLayoutPolicy.pillStyle(width: 240), .full)
        XCTAssertEqual(RemoteLayoutPolicy.pillStyle(width: 180), .full)
        XCTAssertEqual(RemoteLayoutPolicy.pillStyle(width: 179), .short)
        XCTAssertEqual(RemoteLayoutPolicy.pillStyle(width: 150), .short)
        XCTAssertEqual(RemoteLayoutPolicy.pillStyle(width: 149), .compact)
    }

    func testLauncherCardShowsOnlyThePreviewsThatFit() {
        XCTAssertLessThan(RemoteLayoutPolicy.launcherCardRequiredWidth(previews: 0),
                          RemoteLayoutPolicy.launcherCardRequiredWidth(previews: 1))
        XCTAssertEqual(RemoteLayoutPolicy.launcherPreviewCount(cardWidth: 280), 3)
        let three = RemoteLayoutPolicy.launcherCardRequiredWidth(previews: 3)
        XCTAssertEqual(RemoteLayoutPolicy.launcherPreviewCount(cardWidth: three), 3)
        XCTAssertEqual(RemoteLayoutPolicy.launcherPreviewCount(cardWidth: three - 1), 2)
        XCTAssertEqual(RemoteLayoutPolicy.launcherPreviewCount(cardWidth: 40), 0)
        for width: CGFloat in stride(from: 60, through: 300, by: 10) {
            let n = RemoteLayoutPolicy.launcherPreviewCount(cardWidth: width)
            XCTAssertLessThanOrEqual(RemoteLayoutPolicy.launcherCardRequiredWidth(previews: n), max(width, 82))
        }
        XCTAssertEqual(RemoteLayoutPolicy.appCountLabel(0), "No apps")
        XCTAssertEqual(RemoteLayoutPolicy.appCountLabel(1), "1 app")
        XCTAssertEqual(RemoteLayoutPolicy.appCountLabel(9), "9 apps")
    }

    // MARK: §2 folder lifecycle

    func testFolderOpensSettlesAndCloses() {
        var folder = AppsFolderState()
        XCTAssertFalse(folder.isVisible)
        XCTAssertFalse(folder.highlightsSource)
        let opening = folder.open()
        XCTAssertNotNil(opening)
        XCTAssertEqual(folder.phase, .opening)
        XCTAssertTrue(folder.highlightsSource)
        XCTAssertFalse(folder.acceptsLaunch, "no launches mid-animation")
        XCTAssertNil(folder.open(), "already opening")
        folder.settle(opening!)
        XCTAssertEqual(folder.phase, .open)
        XCTAssertTrue(folder.acceptsLaunch)
        XCTAssertTrue(folder.blocksOutside)
        let closing = folder.dismiss(.outsideTap)
        XCTAssertNotNil(closing)
        XCTAssertEqual(folder.phase, .closing)
        XCTAssertFalse(folder.acceptsLaunch)
        XCTAssertFalse(folder.blocksOutside, "the Remote is usable again during the close")
        XCTAssertNil(folder.dismiss(.swipe), "a second dismissal is ignored")
        folder.settle(closing!)
        XCTAssertEqual(folder.phase, .closed)
        XCTAssertFalse(folder.highlightsSource)
        XCTAssertEqual(folder.lastDismissal, .outsideTap)
    }

    func testStaleCompletionCannotStrandTheFolder() {
        var folder = AppsFolderState()
        let opening = folder.open()!
        let closing = folder.dismiss(.swipe)!          // closed before it finished opening
        folder.settle(opening)                          // the open animation's late completion
        XCTAssertEqual(folder.phase, .closing)
        let reopening = folder.open()!                  // reopened while it collapses
        folder.settle(closing)
        XCTAssertEqual(folder.phase, .opening)
        folder.settle(reopening)
        XCTAssertEqual(folder.phase, .open)
    }

    func testEveryDismissPathEndsClosedAndUnhighlighted() {
        let reasons: [AppsFolderState.DismissReason] = [.outsideTap, .swipe, .escape, .launched]
        for reason in reasons {
            var folder = AppsFolderState()
            folder.settle(folder.open()!)
            let g = folder.dismiss(reason)!
            folder.settle(g)
            XCTAssertEqual(folder.phase, .closed, "\(reason)")
            XCTAssertFalse(folder.highlightsSource, "\(reason)")
            XCTAssertEqual(folder.lastDismissal, reason)
        }
        var folder = AppsFolderState()
        let g = folder.open()!
        folder.reset()
        XCTAssertEqual(folder.phase, .closed)
        XCTAssertEqual(folder.lastDismissal, .contextChanged)
        folder.settle(g)
        XCTAssertEqual(folder.phase, .closed, "a completion after a reset is ignored")
    }

    // MARK: §2 folder geometry

    func testPortraitFolderSitsAboveTheAppsKeyInsideTheMargins() {
        let container = CGSize(width: 393, height: 700)
        let key = CGRect(x: 160, y: 560, width: 60, height: 58)
        let frame = AppsFolderLayout.frame(container: container, anchor: key, isLandscape: false,
                                           appCount: 9, showsBanner: false)
        // Continuation §A3: a compact 3 × 3 folder at full tile size.
        XCTAssertEqual(frame.width, 320)
        XCTAssertEqual(AppsFolderLayout.columns(folderWidth: frame.width), 3)
        XCTAssertEqual(frame.height, 372)
        XCTAssertEqual(frame.minX, 30)
        XCTAssertEqual(frame.minY, 178)
        XCTAssertLessThanOrEqual(frame.maxY, key.minY - AppsFolderLayout.gap + 0.001)
        assertInsideMargins(frame, container)
        XCTAssertLessThanOrEqual(frame.height, container.height * AppsFolderLayout.portraitHeightShare)
    }

    func testLandscapeFolderOpensBesideTheLauncherCard() {
        let container = CGSize(width: 700, height: 340)
        let card = CGRect(x: 0, y: 270, width: 180, height: 58)
        let frame = AppsFolderLayout.frame(container: container, anchor: card, isLandscape: true,
                                           appCount: 9, showsBanner: false)
        XCTAssertEqual(frame.width, 340)
        XCTAssertEqual(frame.minX, 190)
        XCTAssertEqual(frame.minY, 12, accuracy: 0.01)
        XCTAssertEqual(frame.height, 316, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(frame.minX, card.maxX)
        assertInsideMargins(frame, container)

        let small = CGSize(width: 568, height: 320)
        let smallFrame = AppsFolderLayout.frame(container: small, anchor: CGRect(x: 0, y: 250, width: 170, height: 58),
                                                isLandscape: true, appCount: 24, showsBanner: true)
        assertInsideMargins(smallFrame, small)
    }

    func testFolderWithoutAnAnchorIsCentredAndAnEmptyFolderKeepsItsMinimum() {
        let container = CGSize(width: 393, height: 700)
        let frame = AppsFolderLayout.frame(container: container, anchor: .zero, isLandscape: false,
                                           appCount: 9, showsBanner: false)
        XCTAssertEqual(frame.midX, container.width / 2, accuracy: 0.5)
        XCTAssertEqual(frame.midY, container.height / 2, accuracy: 0.5)
        XCTAssertEqual(AppsFolderLayout.collapsedFrame(anchor: .zero, container: container).width, 56)

        let empty = AppsFolderLayout.placement(container: container, anchor: CGRect(x: 160, y: 560, width: 60, height: 58),
                                               isLandscape: false, appCount: 0, showsBanner: false)
        let minimum = AppsFolderLayout.inset * 2 + AppsFolderLayout.chromeHeight + empty.metrics.rowHeight
        XCTAssertEqual(empty.frame.height, minimum)
        XCTAssertEqual(empty.metrics.scale, 1)
    }

    func testSwipeToDismissThresholds() {
        XCTAssertTrue(AppsFolderGesture.shouldDismiss(translation: 95, predicted: 0))
        XCTAssertTrue(AppsFolderGesture.shouldDismiss(translation: 40, predicted: 250))
        XCTAssertFalse(AppsFolderGesture.shouldDismiss(translation: 40, predicted: 120))
        XCTAssertEqual(AppsFolderGesture.offset(for: 50), 50)
        XCTAssertEqual(AppsFolderGesture.offset(for: -400), -24)
        XCTAssertLessThan(AppsFolderGesture.offset(for: -4), 0)
    }

    func testFolderKeepsFavouritesFirstWhileSearching() {
        let apps = [
            TVApp(name: "Netflix", package: "com.netflix.ninja", asset: "netflix"),
            TVApp(name: "Disney+", package: "com.disney.disneyplus", asset: "disney"),
            TVApp(name: "YouTube", package: "com.google.android.youtube.tv", asset: "youtube"),
            TVApp(name: "YouTube Kids", package: "com.google.android.youtube.tvkids", asset: "youtubekids")
        ]
        let ordered = AppLauncherPolicy.ordered(apps, favourites: ["com.google.android.youtube.tvkids"])
        let found = AppLauncherPolicy.filtered(ordered, query: "you")
        XCTAssertEqual(found.map(\.package), ["com.google.android.youtube.tvkids", "com.google.android.youtube.tv"])
    }

    private func assertInsideMargins(_ frame: CGRect, _ container: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let m = AppsFolderLayout.margin - 0.001
        XCTAssertGreaterThanOrEqual(frame.minX, m, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, m, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, container.width - m, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, container.height - m, file: file, line: line)
    }
}
