import SwiftUI

/// Phase 7 detail page for a catalogue or watch-history title, after Nuvio's: a full-bleed backdrop
/// that fades into the page, the poster and title (or logo), key facts and the Play action, then the
/// expandable synopsis, credits, cast with portraits, trailers, episodes and more titles in the genre.
/// Everything shown is real catalogue data, and sections without data are left out. Play asks the
/// profile's stream add-ons first and always offers Open in Nuvio; nothing auto-plays.
struct TitleDetailView: View {
    let title: MediaTitle
    let libraryItem: NuvioWatchItem?
    /// Phase 6: set by Discover to close the sheet and show the Remote page after a Nuvio handoff.
    var onShowRemote: (() -> Void)? = nil

    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.glassTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var profiles = ProfileStore.shared
    @StateObject private var model: TitleDetailModel
    @State private var season = 1
    @State private var result = ""
    @State private var handedOff = false
    @State private var showStreams = false
    @State private var opened: MediaTitle?

    init(title: MediaTitle, libraryItem: NuvioWatchItem?, onShowRemote: (() -> Void)? = nil) {
        self.title = title
        self.libraryItem = libraryItem
        self.onShowRemote = onShowRemote
        _model = StateObject(wrappedValue: TitleDetailModel(title: title))
    }

    private static let space = "titleDetailScroll"
    private var motion: Animation { Motion.resolve(Motion.expand, reduceMotion: reduceMotion || MotionPreference.reduced) }

