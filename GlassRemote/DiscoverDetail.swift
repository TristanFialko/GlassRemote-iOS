import SwiftUI

/// Detail sheet for a catalogue or library title: real Cinemeta metadata, the account's playback
/// progress when the title is in the signed-in library, and actions that open it in Stremio on the
/// TV box. Nothing here claims a stream exists.
struct TitleDetailView: View {
    let title: StremioTitle
    let libraryItem: StremioLibraryItem?

    @EnvironmentObject private var remote: RemoteModel
    @State private var detail: StremioCatalog.Detail?
    @State private var loading = true
    @State private var failed = false
    @State private var season = 1
    @State private var result = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                CachedArtwork(url: title.posterURL, fallbackURL: title.fallbackPosterURL, contentMode: .fill) { Color.white.opacity(0.06) }
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                    .padding(.top, 24)
                Text(title.name).scaledFont(24, .bold).multilineTextAlignment(.center)
                chips
                if let libraryItem, libraryItem.progress > 0 { progressBlock(libraryItem) }
                actions
                if !result.isEmpty { Text(result).scaledFont(13).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center) }
                about
                if title.kind == .series, let detail, !detail.seasons.isEmpty { episodes(detail) }
                Text("This is a catalogue listing. It doesn't mean a stream is available for it.")
                    .scaledFont(11).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center).padding(.top, 6)
            }
            .padding(.horizontal, 22).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .background { AmbientBackdrop() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func load() async {
        loading = true; failed = false
        do {
            detail = try await StremioCatalog.detail(kind: title.kind, id: title.id)
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

    private func progressBlock(_ item: StremioLibraryItem) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: item.progress).tint(.white)
            HStack {
                Text(progressText(item)).scaledFont(12).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if let last = item.lastWatched {
                    Text(last, style: .relative).scaledFont(12).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(14).glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func progressText(_ item: StremioLibraryItem) -> String {
        let pct = Int((item.progress * 100).rounded())
        if let e = item.episode { return "Season \(e.season) · Episode \(e.episode) · \(pct)% watched" }
        return "\(pct)% watched"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            if let item = libraryItem, item.isContinueWatching {
                button(item.episode.map { "Resume S\($0.season) E\($0.episode)" } ?? "Resume", "play.fill", prominent: true) {
                    await remote.openInStremio(title, videoID: item.videoID, autoPlay: true)
                }
                Text("Starts the title in Stremio on the TV box. Stremio resumes from its own saved position, so the box must be signed in to the same account.")
                    .scaledFont(11).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center)
            }
            button("Open in Stremio", "arrow.up.forward.app", prominent: libraryItem?.isContinueWatching != true) {
                await remote.openInStremio(title)
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
            if !remote.connected { Text("Connect to the TV box first").scaledFont(10).foregroundStyle(.white.opacity(0.5)).offset(y: 14) }
        }
        .padding(.bottom, remote.connected ? 0 : 12)
    }

    // MARK: About

    @ViewBuilder
    private var about: some View {
        if loading {
            ProgressView().tint(.white.opacity(0.6)).padding(.vertical, 12)
        } else if failed {
            Text("Couldn't load details from the catalogue.").scaledFont(12).foregroundStyle(.white.opacity(0.5))
        } else if let detail {
            VStack(alignment: .leading, spacing: 10) {
                if !detail.genres.isEmpty { Text(detail.genres.joined(separator: " · ")).scaledFont(13, .semibold).foregroundStyle(.white.opacity(0.75)) }
                if !detail.overview.isEmpty { Text(detail.overview).scaledFont(14).foregroundStyle(.white.opacity(0.85)) }
                if !detail.directors.isEmpty { info("Director", detail.directors.joined(separator: ", ")) }
                if !detail.cast.isEmpty { info("Cast", detail.cast.prefix(6).joined(separator: ", ")) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        (Text(label + "  ").foregroundColor(.white.opacity(0.5)) + Text(value)).scaledFont(13)
    }

    // MARK: Episodes

    private func episodes(_ detail: StremioCatalog.Detail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detail.seasons, id: \.self) { s in
                        Button { season = s } label: {
                            Text(s == 0 ? "Specials" : "Season \(s)").scaledFont(13, .semibold)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(season == s ? Color.white.opacity(0.22) : .clear, in: Capsule())
                                .glassSurface(Capsule(), interactive: true)
                        }.buttonStyle(PressStyle())
                    }
                }
            }
            .claimsHorizontalTouches()
            ForEach(detail.episodes.filter { $0.season == season }) { ep in
                let current = libraryItem?.videoID == ep.id
                Button { Task { result = await remote.openInStremio(title, videoID: ep.id) } } label: {
                    HStack(spacing: 10) {
                        Text("\(ep.number)").scaledFont(14, .semibold).frame(width: 28)
                        Text(ep.title.isEmpty ? "Episode \(ep.number)" : ep.title).scaledFont(14).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        if current { Image(systemName: "play.circle.fill").foregroundStyle(.white.opacity(0.8)) }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                }
                .buttonStyle(PressStyle())
                .disabled(!remote.connected).opacity(remote.connected ? 1 : 0.5)
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
