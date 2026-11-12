import SwiftUI
import XCTest
@testable import GlassRemote

/// v5 §2: the three-tab dock, fade-only page switching, the mini-player and the Now Playing
/// presentation over the pages.
final class Phase9DockTests: XCTestCase {

    private func media(state: Int, sampledAt: Date = Date(), title: String = "Dune",
                       package: String = "com.stremio.one") -> MediaState {
        MediaState(package: package, title: title, state: state, positionMs: 0, speed: 1, sampledAt: sampledAt, actions: 0)
    }

    // MARK: Pages

    func testThreePagesInDockOrder() {
        XCTAssertEqual(AppPage.allCases, [.remote, .discover, .profile])
        XCTAssertEqual(AppPage.landing, .remote)
        XCTAssertEqual(AppPage.allCases.map(\.title), ["Remote", "Discover", "Profile"])
        for page in AppPage.allCases {
            XCTAssertFalse(page.symbol(selected: true).isEmpty)
            XCTAssertFalse(page.symbol(selected: false).isEmpty)
        }
        XCTAssertFalse(AppPage.playerSymbolOutline.isEmpty, "Now Playing keeps its glyph for fallbacks")
    }

    func testTabSwitchIsAShortFadeThatNeverMovesPages() {
        XCTAssertGreaterThan(TabSwitchPolicy.fadeDuration, 0)
        XCTAssertLessThanOrEqual(TabSwitchPolicy.fadeDuration, 0.2)
        XCTAssertEqual(TabSwitchPolicy.pageOffset, .zero)
        for current in AppPage.allCases {
            for item in AppPage.allCases {
                XCTAssertEqual(TabSwitchPolicy.opacity(of: item, current: current, playerPresented: false), item == current ? 1 : 0)
                XCTAssertEqual(TabSwitchPolicy.isVisible(item, current: current, playerPresented: false), item == current)
                XCTAssertEqual(TabSwitchPolicy.opacity(of: item, current: current, playerPresented: true), 0,
                               "Now Playing covers every page")
                XCTAssertFalse(TabSwitchPolicy.isVisible(item, current: current, playerPresented: true))
            }
        }
    }

    func testNowPlayingPresentationIsRestrained() {
        XCTAssertLessThanOrEqual(NowPlayingPresentation.duration, 0.35)
        XCTAssertLessThanOrEqual(NowPlayingPresentation.rise, 24)
        XCTAssertEqual(NowPlayingPresentation.offset(presented: true, reduceMotion: false), 0)
        XCTAssertEqual(NowPlayingPresentation.offset(presented: false, reduceMotion: true), 0, "Reduce Motion: fade only")
        if !MotionPreference.reduced {
            XCTAssertEqual(NowPlayingPresentation.offset(presented: false, reduceMotion: false), NowPlayingPresentation.rise)
        }
    }

    // MARK: Navigator

    @MainActor func testDockSelectionClosesNowPlaying() {
        let nav = PageNavigator()
        XCTAssertEqual(nav.page, .remote)
        XCTAssertFalse(nav.playerPresented)

        nav.openPlayer(haptic: false)
        XCTAssertTrue(nav.playerPresented)
        nav.openPlayer(haptic: false)
        XCTAssertTrue(nav.playerPresented, "opening twice is one presentation")

        nav.go(.remote, haptic: false)
        XCTAssertFalse(nav.playerPresented, "the page under the player simply closes it")
        XCTAssertEqual(nav.page, .remote)

        nav.openPlayer(haptic: false)
        nav.go(.discover, haptic: false)
        XCTAssertFalse(nav.playerPresented)
        XCTAssertEqual(nav.page, .discover)

        nav.closePlayer(haptic: false)
        XCTAssertFalse(nav.playerPresented, "closing a closed player is a no-op")
        XCTAssertEqual(nav.page, .discover)
    }

    @MainActor func testOpenProfileStillRoutesThroughTheDock() {
        let nav = PageNavigator()
        nav.openPlayer(haptic: false)
        nav.openProfile()
        XCTAssertEqual(nav.page, .profile)
        XCTAssertFalse(nav.playerPresented)
    }

