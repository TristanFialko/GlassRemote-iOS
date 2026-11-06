import SwiftUI

/// What a See All page shows: a Cinemeta catalogue slice (sortable, filterable, paged) or a fixed
/// local list (the user's own library / history rows).
struct CollectionRequest: Identifiable {
    let id = UUID()
    var title: String
    var kind: MediaTitle.Kind = .movie
    var catalog: String = "top"
    var genre: String? = nil
    var local: [MediaTitle]? = nil

    init(title: String, kind: MediaTitle.Kind, catalog: String, genre: String?) {
        self.title = title; self.kind = kind; self.catalog = catalog; self.genre = genre
    }
    init(title: String, local: [MediaTitle]) { self.title = title; self.local = local }
}

/// The single reusable See All page. One implementation serves every category: only the source differs.
struct CollectionView: View {
    let request: CollectionRequest
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassTheme) private var theme

    enum Phase: Equatable { case loading, loaded, empty, failed }

    @State private var kind: MediaTitle.Kind
    @State private var catalog: String
    @State private var genre: String?
    @State private var items: [MediaTitle] = []
    @State private var phase: Phase = .loading
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var generation = 0
    @State private var target: DetailTarget?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 12, alignment: .top)]

    init(request: CollectionRequest) {
        self.request = request
        _kind = State(initialValue: request.kind)
        _catalog = State(initialValue: request.catalog)
        _genre = State(initialValue: request.genre)
    }

    private var isLocal: Bool { request.local != nil }
    private var heading: String { isLocal ? request.title : CatalogSource(kind: kind, catalog: catalog, genre: genre).title.capitalizedFirst }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isLocal { controls }
            ScrollView {
                content.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 30)
            }
        }
        .foregroundStyle(Color.ink)
        .background { AmbientBackdrop() }
        .themedSheet()
        .sheet(item: $target) { item in
            TitleDetailView(title: item.title, libraryItem: item.libraryItem).environmentObject(remote)
        }
        .task(id: "\(kind.rawValue)|\(catalog)|\(genre ?? "")") { await reload() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").scaledFont(17, .semibold)
                    .frame(width: 44, height: 44).glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Back")
            Text(heading).scaledFont(22, .bold).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            GlassSegmented(
                items: [GlassSegmented<MediaTitle.Kind>.Item(value: .movie, title: "Movies", symbol: "film"),
                        GlassSegmented<MediaTitle.Kind>.Item(value: .series, title: "Series", symbol: "tv")],
                selection: $kind, height: 36)
            HStack(spacing: 10) {
                Menu {
                    Picker("Sort", selection: $catalog) {
                        ForEach(CinemetaCatalog.sortCatalogs, id: \.id) { Text($0.title).tag($0.id) }
                    }
                } label: { chip("arrow.up.arrow.down", CinemetaCatalog.sortCatalogs.first { $0.id == catalog }?.title ?? "Popular") }
                Menu {
                    Picker("Genre", selection: $genre) {
                        Text("All genres").tag(String?.none)
                        ForEach(CinemetaCatalog.genres, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: { chip("line.3.horizontal.decrease", genre ?? "All genres") }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).scaledFont(12, .semibold)
            Text(text).scaledFont(13, .semibold)
            Image(systemName: "chevron.down").scaledFont(10, .semibold).opacity(0.6)
        }
        .padding(.horizontal, 14).frame(height: 36).glassSurface(Capsule(), interactive: true)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.ink.opacity(0.06))
                        .aspectRatio(2.0 / 3.0, contentMode: .fit).overlay(ProgressView())
                }
            }
        case .empty:
            message("film.stack", "Nothing here", isLocal ? "This list is empty." : "The catalogue has no titles for this combination.")
        case .failed:
            VStack(spacing: 10) {
                message("wifi.exclamationmark", "Couldn't load", "Check your internet connection and try again.")
                Button("Try again") { Task { await reload() } }.scaledFont(14, .semibold)
            }
        case .loaded:
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    Button { target = DetailTarget(title: item, libraryItem: NuvioAccount.shared.item(id: item.id)) } label: {
                        PosterCard(title: item, fixedWidth: false)
                    }
                    .buttonStyle(PosterButtonStyle())
                    .onAppear { if item.id == items.suffix(6).first?.id { Task { await loadMore() } } }
                }
            }
            if loadingMore { ProgressView().frame(maxWidth: .infinity).padding(.top, 16) }
        }
    }

    private func message(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).scaledFont(32, .light).foregroundStyle(Color.inkFaint(0.45))
            Text(title).scaledFont(17, .semibold)
            Text(text).scaledFont(13).foregroundStyle(Color.inkFaint(0.58)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 50)
    }

    // MARK: Loading (paged by Cinemeta's `skip` extra)

    private func reload() async {
        generation += 1
        let mine = generation
        reachedEnd = false; loadingMore = false
        if let local = request.local {
            items = local; phase = local.isEmpty ? .empty : .loaded; reachedEnd = true
            return
        }
        phase = .loading; items = []
        do {
            let page = try await CinemetaCatalog.browse(kind: kind, catalog: catalog, genre: genre)
            guard mine == generation else { return }
            items = dedup(page)
            phase = items.isEmpty ? .empty : .loaded
            reachedEnd = page.isEmpty
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private func loadMore() async {
        guard !isLocal, !loadingMore, !reachedEnd, phase == .loaded else { return }
        loadingMore = true
        let mine = generation
        defer { if mine == generation { loadingMore = false } }
        guard let page = try? await CinemetaCatalog.browse(kind: kind, catalog: catalog, genre: genre, skip: items.count), mine == generation else { return }
        let known = Set(items.map(\.id))
        let fresh = dedup(page).filter { !known.contains($0.id) }
        // A page with nothing new means the catalogue is exhausted: stop asking.
        if fresh.isEmpty { reachedEnd = true } else { items += fresh }
    }

    private func dedup(_ list: [MediaTitle]) -> [MediaTitle] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
