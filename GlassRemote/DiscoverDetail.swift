import SwiftUI

/// Detail sheet for a catalogue or watch-history title: real Cinemeta metadata, the Nuvio account's
/// playback progress when it has some for this title, and an action that opens the title in Nuvio on
/// the TV box. Nothing here claims a stream exists, and nothing auto-plays.
struct TitleDetailView: View {
    let title: MediaTitle
    let libraryItem: NuvioWatchItem?

    @EnvironmentObject private var remote: RemoteModel
    @State private var detail: CinemetaCatalog.Detail?
    @State private var loading = true
    @State private var failed = false
    @State private var season = 1
    @State private var result = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                artwork
                Text(title.name).scaledFont(24, .bold).multilineTextAlignment(.center)
                chips
                if let libraryItem, libraryItem.progress > 0 { progressBlock(libraryItem) }
                actions
                if !result.isEmpty { Text(result).scaledFont(13).foregroundStyle(Color.ink.opacity(0.75)).multilineTextAlignment(.center) }
                about
                if title.kind == .series, let detail, !detail.seasons.isEmpty { episodes(detail) }
                Text("This is a catalogue listing. It doesn't mean a stream is available for it.")
                    .scaledFont(11).foregroundStyle(Color.inkFaint(0.4)).multilineTextAlignment(.center).padding(.top, 6)
            }
            .padding(.horizontal, 22).padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
        .task { await load() }
    }

    /// Landscape artwork (backdrop) in a 16:9 frame when the catalogue has one, otherwise the portrait
    /// poster in an exact 2:3 frame. Each source keeps its own aspect ratio; nothing is stretched.
    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if let background = detail?.background ?? title.backgroundURL {
            // True 16:9 base with the backdrop in an overlay, so artwork that isn't exactly 16:9 can't
            // resize the frame or push the sheet wider than the screen.
            Color.clear
                .frame(maxWidth: .infinity).aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { CachedArtwork(url: background, contentMode: .fill) { Color.ink.opacity(0.06) } }
                .clipShape(shape)
                .overlay(shape.stroke(Color.ink.opacity(0.2), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                .padding(.top, 28)
        } else {
            CachedArtwork(url: title.posterURL, fallbackURL: title.fallbackPosterURL, contentMode: .fill) { Color.ink.opacity(0.06) }
                .frame(width: 200, height: 300)
                .clipShape(shape)
                .overlay(shape.stroke(Color.ink.opacity(0.2), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                .padding(.top, 24)
        }
    }

    private func load() async {
        loading = true; failed = false
        do {
            detail = try await CinemetaCatalog.detail(kind: title.kind, id: title.id)
            failed = detail == nil
        } catch { failed = true }
        if let first = detail?.seasons.first {
            season = libraryItem?.episode?.season.nonZero(in: detail?.seasons ?? []) ?? first
        }
        loading = false
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip(title.kind == .movie ? "Movie" : "Series", "film")
            if !title.year.isEmpty { chip(title.year, "calendar") }
            if !title.rating.isEmpty { chip(title.rating, "star.fill") }
            if let runtime = detail?.runtime, !runtime.isEmpty { chip(runtime, "clock") }
        }
    }

    private func progressBlock(_ item: NuvioWatchItem) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: item.progress).tint(Color.ink)
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

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            button("Open in Nuvio", "arrow.up.forward.app", prominent: true) {
                await remote.openInNuvio(title)
            }
            if let item = libraryItem, item.isContinueWatching {
                Text("Opens this title in Nuvio on the TV box. Playback never starts automatically; Nuvio resumes from your synced position when you play it there.")
                    .scaledFont(11).foregroundStyle(Color.inkFaint(0.45)).multilineTextAlignment(.center)
            }
        }
    }

    private func button(_ label: String, _ symbol: String, prominent: Bool, action: @escaping () async -> String) -> some View {
        Button { Task { result = await action() } } label: {
            Label(label, systemImage: symbol).scaledFont(16, .semibold)
                .frame(maxWidth: .infinity).frame(height: 52)
                .glassBar(Capsule())
                .opacity(prominent ? 1 : 0.9)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected).opacity(remote.connected ? 1 : 0.5)
        .overlay(alignment: .bottom) {
            if !remote.connected { Text("Connect to the TV box first").scaledFont(10).foregroundStyle(Color.inkFaint(0.5)).offset(y: 14) }
        }
        .padding(.bottom, remote.connected ? 0 : 12)
    }

    // MARK: About

    @ViewBuilder
    private var about: some View {
        if loading {
            ProgressView().tint(Color.ink.opacity(0.6)).padding(.vertical, 12)
        } else if failed {
            Text("Couldn't load details from the catalogue.").scaledFont(12).foregroundStyle(Color.inkFaint(0.5))
        } else if let detail {
            VStack(alignment: .leading, spacing: 10) {
                if !detail.genres.isEmpty { Text(detail.genres.joined(separator: " · ")).scaledFont(13, .semibold).foregroundStyle(Color.ink.opacity(0.75)) }
                if !detail.overview.isEmpty { Text(detail.overview).scaledFont(14).foregroundStyle(Color.ink.opacity(0.85)) }
                if !detail.directors.isEmpty { info("Director", detail.directors.joined(separator: ", ")) }
                if !detail.cast.isEmpty { info("Cast", detail.cast.prefix(6).joined(separator: ", ")) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        (Text(label + "  ").foregroundColor(Color.inkFaint(0.5)) + Text(value)).scaledFont(13)
    }

    // MARK: Episodes

    private func episodes(_ detail: CinemetaCatalog.Detail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            UnclippedHScroll {
                HStack(spacing: 8) {
                    ForEach(detail.seasons, id: \.self) { s in
                        Button { season = s } label: {
                            Text(s == 0 ? "Specials" : "Season \(s)").scaledFont(13, .semibold)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(season == s ? Color.ink.opacity(0.22) : .clear, in: Capsule())
                                .glassSurface(Capsule(), interactive: true)
                        }.buttonStyle(PressStyle())
                    }
                }
            }
            Text("Episode list from the catalogue. Nuvio has no verified episode link, so episodes can't be opened directly from here.")
                .scaledFont(11).foregroundStyle(Color.inkFaint(0.45))
            ForEach(detail.episodes.filter { $0.season == season }) { ep in
                let current = libraryItem?.episode.map { $0.season == ep.season && $0.episode == ep.number } ?? false
                HStack(spacing: 10) {
                    Text("\(ep.number)").scaledFont(14, .semibold).frame(width: 28)
                    Text(ep.title.isEmpty ? "Episode \(ep.number)" : ep.title).scaledFont(14).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if current { Image(systemName: "play.circle.fill").foregroundStyle(Color.ink.opacity(0.8)) }
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Episode \(ep.number), \(ep.title)\(current ? ", last watched" : "")")
            }
        }
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).scaledFont(12, .semibold)
            .padding(.horizontal, 12).frame(height: 28).glassSurface(Capsule())
    }
}

private extension Int {
    /// Self if it is one of `seasons`, else nil.
    func nonZero(in seasons: [Int]) -> Int? { seasons.contains(self) ? self : nil }
}