    var body: some View {
        GeometryReader { proxy in
            let landscape = LayoutContext.resolve(verticalSizeClass: verticalSizeClass, size: proxy.size).isLandscape
            let heroHeight = DetailLayout.heroHeight(size: proxy.size, isLandscape: landscape)
            let inset = DetailLayout.horizontalInset(isLandscape: landscape)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    hero(width: proxy.size.width, height: heroHeight, inset: inset, landscape: landscape)
                    sections(landscape: landscape, width: proxy.size.width - inset * 2)
                        .padding(.horizontal, inset)
                }
                .padding(.bottom, 36)
            }
            .coordinateSpace(name: Self.space)
            .overlay(alignment: .topTrailing) {
                closeButton.padding(.top, 14).padding(.trailing, inset)
            }
        }
        .foregroundStyle(Color.ink)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
        .task {
            await model.load()
            chooseSeason()
        }
        .animation(motion, value: model.phase)
        .sheet(isPresented: $showStreams) {
            StreamPickerSheet(title: title, episodes: model.detail?.episodes ?? [], initialSeason: season,
                              onHandoff: { _ in handedOff = true })
                .environmentObject(remote)
        }
        .sheet(item: $opened) { other in
            TitleDetailView(title: other, libraryItem: nil, onShowRemote: onShowRemote)
                .environmentObject(remote)
        }
    }

    // MARK: Hero

    private func hero(width: CGFloat, height: CGFloat, inset: CGFloat, landscape: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            backdrop(height: height, landscape: landscape)
            heroInfo(landscape: landscape, height: height)
                .padding(.horizontal, inset)
                .padding(.bottom, landscape ? 22 : 2)
        }
        .frame(width: width, height: height)
    }

    /// The backdrop fades out through an alpha mask, so it dissolves into the themed page behind it
    /// rather than into a guessed colour. Pulling the page down stretches it from the top.
    private func backdrop(height: CGFloat, landscape: Bool) -> some View {
        let art = DetailLayout.artwork(detail: model.detail, title: title)
        return GeometryReader { geo in
            let pull = max(geo.frame(in: .named(Self.space)).minY, 0)
            CachedArtwork(url: art.primary, fallbackURL: art.fallback, contentMode: .fill) {
                Color.inkAlpha(0.04)
            }
            // A poster stretched to the hero width is too soft and too tightly cropped to show sharp.
            .blur(radius: art.isPoster ? 24 : 0)
            .scaleEffect(art.isPoster ? 1.15 : 1)
            .frame(width: geo.size.width, height: height + pull)
            .clipped()
            .overlay(LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(theme.isLight ? 0 : 0.3)],
                                    startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: landscape ? 0.45 : 0.4),
                                         .init(color: .black.opacity(0), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: landscape
                                    ? [.init(color: .black.opacity(0.12), location: 0),
                                       .init(color: .black.opacity(0.55), location: 0.35),
                                       .init(color: .black, location: 0.7)]
                                    : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .offset(y: -pull)
            .animation(Motion.resolve(Motion.artwork, reduceMotion: reduceMotion), value: art)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func heroInfo(landscape: Bool, height: CGFloat) -> some View {
        let facts = model.facts
        if landscape {
            HStack(alignment: .bottom, spacing: 22) {
                poster(width: DetailLayout.posterWidth(isLandscape: true, heroHeight: height))
                VStack(alignment: .leading, spacing: 10) {
                    titleMark(maxWidth: 340, maxHeight: 84, landscape: true)
                    DetailFactsLine(facts: facts)
                    if !facts.genres.isEmpty { DetailGenreLine(genres: facts.genres) }
                    actions.frame(maxWidth: 470, alignment: .leading)
                }
                .frame(maxWidth: 520, alignment: .leading)
                Spacer(minLength: 0)
            }
        } else {
            HStack(alignment: .bottom, spacing: 16) {
                poster(width: DetailLayout.posterWidth(isLandscape: false, heroHeight: height))
                VStack(alignment: .leading, spacing: 8) {
                    titleMark(maxWidth: 230, maxHeight: 64, landscape: false)
                    DetailFactsLine(facts: facts)
                    if !facts.genres.isEmpty { DetailGenreLine(genres: facts.genres) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func poster(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // The card's own poster first: it is already cached, so the zoom transition lands on it.
        return Color.clear
            .frame(width: width, height: width * 1.5)
            .overlay {
                CachedArtwork(url: title.posterURL ?? model.detail?.poster, fallbackURL: title.fallbackPosterURL,
                              contentMode: .fill) {
                    ZStack {
                        Color.inkAlpha(0.08)
                        Image(systemName: "film").font(.system(size: 26)).foregroundStyle(Color.inkFaint(0.4))
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.inkAlpha(0.2), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
            .accessibilityHidden(true)
    }

    /// The title's logo when the catalogue has one (dark themes only: logos are usually light artwork),
    /// otherwise the title in type. A failed logo falls back to the text.
    @ViewBuilder
    private func titleMark(maxWidth: CGFloat, maxHeight: CGFloat, landscape: Bool) -> some View {
        let name = model.displayName
        if let logo = model.logoURL, !theme.isLight {
            CachedArtwork(url: logo, contentMode: .fit) { titleText(name, landscape: landscape) }
                .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityAddTraits(.isHeader)
        } else {
            titleText(name, landscape: landscape)
        }
    }

    private func titleText(_ name: String, landscape: Bool) -> some View {
        Text(name)
            .scaledFont(landscape ? 30 : 26, .bold)
            .foregroundStyle(Color.ink)
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Phase 7: Play asks the profile's stream add-ons first; the picker always offers
                // Open in Nuvio too, so Play works (and reports what happened) even without add-ons.
                Button {
                    Haptics.soft()
                    showStreams = true
                } label: {
                    Label("Play", systemImage: "play.fill").scaledFont(16, .semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(theme.accent))
                        .glassSurface(Capsule(), interactive: true)
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityHint("Finds streams from your add-ons, or opens the title in Nuvio on the TV.")

                if let trailer = model.detail?.trailers.first {
                    Button {
                        Haptics.soft()
                        if let url = RemoteModel.youTubeURL(id: trailer.youTubeID) { openURL(url) }
                    } label: {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .glassBar(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Watch the trailer")
                    .accessibilityHint("Opens it on YouTube on this iPhone.")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Button {
                    Task {
                        let message = await remote.openInNuvio(title)
                        handedOff = true
                        result = message
                    }
                } label: {
                    Label("Nuvio", systemImage: "arrow.up.forward.app").scaledFont(15, .semibold)
                        .padding(.horizontal, 18).frame(height: 52)
                        .glassBar(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!remote.connected)
                .opacity(remote.connected ? 1 : 0.5)
                .accessibilityLabel("Open in Nuvio")
                .accessibilityHint("Opens this title in Nuvio on the TV box.")
            }
            if !remote.connected {
                Text("Connect to the TV box to open titles in Nuvio.")
                    .scaledFont(11).foregroundStyle(Color.inkFaint(0.5))
            } else if let item = libraryItem, item.isContinueWatching {
                Text("Opens this title in Nuvio on the TV box. Playback never starts automatically; Nuvio resumes from your synced position when you play it there.")
                    .scaledFont(11).foregroundStyle(Color.inkFaint(0.45))
            }
            // Phase 6: after the handoff, one tap closes the sheet and opens the Remote page, where the
            // stream (or episode) is picked in Nuvio on the TV with the D-pad.
            if handedOff, let onShowRemote {
                Button {
                    Haptics.soft()
                    onShowRemote()
                } label: {
                    Label("Continue on the TV with the remote", systemImage: "av.remote")
                        .scaledFont(14, .semibold)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .glassSurface(Capsule(), interactive: true)
                }
                .buttonStyle(PressStyle())
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityHint("Closes this page and opens the Remote, to pick a stream in Nuvio on the TV.")
            }
            if !result.isEmpty {
                Text(result).scaledFont(12).foregroundStyle(Color.inkAlpha(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.leading)
        .animation(motion, value: handedOff)
        .animation(motion, value: result)
    }

    // MARK: Sections

    private func sections(landscape: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            if !landscape { actions }
            if let item = libraryItem, item.progress > 0 { progressBlock(item) }
            status
            about(landscape: landscape)
            if let detail = model.detail {
                let people = detail.people
                if !people.isEmpty {
                    DetailSection(title: "Cast") { DetailCastRow(people: people, portrait: landscape ? 84 : 76) }
                        .transition(.opacity)
                }
                if !detail.trailers.isEmpty {
                    DetailSection(title: detail.trailers.count == 1 ? "Trailer" : "Trailers") {
                        DetailTrailerRow(trailers: detail.trailers, cardWidth: landscape ? 280 : min(260, width * 0.72))
                    }
                    .transition(.opacity)
                }
                if title.kind == .series, !detail.episodes.isEmpty {
                    DetailSection(title: "Episodes", subtitle: "Tap an episode to find streams for its season") {
                        DetailEpisodeList(episodes: detail.episodes, seasons: detail.seasons, season: $season,
                                          currentSeason: libraryItem?.episode?.season,
                                          currentEpisode: libraryItem?.episode?.episode) { episode in
                            season = episode.season
                            Haptics.soft()
                            showStreams = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            if !model.similar.isEmpty, let genre = model.similarGenre {
                DetailSection(title: "More like this",
                              subtitle: "Popular \(genre) \(title.kind == .movie ? "movies" : "series")") {
                    DetailSimilarRow(titles: model.similar,
                                     shape: DiscoverCardShape.resolve(profiles.active.settings.posterOrientation, usage: .catalog),
                                     posterWidth: DiscoverMetrics(isLandscape: landscape).poster) { opened = $0 }
                }
                .transition(.opacity)
            }
            Text("Details from the Cinemeta catalogue. Streams come from your add-ons, and playback happens in Nuvio on the TV box.")
                .scaledFont(11).foregroundStyle(Color.inkFaint(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Color.ink)
                Text("Loading details…").scaledFont(13).foregroundStyle(Color.inkAlpha(0.7))
            }
        case .failed:
            if CinemetaCatalog.detailURL(kind: title.kind, id: title.id) == nil {
                Text("More details aren't available for this title.")
                    .scaledFont(13).foregroundStyle(Color.inkAlpha(0.7))
            } else {
                HStack(spacing: 12) {
                    Text("Couldn't load the details.").scaledFont(13).foregroundStyle(Color.inkAlpha(0.7))
                    Button { Task { await model.retry() } } label: {
                        Text("Retry").scaledFont(13, .semibold)
                            .padding(.horizontal, 14).frame(height: 32)
                            .glassBar(Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        case .loaded:
            EmptyView()
        }
    }

    /// Synopsis and credits: stacked in portrait, side by side in landscape.
    @ViewBuilder
    private func about(landscape: Bool) -> some View {
        let overview = model.overview
        let credits = model.credits
        if landscape, !overview.isEmpty, !credits.isEmpty {
            HStack(alignment: .top, spacing: 24) {
                DetailSection(title: "Overview") { DetailOverview(text: overview, collapsedLines: 5) }
                DetailCreditsGrid(credits: credits, columns: 2).frame(maxWidth: 420)
            }
        } else {
            if !overview.isEmpty {
                DetailSection(title: "Overview") { DetailOverview(text: overview) }
            }
            if !credits.isEmpty {
                DetailCreditsGrid(credits: credits, columns: landscape ? 3 : 2).transition(.opacity)
            }
        }
    }

    private func progressBlock(_ item: NuvioWatchItem) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: item.progress).tint(theme.accent)
            HStack {
                Text(progressText(item)).scaledFont(12).foregroundStyle(Color.ink.opacity(0.7))
                Spacer()
                if let last = item.lastWatched {
                    Text(last, style: .relative).scaledFont(12).foregroundStyle(Color.inkFaint(0.5))
                }
            }
        }
        .padding(14).glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func progressText(_ item: NuvioWatchItem) -> String {
        let pct = Int((item.progress * 100).rounded())
        if let e = item.episode { return "Season \(e.season) · Episode \(e.episode) · \(pct)% watched" }
        return "\(pct)% watched"
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 36, height: 36)
                .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close")
    }

    /// The season being watched when the catalogue lists it, otherwise the first season.
    private func chooseSeason() {
        let seasons = model.detail?.seasons ?? []
        guard let first = seasons.first else { return }
        season = libraryItem?.episode?.season.nonZero(in: seasons) ?? first
    }
}

/// Detail-page sizing and artwork choice (pure, unit tested).
enum DetailLayout {
    struct Artwork: Equatable {
        let primary: URL?
        let fallback: URL?
        /// True when no backdrop exists and the poster stands in (drawn blurred).
        let isPoster: Bool
    }

    /// Portrait: about as tall as the screen is wide (plus room for the title block), capped near two
    /// thirds of the screen. Landscape: most of the height, with the info column over the backdrop.
    static func heroHeight(size: CGSize, isLandscape: Bool) -> CGFloat {
        if isLandscape { return min(max(size.height * 0.86, 300), 640) }
        return min(max(size.width * 1.12, 380), max(size.height * 0.64, 380))
    }

    static func posterWidth(isLandscape: Bool, heroHeight: CGFloat) -> CGFloat {
        isLandscape ? min(max(heroHeight * 0.4, 110), 180) : 104
    }

    static func horizontalInset(isLandscape: Bool) -> CGFloat { isLandscape ? 28 : 20 }

    static func artwork(detail: CinemetaCatalog.Detail?, title: MediaTitle) -> Artwork {
        if let backdrop = title.backgroundURL ?? detail?.background {
            let other = detail?.background == backdrop ? nil : detail?.background
            return Artwork(primary: backdrop, fallback: other, isPoster: false)
        }
        return Artwork(primary: title.posterURL ?? detail?.poster, fallback: title.fallbackPosterURL, isPoster: true)
    }
}

private extension Int {
    /// This season number if the catalogue lists it.
    func nonZero(in seasons: [Int]) -> Int? { self > 0 && seasons.contains(self) ? self : nil }
}
