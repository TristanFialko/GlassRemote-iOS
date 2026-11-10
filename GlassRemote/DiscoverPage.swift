import SwiftUI

/// Catalogue discovery with an intentional two-pane landscape composition. Search remains on the
/// left rail while results use the extra width for denser poster browsing.
struct DiscoverPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @StateObject private var model = DiscoverModel()
    @FocusState private var searching: Bool
    @AppStorage(RemoteModel.deepLinkDefaultsKey) private var deepLinkTest = false
    @State private var selected: StremioTitle?
    @State private var hydrated: StremioTitle?
    @State private var result = ""

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscape(proxy)
            } else {
                portrait
            }
        }
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $selected) { title in detail(title) }
    }

    private var portrait: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchField
                content
                handoffToggle
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 24)
        }
        .scrollDismissesKeyboardIfAvailable()
        .background { AmbientBackdrop() }
    }

    private func landscape(_ proxy: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Discover").scaledFont(22, .bold)
                searchField
                handoffToggle
                Text("Cinemeta metadata is fetched from the phone. Playback sources and subtitles stay inside Nuvio.")
                    .scaledFont(12).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: min(320, max(270, proxy.size.width * 0.28)), alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.trailing, 18).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboardIfAvailable()
        }
        .padding(.leading, 18)
        .background { AmbientBackdrop() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("Search movies and series", text: $model.query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: model.query) { _ in model.queryChanged() }
            if !model.query.isEmpty {
                Button { model.query = ""; model.queryChanged() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }.accessibilityLabel("Clear search")
            }
        }
        .scaledFont(16)
        .padding(.horizontal, 16).frame(height: 48)
        .glassSurface(Capsule(), interactive: true)
    }

    private var handoffToggle: some View {
        Toggle(isOn: $deepLinkTest) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Nuvio handoff").scaledFont(14, .semibold)
                Text("Opens the selected title in the configured TV app; it does not query or change addons.")
                    .scaledFont(12).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            note("sparkles.tv", "Search Cinemeta for movies and series.")
        case .searching:
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 30)
        case .empty:
            note("film.stack", "No movies or series found.")
        case .failed(let message):
            note("wifi.exclamationmark", message)
        case .results:
            shelf("Movies", model.movies)
            shelf("Series", model.series)
        }
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).scaledFont(30).foregroundStyle(.white.opacity(0.4))
            Text(text).scaledFont(14).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 36)
    }

    @ViewBuilder
    private func shelf(_ title: String, _ items: [StremioTitle]) -> some View {
        if !items.isEmpty {
            Text(title).scaledFont(18, .bold)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    Button {
                        searching = false
                        result = ""
                        hydrated = nil
                        selected = item
                    } label: { poster(item) }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(item.name)\(item.year.isEmpty ? "" : ", \(item.year)")")
                }
            }
        }
    }

    private func poster(_ item: StremioTitle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedArtwork(url: item.posterURL, contentMode: .fill) {
                Color.white.opacity(0.06).overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.3)))
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.16)))
            Text(item.name).scaledFont(12, .semibold).lineLimit(2).multilineTextAlignment(.leading)
            if !item.year.isEmpty { Text(item.year).scaledFont(11).foregroundStyle(.white.opacity(0.55)) }
        }
    }

    private func detail(_ title: StremioTitle) -> some View {
        let display = hydrated?.id == title.id ? hydrated! : title
        return GeometryReader { proxy in
            Group {
                if proxy.size.width > proxy.size.height {
                    HStack(spacing: 24) {
                        hero(display).frame(width: proxy.size.width * 0.45)
                        detailInfo(display)
                    }
                    .padding(28)
                } else {
                    ScrollView {
                        VStack(spacing: 16) { hero(display); detailInfo(display) }
                            .padding(24)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackdrop() }
        }
        .task(id: title.id) {
            guard title.metadataURL != nil else { return }
            hydrated = try? await StremioCatalog.metadata(for: title)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func hero(_ title: StremioTitle) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedArtwork(url: title.backgroundURL ?? title.posterURL, contentMode: .fill) { Color.black.opacity(0.55) }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            Text(title.kind == .movie ? "MOVIE" : "SERIES")
                .scaledFont(12, .bold)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassSurface(Capsule(), elevated: true)
                .padding(14)
        }
        .frame(maxWidth: .infinity).frame(minHeight: 180, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), elevated: true)
    }

    private func detailInfo(_ title: StremioTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.name).scaledFont(26, .bold).lineLimit(3)
            Text([title.kind == .movie ? "Movie" : "Series", title.year, title.rating.isEmpty ? "" : "IMDb \(title.rating)"]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .scaledFont(14).foregroundStyle(.white.opacity(0.6))
            if !title.genres.isEmpty {
                Text(title.genres.joined(separator: "  ·  ")).scaledFont(13).foregroundStyle(.white.opacity(0.65))
            }
            if !title.description.isEmpty {
                Text(title.description).scaledFont(14).foregroundStyle(.white.opacity(0.78)).lineLimit(7)
            }
            Spacer(minLength: 0)
            if deepLinkTest {
                Button {
                    PlayerArtworkStore.shared.remember(title: title.name, posterURL: title.posterURL)
                    Task { result = await remote.openInStremio(title) }
                } label: {
                    Label("Open in Nuvio / Stremio", systemImage: "play.fill").scaledFont(16, .semibold)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .glassSurface(Capsule(), interactive: true, elevated: true)
                }
                .buttonStyle(PressStyle()).disabled(!remote.connected)
            }
            Text(result.isEmpty ? NuvioIntegration.handoffDescription(for: title) : result)
                .scaledFont(12).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.leading)
            Text(NuvioIntegration.providerNote)
                .scaledFont(11).foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16.0, *) { self.scrollDismissesKeyboard(.interactively) } else { self }
    }
}
