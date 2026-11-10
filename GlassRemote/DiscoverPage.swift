import SwiftUI

/// Page 3: Discover. Always-visible search, Continue Watching and Recently watched from the signed-in
/// Nuvio account's synced watch progress, Cinemeta catalogue carousels (Cinemeta is Nuvio's default
/// metadata addon), genre browsing and a detail sheet.
/// Everything shown is real data. There is no "personalised recommendations" row and no library or
/// watchlist row: Nuvio's library RPCs were not verified, so nothing is invented for them.
/// A catalogue result never means a stream exists.
struct DiscoverPage: View {
    @Environment(\.dockClearance) private var dockClearance
    @Environment(\.layoutContext) private var layoutContext
    @EnvironmentObject private var navigator: PageNavigator
    @Environment(\.glassTheme) private var theme
    @StateObject private var model = DiscoverModel()
    @ObservedObject private var account = NuvioAccount.shared
    @FocusState private var searching: Bool
    /// Plain reference (not observed): the page only submits artwork, so palette animations must not rebuild it.
    private var themeStore: ThemeStore { .shared }
    @State private var target: DetailTarget?
    @State private var collection: CollectionRequest?
    @State private var showAccount = false
    @State private var launchNote = ""
    @State private var heroID: String?
    @State private var playTarget: MediaTitle?
    @State private var headerHeight: CGFloat = 104
    @State private var headerSolid = false
    @Environment(\.railClearance) private var railClearance
    @ObservedObject private var profiles = ProfileStore.shared
    @Namespace private var zoom

