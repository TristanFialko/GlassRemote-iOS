import SwiftUI

/// Discover's cinematic hero: a full-bleed backdrop filling the top of the page (under the status bar and the
/// floating search bar). It fades into the page canvas and carries the featured title (logo when the
/// catalogue has one), metadata, a short synopsis and actions.
///
/// Featured titles cross-fade; swipe sideways or tap the page dots to change. Pulling down stretches the
/// artwork and scrolling gives it a light parallax (one geometry read, no continuous animation).
/// Auto-advance is a single sleeping task that restarts on every change, stops off screen and in the
/// background, and is off with Reduce Motion. The next backdrop is pre-loaded so a change never waits.
struct DiscoverHero: View {
    static let space = "discoverScroll"

    let titles: [MediaTitle]
    @Binding var selection: String?
    let size: CGSize
    let isLandscape: Bool
    let leadingInset: CGFloat
    let onOpen: (MediaTitle) -> Void
    let onPlay: (MediaTitle) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.glassTheme) private var theme

    private var reduceMotion: Bool { systemReduceMotion || MotionPreference.reduced }
    private var current: MediaTitle? { titles.first { $0.id == selection } ?? titles.first }
    private var timerKey: String { "\(current?.id ?? "-")|\(scenePhase == .active)|\(titles.count)" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .contentShape(Rectangle())
                .onTapGesture { if let current { onOpen(current) } }
            if let current {
                info(current)
                    .id(current.id)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(x: 18)), removal: .opacity))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .simultaneousGesture(swipe)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next featured title") { advance(by: 1) }
        .accessibilityAction(named: "Previous featured title") { advance(by: -1) }
        .task(id: timerKey) { await autoAdvance() }
    }

    // MARK: Artwork

    private var backdrop: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(Self.space)).minY
            let pull = max(0, minY)
            let drift = reduceMotion ? 0 : -min(0, minY) * 0.3
            ZStack {
                ForEach(titles) { title in
                    if title.id == current?.id { artwork(title).transition(.opacity) }
                }
                scrim
            }
            .frame(width: size.width, height: size.height + pull)
            .mask(fade)
            .offset(y: drift - pull)
        }
        .frame(width: size.width, height: size.height)
    }

    private func artwork(_ title: MediaTitle) -> some View {
        let art = DiscoverHeroLayout.artwork(for: title)
        return Color.clear
            .overlay {
                CachedArtwork(url: art.primary, fallbackURL: art.fallback, contentMode: .fill) {
                    LinearGradient(colors: [theme.accent.opacity(0.22), Color.clear], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
    }

    /// Top band keeps the status bar and search bar legible; the lower band carries the text; in landscape
    /// a leading band sits behind the text column. A faint accent glow ties the art to the theme.
    private var scrim: some View {
        ZStack {
            LinearGradient(stops: [.init(color: theme.isLight ? theme.canvasTop.opacity(0.75) : .black.opacity(0.55), location: 0),
                                   .init(color: .clear, location: 0.28)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: .clear, location: isLandscape ? 0.3 : 0.38),
                                   .init(color: .black.opacity(0.8), location: 0.88)],
                           startPoint: .top, endPoint: .bottom)
            if isLandscape {
                LinearGradient(stops: [.init(color: .black.opacity(0.72), location: 0), .init(color: .clear, location: 0.62)],
                               startPoint: .leading, endPoint: .trailing)
            }
            RadialGradient(colors: [theme.accent.opacity(0.16), .clear], center: .bottomLeading,
                           startRadius: 0, endRadius: max(size.width, size.height) * 0.8)
        }
        .allowsHitTesting(false)
    }

    /// Fades art and scrim into the page canvas, so the hero has no hard bottom edge.
    private var fade: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                               .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Text and actions

    private func info(_ t: MediaTitle) -> some View {
        VStack(alignment: .leading, spacing: isLandscape ? 8 : 10) {
            titleArt(t)
            metaLine(t)
                .scaledFont(13, .semibold).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
            if !t.overview.isEmpty {
                Text(t.overview)
                    .scaledFont(13).foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
            }
            actions(t).padding(.top, 4)
            if titles.count > 1 { dots.padding(.top, 2) }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: isLandscape ? min(size.width * 0.46, 460) : .infinity, alignment: .leading)
        .padding(.leading, 20 + leadingInset)
        .padding(.trailing, 20)
        .padding(.bottom, max(18, size.height * 0.07))
    }

    /// The catalogue logo when it loads; otherwise the title as large text.
    private func titleArt(_ t: MediaTitle) -> some View {
        CachedArtwork(url: t.logoURL, contentMode: .fit) {
            Text(t.name)
                .scaledFont(isLandscape ? 30 : 34, .heavy)
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: isLandscape ? 300 : 280, maxHeight: isLandscape ? 64 : 88, alignment: .bottomLeading)
        .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.name)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Movie · 2026 · Drama · Thriller · ★ 7.4", one line with even gaps.
    private func metaLine(_ t: MediaTitle) -> Text {
        var parts = [DiscoverMetaLine.kindAndYear(t.kind, year: t.year)]
        parts += t.genres.prefix(2)
        var line = Text(parts.joined(separator: DiscoverMetaLine.separator))
        let rating = t.rating.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rating.isEmpty {
            line = line + Text(DiscoverMetaLine.separator) + Text(Image(systemName: "star.fill")).foregroundColor(.yellow) + Text(" \(rating)")
        }
        return line
    }

    /// Movies go straight to the stream picker. Series open the detail page, where the episode is chosen.
    private func actions(_ t: MediaTitle) -> some View {
        HStack(spacing: 10) {
            Button { onPlay(t) } label: {
                Label(t.kind == .movie ? "Play" : "Episodes",
                      systemImage: t.kind == .movie ? "play.fill" : "list.bullet.rectangle.portrait")
                    .scaledFont(15, .semibold)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel(t.kind == .movie ? "Play \(t.name)" : "Episodes of \(t.name)")
            Button { onOpen(t) } label: {
                Label("Details", systemImage: "info.circle")
                    .scaledFont(15, .semibold)
                    .padding(.horizontal, 18).frame(height: 44)
                    .glassSurface(Capsule(), interactive: true)
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Details for \(t.name)")
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(titles) { t in
                let on = t.id == current?.id
                Capsule().fill(Color.white.opacity(on ? 0.95 : 0.4))
                    .frame(width: on ? 18 : 6, height: 6)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { select(t.id) }
            }
        }
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: current?.id)
        .accessibilityHidden(true)
    }

    // MARK: Changing title

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) > 50, abs(dx) > abs(dy) * 1.4 else { return }
            Haptics.soft()
            advance(by: dx < 0 ? 1 : -1)
        }
    }

    private func select(_ id: String) {
        withAnimation(Motion.resolve(Motion.artwork, reduceMotion: reduceMotion)) { selection = id }
    }

    private func advance(by step: Int) {
        guard titles.count > 1 else { return }
        let i = titles.firstIndex { $0.id == current?.id } ?? 0
        let n = titles.count
        select(titles[((i + step) % n + n) % n].id)
    }

    private func autoAdvance() async {
        guard titles.count > 1 else { return }
        if let i = titles.firstIndex(where: { $0.id == current?.id }),
           let url = DiscoverHeroLayout.artwork(for: titles[(i + 1) % titles.count]).primary {
            _ = await ArtworkCache.shared.image(for: url)
        }
        guard !reduceMotion, scenePhase == .active else { return }
        try? await Task.sleep(nanoseconds: 9_000_000_000)
        guard !Task.isCancelled else { return }
        advance(by: 1)
    }
}
