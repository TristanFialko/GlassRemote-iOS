import SwiftUI

// Phase 9 §2: the Apps launcher is an expanding folder anchored to the Apps control, like opening a
// folder on iPhone. The glass shell grows out of the Apps key (portrait) or the launcher card
// (landscape), floats above the Remote page and collapses back into it. It replaces the Phase 8
// bottom sheet. Everything that decides state, geometry and dismissal is pure and unit tested
// (Phase9RemoteTests); the view only follows it.

// MARK: - Catalogue rules (unchanged from Phase 8)

/// Pure rules for the Apps launcher (unit tested in Phase8RemoteTests).
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

    /// Grid columns for a width: 3 on a narrow phone, up to 6 in landscape.
    static func columns(for width: CGFloat) -> Int {
        let tile: CGFloat = 96
        return min(max(Int((width - 32) / tile), 3), 6)
    }
}

// MARK: - Folder lifecycle

/// The folder's lifecycle. `generation` moves on with every transition, so the completion of an
/// animation that has since been interrupted (reopened mid-close, closed mid-open) is ignored and
/// can never leave the folder or the Apps highlight in the wrong state.
struct AppsFolderState: Equatable {
    enum Phase: Equatable { case closed, opening, open, closing }

    enum DismissReason: Equatable {
        case outsideTap, closeButton, swipe, escape, launched, contextChanged
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
    /// swipe that ends after the close button was pressed, ...).
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

// MARK: - Folder geometry

/// Where the folder sits and how big it is. Pure. All rects are in the overlay's coordinates.
enum AppsFolderLayout {
    static let margin: CGFloat = 12
    /// Gap between the Apps control and the folder.
    static let gap: CGFloat = 10
    static let inset: CGFloat = 16
    static let tileSide: CGFloat = 62
    static let tileSpacing: CGFloat = 14
    /// Icon, gap and a one-line name.
    static let rowHeight: CGFloat = 62 + 6 + 16
    static let rowSpacing: CGFloat = 16
    /// Title row and search field with their spacing.
    static let chromeHeight: CGFloat = 40 + 12 + 40 + 12
    static let bannerHeight: CGFloat = 52
    static let cornerRadius: CGFloat = 34
    /// Portrait never covers more than this share of the height, so the status header stays visible.
    static let portraitHeightShare: CGFloat = 0.72

    static func width(container: CGSize, isLandscape: Bool) -> CGFloat {
        let room = max(container.width - margin * 2, 0)
        if isLandscape { return min(max(container.width * 0.5, 340), 560, room) }
        return min(400, room)
    }

    static func columns(folderWidth: CGFloat) -> Int {
        let usable = folderWidth - inset * 2
        let fit = Int((usable + tileSpacing) / (tileSide + tileSpacing))
        return min(max(fit, 3), 6)
    }

    static func rows(appCount: Int, columns: Int) -> Int {
        let count = max(appCount, 1)
        let cols = max(columns, 1)
        return (count + cols - 1) / cols
    }

    /// Natural height for the content, before it is capped by the room available.
    static func contentHeight(appCount: Int, columns: Int, showsBanner: Bool) -> CGFloat {
        let rows = rows(appCount: appCount, columns: columns)
        let grid = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
        return inset * 2 + chromeHeight + (showsBanner ? bannerHeight + 12 : 0) + grid
    }

    static func isUsableAnchor(_ anchor: CGRect, in container: CGSize) -> Bool {
        !anchor.isNull && !anchor.isInfinite && anchor.width > 0 && anchor.height > 0
            && CGRect(origin: .zero, size: container).intersects(anchor)
    }

    /// The open folder's frame. Portrait: centred on the Apps key and above it. Landscape: beside
    /// the launcher card (over the pad), bottom-aligned with it, so the status column stays visible.
    /// Always inside the container's margins.
    static func frame(container: CGSize, anchor: CGRect, isLandscape: Bool,
                      appCount: Int, showsBanner: Bool) -> CGRect {
        let w = width(container: container, isLandscape: isLandscape)
        let cols = columns(folderWidth: w)
        let natural = contentHeight(appCount: appCount, columns: cols, showsBanner: showsBanner)
        let room = max(container.height - margin * 2, 0)
        let cap = isLandscape ? room : min(room, container.height * portraitHeightShare)
        let minimum = min(inset * 2 + chromeHeight + rowHeight, cap)
        let h = min(max(natural, minimum), cap)

        let maxX = max(container.width - margin - w, margin)
        let maxY = max(container.height - margin - h, margin)
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, margin), maxX) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, margin), maxY) }

        guard isUsableAnchor(anchor, in: container) else {
            return CGRect(x: clampX((container.width - w) / 2), y: clampY((container.height - h) / 2),
                          width: w, height: h)
        }
        if isLandscape {
            var x = anchor.maxX + gap
            if x + w > container.width - margin { x = container.width - margin - w }
            return CGRect(x: clampX(x), y: clampY(anchor.maxY - h), width: w, height: h)
        }
        return CGRect(x: clampX(anchor.midX - w / 2), y: clampY(anchor.minY - gap - h), width: w, height: h)
    }

    /// The closed shell: exactly the Apps control's frame, so the folder grows out of it and
    /// collapses back into it. Without a usable anchor, a small shell in the centre.
    static func collapsedFrame(anchor: CGRect, container: CGSize) -> CGRect {
        if isUsableAnchor(anchor, in: container) { return anchor }
        return CGRect(x: container.width / 2 - 28, y: container.height / 2 - 28, width: 56, height: 56)
    }
}