    private var settings: ProfileSettings { profiles.active.settings }
    private var metrics: DiscoverMetrics { DiscoverMetrics(isLandscape: layoutContext.isLandscape) }
    private var heroTitles: [MediaTitle] { model.featuredPool }
    private var currentHero: MediaTitle? { heroTitles.first { $0.id == heroID } ?? heroTitles.first }
    /// The popular rows that feed the hero are still loading, so its space is reserved (no layout jump).
    private var heroLoading: Bool {
        model.rows.contains { $0.source.catalog == "top" && $0.source.genre == nil && ($0.phase == .idle || $0.phase == .loading) }
    }
    private var showsHero: Bool { !model.isSearching && (!heroTitles.isEmpty || heroLoading) }

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12, alignment: .top)]
    private let wideColumns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12, alignment: .top)]

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let heroWidth = proxy.size.width + railClearance
            let heroHeight = DiscoverHeroLayout.height(width: heroWidth, height: proxy.size.height + insets.top,
                                                       isLandscape: layoutContext.isLandscape)
            let solidAfter = heroHeight - insets.top - headerHeight - 12
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).background {
                            GeometryReader { g in
                                Color.clear.preference(key: DiscoverScrollOffsetKey.self, value: g.frame(in: .named(DiscoverHero.space)).minY)
                            }
                        }
                        if showsHero {
                            hero(width: heroWidth, height: heroHeight)
                        } else {
                            // Room for the floating search bar when there is no hero behind it.
                            Color.clear.frame(height: insets.top + headerHeight + 8)
                        }
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if model.isSearching { searchContent } else { home }
                            if !launchNote.isEmpty {
                                Text(launchNote).scaledFont(12).foregroundStyle(Color.inkAlpha(0.7)).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, showsHero ? 4 : 0)
                        .padding(.leading, railClearance)
                        .padding(.bottom, dockClearance + 16)
                    }
                }
                .coordinateSpace(name: DiscoverHero.space)
                .scrollDismissesKeyboard(.interactively)
                // The hero runs under the status bar and, in landscape, under the glass rail.
                .padding(.leading, -railClearance)
                .ignoresSafeArea(.container, edges: .top)

                headerBar
                    .background {
                        GeometryReader { g in Color.clear.preference(key: DiscoverHeaderHeightKey.self, value: g.size.height) }
                    }
            }
            .onPreferenceChange(DiscoverHeaderHeightKey.self) { headerHeight = $0 }
            .onPreferenceChange(DiscoverScrollOffsetKey.self) { y in
                let solid = -y > solidAfter
                if solid != headerSolid { headerSolid = solid }
            }
        }
        .foregroundStyle(Color.ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $target) { item in
            TitleDetailView(title: item.title, libraryItem: item.libraryItem, onShowRemote: {
                target = nil
                navigator.go(.remote)
            })
            .environmentObject(RemoteModel.shared)
            .modifier(DetailZoomDestination(id: item.sourceID, namespace: zoom))
        }
        .sheet(item: $playTarget) { title in
            StreamPickerSheet(title: title, onHandoff: { launchNote = $0 })
                .environmentObject(RemoteModel.shared)
        }
        .sheet(isPresented: $showAccount) { NuvioAccountSheet() }
        .fullScreenCover(item: $collection) { request in
            CollectionView(request: request).environmentObject(RemoteModel.shared)
        }
        .task { await model.loadHomeIfNeeded() }
        // Adaptive theme: the featured artwork (or the title being viewed) feeds the ONE shared palette.
        .onChange(of: model.featured?.id) { _ in publishArtwork() }
        .onChange(of: target?.id) { _ in publishArtwork() }
        .onChange(of: heroID) { _ in publishArtwork() }
        .task { if account.state == .signedIn, account.libraryPhase == .idle { await account.refresh() } }
        // Search shortcut from the Remote page: wait for the page slide, then bring up the keyboard.
        .onChange(of: navigator.searchFocusToken) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                searching = true
            }
        }
    }

    /// Floating glass header over the hero. Search stays reachable at all times; in landscape the filter
    /// sits beside it (one row). AnyLayout keeps the field's identity, so focus survives rotation.
    /// Once rows scroll beneath it a canvas-coloured veil fades in behind it for legibility.
    private var headerBar: some View {
        let solid = headerSolid || !showsHero
        return header {
            HStack(spacing: 10) {
                searchField
                accountButton
            }
            GlassSegmented(
                items: [GlassSegmented<DiscoverModel.Filter>.Item(value: .all, title: "All", symbol: nil),
                        GlassSegmented<DiscoverModel.Filter>.Item(value: .movies, title: "Movies", symbol: nil),
                        GlassSegmented<DiscoverModel.Filter>.Item(value: .series, title: "Series", symbol: nil)],
                selection: $model.filter, height: 36)
            .frame(maxWidth: layoutContext.isLandscape ? 300 : .infinity)
        }
        .padding(.horizontal, 16).padding(.top, layoutContext.isLandscape ? 6 : 10).padding(.bottom, 8)
        .background {
            LinearGradient(colors: [theme.canvasTop.opacity(0.94), theme.canvasTop.opacity(0)], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -18)
                .ignoresSafeArea(.container, edges: .top)
                .opacity(solid ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: solid)
                .allowsHitTesting(false)
        }
    }

    /// Portrait: search row above the filter. Landscape: one row, so more of the catalogue is visible.
    private var header: AnyLayout {
        layoutContext.isLandscape ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 10))
    }

    private func publishArtwork() {
        let shown = target?.title ?? currentHero
        themeStore.submitArtwork(shown?.backgroundURL ?? shown?.posterURL, for: .discover)
    }

    // MARK: Search field and account

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").scaledFont(16, .medium).foregroundStyle(Color.inkAlpha(0.65))
            TextField("Search movies and series", text: $model.query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: model.query) { _ in model.queryChanged() }
                .onSubmit { searching = false }
            if !model.query.isEmpty {
                Button { model.query = ""; model.queryChanged(); searching = true } label: {
                    Image(systemName: "xmark.circle.fill").scaledFont(17).foregroundStyle(Color.inkAlpha(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(16)
        .padding(.horizontal, 16).frame(height: 48)
        .glassBar(Capsule())
    }

    private var accountButton: some View {
        Button { showAccount = true } label: {
            Image(systemName: account.state == .signedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .scaledFont(22, .regular)
                .foregroundStyle(account.state == .signedIn ? Color.ink : Color.inkAlpha(0.75))
                .frame(width: 48, height: 48)
                .glassSurface(Circle(), interactive: true)
                .overlay(alignment: .topTrailing) {
                    if account.state == .expired { Circle().fill(Color.orange).frame(width: 10, height: 10).offset(x: -3, y: 3) }
                }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(account.state == .signedIn ? "Nuvio account, connected" : "Connect Nuvio account")
    }

    // MARK: Home

    @ViewBuilder
    private var home: some View {
        accountSections
        if !model.recents.isEmpty { recentChips }
        let rows = model.visibleRows
        // Popular / Top rated / Newest first, then genre browsing, then the genre collections.
        ForEach(rows.filter { $0.source.genre == nil }) { row in carousel(row) }
        genreChips
        ForEach(rows.filter { $0.source.genre != nil }) { row in carousel(row) }
    }

    @ViewBuilder
    private func hero(width: CGFloat, height: CGFloat) -> some View {
        if heroTitles.isEmpty {
            ZStack {
                LinearGradient(colors: [theme.accent.opacity(0.2), Color.clear], startPoint: .top, endPoint: .bottom)
                ProgressView().tint(Color.inkAlpha(0.6))
            }
            .frame(width: width, height: height)
            .accessibilityLabel("Loading featured titles")
        } else {
            DiscoverHero(titles: heroTitles, selection: $heroID, size: CGSize(width: width, height: height),
                         isLandscape: layoutContext.isLandscape, leadingInset: railClearance,
                         onOpen: { open($0) },
                         onPlay: { title in
                             if title.kind == .movie { searching = false; playTarget = title } else { open(title) }
                         })
        }
    }

    // MARK: Account sections (Continue Watching, Library)

    @ViewBuilder
    private var accountSections: some View {
        switch account.state {
        case .signedOut:
            connectCard(text: "Connect your Nuvio account to see Continue Watching and your watch history here.", action: "Connect")
        case .expired:
            connectCard(text: "Your Nuvio session expired.", action: "Sign in again")
        case .signedIn:
            switch account.libraryPhase {
            case .idle, .loading:
                if account.items.isEmpty { skeletonRow(title: "Continue Watching", usage: .progress) }
                else { loadedAccountRows }
            case .failed(let message):
                VStack(spacing: 8) {
                    Text("Couldn't load your Nuvio watch progress").scaledFont(14, .semibold)
                    Text(message).scaledFont(12).foregroundStyle(Color.inkAlpha(0.6)).multilineTextAlignment(.center)
                    Button("Try again") { Task { await account.refresh() } }.scaledFont(13, .semibold)
                }
                .frame(maxWidth: .infinity).padding(14)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous)).padding(.horizontal, 16)
            case .loaded:
                loadedAccountRows
            }
        }
    }

    @ViewBuilder
    private var loadedAccountRows: some View {
        let cw = account.continueWatching.filter { model.filter == .all || ($0.title == .movie) == (model.filter == .movies) }
        if !cw.isEmpty && settings.showContinueWatching {
            sectionHeader("Continue Watching", count: cw.count, seeAll: { collection = CollectionRequest(title: "Continue Watching", local: cw.compactMap(\.asTitle)) })
            UnclippedHScroll {
                LazyHStack(alignment: .top, spacing: metrics.spacing) {
                    ForEach(cw) { item in
                        if let t = item.asTitle {
                            Button { target = DetailTarget(title: t, libraryItem: item, sourceID: "cw|\(t.id)") } label: {
                                card(t, usage: .progress, progress: item.progress, caption: continueCaption(item), zoomID: "cw|\(t.id)")
                            }.buttonStyle(PosterButtonStyle())
                        }
                    }
                }.padding(.horizontal, 16)
            }
        }
        // Finished titles and anything else with recorded playback that is not in progress.
        let history = account.watchHistory.filter { !$0.isContinueWatching && $0.title != nil
            && (model.filter == .all || ($0.title == .movie) == (model.filter == .movies)) }
        if !history.isEmpty {
            sectionHeader("Recently watched", count: history.count,
                          seeAll: { collection = CollectionRequest(title: "Recently watched", local: history.compactMap(\.asTitle)) })
            UnclippedHScroll {
                LazyHStack(alignment: .top, spacing: metrics.spacing) {
                    ForEach(history.prefix(30)) { item in
                        if let t = item.asTitle {
                            Button { target = DetailTarget(title: t, libraryItem: item, sourceID: "hist|\(t.id)") } label: {
                                card(t, zoomID: "hist|\(t.id)")
                            }
                            .buttonStyle(PosterButtonStyle())
                        }
                    }
                }.padding(.horizontal, 16)
            }
        }
        if cw.isEmpty && history.isEmpty {
            Text("Nothing in your Nuvio watch history yet.")
                .scaledFont(13).foregroundStyle(Color.inkAlpha(0.55)).frame(maxWidth: .infinity).padding(.horizontal, 16)
        }
    }

    private func continueCaption(_ item: NuvioWatchItem) -> String {
        var parts: [String] = []
        if let e = item.episode { parts.append("S\(e.season) · E\(e.episode)") }
        let left = max(0, Int((item.durationMs - item.timeOffsetMs) / 60_000))
        if left > 0 { parts.append(left >= 60 ? "\(left / 60) h \(left % 60) min left" : "\(left) min left") }
        return parts.joined(separator: " · ")
    }

    private func connectCard(text: String, action: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus").scaledFont(26, .light).foregroundStyle(Color.inkAlpha(0.7))
            Text(text).scaledFont(13).foregroundStyle(Color.inkAlpha(0.78)).frame(maxWidth: .infinity, alignment: .leading)
            Button { showAccount = true } label: {
                Text(action).scaledFont(13, .semibold).padding(.horizontal, 14).frame(height: 34)
                    .glassSurface(Capsule(), interactive: true, elevated: true)
            }.buttonStyle(PressStyle())
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: Recents and genres

    private var recentChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent searches").scaledFont(16, .bold)
                Spacer()
                Button("Clear") { model.clearRecents() }.scaledFont(13, .semibold).foregroundStyle(Color.inkAlpha(0.7))
            }.padding(.horizontal, 16)
            UnclippedHScroll {
                HStack(spacing: 8) {
                    ForEach(model.recents, id: \.self) { text in
                        Button { model.useRecent(text) } label: {
                            Label(text, systemImage: "clock.arrow.circlepath").scaledFont(13).lineLimit(1)
                                .padding(.horizontal, 14).frame(height: 36)
                                .glassSurface(Capsule(), interactive: true)
                        }.buttonStyle(PressStyle())
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    private var genreChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by genre").scaledFont(16, .bold).padding(.horizontal, 16)
            UnclippedHScroll {
                HStack(spacing: 8) {
                    ForEach(CinemetaCatalog.genres, id: \.self) { g in
                        Button {
                            collection = CollectionRequest(title: g, kind: model.filter == .series ? .series : .movie, catalog: "top", genre: g)
                        } label: {
                            Text(g).scaledFont(13, .semibold).padding(.horizontal, 14).frame(height: 34)
                                .glassSurface(Capsule(), interactive: true)
                        }
                        .buttonStyle(PressStyle())
                    }
                }.padding(.horizontal, 16)
            }
        }
    }

    // MARK: Carousels

    private func sectionHeader(_ title: String, count: Int? = nil, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).scaledFont(20, .bold)
            if let count { Text("\(count)").scaledFont(13).foregroundStyle(Color.inkAlpha(0.5)) }
            Spacer()
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 3) { Text("See All"); Image(systemName: "chevron.right").scaledFont(11, .semibold) }
                        .scaledFont(13, .semibold).foregroundStyle(theme.accent)
                        .padding(.vertical, 6).padding(.leading, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(title)")
            }
        }.padding(.horizontal, 16)
    }

    @ViewBuilder
    private func carousel(_ row: DiscoverRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(row.title, seeAll: row.phase == .failed ? nil : {
                collection = CollectionRequest(title: row.title, kind: row.kind, catalog: row.source.catalog, genre: row.source.genre)
            })
            switch row.phase {
            case .idle, .loading: skeletonStrip()
            case .failed:
                HStack {
                    Text("Couldn't load this row.").scaledFont(12).foregroundStyle(Color.inkAlpha(0.5))
                    Button("Retry") { Task { await model.retryRow(row.id) } }.scaledFont(12, .semibold)
                }.padding(.horizontal, 16)
            case .loaded:
                UnclippedHScroll {
                    LazyHStack(alignment: .top, spacing: metrics.spacing) {
                        ForEach(row.items) { item in
                            Button { open(item, zoomID: "\(row.id)|\(item.id)") } label: {
                                card(item, zoomID: "\(row.id)|\(item.id)")
                            }
                            .buttonStyle(PosterButtonStyle())
                        }
                    }.padding(.horizontal, 16)
                }
            }
        }
        // Rows request their data only when they scroll into view.
        .task { await model.loadRowIfNeeded(row.id) }
    }

    /// One card in the profile's artwork orientation; zoomID ties it to the detail page's zoom transition.
    @ViewBuilder
    private func card(_ t: MediaTitle, usage: DiscoverCardShape.Usage = .catalog, progress: Double? = nil,
                      caption: String? = nil, zoomID: String) -> some View {
        Group {
            switch DiscoverCardShape.resolve(settings.posterOrientation, usage: usage) {
            case .portrait: PosterCard(title: t, progress: progress, caption: caption, cardWidth: metrics.poster)
            case .landscape: LandscapeCard(title: t, progress: progress, caption: caption, cardWidth: metrics.landscape)
            }
        }
        .modifier(DetailZoomSource(id: zoomID, namespace: zoom))
    }

    /// Placeholder cards with the same shape and size as the cards that will replace them.
    private func skeletonStrip(_ usage: DiscoverCardShape.Usage = .catalog) -> some View {
        let portrait = DiscoverCardShape.resolve(settings.posterOrientation, usage: usage) == .portrait
        let width = portrait ? metrics.poster : metrics.landscape
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.spacing) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: portrait ? 16 : 18, style: .continuous).fill(Color.ink.opacity(0.06))
                        .frame(width: width, height: portrait ? width * 1.5 : width * 9 / 16)
                        .overlay(ProgressView().tint(Color.inkAlpha(0.5)))
                }
            }.padding(.horizontal, 16)
        }
        .disabled(true).accessibilityLabel("Loading")
    }

    private func skeletonRow(title: String, usage: DiscoverCardShape.Usage = .catalog) -> some View {
        VStack(alignment: .leading, spacing: 10) { sectionHeader(title); skeletonStrip(usage) }
    }

    // MARK: Search results

    @ViewBuilder
    private var searchContent: some View {
        switch model.phase {
        case .searching where model.hasResults:
            results(updating: true)
        case .idle, .searching:
            VStack(alignment: .leading, spacing: 12) {
                suggestionList
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ink.opacity(0.06))
                            .aspectRatio(2.0 / 3.0, contentMode: .fit).overlay(ProgressView().tint(Color.inkAlpha(0.6)))
                    }
                }.padding(.horizontal, 16)
            }
        case .empty:
            note("film.stack", "No results", "Nothing in the catalogue matches “\(model.query)”.", searchInNuvio: true)
        case .failed(let message):
            VStack(spacing: 10) {
                note("wifi.exclamationmark", "Can't reach the catalogue", message, searchInNuvio: false)
                Button("Try again") { model.retrySearch() }.scaledFont(14, .semibold)
            }
        case .results:
            if model.visibleMovies.isEmpty && model.visibleSeries.isEmpty {
                note(model.filter == .movies ? "film" : "tv", model.filter == .movies ? "No movies" : "No series",
                     "Try “All” to see everything that matched.", searchInNuvio: false)
            } else {
                results(updating: false)
            }
        }
    }

    /// Ranked results. While a newer query loads, the previous results stay with a small progress badge.
    private func results(updating: Bool) -> some View {
        let top = model.topResult
        return VStack(alignment: .leading, spacing: 14) {
            suggestionList
            if let top { topResultCard(top) }
            searchInNuvioButton
            grid("Movies", model.visibleMovies.filter { $0.id != top?.id })
            grid("Series", model.visibleSeries.filter { $0.id != top?.id })
        }
        .overlay(alignment: .top) {
            if updating {
                ProgressView().tint(Color.inkAlpha(0.7)).padding(8).glassSurface(Circle())
                    .transition(.opacity).accessibilityLabel("Updating results")
            }
        }
    }

    private func topResultCard(_ t: MediaTitle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Top result")
            Button { open(t, zoomID: "top|\(t.id)") } label: {
                HStack(spacing: 14) {
                    Color.clear.frame(width: 84, height: 126)
                        .overlay {
                            CachedArtwork(url: t.posterURL, fallbackURL: t.fallbackPosterURL, contentMode: .fill) { Color.ink.opacity(0.06) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.name).scaledFont(18, .bold).lineLimit(2).multilineTextAlignment(.leading)
                        Text(DiscoverMetaLine.kindAndYear(t.kind, year: t.year)).scaledFont(13).foregroundStyle(Color.inkAlpha(0.6))
                        if !t.overview.isEmpty {
                            Text(t.overview).scaledFont(12).foregroundStyle(Color.inkAlpha(0.7)).lineLimit(3).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").scaledFont(13, .semibold).foregroundStyle(Color.inkAlpha(0.4))
                }
                .padding(12)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                .modifier(DetailZoomSource(id: "top|\(t.id)", namespace: zoom))
            }
            .buttonStyle(PosterButtonStyle())
            .padding(.horizontal, 16)
            .accessibilityLabel("Top result: \(t.name)")
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        let list = model.suggestions
        if !list.isEmpty {
            VStack(spacing: 6) {
                ForEach(list.prefix(3), id: \.self) { text in
                    Button { model.useRecent(text) } label: {
                        HStack { Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.inkAlpha(0.55)); Text(text).scaledFont(14); Spacer() }
                            .padding(.horizontal, 16).frame(height: 40).glassSurface(Capsule(), interactive: true)
                    }.buttonStyle(PressStyle())
                }
            }.padding(.horizontal, 16)
        }
    }

    /// Its own view so the connection model (which publishes often) only re-renders this button,
    /// not the whole scrolling page.
    private var searchInNuvioButton: some View {
        SearchInNuvioButton(query: model.query) { launchNote = $0 }
    }

    private func note(_ symbol: String, _ title: String, _ text: String, searchInNuvio: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).scaledFont(32, .light).foregroundStyle(Color.inkAlpha(0.45))
            Text(title).scaledFont(17, .semibold)
            Text(text).scaledFont(13).foregroundStyle(Color.inkAlpha(0.58)).multilineTextAlignment(.center)
            if searchInNuvio { searchInNuvioButton.padding(.top, 8) }
        }
        .frame(maxWidth: .infinity).padding(.top, 30).padding(.horizontal, 12)
    }

    @ViewBuilder
    private func grid(_ title: String, _ items: [MediaTitle]) -> some View {
        if !items.isEmpty {
            let portrait = DiscoverCardShape.resolve(settings.posterOrientation, usage: .catalog) == .portrait
            sectionHeader(title, count: items.count)
            LazyVGrid(columns: portrait ? columns : wideColumns, spacing: 16) {
                ForEach(items) { item in
                    Button { open(item, zoomID: "grid|\(item.id)") } label: {
                        Group {
                            if portrait { PosterCard(title: item, fixedWidth: false) }
                            else { LandscapeCard(title: item, cardWidth: nil) }
                        }
                        .modifier(DetailZoomSource(id: "grid|\(item.id)", namespace: zoom))
                    }
                    .buttonStyle(PosterButtonStyle())
                }
            }.padding(.horizontal, 16)
        }
    }

    private func open(_ title: MediaTitle, zoomID: String? = nil) {
        searching = false; launchNote = ""
        target = DetailTarget(title: title, libraryItem: account.item(id: title.id), sourceID: zoomID)
    }
}

