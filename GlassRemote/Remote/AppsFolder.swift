import SwiftUI

// Phase 9 §2 / continuation §A: the Apps launcher is an expanding folder anchored to the Apps control,
// like opening a folder on iPhone. The glass shell grows out of the Apps key (portrait) or the launcher
// card (landscape), floats above the Remote page and collapses back into it. Everything that decides
// state, geometry, motion and dismissal is pure and unit tested (Phase9RemoteTests,
// Phase9ContinuationTests); the view only follows it.
//
// Continuation §A refinements: no close button and no instructional subtitle (dismissal is an outside
// tap, a pull on the grabber, Escape, the VoiceOver escape gesture or a context change); a fixed
// three-column grid whose tiles scale before the structure changes; a quicker spring; the visible
// catalogue is cached instead of being rebuilt on every frame.

// MARK: - Catalogue rules

/// Pure rules for the Apps launcher (unit tested in Phase8RemoteTests and Phase9ContinuationTests).
///
/// Package discovery stays informational (see `RemoteModel.refreshApps`): it never hides, dims or
/// disables a tile. The launcher only reports the scan's state in a banner.
enum AppLauncherPolicy {
    enum Banner: Equatable {
        /// Connected and the package scan finished.
        case none
        /// The box is not connected: tiles are shown, launching reports the failure, Reconnect offered.
        case offline
        /// Connected, the package scan has not reported yet.
        case scanning
        /// Connected, but the package scan failed.
        case scanFailed
    }

    static func banner(connected: Bool, installedCount: Int, status: String) -> Banner {
        guard connected else { return .offline }
        if status.localizedCaseInsensitiveContains("app scan failed") { return .scanFailed }
        return installedCount == 0 ? .scanning : .none
    }

    /// Favourites first (in the order they were starred), then the rest in catalogue order.
    static func ordered(_ apps: [TVApp], favourites: [String]) -> [TVApp] {
        let favs = favourites.compactMap { pkg in apps.first { $0.package == pkg } }
        let favSet = Set(favourites)
        return favs + apps.filter { !favSet.contains($0.package) }
    }

    /// Case- and diacritic-insensitive name filter; a blank query keeps everything.
    static func filtered(_ apps: [TVApp], query: String) -> [TVApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// What the folder shows: favourites first, then filtered by the query (favourites stay first
    /// among the matches).
    static func visible(_ apps: [TVApp], favourites: [String], query: String) -> [TVApp] {
        filtered(ordered(apps, favourites: favourites), query: query)
    }

    /// The empty state's message, or nil when there is something to show.
    static func emptyMessage(visibleCount: Int, query: String) -> String? {
        guard visibleCount == 0 else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "No apps" : "No apps match “\(q)”"
    }

    /// Continuation §A3: the grid always has three columns, whatever the width. Narrow screens
    /// scale the tiles (AppsFolderLayout.metrics) instead of dropping or adding columns.
    static func columns(for width: CGFloat) -> Int { AppsFolderLayout.columns }
}

// MARK: - Folder lifecycle

/// The folder's lifecycle. `generation` moves on with every transition, so the completion of an
/// animation that has since been interrupted (reopened mid-close, closed mid-open) is ignored and
/// can never leave the folder or the Apps highlight in the wrong state.
struct AppsFolderState: Equatable {
    enum Phase: Equatable { case closed, opening, open, closing }

    /// How the folder was closed. There is no close button (continuation §A1): an outside tap, a
    /// pull on the grabber, Escape / the VoiceOver escape gesture, launching an app, or a context
    /// change (device switch, leaving the Remote page, the view disappearing).
    enum DismissReason: Equatable, CaseIterable {
        case outsideTap, swipe, escape, launched, contextChanged
    }

    private(set) var phase: Phase = .closed
    private(set) var generation = 0
    private(set) var lastDismissal: DismissReason?

    /// The overlay is in the hierarchy (including while it collapses back into the Apps control).
    var isVisible: Bool { phase != .closed }
    /// The folder is open or opening: the shell is (becoming) expanded.
    var isExpanded: Bool { phase == .opening || phase == .open }
    /// The Apps control looks selected only while its folder is on screen or animating.
    var highlightsSource: Bool { phase != .closed }
    /// Tiles launch only once the folder has fully opened and never while it closes, so a tap that
    /// lands during a dismissal can't start an app.
    var acceptsLaunch: Bool { phase == .open }
    /// The outside scrim takes taps only while the folder is (becoming) open; during the close the
    /// Remote underneath is usable again at once.
    var blocksOutside: Bool { isExpanded }

