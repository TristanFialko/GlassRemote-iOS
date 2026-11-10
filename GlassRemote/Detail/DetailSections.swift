import SwiftUI

// Building blocks of the Phase 7 detail page. Each renders plain values; TitleDetailView decides which
// sections exist, and only sections with real data are shown.

/// A titled detail section with consistent spacing.
struct DetailSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: title, subtitle: subtitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "2008–2013 · 49m · 5 Seasons  [TV-MA]  ★ 9.5" — drops to the first two facts when space is short.
struct DetailFactsLine: View {
    let facts: DetailFacts

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(facts.line, badges: true)
            row(Array(facts.line.prefix(2)), badges: true)
            row(Array(facts.line.prefix(1)), badges: false)
        }
    }

    private func row(_ items: [String], badges: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Text("·").foregroundStyle(Color.inkFaint(0.45)) }
                Text(item)
            }
            if badges, !facts.certification.isEmpty {
                Text(facts.certification)
                    .scaledFont(11, .bold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.inkAlpha(0.55), lineWidth: 1))
                    .accessibilityLabel("Rated \(facts.certification)")
            }
            if !facts.rating.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(Color.yellow)
                    Text(facts.rating)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rating \(facts.rating)")
            }
        }
        .scaledFont(13, .semibold)
        .foregroundStyle(Color.inkAlpha(0.85))
        .lineLimit(1)
        .fixedSize()
    }
}

/// Up to three genres as small glass capsules.
struct DetailGenreLine: View {
    let genres: [String]

    var body: some View {
        // Three capsules when they fit, otherwise fewer: genres never wrap or clip.
        ViewThatFits(in: .horizontal) {
            line(genres)
            line(Array(genres.prefix(2)))
            line(Array(genres.prefix(1)))
        }
    }

    private func line(_ items: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { genre in
                Text(genre)
                    .scaledFont(12, .semibold)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassSurface(Capsule())
            }
        }
        .foregroundStyle(Color.inkAlpha(0.85))
        .fixedSize()
    }
}

/// Synopsis that expands in place (More / Less) instead of opening another screen.
struct DetailOverview: View {
    let text: String
    var collapsedLines = 4
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .scaledFont(15)
                .foregroundStyle(Color.inkAlpha(0.85))
                .lineSpacing(3)
                .lineLimit(expanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if Self.isLong(text, lines: collapsedLines) {
                Button {
                    withAnimation(Motion.resolve(Motion.expand, reduceMotion: reduceMotion || MotionPreference.reduced)) {
                        expanded.toggle()
                    }
                } label: {
                    Text(expanded ? "Less" : "More").scaledFont(13, .bold).foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Show less of the synopsis" : "Show the full synopsis")
            }
        }
    }

    /// Roughly 45 characters per line on a phone; short synopses get no toggle.
    static func isLong(_ text: String, lines: Int) -> Bool { text.count > lines * 45 }
}

