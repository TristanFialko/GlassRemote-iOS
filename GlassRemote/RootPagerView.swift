import SwiftUI
import UIKit

/// v5 §2: hosts the three dock pages (Remote, Discover, Profile) and the Now Playing presentation,
/// and keeps ALL of them alive. Switching pages is a short opacity fade (`TabSwitchPolicy`): nothing
/// slides, nothing is torn down or recreated, so ADB, the HID helpers, media polling and the Remote
/// page's touch state are never affected by navigation. Navigation sends no TV input.
///
/// There is no page swipe any more (the Phase 6 to 9 `PagerPan` recogniser is gone): the dock in
/// portrait and the glass rail in landscape are the only page controls, so a swipe on the trackpad,
/// in a carousel or in a scroll view only ever does that thing.
///
/// Now Playing is not a page. It opens from the mini-player above the dock (portrait) or the artwork
/// tile under the rail (landscape), which only appear while a session is genuinely active
/// (`MiniPlayerPolicy`). The player stays mounted while closed (invisible, no touches, hidden from
/// VoiceOver), so its artwork lookup and the Adaptive theme keep following the session and opening it
/// is instant. Its artwork background is part of the root canvas (`PlayerBackdrop`), under the dock.
///
/// Keyboard: the dock and mini-player live in their own layer that ignores the keyboard safe area,
/// so they stay anchored at the bottom when Discover's search keyboard comes up (pages still avoid it).
///
/// Landscape (Phase 6): the dock stands on end as a vertical glass rail on the leading edge and pages
/// sit beside it. Rotation only changes values (padding, alignment, the dock's axis), never the views.
struct RootPagerView: View {
    @StateObject private var navigator = PageNavigator()
    /// Whether a genuinely active session should show the mini-player. Reported by `MiniPlayerProbe`,
    /// so this view never observes `RemoteModel` and does not re-render on its updates.
    @State private var miniPlayerVisible = false
    /// The bottom safe-area inset measured with the keyboard ignored (the home indicator only).
    @State private var stableSafeBottom: CGFloat = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var page: AppPage { navigator.page }
    private var presented: Bool { navigator.playerPresented }

    var body: some View {
        ZStack {
            pages
            chrome
        }
        .background {
            // Phase 9 §A2: one root canvas. The player's artwork background is part of it, under the dock,
            // the landscape rail and every page, so it never splits at the rail's edge.
            ZStack {
                AmbientBackdrop()
                PlayerBackdrop(visible: navigator.playerPresented)
            }
        }
        .environmentObject(navigator)
        .onChange(of: navigator.page) { _, page in ThemeStore.shared.pageChanged(page) }
        .onChange(of: navigator.playerPresented) { _, shown in ThemeStore.shared.playerPresentationChanged(shown) }
    }

    // MARK: Pages

    private var pages: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let safeLeading = geo.safeAreaInsets.leading
            let safeTrailing = geo.safeAreaInsets.trailing
            let landscape = LayoutContext.resolve(verticalSizeClass: verticalSizeClass, size: geo.size).isLandscape
            let clearance = landscape ? DockMetrics.landscapeBottomClearance
                : DockMetrics.clearance(safeBottom: stableSafeBottom, miniPlayer: miniPlayerVisible)
            // The mini-player hides while the player is open, so the player keeps only the dock's clearance.
            let playerClearance = landscape ? DockMetrics.landscapeBottomClearance
                : DockMetrics.clearance(safeBottom: stableSafeBottom)
            let leading: CGFloat = landscape ? DockMetrics.railClearance(safeLeading: safeLeading) : 0
            let context = LayoutContext(isLandscape: landscape,
                                        size: CGSize(width: max(width - leading, 0), height: height))