    /// Starts opening. Also reopens a folder that is still collapsing. Nil when already open(ing).
    @discardableResult
    mutating func open() -> Int? {
        guard phase == .closed || phase == .closing else { return nil }
        phase = .opening
        lastDismissal = nil
        generation &+= 1
        return generation
    }

    /// Starts closing. Nil when the folder is already closed or closing (a second outside tap, a
    /// swipe that ends after Escape was pressed, ...).
    @discardableResult
    mutating func dismiss(_ reason: DismissReason) -> Int? {
        guard phase == .opening || phase == .open else { return nil }
        phase = .closing
        lastDismissal = reason
        generation &+= 1
        return generation
    }

    /// The animation started by transition `generation` finished. Stale completions do nothing.
    mutating func settle(_ generation: Int) {
        guard generation == self.generation else { return }
        switch phase {
        case .opening: phase = .open
        case .closing: phase = .closed
        case .open, .closed: break
        }
    }

    /// Closes at once, without animation: the Remote left the screen or the device changed.
    mutating func reset() {
        guard phase != .closed else { return }
        phase = .closed
        lastDismissal = .contextChanged
        generation &+= 1
    }
}

// MARK: - Interaction rules

/// Continuation §A2: searching never launches an app or closes the folder by accident.
enum AppsFolderInteraction {
    enum OutsideTapResult: Equatable {
        /// The keyboard was up: the tap only puts it away; the folder stays open.
        case endSearch
        /// The folder closes.
        case dismiss
    }

    static func outsideTap(searchFocused: Bool) -> OutsideTapResult {
        searchFocused ? .endSearch : .dismiss
    }

    /// Return in the search field only puts the keyboard away. It never launches the first match.
    static let submitLaunchesFirstMatch = false

    /// Every way to close the folder now that there is no close button. At least one is always
    /// reachable by touch (outside tap, grabber), keyboard (Escape) and VoiceOver (escape gesture).
    static let touchDismissals: [AppsFolderState.DismissReason] = [.outsideTap, .swipe]
    static let keyboardDismissals: [AppsFolderState.DismissReason] = [.escape]
    static let voiceOverDismissals: [AppsFolderState.DismissReason] = [.escape]
}

// MARK: - Dismiss gesture

enum AppsFolderGesture {
    /// Pull the folder down this far (or flick it further) to dismiss it.
    static let dismissDistance: CGFloat = 90
    static let dismissPredicted: CGFloat = 200

    static func shouldDismiss(translation: CGFloat, predicted: CGFloat) -> Bool {
        translation > dismissDistance || predicted > dismissPredicted
    }

    /// The shell follows a downward pull one to one and resists an upward one.
    static func offset(for translation: CGFloat) -> CGFloat {
        translation >= 0 ? translation : -min(sqrt(-translation) * 2.5, 24)
    }
}

// MARK: - Motion

/// Continuation §A4: a quicker, tactile expansion. Still a pronounced spring, but it settles fast;
/// the close is quicker again and does not bounce. Under Reduce Motion the shell does not morph out
/// of the Apps control: it fades in place, briefly.
enum AppsFolderMotion {
    /// The Phase 9 checkpoint 1 values, kept so the tests can prove the new motion is faster.
    static let previousOpenResponse: Double = 0.44
    static let previousCloseResponse: Double = 0.34

    static let openResponse: Double = 0.30
    static let openDamping: Double = 0.80
    static let closeResponse: Double = 0.22
    static let closeDamping: Double = 0.94
    static let reducedDuration: Double = 0.14

    /// Content scale while collapsed (it grows to 1 with the shell).
    static let collapsedContentScale: CGFloat = 0.6

    static func animation(opening: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: reducedDuration) }
        return opening ? .spring(response: openResponse, dampingFraction: openDamping)
                       : .spring(response: closeResponse, dampingFraction: closeDamping)
    }

    /// Whether the shell morphs out of the Apps control (false under Reduce Motion: it cross-fades).
    static func morphs(reduceMotion: Bool) -> Bool { !reduceMotion }

    static func contentScale(expanded: Bool, reduceMotion: Bool) -> CGFloat {
        expanded || reduceMotion ? 1 : collapsedContentScale
    }
}