/// Director, writers, release date and other credits in a calm two- or three-column grid.
struct DetailCreditsGrid: View {
    let credits: [DetailCredit]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: max(columns, 1)),
                  alignment: .leading, spacing: 14) {
            ForEach(credits) { credit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(credit.label.uppercased()).tracking(0.6)
                        .scaledFont(11, .bold).foregroundStyle(Color.inkFaint(0.5))
                    Text(credit.value)
                        .scaledFont(14, .medium).foregroundStyle(Color.inkAlpha(0.9))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: Cast

/// Horizontal cast carousel: circular portraits (initials while loading or when the source has no
/// photo), actor name and character.
struct DetailCastRow: View {
    let people: [CinemetaCatalog.Person]
    var portrait: CGFloat = 76

    var body: some View {
        UnclippedHScroll {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(people) { person in DetailCastCard(person: person, portrait: portrait) }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct DetailCastCard: View {
    let person: CinemetaCatalog.Person
    var portrait: CGFloat = 76

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.inkAlpha(0.08))
                if person.photo != nil {
                    CachedArtwork(url: person.photo, contentMode: .fill) { monogram }
                } else {
                    monogram
                }
            }
            .frame(width: portrait, height: portrait)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.inkAlpha(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            VStack(spacing: 2) {
                Text(person.name).scaledFont(12, .semibold).foregroundStyle(Color.ink)
                if !person.character.isEmpty {
                    Text(person.character).scaledFont(11).foregroundStyle(Color.inkFaint(0.55))
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(width: portrait + 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.character.isEmpty ? person.name : "\(person.name) as \(person.character)")
    }

    private var monogram: some View {
        Text(person.initials.isEmpty ? "?" : person.initials)
            .scaledFont(portrait * 0.3, .bold)
            .foregroundStyle(Color.inkAlpha(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Trailers

/// 16:9 trailer cards. YouTube is the only trailer source Stremio metadata publishes, so a tap opens
/// the video in the YouTube app (or Safari) on this iPhone.
struct DetailTrailerRow: View {
    let trailers: [CinemetaCatalog.Trailer]
    var cardWidth: CGFloat = 240
    @Environment(\.openURL) private var openURL

    var body: some View {
        UnclippedHScroll {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(trailers) { trailer in
                    Button {
                        Haptics.soft()
                        if let url = RemoteModel.youTubeURL(id: trailer.youTubeID) { openURL(url) }
                    } label: {
                        DetailTrailerCard(trailer: trailer, width: cardWidth)
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Play \(trailer.title)")
                    .accessibilityHint("Opens the trailer on YouTube on this iPhone.")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct DetailTrailerCard: View {
    let trailer: CinemetaCatalog.Trailer
    let width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(width: width, height: width * 9 / 16)
                .overlay { CachedArtwork(url: trailer.thumbnail, contentMode: .fill) { Color.inkAlpha(0.08) } }
                .overlay { LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom) }
                .clipShape(shape)
                .overlay(shape.stroke(Color.inkAlpha(0.14), lineWidth: 0.8))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                        .glassSurface(Circle(), interactive: true)
                }
            Text(trailer.title)
                .scaledFont(13, .semibold).foregroundStyle(Color.ink)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

// MARK: Episodes

/// Season picker and the season's episodes. Tapping an episode opens Play for that season: the stream
/// picker lists the season's episodes, and Nuvio has no verified per-episode link to open instead.
struct DetailEpisodeList: View {
    let episodes: [CinemetaCatalog.Episode]
    let seasons: [Int]
    @Binding var season: Int
    var currentSeason: Int? = nil
    var currentEpisode: Int? = nil
    var onPlay: (CinemetaCatalog.Episode) -> Void

    @Environment(\.glassTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if seasons.count > 1 {
                UnclippedHScroll {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { value in seasonChip(value) }
                    }
                    .padding(.horizontal, 2)
                }
            }
            LazyVStack(spacing: 10) {
                ForEach(episodes.filter { $0.season == season }) { episode in
                    Button { onPlay(episode) } label: {
                        DetailEpisodeRow(episode: episode,
                                         isCurrent: currentSeason == episode.season && currentEpisode == episode.number)
                    }
                    .buttonStyle(GlassPressStyle(scale: 0.98))
                    .accessibilityHint("Finds streams for this season with your add-ons.")
                }
            }
        }
    }

    private func seasonChip(_ value: Int) -> some View {
        let selected = value == season
        return Button {
            withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion || MotionPreference.reduced)) { season = value }
        } label: {
            Text("Season \(value)")
                .scaledFont(13, .semibold)
                .foregroundStyle(selected ? Color.white : Color.ink)
                .padding(.horizontal, 14).frame(height: 34)
                .background { if selected { Capsule().fill(theme.accent) } }
                .glassSurface(Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DetailEpisodeRow: View {
    let episode: CinemetaCatalog.Episode
    var isCurrent = false
    @Environment(\.glassTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            if let thumbnail = episode.thumbnail {
                Color.clear
                    .frame(width: 112, height: 63)
                    .overlay { CachedArtwork(url: thumbnail, contentMode: .fill) { Color.inkAlpha(0.08) } }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("\(episode.number)")
                    .scaledFont(15, .bold)
                    .frame(width: 38, height: 38)
                    .glassSurface(Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Episode \(episode.number)").scaledFont(12, .bold).foregroundStyle(Color.inkFaint(0.55))
                    if isCurrent { Text("Watching").scaledFont(11, .bold).foregroundStyle(theme.accent) }
                }
                if !episode.title.isEmpty {
                    Text(episode.title).scaledFont(14, .semibold).foregroundStyle(Color.ink).lineLimit(2)
                }
                if !episode.overview.isEmpty {
                    Text(episode.overview).scaledFont(12).foregroundStyle(Color.inkAlpha(0.65)).lineLimit(2)
                }
                if let released = episode.released {
                    Text(released, style: .date).scaledFont(11).foregroundStyle(Color.inkFaint(0.45))
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "play.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color.inkAlpha(0.6))
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(shape)
        .overlay { if isCurrent { shape.stroke(theme.accent.opacity(0.7), lineWidth: 1.2) } }
    }
}

// MARK: More like this

/// Popular titles in the same genre, drawn in the profile's artwork orientation.
struct DetailSimilarRow: View {
    let titles: [MediaTitle]
    var shape: DiscoverCardShape = .portrait
    var posterWidth: CGFloat = PosterCard.width
    var onOpen: (MediaTitle) -> Void

    var body: some View {
        UnclippedHScroll {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(titles) { title in
                    Button { onOpen(title) } label: {
                        if shape == .landscape {
                            LandscapeCard(title: title)
                        } else {
                            PosterCard(title: title, cardWidth: posterWidth)
                        }
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel(title.name)
                    .accessibilityHint("Opens this title's details.")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
