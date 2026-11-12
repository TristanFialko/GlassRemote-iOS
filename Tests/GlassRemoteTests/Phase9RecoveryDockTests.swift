import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 9 recovery §2: the dock's moving Liquid Glass bubble is back. The dock is the shared
/// `GlassScrubSelector` in its dock role: three pages, release-to-commit, the accent on the selected
/// icon (never an accent-filled bubble), refraction confined to the bar on both axes, and a rigid
/// bubble with Reduce Motion.
final class Phase9RecoveryDockTests: XCTestCase {
    /// A 393 pt wide iPhone in portrait, minus the dock's side insets.
    private let portraitDock: CGFloat = 393 - DockMetrics.sideInset * 2
    private let count = AppPage.allCases.count

    private struct Bar {
        let vertical: Bool
        let length: CGFloat
        let thickness: CGFloat
        let inset: CGFloat
        var segment: CGFloat { ScrubGeometry.segment(length: length, inset: inset, count: AppPage.allCases.count) }
        var rect: CGRect { CGRect(x: 0, y: 0, width: vertical ? thickness : length, height: vertical ? length : thickness) }
    }

    private var bars: [Bar] {
        [Bar(vertical: false, length: portraitDock, thickness: DockMetrics.height, inset: DockMetrics.itemInset),
         Bar(vertical: true, length: DockMetrics.railLength(count: count), thickness: DockMetrics.railWidth,
             inset: DockMetrics.railInset)]
    }

    func testDockKeepsThreeDestinationsInOrder() {
        XCTAssertEqual(AppPage.allCases, [.remote, .discover, .profile])
    }

    func testEachRestingBubbleMapsToItsPageOnBothAxes() {
        for bar in bars {
            XCTAssertGreaterThanOrEqual(bar.segment, DockMetrics.minimumTouchTarget, "vertical: \(bar.vertical)")
            for i in 0..<count {
                let rest = bar.inset + bar.segment * CGFloat(i)
                XCTAssertEqual(ScrubGeometry.index(forOffset: rest, inset: bar.inset, segment: bar.segment, count: count), i)
                // The centre crossing a midpoint is what moves the highlight to the next page.
                if i + 1 < count {
                    let pastMidpoint = rest + bar.segment * 0.51
                    XCTAssertEqual(ScrubGeometry.index(forOffset: pastMidpoint, inset: bar.inset, segment: bar.segment, count: count), i + 1)
                }
            }
        }
        XCTAssertEqual(bars[1].segment, DockMetrics.railSegment, accuracy: 0.001, "the rail's segments are the rail tiles")
    }

    func testRestingLensGeometryOnBothAxes() {
        let h = bars[0], v = bars[1]
        let portrait = ScrubGeometry.lensRect(offset: h.inset, segment: h.segment, thickness: h.thickness, inset: h.inset,
                                              vertical: false, along: 1, across: 1)
        XCTAssertEqual(portrait.minX, h.inset, accuracy: 0.001)
        XCTAssertEqual(portrait.width, h.segment, accuracy: 0.001)
        XCTAssertEqual(portrait.minY, h.inset, accuracy: 0.001)
        XCTAssertEqual(portrait.height, h.thickness - h.inset * 2, accuracy: 0.001)

        let rail = ScrubGeometry.lensRect(offset: v.inset, segment: v.segment, thickness: v.thickness, inset: v.inset,
                                          vertical: true, along: 1, across: 1)
        XCTAssertEqual(rail.minY, v.inset, accuracy: 0.001)
        XCTAssertEqual(rail.height, v.segment, accuracy: 0.001)
        XCTAssertEqual(rail.minX, v.inset, accuracy: 0.001)
        XCTAssertEqual(rail.width, v.thickness - v.inset * 2, accuracy: 0.001)
    }