    // MARK: Mini-player

    func testMiniPlayerShowsOnlyForAGenuinelyActiveSession() {
        let now = Date()
        XCTAssertTrue(MiniPlayerPolicy.isVisible(media: media(state: 3, sampledAt: now), connected: true, connecting: false, now: now))
        XCTAssertTrue(MiniPlayerPolicy.isVisible(media: media(state: 2, sampledAt: now), connected: true, connecting: false, now: now))
        XCTAssertTrue(MiniPlayerPolicy.isVisible(media: media(state: 6, sampledAt: now), connected: true, connecting: false, now: now))
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: .idle, connected: true, connecting: false, now: now), "idle")
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: media(state: 3, sampledAt: now), connected: false, connecting: false, now: now),
                       "disconnected")
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: media(state: 3, sampledAt: now), connected: false, connecting: true, now: now),
                       "connecting")
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: media(state: 3, sampledAt: now.addingTimeInterval(-120)),
                                                  connected: true, connecting: false, now: now), "stale")

        for phase in [PlayerSessionPhase.playing, .paused, .buffering] { XCTAssertTrue(MiniPlayerPolicy.isVisible(phase: phase)) }
        for phase in [PlayerSessionPhase.disconnected, .connecting, .idle, .stale] { XCTAssertFalse(MiniPlayerPolicy.isVisible(phase: phase)) }

        XCTAssertTrue(MiniPlayerPolicy.isShown(sessionVisible: true, playerPresented: false))
        XCTAssertFalse(MiniPlayerPolicy.isShown(sessionVisible: true, playerPresented: true), "hidden under the full player")
        XCTAssertFalse(MiniPlayerPolicy.isShown(sessionVisible: false, playerPresented: false))
        XCTAssertLessThanOrEqual(MiniPlayerPolicy.recheckNanos, UInt64(PlayerSessionPhase.staleAfter * 1_000_000_000))
    }

    func testMiniPlayerSummary() {
        var episode = media(state: 3, title: "Dune: Part Two")
        episode.subtitle = "S1 · E2"
        let s = MiniPlayerSummary.resolve(media: episode, appName: "Stremio")
        XCTAssertEqual(s.title, "Dune: Part Two")
        XCTAssertEqual(s.detail, "S1 · E2")
        XCTAssertEqual(s.accessibilityLabel, "Now playing: Dune: Part Two, S1 · E2")

        var headline = media(state: 3, title: "raw-file-name.mkv")
        headline.headline = "Arrival"
        XCTAssertEqual(MiniPlayerSummary.resolve(media: headline, appName: nil).title, "Arrival")
        XCTAssertEqual(MiniPlayerSummary.resolve(media: headline, appName: nil).sessionTitle, "Arrival")

        XCTAssertEqual(MiniPlayerSummary.resolve(media: media(state: 3, title: "Dune"), appName: "Stremio").detail, "Stremio")
        let untitled = MiniPlayerSummary.resolve(media: media(state: 3, title: ""), appName: "YouTube")
        XCTAssertEqual(untitled.title, "YouTube")
        XCTAssertEqual(untitled.detail, "", "never repeats the title")
        XCTAssertEqual(untitled.accessibilityLabel, "Now playing: YouTube")
        XCTAssertEqual(MiniPlayerSummary.resolve(media: media(state: 3, title: "  "), appName: nil).title, "Now Playing")
    }

    // MARK: Geometry

    func testDockIsThinnerButKeepsComfortableTargets() {
        XCTAssertLessThan(DockMetrics.height, 70, "thinner than the v4 dock")
        XCTAssertGreaterThanOrEqual(DockMetrics.height, DockMetrics.minimumTouchTarget)
        XCTAssertEqual(DockMetrics.minimumTouchTarget, 44)
        XCTAssertGreaterThanOrEqual(DockMetrics.railSegment, DockMetrics.minimumTouchTarget)
        for screen in [320, 375, 393, 440] as [CGFloat] {
            let width = screen - 2 * DockMetrics.sideInset
            XCTAssertGreaterThanOrEqual(DockMetrics.itemWidth(dockWidth: width, count: AppPage.allCases.count),
                                        DockMetrics.minimumTouchTarget)
        }
        XCTAssertEqual(DockMetrics.itemWidth(dockWidth: 100, count: 0), 0)
        XCTAssertEqual(DockMetrics.railLength(count: AppPage.allCases.count), 3 * DockMetrics.railSegment + 2 * DockMetrics.railInset)
    }

    func testMiniPlayerAddsItsOwnClearance() {
        XCTAssertGreaterThanOrEqual(DockMetrics.miniPlayerHeight, DockMetrics.minimumTouchTarget)
        for inset in [0, 20, 34] as [CGFloat] {
            XCTAssertEqual(DockMetrics.clearance(safeBottom: inset, miniPlayer: false), DockMetrics.clearance(safeBottom: inset))
            XCTAssertEqual(DockMetrics.clearance(safeBottom: inset, miniPlayer: true),
                           DockMetrics.clearance(safeBottom: inset) + DockMetrics.miniPlayerHeight + DockMetrics.miniPlayerGap)
        }
    }

    func testLandscapeTileOnlyWhenItFitsBelowTheRail() {
        XCTAssertTrue(DockMetrics.railTileFits(height: 372, count: 3), "iPhone Pro landscape")
        XCTAssertTrue(DockMetrics.railTileFits(height: 354, count: 3), "iPhone mini landscape")
        XCTAssertFalse(DockMetrics.railTileFits(height: 240, count: 3))
        XCTAssertLessThanOrEqual(DockMetrics.railTileArtwork, DockMetrics.railWidth)
    }

    // MARK: Dock colour

    func testSelectedDockIconUsesTheAccentOnlyWhenLegible() {
        let vivid = ColorMath.luminance(r: 0.20, g: 0.55, b: 1.0)
        XCTAssertTrue(DockStyle.usesAccent(accentLuminance: vivid, light: false))
        let nearBlack = ColorMath.luminance(r: 0.05, g: 0.05, b: 0.06)
        XCTAssertFalse(DockStyle.usesAccent(accentLuminance: nearBlack, light: false))
        let pale = ColorMath.luminance(r: 0.95, g: 0.93, b: 0.85)
        XCTAssertFalse(DockStyle.usesAccent(accentLuminance: pale, light: true))
        let deep = ColorMath.luminance(r: 0.0, g: 0.30, b: 0.75)
        XCTAssertTrue(DockStyle.usesAccent(accentLuminance: deep, light: true))
        XCTAssertEqual(DockStyle.minimumContrast, 3.0)
        XCTAssertLessThan(DockStyle.pressedOpacity, 1)
    }

    // MARK: Adaptive theme

    @MainActor func testAdaptiveArtworkFollowsNowPlayingWhenPresented() {
        let d = URL(string: "https://example.com/d.jpg")!
        let n = URL(string: "https://example.com/n.jpg")!
        let both: [ArtworkSource: URL] = [.discover: d, .nowPlaying: n]
        XCTAssertEqual(ThemeStore.resolveActiveURL(page: .discover, playerPresented: false, sources: both), d)
        XCTAssertEqual(ThemeStore.resolveActiveURL(page: .discover, playerPresented: true, sources: both), n)
        XCTAssertEqual(ThemeStore.resolveActiveURL(page: .remote, playerPresented: false, sources: both), n)
        XCTAssertEqual(ThemeStore.resolveActiveURL(page: .profile, playerPresented: false, sources: [.discover: d]), d)
        XCTAssertEqual(ThemeStore.resolveActiveURL(page: .remote, playerPresented: true, sources: [.discover: d]), d)
        XCTAssertNil(ThemeStore.resolveActiveURL(page: .remote, playerPresented: false, sources: [:]))
    }
}