extension Motion {
    /// The Apps folder opening out of its icon.
    static let folderOpen = AppsFolderMotion.animation(opening: true, reduceMotion: false)
    /// The Apps folder collapsing back into its icon: quicker, no bounce.
    static let folderClose = AppsFolderMotion.animation(opening: false, reduceMotion: false)
}

// MARK: - Folder geometry

/// Tile metrics at a given scale. The grid always has three columns; on small screens the tiles and
/// their spacing shrink (down to `AppsFolderLayout.minimumScale`) before anything else changes.
struct AppsFolderMetrics: Equatable {
    var scale: CGFloat

    var tileSide: CGFloat { AppsFolderLayout.baseTileSide * scale }
    var columnSpacing: CGFloat { AppsFolderLayout.baseColumnSpacing * scale }
    var rowSpacing: CGFloat { AppsFolderLayout.baseRowSpacing * scale }
    var tileCornerRadius: CGFloat { 16 * scale }
    var rowHeight: CGFloat { tileSide + AppsFolderLayout.labelGap + AppsFolderLayout.labelHeight }
    var gridWidth: CGFloat { tileSide * CGFloat(AppsFolderLayout.columns) + columnSpacing * CGFloat(AppsFolderLayout.columns - 1) }
    /// Each column is a third of the grid, so the tiles sit centred with even gutters.
    var columnWidth: CGFloat { gridWidth / CGFloat(AppsFolderLayout.columns) }

    func gridHeight(rows: Int) -> CGFloat {
        let r = max(rows, 1)
        return CGFloat(r) * rowHeight + CGFloat(r - 1) * rowSpacing
    }
}

/// Where the folder sits and how big it is. Pure. All rects are in the overlay's coordinates.
enum AppsFolderLayout {
    static let margin: CGFloat = 12
    /// Gap between the Apps control and the folder.
    static let gap: CGFloat = 10
    static let inset: CGFloat = 16
    /// Continuation §A3: a deliberate 3 × 3 grid. More than nine apps add rows that scroll.
    static let columns = 3
    static let visibleRows = 3
    static let baseTileSide: CGFloat = 64
    static let baseColumnSpacing: CGFloat = 26
    static let baseRowSpacing: CGFloat = 18
    static let labelGap: CGFloat = 5
    static let labelHeight: CGFloat = 15
    /// Tiles never shrink below 44 pt (the minimum touch target).
    static let minimumScale: CGFloat = 44 / 64
    /// One row holding the compact title and the search field, plus its spacing.
    static let chromeHeight: CGFloat = 40 + 12
    static let bannerHeight: CGFloat = 52
    static let cornerRadius: CGFloat = 34
    static let portraitWidth: CGFloat = 320
    static let landscapeWidth: CGFloat = 340
    /// Portrait never covers more than this share of the height, so the status header stays visible.
    static let portraitHeightShare: CGFloat = 0.72

    struct Placement: Equatable {
        var frame: CGRect
        var metrics: AppsFolderMetrics
        /// More rows than fit: the grid scrolls inside the folder.
        var scrolls: Bool
    }

    static func width(container: CGSize, isLandscape: Bool) -> CGFloat {
        let room = max(container.width - margin * 2, 0)
        return min(isLandscape ? landscapeWidth : portraitWidth, room)
    }

    /// Always three (kept as a function so callers and tests read the same rule).
    static func columns(folderWidth: CGFloat) -> Int { columns }

    static func rows(appCount: Int) -> Int {
        let count = max(appCount, 1)
        return (count + columns - 1) / columns
    }

    static func heightCap(container: CGSize, isLandscape: Bool) -> CGFloat {
        let room = max(container.height - margin * 2, 0)
        return isLandscape ? room : min(room, container.height * portraitHeightShare)
    }

    static func bannerSpace(_ showsBanner: Bool) -> CGFloat { showsBanner ? bannerHeight + 12 : 0 }

    /// The largest tile scale (at most 1) at which three columns fit the width and up to three rows
    /// fit `maxGridHeight`; never below `minimumScale` unless the width itself forces it.
    static func metrics(folderWidth: CGFloat, maxGridHeight: CGFloat, appCount: Int) -> AppsFolderMetrics {
        let usable = max(folderWidth - inset * 2, 0)
        let baseGridWidth = baseTileSide * CGFloat(columns) + baseColumnSpacing * CGFloat(columns - 1)
        let widthScale = usable / baseGridWidth
        let shown = min(rows(appCount: appCount), visibleRows)
        let fixed = CGFloat(shown) * (labelGap + labelHeight)
        let scalable = CGFloat(shown) * baseTileSide + CGFloat(shown - 1) * baseRowSpacing
        let heightScale = scalable > 0 ? (maxGridHeight - fixed) / scalable : 1
        let floor = min(minimumScale, widthScale)
        let scale = max(min(1, widthScale, heightScale), floor)
        return AppsFolderMetrics(scale: max(scale, 0))
    }