private struct DiscoverHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct DiscoverScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DetailTarget: Identifiable {
    let title: MediaTitle
    let libraryItem: NuvioWatchItem?
    /// The card the detail page zooms out of (nil: standard sheet).
    var sourceID: String? = nil
    var id: String { title.id }
}

private struct SearchInNuvioButton: View {
    @EnvironmentObject private var remote: RemoteModel
    let query: String
    let onResult: (String) -> Void

    var body: some View {
        Button {
            Task { onResult(await remote.searchInNuvio(query)) }
        } label: {
            Label("Search “\(query.trimmingCharacters(in: .whitespaces))” in Nuvio on the TV", systemImage: "arrow.up.forward.app")
                .scaledFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 40).glassSurface(Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected).controlDisabled(!remote.connected)
        .padding(.horizontal, 16)
    }
}

/// Portrait 2:3 poster with title and year. Artwork is never stretched or square-cropped.
struct PosterCard: View {
    static let width: CGFloat = 112
    let title: MediaTitle
    var progress: Double? = nil
    var caption: String? = nil
    var fixedWidth = true
    var cardWidth: CGFloat = PosterCard.width

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Exact 2:3 base with the artwork in an overlay: catalogue posters are often slightly wider
            // than 2:3, and as the base a filled poster grew the card past its width once it loaded.
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    CachedArtwork(url: title.posterURL, fallbackURL: title.fallbackPosterURL, contentMode: .fill) { placeholder }
                }
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0 {
                        ProgressView(value: progress).tint(Color.white).padding(8)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.ink.opacity(0.22), lineWidth: 0.8))
                // Shadow from a plain shape behind the poster, not from the decoded image.
                .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black).shadow(color: .black.opacity(0.45), radius: 8, y: 5) }
            Text(title.name).scaledFont(13, .semibold).lineLimit(2).multilineTextAlignment(.leading)
            if let caption, !caption.isEmpty {
                Text(caption).scaledFont(11).foregroundStyle(Color.inkAlpha(0.6)).lineLimit(2).multilineTextAlignment(.leading)
            } else if !title.year.isEmpty {
                Text(title.year).scaledFont(11).foregroundStyle(Color.inkAlpha(0.55))
            }
        }
        .frame(width: fixedWidth ? cardWidth : nil, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title.name)\(title.year.isEmpty ? "" : ", \(title.year)")")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.ink.opacity(0.09), Color.ink.opacity(0.03)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Image(systemName: title.kind == .movie ? "film" : "tv").scaledFont(24, .light)
                Text(title.name).scaledFont(11, .medium).lineLimit(3).multilineTextAlignment(.center).padding(.horizontal, 8)
            }.foregroundStyle(Color.ink.opacity(0.4))
        }
    }
}

