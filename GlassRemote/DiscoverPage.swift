import SwiftUI

/// Page 3: Discover. A Stremio-style browser: always-visible search, Continue Watching and Library
/// from the signed-in Stremio account, Cinemeta carousels, genre browsing and a detail sheet.
/// Everything shown is real data: catalogue entries come from Cinemeta, account rows from the
/// user's own Stremio library, and nothing is shown for a section whose data could not be loaded.
/// A catalogue result never means a stream exists.
struct DiscoverPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    @Environment(\.glassTheme) private var theme
    @StateObject private var model = DiscoverModel()
    @ObservedObject private var account = StremioAccount.shared
    @FocusState private var searching: Bool
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var target: DetailTarget?
    @State private var collection: CollectionRequest?
    @State private var showAccount = false
    @State private var launchNote = ""

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(spacing: 10) {
            // Search stays pinned above the scrolling content so it is reachable at all times.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    searchField
                    accountButton
                }
                GlassSegmented(
                    items: [GlassSegmented<DiscoverModel.Filter>.Item(value: .all, title: "All", symbol: nil),
                            GlassSegmented<DiscoverModel.Filter>.Item(value: .movies, title: "Movies", symbol: "film"),
                            GlassSegmented<DiscoverModel.Filter>.Item(value: .series, title: "Series", symbol: "tv")],
                    selection: $model.filter, height: 36)
            }
            .padding(.horizontal, 16).padding(.top, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if model.isSearching { searchContent } else { home }
                    if !launchNote.isEmpty {
                        Text(launchNote).scaledFont(12).foregroundStyle(Color.ink.opacity(0.7)).frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, DockMetrics.clearance + 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Color.ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $target) { item in
            TitleDetailView(title: item.title, libraryItem: item.libraryItem).environmentObject(remote)
        }
        .sheet(isPresented: $showAccount) { StremioAccountSheet() }
        .fullScreenCover(item: $collection) { request in
            CollectionView(request: request).environmentObject(remote)
        }
        .task { await model.loadHomeIfNeeded() }
        // Adaptive theme: the featured artwork (or the title being viewed) feeds the ONE shared palette.
        .onChange(of: model.featured?.id) { _ in publishArtwork() }
        .onChange(of: target?.id) { _ in publishArtwork() }
        .task { if account.state == .signedIn, account.libraryPhase == .idle { await account.refresh() } }
        // Search shortcut from the Remote page: wait for the page slide, then bring up the keyboard.
        .onChange(of: navigator.searchFocusToken) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                searching = true
            }
        }
    }

    private func publishArtwork() {
        let shown = target?.title ?? model.featured
        themeStore.submitArtwork(shown?.backgroundURL ?? shown?.posterURL, for: .discover)
    }

    // MARK: Search field and account

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").scaledFont(16, .medium).foregroundStyle(Color.ink.opacity(0.65))
            TextField("Search movies and series", text: $model.query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: model.query) { _ in model.queryChanged() }
                .onSubmit { searching = false }
            if !model.query.isEmpty {
                Button { model.query = ""; model.queryChanged(); searching = true } label: {
                    Image(systemName: "xmark.circle.fill").scaledFont(17).foregroundStyle(Color.ink.opacity(0.55))
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
                .foregroundStyle(account.state == .signedIn ? Color.ink : Color.ink.opacity(0.75))
                .frame(width: 48, height: 48)
                .glassSurface(Circle(), interactive: true)
                .overlay(alignment: .topTrailing) {
                    if account.state == .expired { Circle().fill(Color.orange).frame(width: 10, height: 10).offset(x: -3, y: 3) }
                }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(account.state == .signedIn ? "Stremio account, connected" : "Connect Stremio account")
    }

    // MARK: Home

    @ViewBuilder
    private var home: some View {
        if let featured = model.featured { hero(featured) }
        accountSections
        if !model.recents.isEmpty { recentChips }
        genreChips
        ForEach(model.visibleRows) { row in carousel(row) }
    }

    private func hero(_ title: StremioTitle) -> some View {
        Button { open(title) } label: {
            ZStack(alignment: .bottomLeading) {
                CachedArtwork(url: title.backgroundURL ?? title.posterURL, contentMode: .fill) {
                    Color.white.opacity(0.06)
                }
                .frame(height: 210).frame(maxWidth: .infinity).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Featured").scaledFont(11, .semibold).foregroundStyle(Color.white.opacity(0.7)).textCase(.uppercase)
                    Text(title.name).scaledFont(24, .bold).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(title.kind == .movie ? "Movie" : "Series")
                        if !title.year.isEmpty { Text("· \(title.year)") }
                        if !title.rating.isEmpty { Label(title.rating, systemImage: "star.fill").labelStyle(.titleAndIcon) }
                    }
                    .scaledFont(12, .medium).foregroundStyle(Color.white.opacity(0.8))
                }
                .foregroundStyle(Color.white)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PosterButtonStyle())
        .accessibilityLabel("Featured: \(title.name)")
    }

    // MARK: Account sections (Continue Watching, Library)

    @ViewBuilder
    private var accountSections: some View {
        switch account.state {
        case .signedOut, .signingIn:
            connectCard(text: "Connect your Stremio account to see Continue Watching and your Library here.", action: "Connect")
        case .expired:
            connectCard(text: "Your Stremio session expired.", action: "Sign in again")
        case .signedIn:
            switch account.libraryPhase {
            case .idle, .loading:
                if account.items.isEmpty { skeletonRow(title: "Continue Watching") }
                else { loadedAccountRows }
            case .failed(let message):
                VStack(spacing: 8) {
                    Text("Couldn't load your Stremio library").scaledFont(14, .semibold)
                    Text(message).scaledFont(12).foregroundStyle(Color.ink.opacity(0.6)).multilineTextAlignment(.center)
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
        if !cw.isEmpty {
            sectionHeader("Continue Watching", count: cw.count, seeAll: { collection = CollectionRequest(title: "Continue Watching", local: cw.compactMap(\.asTitle)) })
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(cw) { item in
                        if let t = item.asTitle {
                            Button { target = DetailTarget(title: t, libraryItem: item) } label: {
                                PosterCard(title: t, progress: item.progress, caption: continueCaption(item))
                            }.buttonStyle(PosterButtonStyle())
                        }
                    }
                }.padding(.horizontal, 16)
            }
            .claimsHorizontalTouches()
        }
        let lib = account.library.filter { $0.title != nil && (model.filter == .all || ($0.title == .movie) == (model.filter == .movies)) }
        ForEach([StremioTitle.Kind.movie, .series], id: \.rawValue) { kind in
            let items = lib.filter { $0.title == kind }
            if !items.isEmpty {
                sectionHeader(kind == .movie ? "Your movies" : "Your series", count: items.count,
                              seeAll: { collection = CollectionRequest(title: kind == .movie ? "Your movies" : "Your series", local: items.compactMap(\.asTitle)) })
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            if let t = item.asTitle {
                                Button { target = DetailTarget(title: t, libraryItem: item) } label: { PosterCard(title: t) }
                                    .buttonStyle(PosterButtonStyle())
                            }
                        }
                    }.padding(.horizontal, 16)
                }
                .claimsHorizontalTouches()
            }
        }
        // Watch history that is not in progress and not saved to the library (finished or watch-only titles).
        let history = account.watchHistory.filter { !$0.isContinueWatching && $0.title != nil
            && (model.filter == .all || ($0.title == .movie) == (model.filter == .movies)) }
        if !history.isEmpty {
            sectionHeader("Recently watched", count: history.count,
                          seeAll: { collection = CollectionRequest(title: "Recently watched", local: history.compactMap(\.asTitle)) })
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(history.prefix(30)) { item in
                        if let t = item.asTitle {
                            Button { target = DetailTarget(title: t, libraryItem: item) } label: { PosterCard(title: t) }
                                .buttonStyle(PosterButtonStyle())
                        }
                    }
                }.padding(.horizontal, 16)
            }
            .claimsHorizontalTouches()
        }
        if cw.isEmpty && lib.isEmpty && history.isEmpty {
            Text("Nothing in your Stremio library or watch history yet.")
                .scaledFont(13).foregroundStyle(Color.ink.opacity(0.55)).frame(maxWidth: .infinity).padding(.horizontal, 16)
        }
    }

    private func continueCaption(_ item: StremioLibraryItem) -> String {
        var parts: [String] = []
        if let e = item.episode { parts.append("S\(e.season) · E\(e.episode)") }
        let left = max(0, Int((item.durationMs - item.timeOffsetMs) / 60_000))
        if left > 0 { parts.append(left >= 60 ? "\(left / 60) h \(left % 60) min left" : "\(left) min left") }
        return parts.joined(separator: " · ")
    }

    private func connectCard(text: String, action: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus").scaledFont(26, .light).foregroundStyle(Color.ink.opacity(0.7))
            Text(text).scaledFont(13).foregroundStyle(Color.ink.opacity(0.78)).frame(maxWidth: .infinity, alignment: .leading)
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
                Button("Clear") { model.clearRecents() }.scaledFont(13, .semibold).foregroundStyle(Color.ink.opacity(0.7))
            }.padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
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
            .claimsHorizontalTouches()
        }
    }

    private var genreChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by genre").scaledFont(16, .bold).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StremioCatalog.genres, id: \.self) { g in
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
            .claimsHorizontalTouches()
        }
    }

    // MARK: Carousels

    private func sectionHeader(_ title: String, count: Int? = nil, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).scaledFont(20, .bold)
            if let count { Text("\(count)").scaledFont(13).foregroundStyle(Color.ink.opacity(0.5)) }
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
            case .idle, .loading: skeletonStrip
            case .failed:
                HStack {
                    Text("Couldn't load this row.").scaledFont(12).foregroundStyle(Color.ink.opacity(0.5))
                    Button("Retry") { Task { await model.retryRow(row.id) } }.scaledFont(12, .semibold)
                }.padding(.horizontal, 16)
            case .loaded:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(row.items) { item in
                            Button { open(item) } label: { PosterCard(title: item) }.buttonStyle(PosterButtonStyle())
                        }
                    }.padding(.horizontal, 16)
                }
                .claimsHorizontalTouches()
            }
        }
        // Rows request their data only when they scroll into view.
        .task { await model.loadRowIfNeeded(row.id) }
    }

    private var skeletonStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ink.opacity(0.06))
                        .frame(width: PosterCard.width, height: PosterCard.width * 1.5)
                        .overlay(ProgressView().tint(Color.ink.opacity(0.5)))
                }
            }.padding(.horizontal, 16)
        }
        .disabled(true).accessibilityLabel("Loading")
    }

    private func skeletonRow(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { sectionHeader(title); skeletonStrip }
    }

    // MARK: Search results

    @ViewBuilder
    private var searchContent: some View {
        switch model.phase {
        case .idle, .searching:
            VStack(alignment: .leading, spacing: 12) {
                suggestionList
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ink.opacity(0.06))
                            .aspectRatio(2.0 / 3.0, contentMode: .fit).overlay(ProgressView().tint(Color.ink.opacity(0.6)))
                    }
                }.padding(.horizontal, 16)
            }
        case .empty:
            note("film.stack", "No results", "Nothing in the catalogue matches “\(model.query)”.", searchInStremio: true)
        case .failed(let message):
            VStack(spacing: 10) {
                note("wifi.exclamationmark", "Can't reach the catalogue", message, searchInStremio: false)
                Button("Try again") { model.retrySearch() }.scaledFont(14, .semibold)
            }
        case .results:
            if model.visibleMovies.isEmpty && model.visibleSeries.isEmpty {
                note(model.filter == .movies ? "film" : "tv", model.filter == .movies ? "No movies" : "No series",
                     "Try “All” to see everything that matched.", searchInStremio: false)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    suggestionList
                    searchInStremioButton
                    grid("Movies", model.visibleMovies)
                    grid("Series", model.visibleSeries)
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        let list = model.suggestions
        if !list.isEmpty {
            VStack(spacing: 6) {
                ForEach(list.prefix(3), id: \.self) { text in
                    Button { model.useRecent(text) } label: {
                        HStack { Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.ink.opacity(0.55)); Text(text).scaledFont(14); Spacer() }
                            .padding(.horizontal, 16).frame(height: 40).glassSurface(Capsule(), interactive: true)
                    }.buttonStyle(PressStyle())
                }
            }.padding(.horizontal, 16)
        }
    }

    private var searchInStremioButton: some View {
        Button {
            Task { launchNote = await remote.searchInStremio(model.query) }
        } label: {
            Label("Search “\(model.query.trimmingCharacters(in: .whitespaces))” in Stremio on the TV", systemImage: "arrow.up.forward.app")
                .scaledFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 40).glassSurface(Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected).opacity(remote.connected ? 1 : 0.5)
        .padding(.horizontal, 16)
    }

    private func note(_ symbol: String, _ title: String, _ text: String, searchInStremio: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).scaledFont(32, .light).foregroundStyle(Color.ink.opacity(0.45))
            Text(title).scaledFont(17, .semibold)
            Text(text).scaledFont(13).foregroundStyle(Color.ink.opacity(0.58)).multilineTextAlignment(.center)
            if searchInStremio { searchInStremioButton.padding(.top, 8) }
        }
        .frame(maxWidth: .infinity).padding(.top, 30).padding(.horizontal, 12)
    }

    @ViewBuilder
    private func grid(_ title: String, _ items: [StremioTitle]) -> some View {
        if !items.isEmpty {
            sectionHeader(title, count: items.count)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    Button { open(item) } label: { PosterCard(title: item, fixedWidth: false) }
                        .buttonStyle(PosterButtonStyle())
                }
            }.padding(.horizontal, 16)
        }
    }

    private func open(_ title: StremioTitle) {
        searching = false; launchNote = ""
        target = DetailTarget(title: title, libraryItem: account.item(id: title.id))
    }
}