    /// Natural height for the content, before it is capped by the room available.
    static func contentHeight(metrics: AppsFolderMetrics, appCount: Int, showsBanner: Bool) -> CGFloat {
        let shown = min(rows(appCount: appCount), visibleRows)
        return inset * 2 + chromeHeight + bannerSpace(showsBanner) + metrics.gridHeight(rows: shown)
    }

    static func isUsableAnchor(_ anchor: CGRect, in container: CGSize) -> Bool {
        !anchor.isNull && !anchor.isInfinite && anchor.width > 0 && anchor.height > 0
            && CGRect(origin: .zero, size: container).intersects(anchor)
    }

    /// The open folder's frame and tile metrics. Portrait: centred on the Apps key and above it.
    /// Landscape: beside the launcher card (over the pad), bottom-aligned with it, so the status
    /// column stays visible. Always inside the container's margins.
    static func placement(container: CGSize, anchor: CGRect, isLandscape: Bool,
                          appCount: Int, showsBanner: Bool) -> Placement {
        let w = width(container: container, isLandscape: isLandscape)
        let cap = heightCap(container: container, isLandscape: isLandscape)
        let maxGrid = max(cap - inset * 2 - chromeHeight - bannerSpace(showsBanner), 0)
        let m = metrics(folderWidth: w, maxGridHeight: maxGrid, appCount: appCount)
        let natural = contentHeight(metrics: m, appCount: appCount, showsBanner: showsBanner)
        let minimum = min(inset * 2 + chromeHeight + m.rowHeight, cap)
        let h = min(max(natural, minimum), cap)
        let totalGrid = m.gridHeight(rows: rows(appCount: appCount))
        let scrolls = totalGrid > h - inset * 2 - chromeHeight - bannerSpace(showsBanner) + 0.5

        let maxX = max(container.width - margin - w, margin)
        let maxY = max(container.height - margin - h, margin)
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, margin), maxX) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, margin), maxY) }

        let frame: CGRect
        if !isUsableAnchor(anchor, in: container) {
            frame = CGRect(x: clampX((container.width - w) / 2), y: clampY((container.height - h) / 2),
                           width: w, height: h)
        } else if isLandscape {
            var x = anchor.maxX + gap
            if x + w > container.width - margin { x = container.width - margin - w }
            frame = CGRect(x: clampX(x), y: clampY(anchor.maxY - h), width: w, height: h)
        } else {
            frame = CGRect(x: clampX(anchor.midX - w / 2), y: clampY(anchor.minY - gap - h), width: w, height: h)
        }
        return Placement(frame: frame, metrics: m, scrolls: scrolls)
    }

    static func frame(container: CGSize, anchor: CGRect, isLandscape: Bool,
                      appCount: Int, showsBanner: Bool) -> CGRect {
        placement(container: container, anchor: anchor, isLandscape: isLandscape,
                  appCount: appCount, showsBanner: showsBanner).frame
    }

    /// The closed shell: exactly the Apps control's frame, so the folder grows out of it and
    /// collapses back into it. Without a usable anchor, a small shell in the centre.
    static func collapsedFrame(anchor: CGRect, container: CGSize) -> CGRect {
        if isUsableAnchor(anchor, in: container) { return anchor }
        return CGRect(x: container.width / 2 - 28, y: container.height / 2 - 28, width: 56, height: 56)
    }
}

// MARK: - Folder view

