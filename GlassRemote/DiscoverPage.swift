import SwiftUI

/// Page 3: Stremio discovery. Search uses Stremio's public Cinemeta catalogue from the phone
/// (unchanged backend). Dictation is the keyboard's microphone. Opening a title in Stremio is an
/// experimental deep link the user must switch on; a catalogue result never means a stream exists.
struct DiscoverPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    @StateObject private var model = DiscoverModel()
    @FocusState private var searching: Bool
    @AppStorage(RemoteModel.deepLinkDefaultsKey) private var deepLinkTest = false
    @State private var selected: StremioTitle?
    @State private var result = ""

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                GlassSegmented(
                    items: [GlassSegmented<DiscoverModel.Filter>.Item(value: .all, title: "All", symbol: nil),
                            GlassSegmented<DiscoverModel.Filter>.Item(value: .movies, title: "Movies", symbol: "film"),
                            GlassSegmented<DiscoverModel.Filter>.Item(value: .series, title: "Series", symbol: "tv")],
                    selection: $model.filter, height: 38)
                content
                launchToggle
            }
            .padding(.horizontal, 16).padding(.top, 10)
            .padding(.bottom, DockMetrics.clearance + 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $selected) { title in detail(title) }
        // Search shortcut from the Remote page: wait for the page slide, then bring up the keyboard.
        .onChange(of: navigator.searchFocusToken) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                searching = true
            }
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").scaledFont(16, .medium).foregroundStyle(.white.opacity(0.65))
            TextField("Search movies and series", text: $model.query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: model.query) { _ in model.queryChanged() }
                .onSubmit { searching = false }
            if !model.query.isEmpty {
                Button { model.query = ""; model.queryChanged(); searching = true } label: {
                    Image(systemName: "xmark.circle.fill").scaledFont(17).foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(16)
        .padding(.horizontal, 16).frame(height: 52)
        .glassBar(Capsule())
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if model.recents.isEmpty {
                note("sparkle.magnifyingglass", "Find something to watch",
                     "Search Stremio's catalogue. Tap the keyboard's microphone to dictate.")
            } else {
                recentsList
            }
        case .searching:
            skeleton
        case .empty:
            note("film.stack", "No results", "Nothing in the catalogue matches “\(model.query)”.")
        case .failed(let message):
            note("wifi.exclamationmark", "Can't reach the catalogue", message)
        case .results:
            if model.visibleMovies.isEmpty && model.visibleSeries.isEmpty {
                note(model.filter == .movies ? "film" : "tv", model.filter == .movies ? "No movies" : "No series",
                     "Try “All” to see everything that matched.")
            } else {
                shelf("Movies", model.visibleMovies)
                shelf("Series", model.visibleSeries)
            }
        }
    }

    private func note(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).scaledFont(32, .light).foregroundStyle(.white.opacity(0.45))
            Text(title).scaledFont(17, .semibold)
            Text(text).scaledFont(13).foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 12)
    }

    private var recentsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").scaledFont(16, .bold)
                Spacer()
                Button("Clear") { model.clearRecents() }.scaledFont(13, .semibold).foregroundStyle(.white.opacity(0.7))
            }
            GlassGroup(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(model.recents, id: \.self) { text in
                        Button { model.useRecent(text) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white.opacity(0.55))
                                Text(text).scaledFont(15).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 16).frame(height: 46)
                            .glassSurface(Capsule(), interactive: true)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    private var skeleton: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay(ProgressView().tint(.white.opacity(0.6)))
            }
        }
        .accessibilityLabel("Searching")
    }

    // MARK: Results

    @ViewBuilder
    private func shelf(_ title: String, _ items: [StremioTitle]) -> some View {
        if !items.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).scaledFont(20, .bold)
                Text("\(items.count)").scaledFont(13).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 4)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    Button { searching = false; result = ""; selected = item } label: { poster(item) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("\(item.name)\(item.year.isEmpty ? "" : ", \(item.year)")")
                }
            }
        }
    }

    private func poster(_ item: StremioTitle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            CachedArtwork(url: item.posterURL, fallbackURL: item.fallbackPosterURL, contentMode: .fill) {
                posterPlaceholder(item)
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
            Text(item.name).scaledFont(13, .semibold).lineLimit(2).multilineTextAlignment(.leading)
            if !item.year.isEmpty { Text(item.year).scaledFont(11).foregroundStyle(.white.opacity(0.55)) }
        }
    }

    /// Shown while artwork loads or when none exists: same shape and glass edge as a real poster.
    private func posterPlaceholder(_ item: StremioTitle) -> some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Image(systemName: item.kind == .movie ? "film" : "tv").scaledFont(24, .light)
                Text(item.name).scaledFont(11, .medium).lineLimit(3).multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Launch toggle

    private var launchToggle: some View {
        Toggle(isOn: $deepLinkTest) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open titles in Stremio").scaledFont(14, .semibold)
                Text("Experimental. Sends a Stremio detail link to the TV box. Not yet confirmed on your box.")
                    .scaledFont(12).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 6)
    }

    // MARK: Detail sheet

    private func detail(_ title: StremioTitle) -> some View {
        VStack(spacing: 14) {
            CachedArtwork(url: title.posterURL, fallbackURL: title.fallbackPosterURL, contentMode: .fit) { Color.clear }
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                .padding(.top, 24)
            Text(title.name).scaledFont(24, .bold).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                chip(title.kind == .movie ? "Movie" : "Series", "film")
                if !title.year.isEmpty { chip(title.year, "calendar") }
                if !title.rating.isEmpty { chip(title.rating, "star.fill") }
            }
            if deepLinkTest {
                Button {
                    PlayerArtworkStore.shared.remember(title: title.name, posterURL: title.posterURL)
                    Task { result = await remote.openInStremio(title) }
                } label: {
                    Label("Open in Stremio", systemImage: "play.fill").scaledFont(16, .semibold)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .glassBar(Capsule())
                }
                .buttonStyle(PressStyle()).disabled(!remote.connected).opacity(remote.connected ? 1 : 0.5)
            } else {
                Text("Turn on “Open titles in Stremio” on the Discover page to try launching from here.")
                    .scaledFont(13).foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center)
            }
            if !result.isEmpty { Text(result).scaledFont(13).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center) }
            Text("This is a catalogue listing. It doesn't mean a stream is available for it.")
                .scaledFont(11).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).scaledFont(12, .semibold)
            .padding(.horizontal, 12).frame(height: 28)
            .glassSurface(Capsule())
    }
}