struct DetailTarget: Identifiable {
    let title: StremioTitle
    let libraryItem: StremioLibraryItem?
    var id: String { title.id }
}

/// Portrait 2:3 poster with title and year. Artwork is never stretched or square-cropped.
struct PosterCard: View {
    static let width: CGFloat = 112
    let title: StremioTitle
    var progress: Double? = nil
    var caption: String? = nil
    var fixedWidth = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedArtwork(url: title.posterURL, fallbackURL: title.fallbackPosterURL, contentMode: .fill) { placeholder }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0 {
                        ProgressView(value: progress).tint(Color.white).padding(8)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.ink.opacity(0.22), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
            Text(title.name).scaledFont(13, .semibold).lineLimit(2).multilineTextAlignment(.leading)
            if let caption, !caption.isEmpty {
                Text(caption).scaledFont(11).foregroundStyle(Color.ink.opacity(0.6)).lineLimit(2).multilineTextAlignment(.leading)
            } else if !title.year.isEmpty {
                Text(title.year).scaledFont(11).foregroundStyle(Color.ink.opacity(0.55))
            }
        }
        .frame(width: fixedWidth ? Self.width : nil, alignment: .topLeading)
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

extension View {
    /// Horizontal carousels scroll their own content. Only a horizontal-dominant drag marks the touch
    /// as "not a page swipe" for the pager; vertical drags are never claimed, so the page scrolls
    /// normally even when the finger starts on a carousel. (The Phase 3 version attached a
    /// zero-distance drag to every carousel, which grabbed the touch immediately.)
    func claimsHorizontalTouches() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) { ScrubTouch.shared.touch() }
            }
        )
    }
}

/// Poster tap style: a light press scale with NO haptic. A haptic on touch-down fired at the start
/// of every scroll that began on a poster.
struct PosterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