    func testRefractionNeverLeavesTheBar() {
        let scale = ScrubGeometry.lensScale(dragging: true, speed: 100_000, reduceMotion: false)
        for bar in bars {
            let tolerant = bar.rect.insetBy(dx: -0.001, dy: -0.001)
            for raw in stride(from: CGFloat(-200), through: bar.length + 200, by: 7) {
                let offset = ScrubGeometry.clamp(raw, inset: bar.inset, length: bar.length, segment: bar.segment)
                let lens = ScrubGeometry.lensRect(offset: offset, segment: bar.segment, thickness: bar.thickness,
                                                  inset: bar.inset, vertical: bar.vertical,
                                                  along: scale.along, across: scale.across)
                XCTAssertTrue(tolerant.contains(ScrubGeometry.boundedLens(lens, in: bar.rect)),
                              "vertical: \(bar.vertical), offset \(offset)")
            }
            // Without the clip, a lifted, stretched bubble on the first page overhangs the end cap.
            let end = ScrubGeometry.lensRect(offset: bar.inset, segment: bar.segment, thickness: bar.thickness,
                                             inset: bar.inset, vertical: bar.vertical,
                                             along: scale.along, across: scale.across)
            XCTAssertFalse(bar.rect.contains(end), "the clip is what keeps the refraction inside (vertical: \(bar.vertical))")
        }
        let outside = ScrubGeometry.boundedLens(CGRect(x: 500, y: 500, width: 10, height: 10),
                                                in: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(outside.width, 0)
        XCTAssertEqual(outside.height, 0)
        XCTAssertLessThan(outside.width, RefractionPolicy.minimumSide, "a lens outside the bar switches refraction off")
    }

    func testReleaseCommitsNearTheBarAndCancelsWellAway() {
        let t = DockMetrics.height
        XCTAssertTrue(ScrubGeometry.releaseCommits(cross: t / 2, thickness: t))
        XCTAssertTrue(ScrubGeometry.releaseCommits(cross: -20, thickness: t), "a finger drifting slightly off still commits")
        XCTAssertTrue(ScrubGeometry.releaseCommits(cross: t + ScrubGeometry.releaseSlop, thickness: t))
        XCTAssertFalse(ScrubGeometry.releaseCommits(cross: -ScrubGeometry.releaseSlop - 1, thickness: t))
        XCTAssertFalse(ScrubGeometry.releaseCommits(cross: t + 120, thickness: t))
        XCTAssertGreaterThanOrEqual(ScrubGeometry.releaseSlop, DockMetrics.minimumTouchTarget)
    }

    func testReduceMotionKeepsTheBubbleRigid() {
        let reduced = ScrubGeometry.lensScale(dragging: true, speed: 5000, reduceMotion: true)
        XCTAssertEqual(reduced.along, 1)
        XCTAssertEqual(reduced.across, 1)
        let resting = ScrubGeometry.lensScale(dragging: false, speed: 5000, reduceMotion: false)
        XCTAssertEqual(resting.along, 1)
        XCTAssertEqual(resting.across, 1)
        let moving = ScrubGeometry.lensScale(dragging: true, speed: 5000, reduceMotion: false)
        XCTAssertEqual(moving.along, 1.10 * ScrubGeometry.stretch(speed: 5000), accuracy: 0.0001)
        XCTAssertGreaterThan(moving.along, 1.10)
        XCTAssertLessThan(moving.across, moving.along, "the stretch thins the bubble across the bar")
    }

    func testSelectedIconTakesTheAccentAndOthersStayMuted() {
        var sawAccent = false
        for id in ThemeID.allCases where id != .adaptive && id != .auto {
            let theme = GlassTheme.base(for: id, systemScheme: .dark)
            XCTAssertEqual(DockStyle.iconInk(selected: true, theme: theme), DockStyle.selectedInk(theme), "\(id)")
            XCTAssertEqual(DockStyle.iconInk(selected: false, theme: theme), theme.dockInkInactive, "\(id)")
            if DockStyle.selectedInk(theme) == theme.accent { sawAccent = true }
        }
        XCTAssertTrue(sawAccent, "legible accents reach the selected dock icon")
    }

    func testNoPageIsMarkedSelectedUnderTheFullPlayer() {
        XCTAssertTrue(DockStyle.showsSelection(highlighted: true, playerPresented: false))
        XCTAssertFalse(DockStyle.showsSelection(highlighted: true, playerPresented: true))
        XCTAssertFalse(DockStyle.showsSelection(highlighted: false, playerPresented: false))
    }

    /// The dock's commit goes through `navigator.go`: a new page switches; the page already under the
    /// full player closes the player and stays put.
    @MainActor func testCommitGoesThroughTheNavigator() {
        let nav = PageNavigator()
        nav.go(.remote, haptic: false)
        nav.go(.discover, haptic: false)
        XCTAssertEqual(nav.page, .discover)
        nav.openPlayer(haptic: false)
        XCTAssertTrue(nav.playerPresented)
        nav.go(.discover, haptic: false)
        XCTAssertFalse(nav.playerPresented)
        XCTAssertEqual(nav.page, .discover)
    }

    // MARK: Source guards

    private func source(_ path: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(path)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw XCTSkip("sources not readable from the test host")
        }
        return text
    }

    func testDockIsTheSharedGlassSelectorCommittingOnRelease() throws {
        let text = try source("GlassRemote/RootPagerView.swift")
        let start = try XCTUnwrap(text.range(of: "struct PageDock: View"))
        let end = try XCTUnwrap(text.range(of: "private struct DockIcon", range: start.upperBound..<text.endIndex))
        let dock = String(text[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(dock.contains("GlassScrubSelector("), "the moving bubble comes from the shared selector")
        XCTAssertTrue(dock.contains("role: .dock"), "dock scrim, edge and sheen")
        XCTAssertTrue(dock.contains("axis: axis"), "the same dock drives the landscape rail")
        XCTAssertTrue(dock.contains("commitOnRelease: true"))
        XCTAssertTrue(dock.contains("navigator.go($0)"))
        XCTAssertTrue(dock.contains("DockStyle.iconInk("))
        XCTAssertTrue(dock.contains(".accessibilityLabel(item.title)"), "label-free icons keep their names for VoiceOver")
        XCTAssertFalse(dock.contains(".glassLens("), "no extra accent lens on top of the selector's clear bubble")
        // Now Playing wiring around the dock is untouched.
        XCTAssertTrue(text.contains("NowPlayingMiniPlayer()"))
        XCTAssertTrue(text.contains("NowPlayingRailTile()"))
    }

    func testSelectorRefractionIsClippedToTheBar() throws {
        let style = try source("GlassRemote/GlassStyle.swift")
        XCTAssertTrue(style.contains("ScrubGeometry.boundedLens("))
        XCTAssertTrue(style.contains(".refractiveLens(lensRect, cornerRadius: .infinity, style: .selector)"))
        XCTAssertTrue(style.contains("DockSheen(progress: progress"), "the dock's moving sheen is drawn")
    }
}