/// Pure text for the Discover hero's meta line (unit tested).
enum DiscoverMetaLine {
    /// One spaced middle dot between parts, so every gap on the line is the same width.
    static let separator = " · "

    /// "Movie · 2026", or just "Series" when the catalogue has no year (no dangling dot).
    static func kindAndYear(_ kind: MediaTitle.Kind, year: String) -> String {
        [kind == .movie ? "Movie" : "Series", year.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}

/// Poster tap style: a light press scale with NO haptic. A haptic on touch-down fired at the start
/// of every scroll that began on a poster.
struct PosterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : Motion.snappy, value: configuration.isPressed)
    }
}

/// Horizontal scroller whose content can grow past its natural bounds without being cut off.
///
/// Root cause of the old clipping bug: a horizontal `ScrollView` clips to its own frame, and the chip
/// rows were exactly as tall as their chips. A held `.glassEffect(.interactive())` chip (and a pressed
/// poster with its shadow) grows beyond that frame, so the scroll view sliced it. The fix is structural:
/// the content gets vertical breathing room inside the scroll view, the surplus is cancelled with a
/// negative outer padding so page spacing is unchanged, and `scrollClipDisabled` (iOS 17+) lets glass
/// extend past the edges. No fixed heights were changed and nothing is hidden.
struct UnclippedHScroll<Content: View>: View {
    private let inset: CGFloat
    private let content: Content
    init(inset: CGFloat = 12, @ViewBuilder content: () -> Content) { self.inset = inset; self.content = content() }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { content.padding(.vertical, inset) }
            .modifier(ScrollClipOff())
            .padding(.vertical, -inset)
    }
}

