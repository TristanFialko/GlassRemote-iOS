import SwiftUI

/// Discover's cinematic hero: a full-bleed backdrop filling the top of the page (under the status bar and the
/// floating search bar). It fades into the page canvas and carries the featured title (logo when the
/// catalogue has one), metadata, a short synopsis and actions.
///
/// Featured titles cross-fade; swipe sideways or tap the page dots to change. Phase 7.3: the hero is a
/// no-page-swipe zone, so a sideways swipe on it only changes the title (the text follows the finger and
/// snaps back as the next title fades in); opening is tap-only (a drag never opens), see HeroSwipePolicy. Pulling down stretches the
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
    /// Phase 7.4: bottom of Discover's floating header (global). A tap above it belongs to the header.
    var headerBottom: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.glassTheme) private var theme
    /// Horizontal finger travel while a hero swipe is in progress; springs back on lift or cancellation.
    @GestureState(resetTransaction: Transaction(animation: Motion.release))
    private var drag: CGFloat = 0

    private var reduceMotion: Bool { systemReduceMotion || MotionPreference.reduced }
    private var current: MediaTitle? { titles.first { $0.id == selection } ?? titles.first }
    private var timerKey: String { "\(current?.id ?? "-")|\(scenePhase == .active)|\(titles.count)" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                    guard DiscoverTouchPolicy.heroMayOpen(tapY: tap.location.y, headerBottom: headerBottom),
                          let current else { return }
                    onOpen(current)
                })
            if let current {
                info(current)
                    .id(current.id)
                    .offset(x: reduceMotion ? 0 : HeroSwipePolicy.follow(drag))
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(x: 18)), removal: .opacity))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        // Phase 7.3: a touch that lands on the hero never starts a page swipe.
        .background { PagerExclusionZone() }
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
                    .foregroundStyle(theme.playInk)
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(Capsule().fill(theme.playFill))
                    .glassSurface(Capsule(), interactive: true)
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
        DragGesture(minimumDistance: 24)
            .updating($drag) { value, state, _ in
                if HeroSwipePolicy.isHorizontal(value.translation) { state = value.translation.width }
            }
            .onEnded { value in
                guard let step = HeroSwipePolicy.step(translation: value.translation,
                                                      predicted: value.predictedEndTranslation) else { return }
                Haptics.soft()
                advance(by: step)
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

/// Phase 7.3: pure rules for the hero swipe (unit tested).
enum HeroSwipePolicy {
    static let minimumTravel: CGFloat = 50
    static let dominance: CGFloat = 1.4
    /// The text follows the finger at this fraction, never more than `maxFollow` points.
    static let followFactor: CGFloat = 0.35
    static let maxFollow: CGFloat = 60

    static func isHorizontal(_ t: CGSize) -> Bool { abs(t.width) > abs(t.height) * dominance }

    /// +1 for the next title, -1 for the previous, nil when the drag is not a hero swipe (vertical scroll,
    /// too short). A quick flick in the same direction counts by where it would land.
    static func step(translation: CGSize, predicted: CGSize) -> Int? {
        guard isHorizontal(translation) else { return nil }
        let sameDirection = (predicted.width < 0) == (translation.width < 0)
        let travel = sameDirection && abs(predicted.width) > abs(translation.width) ? predicted.width : translation.width
        guard abs(travel) > minimumTravel else { return nil }
        return travel < 0 ? 1 : -1
    }

    static func follow(_ dx: CGFloat) -> CGFloat {
        max(-maxFollow, min(maxFollow, dx * followFactor))
    }
}

/// Phase 7.4: the floating search header sits over the hero. A tap inside it (or within a finger's
/// slop of its bottom edge) never opens the featured title.
enum DiscoverTouchPolicy {
    static let headerSlop: CGFloat = 6
    static func heroMayOpen(tapY: CGFloat, headerBottom: CGFloat) -> Bool { tapY > headerBottom + headerSlop }
}
