import SwiftUI

/// Page 3: Stremio-oriented discovery. Search uses Stremio's public Cinemeta catalog from the
/// phone. Dictation: tap the microphone on the iOS keyboard (system dictation; the app needs no
/// extra permission). Launching is an experimental, user-enabled deep link (see
/// RemoteModel+Stremio.swift); until it is verified on the device the UI says so.
struct DiscoverPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @StateObject private var model = DiscoverModel()
    @FocusState private var searching: Bool
    @AppStorage(RemoteModel.deepLinkDefaultsKey) private var deepLinkTest = false
    @State private var selected: StremioTitle?
    @State private var result = ""

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchField
                content
                Toggle(isOn: $deepLinkTest) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try opening titles in Stremio").scaledFont(14, .semibold)
                        Text("Experimental. Sends a Stremio detail link to the TV. Not yet confirmed to work on your box.")
                            .scaledFont(12).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(14)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 24)
        }
        .scrollDismissesKeyboardIfAvailable()
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheet(item: $selected) { title in detail(title) }
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

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            note("search", "Search Stremio's catalogue. Use the keyboard's microphone to dictate.")
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
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    Button { searching = false; result = ""; selected = item } label: { poster(item) }
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
        VStack(spacing: 16) {
            CachedArtwork(url: title.posterURL, contentMode: .fit) { Color.clear }
                .frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title.name).scaledFont(22, .bold).multilineTextAlignment(.center)
            Text([title.kind == .movie ? "Movie" : "Series", title.year, title.rating.isEmpty ? "" : "IMDb \(title.rating)"]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .scaledFont(14).foregroundStyle(.white.opacity(0.6))
            if deepLinkTest {
                Button {
                    PlayerArtworkStore.shared.remember(title: title.name, posterURL: title.posterURL)
                    Task { result = await remote.openInStremio(title) }
                } label: {
                    Label("Open in Stremio", systemImage: "play.fill").scaledFont(16, .semibold)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .glassSurface(Capsule(), interactive: true, elevated: true)
                }
                .buttonStyle(PressStyle()).disabled(!remote.connected)
            } else {
                Text("Turn on “Try opening titles in Stremio” on the Discover page to test launching.")
                    .scaledFont(13).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            }
            if !result.isEmpty { Text(result).scaledFont(13).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackdrop() }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private extension View {
    /// `scrollDismissesKeyboard` is iOS 16+, matching the deployment target; kept behind a helper
    /// so it is one place to change.
    @ViewBuilder func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16.0, *) { self.scrollDismissesKeyboard(.interactively) } else { self }
    }
}