private struct ScrollClipOff: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) { content.scrollClipDisabled() } else { content }
    }
}

/// 16:9 card for landscape artwork. Uses the title's backdrop; with no backdrop the poster is shown
/// whole (aspect-fit) on a dark panel instead of being stretched or cropped into the wide frame.
struct LandscapeCard: View {
    static let width: CGFloat = 232
    let title: MediaTitle
    var progress: Double? = nil
    var caption: String? = nil
    /// Nil fills the available width (grids); the 16:9 shape is kept either way.
    var cardWidth: CGFloat? = LandscapeCard.width

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(width: cardWidth)
                .overlay {
                    ZStack {
                        if let background = title.backgroundURL {
                            CachedArtwork(url: background, contentMode: .fill) { Color.ink.opacity(0.06) }
                        } else {
                            Color.black.opacity(0.5)
                            CachedArtwork(url: title.posterURL, fallbackURL: title.fallbackPosterURL, contentMode: .fit) { Color.clear }.padding(6)
                        }
                    }
                }
            .overlay(alignment: .bottom) {
                if let progress, progress > 0 {
                    ProgressView(value: progress).tint(Color.white).padding(8)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.ink.opacity(0.22), lineWidth: 0.8))
            .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black).shadow(color: .black.opacity(0.45), radius: 8, y: 5) }
            Text(title.name).scaledFont(13, .semibold).lineLimit(1)
            if let caption, !caption.isEmpty {
                Text(caption).scaledFont(11).foregroundStyle(Color.inkAlpha(0.6)).lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title.name)\(caption.map { ", \($0)" } ?? "")")
    }
}