/// The floating folder. The shell's frame and corner radius move between the Apps control's frame
/// and the folder frame; the content is laid out at the open size and scales and fades with it, so
/// icon, shell and tiles read as one transition. Native Liquid Glass throughout.
struct AppsFolderOverlay: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var favourites = AppFavourites.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let state: AppsFolderState
    /// Shell expansion, animated by the Remote page.
    let expanded: Bool
    /// The Apps control's frame in global coordinates.
    let anchor: CGRect
    let anchorCornerRadius: CGFloat
    let isLandscape: Bool
    let onDismiss: (AppsFolderState.DismissReason) -> Void
    let onLaunch: (TVApp) -> Void
    let onRestart: (TVApp) -> Void
    /// Called once the overlay is in the hierarchy, so the shell expands from the collapsed frame.
    let onMounted: () -> Void

    @State private var query = ""
    @State private var dragOffset: CGFloat = 0
    /// Continuation §A5: the visible catalogue is rebuilt only when the apps, favourites or query
    /// change, never on an animation or drag frame.
    @State private var visibleApps: [TVApp] = []
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool

    private var reduceMotion: Bool { systemReduceMotion || MotionPreference.reduced }

    private var banner: AppLauncherPolicy.Banner {
        AppLauncherPolicy.banner(connected: remote.connected, installedCount: remote.installed.count,
                                 status: remote.status)
    }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let local = anchor.offsetBy(dx: -origin.x, dy: -origin.y)
            let placement = AppsFolderLayout.placement(container: geo.size, anchor: local, isLandscape: isLandscape,
                                                       appCount: remote.apps.count, showsBanner: banner != .none)
            let target = placement.frame
            let collapsed = AppsFolderLayout.collapsedFrame(anchor: local, container: geo.size)
            let morphs = AppsFolderMotion.morphs(reduceMotion: reduceMotion)
            let frame = (expanded || !morphs) ? target : collapsed
            let radius = (expanded || !morphs) ? AppsFolderLayout.cornerRadius : anchorCornerRadius
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack(alignment: .topLeading) {
                scrim
                folderContent(placement: placement)
                    .frame(width: target.width, height: target.height)
                    .scaleEffect(AppsFolderMotion.contentScale(expanded: expanded, reduceMotion: reduceMotion),
                                 anchor: .center)
                    .opacity(expanded ? 1 : 0)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(shape)
                    .glassSurface(shape, elevated: true)
                    .opacity(morphs || expanded ? 1 : 0)
                    .contentShape(shape)
                    .background { escapeShortcut }
                    .offset(x: frame.minX, y: frame.minY + dragOffset)
                    .allowsHitTesting(state.phase != .closing)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityLabel("Apps folder")
                    .accessibilityHint("Scrub with two fingers to close")
                    .accessibilityAction(.escape) { close(.escape) }
                    .accessibilityAction(named: Text("Close Apps")) { close(.escape) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onAppear {
            query = ""
            refreshVisible()
            onMounted()
        }
        .onChange(of: query) { _, _ in refreshVisible() }
        .onChange(of: favourites.packages) { _, _ in refreshVisible() }
        .onChange(of: remote.apps.map(\.package)) { _, _ in refreshVisible() }
        .onChange(of: state.phase) { _, phase in
            if phase == .open { titleFocused = true }
            if phase == .closing { searchFocused = false }
        }
    }

    private func refreshVisible() {
        visibleApps = AppLauncherPolicy.visible(remote.apps, favourites: favourites.packages, query: query)
    }

    private func close(_ reason: AppsFolderState.DismissReason) {
        searchFocused = false
        onDismiss(reason)
    }

    /// Escape on a hardware keyboard closes the folder (it replaced the close button's shortcut).
    /// Invisible and outside the accessibility tree; VoiceOver uses the escape action instead.
    private var escapeShortcut: some View {
        Button("Close Apps") { close(.escape) }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Dims the Remote and catches outside taps while the folder is open, and keeps a page swipe
    /// from starting under it. It never forwards a touch to the pad. While the search keyboard is
    /// up, the first outside tap only puts it away (continuation §A2).
    private var scrim: some View {
        Color.black.opacity(expanded ? 0.22 : 0)
            .contentShape(Rectangle())
            .background(PagerExclusionZone())
            .onTapGesture {
                switch AppsFolderInteraction.outsideTap(searchFocused: searchFocused) {
                case .endSearch: searchFocused = false
                case .dismiss: close(.outsideTap)
                }
            }
            .allowsHitTesting(state.blocksOutside)
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }

    /// A pull on the grabber or the title closes the folder; the grid keeps its own scrolling.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in dragOffset = AppsFolderGesture.offset(for: value.translation.height) }
            .onEnded { value in
                if AppsFolderGesture.shouldDismiss(translation: value.translation.height,
                                                   predicted: value.predictedEndTranslation.height) {
                    close(.swipe)
                }
                withAnimation(Motion.resolve(Motion.snappy, reduceMotion: systemReduceMotion)) { dragOffset = 0 }
            }
    }

    private func folderContent(placement: AppsFolderLayout.Placement) -> some View {
        let metrics = placement.metrics
        let grid = Array(repeating: GridItem(.fixed(metrics.columnWidth), spacing: 0),
                         count: AppsFolderLayout.columns)
        return VStack(spacing: 0) {
            grabber
            VStack(spacing: 12) {
                header
                bannerView
                if let message = AppLauncherPolicy.emptyMessage(visibleCount: visibleApps.count, query: query) {
                    emptyState(message)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: grid, spacing: metrics.rowSpacing) {
                            ForEach(visibleApps) { app in tile(app, metrics: metrics) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, placement.scrolls ? 8 : 0)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDisabled(!placement.scrolls)
                }
            }
            .padding(.horizontal, AppsFolderLayout.inset)
            .padding(.bottom, AppsFolderLayout.inset)
        }
        .foregroundStyle(Color.ink)
    }

    /// The folder's top inset doubles as its grabber: a small pill that shows it can be pulled down.
    private var grabber: some View {
        Capsule(style: .continuous)
            .fill(Color.inkAlpha(0.28))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: AppsFolderLayout.inset)
            .contentShape(Rectangle())
            .gesture(dismissDrag)
            .accessibilityHidden(true)
    }

    /// Compact title (the VoiceOver landing point) and the search field on one row.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Apps")
                .scaledFont(18, .bold)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .contentShape(Rectangle())
                .gesture(dismissDrag)
            searchField
        }
        .frame(height: 40)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.inkAlpha(0.55))
                .accessibilityHidden(true)
            TextField("Search apps", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkAlpha(0.45))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(15)
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 6)
        .frame(height: 40)
        .glassSurface(Capsule())
    }

    @ViewBuilder
    private var bannerView: some View {
        switch banner {
        case .none:
            EmptyView()
        case .scanning:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking installed apps…").scaledFont(13).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.inkAlpha(0.72))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .scanFailed:
            noticeRow(symbol: "exclamationmark.triangle", text: "Couldn't list installed apps. Every app can still be opened.",
                      action: nil)
        case .offline:
            noticeRow(symbol: "wifi.exclamationmark", text: "The TV box isn't connected.",
                      action: ("Reconnect", { remote.connect() }))
        }
    }

    private func noticeRow(symbol: String, text: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).scaledFont(13).foregroundStyle(Color.inkAlpha(0.8)).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let action {
                Button(action.0) { action.1() }
                    .scaledFont(13, .semibold)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .glassSurface(Capsule(), interactive: true, accent: true)
                    .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "square.grid.3x3" : "magnifyingglass").scaledFont(26, .light)
                .accessibilityHidden(true)
            Text(message).scaledFont(14, .semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if !query.isEmpty {
                Button("Clear search") { query = "" }
                    .scaledFont(13, .semibold)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .glassSurface(Capsule(), interactive: true)
                    .buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(Color.inkAlpha(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ app: TVApp, metrics: AppsFolderMetrics) -> some View {
        let isFavourite = favourites.contains(app.package)
        let corner = metrics.tileCornerRadius
        return Button {
            guard state.acceptsLaunch else { return }
            searchFocused = false
            onLaunch(app)
        } label: {
            VStack(spacing: AppsFolderLayout.labelGap) {
                AppIconImage(asset: "\(app.asset)_dark")
                    .frame(width: metrics.tileSide, height: metrics.tileSide)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Color.ink.opacity(0.42), Color.ink.opacity(0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.ink.opacity(0.07))
                    }
                    .shadow(color: .black.opacity(0.26), radius: 7, y: 4)
                    .overlay(alignment: .topTrailing) {
                        if isFavourite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(4)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .offset(x: 4, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
                Text(app.name)
                    .scaledFont(11, .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: AppsFolderLayout.labelHeight)
                    .foregroundStyle(Color.inkAlpha(0.86))
            }
            .frame(width: metrics.columnWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(app.name + (isFavourite ? ", favourite" : ""))
        .accessibilityHint("Opens on the TV box")
        .contextMenu {
            Button { favourites.toggle(app.package) } label: {
                Label(isFavourite ? "Remove favourite" : "Favourite", systemImage: isFavourite ? "star.slash" : "star")
            }
            Button(role: .destructive) {
                onRestart(app)
            } label: {
                Label("Restart \(app.name)", systemImage: "arrow.clockwise")
            }
        }
    }
}