extension Motion {
    /// The Apps folder opening out of its icon.
    static let folderOpen = Animation.spring(response: 0.44, dampingFraction: 0.84)
    /// The Apps folder collapsing back into its icon: a touch quicker, no bounce.
    static let folderClose = Animation.spring(response: 0.34, dampingFraction: 0.92)
}

// MARK: - Folder view

/// The floating folder. The shell's frame and corner radius move between the Apps control's frame
/// and the folder frame; the content is laid out at the open size and scales and fades with it, so
/// icon, shell and tiles read as one transition. Native Liquid Glass throughout.
struct AppsFolderOverlay: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var favourites = AppFavourites.shared

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
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool

    private var banner: AppLauncherPolicy.Banner {
        AppLauncherPolicy.banner(connected: remote.connected, installedCount: remote.installed.count,
                                 status: remote.status)
    }

    private var apps: [TVApp] {
        AppLauncherPolicy.filtered(AppLauncherPolicy.ordered(remote.apps, favourites: favourites.packages),
                                   query: query)
    }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let local = anchor.offsetBy(dx: -origin.x, dy: -origin.y)
            let target = AppsFolderLayout.frame(container: geo.size, anchor: local, isLandscape: isLandscape,
                                                appCount: remote.apps.count, showsBanner: banner != .none)
            let collapsed = AppsFolderLayout.collapsedFrame(anchor: local, container: geo.size)
            let frame = expanded ? target : collapsed
            let radius = expanded ? AppsFolderLayout.cornerRadius : anchorCornerRadius
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack(alignment: .topLeading) {
                scrim
                folderContent(width: target.width)
                    .frame(width: target.width, height: target.height)
                    .scaleEffect(expanded ? 1 : 0.55, anchor: .center)
                    .opacity(expanded ? 1 : 0)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(shape)
                    .glassSurface(shape, elevated: true)
                    .contentShape(shape)
                    .offset(x: frame.minX, y: frame.minY + dragOffset)
                    .allowsHitTesting(state.phase != .closing)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityLabel("Apps folder")
                    .accessibilityAction(.escape) { close(.escape) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onAppear {
            query = ""
            onMounted()
        }
        .onChange(of: state.phase) { _, phase in
            if phase == .open { titleFocused = true }
            if phase == .closing { searchFocused = false }
        }
    }

    private func close(_ reason: AppsFolderState.DismissReason) {
        searchFocused = false
        onDismiss(reason)
    }

    /// Dims the Remote and catches outside taps while the folder is open, and keeps a page swipe
    /// from starting under it. It never forwards a touch to the pad.
    private var scrim: some View {
        Color.black.opacity(expanded ? 0.22 : 0)
            .contentShape(Rectangle())
            .background(PagerExclusionZone())
            .onTapGesture { close(.outsideTap) }
            .allowsHitTesting(state.blocksOutside)
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }

    private func folderContent(width: CGFloat) -> some View {
        let count = AppsFolderLayout.columns(folderWidth: width)
        let grid = Array(repeating: GridItem(.flexible(), spacing: AppsFolderLayout.tileSpacing), count: count)
        return VStack(spacing: 12) {
            header
            searchField
            bannerView
            if apps.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: grid, spacing: AppsFolderLayout.rowSpacing) {
                        ForEach(apps) { app in tile(app) }
                    }
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(AppsFolderLayout.inset)
        .foregroundStyle(Color.ink)
    }

    /// Title row. Pulling it down dismisses the folder (the grid keeps its own scrolling).
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Apps").scaledFont(22, .bold).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(remote.connected ? "Tap to open on the TV box" : "TV box offline")
                    .scaledFont(12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Color.inkAlpha(0.6))
            }
            Spacer(minLength: 0)
            Button { close(.closeButton) } label: {
                Image(systemName: "xmark")
                    .scaledFont(14, .semibold)
                    .frame(width: 40, height: 40)
                    .glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Apps")
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in dragOffset = AppsFolderGesture.offset(for: value.translation.height) }
                .onEnded { value in
                    if AppsFolderGesture.shouldDismiss(translation: value.translation.height,
                                                       predicted: value.predictedEndTranslation.height) {
                        close(.swipe)
                    }
                    withAnimation(Motion.snappy) { dragOffset = 0 }
                }
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.inkAlpha(0.55))
            TextField("Search apps", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkAlpha(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(15)
        .padding(.horizontal, 14)
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2").scaledFont(28, .light)
            Text(query.isEmpty ? "No apps" : "No apps match “\(query)”").scaledFont(14, .semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if !query.isEmpty {
                Button("Clear search") { query = "" }.scaledFont(13)
            }
        }
        .foregroundStyle(Color.inkAlpha(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ app: TVApp) -> some View {
        let isFavourite = favourites.contains(app.package)
        return Button {
            guard state.acceptsLaunch else { return }
            searchFocused = false
            onLaunch(app)
        } label: {
            VStack(spacing: 6) {
                AppIconImage(asset: "\(app.asset)_dark")
                    .frame(width: AppsFolderLayout.tileSide, height: AppsFolderLayout.tileSide)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Color.ink.opacity(0.42), Color.ink.opacity(0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ink.opacity(0.07))
                    }
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
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
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color.inkAlpha(0.86))
            }
            .frame(maxWidth: .infinity)
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