            ZStack {
                ForEach(AppPage.allCases) { item in
                    let visible = TabSwitchPolicy.isVisible(item, current: page, playerPresented: presented)
                    content(for: item, clearance: clearance)
                        // Landscape: pages sit beside the rail. Only a value changes on rotation, never
                        // the view, so every page (and the Remote's touch state) stays alive.
                        .padding(.leading, leading)
                        .frame(width: width, height: height)
                        .opacity(visible ? 1 : 0)
                        .allowsHitTesting(visible)
                        .accessibilityHidden(!visible)
                }

                PlayerPage()
                    .padding(.leading, leading)
                    .frame(width: width, height: height)
                    .environment(\.dockClearance, playerClearance)
                    .opacity(presented ? 1 : 0)
                    .offset(y: NowPlayingPresentation.offset(presented: presented, reduceMotion: reduceMotion))
                    .allowsHitTesting(presented)
                    .accessibilityHidden(!presented)
                    .animation(NowPlayingPresentation.presentationAnimation(reduceMotion: reduceMotion), value: presented)
            }
            // Phase 7.4: reports when the switch has finished (Discover's search focus waits for it).
            .modifier(PageSettleObserver(page: page) { navigator.pageSettled($0) })
            .animation(TabSwitchPolicy.switchAnimation(reduceMotion: reduceMotion), value: page)
            .frame(width: width, height: height)
            .environment(\.dockClearance, clearance)
            .environment(\.railClearance, leading)
            // Continuation §F2: the safe areas beside a landscape page, for full-bleed artwork.
            .environment(\.pageBleed, HorizontalBleed.resolve(isLandscape: landscape, safeLeading: safeLeading,
                                                               safeTrailing: safeTrailing))
            .environment(\.layoutContext, context)
            // §G2: pages with their own backdrop align it to this window canvas (no seams).
            .environment(\.windowCanvasSize, BackdropAlignment.canvasSize(size: geo.size, insets: geo.safeAreaInsets))
        }
    }

    @ViewBuilder
    private func content(for item: AppPage, clearance: CGFloat) -> some View {
        switch item {
        case .remote: RemoteView().padding(.bottom, clearance)
        case .discover: DiscoverPage()
        case .profile: ProfilePage()
        }
    }

    // MARK: Dock, rail and mini-player

    private var chrome: some View {
        GeometryReader { geo in
            let landscape = LayoutContext.resolve(verticalSizeClass: verticalSizeClass, size: geo.size).isLandscape
            let safeBottom = geo.safeAreaInsets.bottom
            let safeLeading = geo.safeAreaInsets.leading
            let showMini = MiniPlayerPolicy.isShown(sessionVisible: miniPlayerVisible, playerPresented: presented)
            // The rail never grows past the visible height.
            let railLength = min(DockMetrics.railLength(count: AppPage.allCases.count), max(geo.size.height - 8, 120))

            ZStack(alignment: landscape ? .leading : .bottom) {
                if landscape {
                    // The dock stands on end as a glass rail on the leading edge, vertically centred; the
                    // Now Playing tile sits below it, so the rail never moves when the tile appears.
                    PageDock(axis: .vertical)
                        .frame(height: railLength)
                        .padding(.leading, DockMetrics.railGap)
                        .offset(x: -DockMetrics.railDrop(safeLeading: safeLeading))
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottomLeading) {
                            if showMini && DockMetrics.railTileFits(height: geo.size.height, count: AppPage.allCases.count) {
                                NowPlayingRailTile()
                                    .padding(.leading, DockMetrics.railGap)
                                    .padding(.bottom, DockMetrics.railMiniBottom)
                                    .offset(x: -DockMetrics.railDrop(safeLeading: safeLeading))
                                    .transition(.opacity)
                            }
                        }
                        .transition(.opacity)
                } else {
                    VStack(spacing: DockMetrics.miniPlayerGap) {
                        if showMini {
                            NowPlayingMiniPlayer()
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                        PageDock()
                    }
                    .padding(.horizontal, DockMetrics.sideInset)
                    .padding(.bottom, DockMetrics.baseGap)
                    // Sinks into the bottom safe area by a measured amount (never into the indicator).
                    .offset(y: DockMetrics.drop(safeBottom: safeBottom))
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: landscape ? .leading : .bottom)
            .animation(NowPlayingPresentation.presentationAnimation(reduceMotion: reduceMotion), value: showMini)
            .background { MiniPlayerProbe(visible: $miniPlayerVisible) }
            .onAppear { stableSafeBottom = safeBottom }
            .onChange(of: safeBottom) { _, value in stableSafeBottom = value }
        }
        // v5 §2: the keyboard never lifts the dock or the mini-player.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// Watches the media session and reports whether the mini-player should show. Isolated in its own
/// tiny view so the root never re-renders on `RemoteModel` updates.
///
/// v6 §1: state driven, with no sleeping loop. Every sample, connection or connecting change
/// re-renders this view and re-evaluates at once; the only change that arrives without input (a
/// session that stops reporting going stale) is a single entry on an explicit timeline, scheduled for
/// just after the stale point (`MiniPlayerPolicy.recheckSchedule`). SwiftUI owns and cancels the
/// timeline with the view.
private struct MiniPlayerProbe: View {
    @EnvironmentObject private var remote: RemoteModel
    @Binding var visible: Bool

    var body: some View {
        let media = remote.media
        let connected = remote.connected
        let connecting = remote.isBusyConnecting
        TimelineView(.explicit(MiniPlayerPolicy.recheckSchedule(media: media, now: Date()))) { context in
            let shown = MiniPlayerPolicy.isVisible(media: media, connected: connected, connecting: connecting,
                                                   now: max(context.date, Date()))
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear { report(shown) }
                .onChange(of: shown) { _, value in report(value) }
        }
    }

    private func report(_ shown: Bool) {
        if shown != visible { visible = shown }
    }
}

// MARK: - Gesture policy (retained)

/// Phase 6 to 9 page-swipe decisions. v5 §2 removed the page swipe, so the root no longer uses
/// these, but they stay as pure, tested helpers (selector exclusion zones, carousel detection).

/// Pure decisions of the page-swipe recogniser (unit tested).
enum PagerGesturePolicy {
    /// A page swipe must be clearly horizontal at the moment it would begin.
    static let dominance: CGFloat = 1.4

    static func isHorizontalDominant(dx: CGFloat, dy: CGFloat) -> Bool { abs(dx) > abs(dy) * dominance }

    /// Continuation §D: the landscape (vertical) counterpart, with the same dominance.
    static func isVerticalDominant(dx: CGFloat, dy: CGFloat) -> Bool { abs(dy) > abs(dx) * dominance }

    /// Continuation §D: whether a touch at `point` may start a page swipe on `page` along `axis`.
    /// Portrait is unchanged (the Remote pages only from its edge strips). In landscape the Remote pages
    /// only from `swipeAreas`, the free space in its side columns; every other page from anywhere.
    static func acceptsTouch(on page: AppPage, at point: CGPoint, in size: CGSize, edgeWidth: CGFloat,
                             axis: PagerAxis, swipeAreas: [CGRect]) -> Bool {
        guard page == .remote else { return true }
        switch axis {
        case .horizontal: return acceptsTouch(on: page, x: point.x, width: size.width, edgeWidth: edgeWidth)
        case .vertical: return swipeAreas.contains { $0.contains(point) }
        }
    }

    /// Continuation §D: a page's own vertical scroll view that can actually scroll.
    static func isVerticalScroller(contentHeight: CGFloat, boundsHeight: CGFloat, insetTop: CGFloat,
                                   insetBottom: CGFloat, scrollEnabled: Bool) -> Bool {
        scrollEnabled && contentHeight + insetTop + insetBottom > boundsHeight + 1
    }

    /// Continuation §D: a vertical swipe that begins inside a scrolling page pages only when that
    /// scroll view is already at its end in the swipe's direction (pull down at the top for the page
    /// above, push up at the bottom for the page below). Anywhere else the scroll view keeps the drag.
    static func scrollerYieldsVerticalPage(dy: CGFloat, offsetY: CGFloat, contentHeight: CGFloat,
                                           boundsHeight: CGFloat, insetTop: CGFloat, insetBottom: CGFloat) -> Bool {
        let tolerance: CGFloat = 1
        if dy > 0 { return offsetY <= -insetTop + tolerance }
        if dy < 0 { return offsetY >= contentHeight + insetBottom - boundsHeight - tolerance }
        return false
    }

    /// Continuation §D: a swipe in progress when the axis flips (rotation) is cancelled, never carried over.
    static func cancelsOnAxisChange(active: Bool, from old: PagerAxis, to new: PagerAxis) -> Bool {
        active && old != new
    }

    /// Landscape: a touch that lands on the leading rail belongs to the rail (it scrubs by itself).
    /// `x` is measured from the left of the screen; in right-to-left layouts the rail is on the right.
    static func inRail(x: CGFloat, width: CGFloat, railZone: CGFloat, rightToLeft: Bool) -> Bool {
        guard railZone > 0 else { return false }
        return (rightToLeft ? width - x : x) < railZone
    }

    /// Extra room around a selector that still counts as the selector (fingers are wider than its edge).
    static let exclusionSlop: CGFloat = 6

    /// Phase 7.1: a touch inside (or just outside) any selector's frame never starts a page swipe.
    static func inExcludedZone(_ point: CGPoint, zones: [CGRect], slop: CGFloat = exclusionSlop) -> Bool {
        zones.contains { $0.insetBy(dx: -slop, dy: -slop).contains(point) }
    }

    /// Phase 7.3: only zones with a real size that are at least partly on screen count.
    static func visibleZones(_ zones: [CGRect], in bounds: CGRect) -> [CGRect] {
        zones.filter { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 && $0.intersects(bounds) }
    }

    /// Whether a touch that lands at `x` (of `width`) may start a page swipe on `page`.
    /// Remote pages only from its edge strips; the others anywhere.
    static func acceptsTouch(on page: AppPage, x: CGFloat, width: CGFloat, edgeWidth: CGFloat) -> Bool {
        page != .remote || x < edgeWidth || x > width - edgeWidth
    }

    /// Is this scroll view a carousel? It must be able to scroll sideways (content wider than itself)
    /// and have no vertical range. A page's own vertical scroll view is never a carousel: its content
    /// is not wider than it is, and it is taller than its frame.
    static func isHorizontalScroller(contentSize: CGSize, bounds: CGSize, scrollEnabled: Bool) -> Bool {
        scrollEnabled && contentSize.width > bounds.width + 1 && contentSize.height <= bounds.height + 1
    }
}

// MARK: - Dock

/// v5 §2: a thinner, icon-only Liquid Glass bar (Apple Music style). Three full-height buttons, each
/// filling its share of the bar, so every target is comfortably larger than 44 pt. A button commits on
/// release (a press that slides off cancels), there is no sliding lens and no refraction over the icons,
/// so they stay crisp. The selected icon takes the theme accent when it is legible on the dock
/// (`DockStyle`), otherwise full dock ink; the others are muted dock ink. In landscape the same dock
/// runs vertically as the page rail (`axis: .vertical`).
struct PageDock: View {
    var axis: Axis = .horizontal
    @EnvironmentObject private var navigator: PageNavigator
    @Environment(\.glassTheme) private var theme

    var body: some View {
        let vertical = axis == .vertical
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let selectedInk = DockStyle.selectedInk(theme)
        layout {
            ForEach(AppPage.allCases) { item in
                let selected = item == navigator.page && !navigator.playerPresented
                Button { navigator.go(item) } label: {
                    DockIcon(item: item, selected: selected, vertical: vertical)
                        .foregroundStyle(selected ? selectedInk : theme.dockInkInactive)
                        .frame(minWidth: DockMetrics.minimumTouchTarget, maxWidth: .infinity,
                               minHeight: DockMetrics.minimumTouchTarget, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DockButtonStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(vertical ? .vertical : .horizontal, vertical ? DockMetrics.railInset : DockMetrics.itemInset)
        .frame(width: vertical ? DockMetrics.railWidth : nil, height: vertical ? nil : DockMetrics.height)
        .glassBar(Capsule(), interactive: false)
        .animation(TabSwitchPolicy.animation, value: navigator.page)
        .animation(TabSwitchPolicy.animation, value: navigator.playerPresented)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }
}

private struct DockIcon: View {
    let item: AppPage
    let selected: Bool
    let vertical: Bool

    var body: some View {
        if item == .profile {
            // §G3: the active profile's photo or initials instead of a generic glyph.
            DockProfileAvatar(size: vertical ? 26 : 28, selected: selected)
        } else {
            Image(systemName: item.symbol(selected: selected))
                .scaledFont(vertical ? 21 : 22, selected ? .semibold : .medium)
        }
    }
}

/// Dock and mini-player buttons: pressed items dim slightly; nothing scales or refracts.
struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? DockStyle.pressedOpacity : 1)
            .animation(Motion.pressDim, value: configuration.isPressed)
    }
}

// MARK: - Mini-player

/// v5 §2: the compact Now Playing bar above the dock (Apple Music style). Artwork, title and
/// subtitle open the full player; the play / pause button sends the explicit command through
/// `RemoteModel.sendMedia`. Shown only for a genuinely active session (`MiniPlayerPolicy`).
struct NowPlayingMiniPlayer: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    @ObservedObject private var artwork = PlayerArtworkStore.shared
    @Environment(\.glassTheme) private var theme

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })
        let summary = MiniPlayerSummary.resolve(media: media, appName: app?.name)
        let controls = PlayerControls.resolve(media: media)
        let key = PlayerTransition.key(media: media)

        HStack(spacing: 8) {
            Button { navigator.openPlayer() } label: {
                HStack(spacing: 11) {
                    MiniArtwork(url: artwork.posterURL(forSessionTitle: summary.sessionTitle)
                                    ?? artwork.landscapeURL(forSessionTitle: summary.sessionTitle),
                                appAsset: app?.asset, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.title).scaledFont(15, .semibold).lineLimit(1)
                        if !summary.detail.isEmpty {
                            Text(summary.detail).scaledFont(12.5, .medium)
                                .foregroundStyle(theme.dockInkInactive).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Artwork and metadata change together.
                .id(key)
                .transition(.opacity)
                .contentShape(Rectangle())
            }
            .buttonStyle(DockButtonStyle())
            .accessibilityLabel(summary.accessibilityLabel)
            .accessibilityHint("Opens Now Playing")

            Button { remote.sendMedia(PlayerControls.playPauseCommand(for: media)) } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .scaledFont(19, .semibold)
                    .frame(width: DockMetrics.minimumTouchTarget, height: DockMetrics.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DockButtonStyle())
            .disabled(!controls.playPause || remote.mediaCommandPending)
            .opacity(controls.playPause ? 1 : 0.4)
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
        }
        .foregroundStyle(theme.dockInk)
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(height: DockMetrics.miniPlayerHeight)
        .glassBar(Capsule(), interactive: false)
        .animation(Motion.adaptive(Motion.fade), value: key)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Landscape: the mini-player is a single artwork tile under the rail; tapping it opens the player.
struct NowPlayingRailTile: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    @ObservedObject private var artwork = PlayerArtworkStore.shared

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })
        let summary = MiniPlayerSummary.resolve(media: media, appName: app?.name)
        Button { navigator.openPlayer() } label: {
            MiniArtwork(url: artwork.posterURL(forSessionTitle: summary.sessionTitle)
                            ?? artwork.landscapeURL(forSessionTitle: summary.sessionTitle),
                        appAsset: app?.asset, size: DockMetrics.railTileArtwork)
                .id(PlayerTransition.key(media: media))
                .transition(.opacity)
                .frame(width: DockMetrics.railWidth, height: DockMetrics.railWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(DockButtonStyle())
        .glassBar(RoundedRectangle(cornerRadius: DockMetrics.railWidth / 2.6, style: .continuous), interactive: false)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityHint("Opens Now Playing")
    }
}

/// Small square artwork: the session's poster when known, else the app's icon, else a glyph.
private struct MiniArtwork: View {
    let url: URL?
    let appAsset: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                CachedArtwork(url: url, contentMode: .fill) { fallback }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var fallback: some View {
        if let appAsset, UIImage(named: "\(appAsset)_dark") != nil {
            Image("\(appAsset)_dark").resizable().scaledToFill()
        } else {
            ZStack {
                Color.inkAlpha(0.12)
                Image(systemName: AppPage.playerSymbolOutline).scaledFont(size * 0.42, .medium)
                    .foregroundStyle(Color.inkAlpha(0.7))
            }
        }
    }
}

private struct RailClearanceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// Width reserved for the landscape glass rail on the leading edge (0 in portrait). Pages inset their
    /// content by it; Discover's hero artwork runs underneath the rail.
    var railClearance: CGFloat {
        get { self[RailClearanceKey.self] }
        set { self[RailClearanceKey.self] = newValue }
    }
}
