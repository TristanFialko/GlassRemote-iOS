import SwiftUI

/// Now Playing (v5 §3), laid out like the Apple Music player. Independent of the Remote page: it only
/// reads `remote.media` (the shared, read-only `dumpsys media_session` poll) and sends transport
/// commands through `RemoteModel.sendMedia`, which uses explicit Play / Pause and confirms against the
/// session.
///
/// Portrait: the artwork runs edge to edge from the top of the screen and fades into the backdrop
/// made from it; the title sits on that fade, then a thin timeline, plain transport glyphs and the
/// volume row, with nothing boxed. Landscape is its own layout: a large rounded artwork card on the
/// leading side, and beside it a column as tall as the card with the title at its top, the volume at
/// its bottom and the timeline and transport spread between. Without title artwork both show the
/// app's artwork on a rounded card. A grabber at the top closes the player.
///
/// Real data only: title, optional subtitle, playback state, position (extrapolated between polls) and
/// the actions the session advertises. The box reports no duration and no way to seek to a position,
/// so the timeline is display-only: it fills only with a real duration and otherwise stays an empty
/// track beside the elapsed time. Rewind and fast-forward use the app's own relative step
/// (SEEKING_REPORT.md). The full-screen artwork background, and its no-artwork fallback, are drawn
/// once by `RootPagerView` (PlayerBackdrop.swift), so they run unbroken behind the dock and the rail
/// and are never redrawn by the playback clock.
struct PlayerPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    @ObservedObject private var artwork = PlayerArtworkStore.shared
    @Environment(\.glassTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dockClearance) private var dockClearance
    @Environment(\.layoutContext) private var layoutContext

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })
        let sessionTitle = media.headline.isEmpty ? media.title : media.headline
        let posterURL = media.isActive ? artwork.posterURL(forSessionTitle: sessionTitle) : nil
        let landscapeURL = (media.isActive && posterURL == nil) ? artwork.landscapeURL(forSessionTitle: sessionTitle) : nil
        let art = posterURL ?? landscapeURL
        let scene = PlayerScene(media: media,
                                app: app,
                                art: art,
                                kind: PlayerArtworkKind.resolve(posterURL: posterURL, landscapeURL: landscapeURL),
                                controls: PlayerControls.resolve(media: media),
                                key: PlayerTransition.key(media: media))

        GeometryReader { proxy in
            if layoutContext.isLandscape {
                landscapeLayout(size: proxy.size, scene: scene)
            } else {
                portraitLayout(scene: scene)
            }
        }
        // v5 §2: Now Playing is presented over the pages; the grabber closes it (so does any dock item).
        .overlay(alignment: .top) { grabber }
        .foregroundStyle(Color.ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Nuvio's media session is not known to carry artwork: look the title up so playback started in Nuvio itself
        // (not just from Discover) still gets its poster.
        .task(id: sessionTitle + "|" + media.subtitle) {
            guard media.isActive, PlayerArtworkStore.usesCatalogue(package: media.package), !sessionTitle.isEmpty else { return }
            await artwork.resolve(sessionTitle: sessionTitle, subtitle: media.subtitle)
        }
        // Adaptive theme: this page only reports its artwork; the shared palette decides the colours. The
        // backdrop store makes the background once per artwork, not per poll.
        .onChange(of: art) { _, url in
            ThemeStore.shared.submitArtwork(url, for: .nowPlaying)
            PlayerBackdropStore.shared.show(url)
        }
        .onAppear {
            ThemeStore.shared.submitArtwork(art, for: .nowPlaying)
            PlayerBackdropStore.shared.show(art)
        }
    }

    /// The small grabber at the top of the sheet, as in Apple Music. A full 44 pt target.
    private var grabber: some View {
        Button { navigator.closePlayer() } label: {
            Capsule(style: .continuous)
                .fill(Color.inkAlpha(0.5))
                .frame(width: PlayerLayoutPolicy.grabberSize.width, height: PlayerLayoutPolicy.grabberSize.height)
                .frame(width: 88, height: 44, alignment: .top)
                .padding(.top, layoutContext.isLandscape ? 6 : 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(DockButtonStyle())
        .accessibilityLabel("Close Now Playing")
    }

    // MARK: Layouts

    /// Portrait: the artwork takes everything above the controls; the controls are measured at their
    /// natural height and sit just above the dock. Title artwork bleeds to the screen edges and under
    /// the status bar, and its lower part fades out behind the title.
    private func portraitLayout(scene: PlayerScene) -> some View {
        let margin = PlayerLayoutPolicy.nowPlayingMargin
        return VStack(spacing: 0) {
            GeometryReader { region in
                ZStack(alignment: .top) {
                    if scene.art != nil {
                        // The page ends at the safe area, so the artwork is drawn that much taller
                        // and moved up: it runs under the status bar to the top of the screen.
                        let top = region.safeAreaInsets.top
                        let bleed = PlayerLayoutPolicy.portraitBleed(region: region.size, margin: margin, topInset: top)
                        bleedArtwork(scene: scene, size: bleed)
                            .offset(y: -top)
                            .id(scene.key)                       // artwork and metadata change together
                            .transition(.opacity)
                    } else {
                        let frame = PlayerLayoutPolicy.nowPlayingArtwork(kind: .appIcon,
                                                                         region: PlayerLayoutPolicy.portraitCardRegion(region: region.size))
                        artworkCard(scene: scene, size: frame)
                            .id(scene.key)
                            .transition(.opacity)
                            .frame(width: region.size.width, height: region.size.height)
                    }
                }
                .frame(width: region.size.width, height: region.size.height, alignment: .top)
            }
            controlsColumn(scene: scene, spread: false)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.adaptive(Motion.content), value: scene.key)
        .padding(.horizontal, margin)
        .padding(.bottom, dockClearance + PlayerLayoutPolicy.portraitBottomGap)
    }

    /// Landscape: a large artwork card on the leading side and, beside it, a column as tall as the
    /// card. The rail stays visible (the page already starts after it). Not a rotated portrait layout.
    private func landscapeLayout(size: CGSize, scene: PlayerScene) -> some View {
        let split = PlayerLayoutPolicy.landscape(page: size, bottomClearance: dockClearance)
        let frame = PlayerLayoutPolicy.nowPlayingArtwork(kind: scene.kind,
                                                         region: CGSize(width: split.artSide, height: split.artSide))
        return HStack(spacing: split.spacing) {
            ZStack {
                artworkCard(scene: scene, size: frame)
                    .id(scene.key)
                    .transition(.opacity)
            }
            // The region hugs the card's own width, so the gap to the column is the same for a
            // 4:5 poster as for a square card.
            .frame(width: frame.width, height: split.artSide)
            controlsColumn(scene: scene, spread: true)
                .frame(width: split.column, height: PlayerLayoutPolicy.landscapeColumnHeight(artSide: split.artSide))
        }
        .animation(Motion.adaptive(Motion.content), value: scene.key)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, PlayerLayoutPolicy.landscapeTopInset)
        .padding(.bottom, dockClearance)
    }

    /// Title, timeline, transport, volume. Portrait stacks them at a fixed rhythm; landscape
    /// (`spread`) pins the title to the top and the volume to the bottom of the column.
    private func controlsColumn(scene: PlayerScene, spread: Bool) -> some View {
        VStack(alignment: .leading, spacing: spread ? 0 : PlayerLayoutPolicy.controlSpacing) {
            ZStack(alignment: .leading) {
                titleBlock(app: scene.app, media: scene.media)
                    .id(scene.key)
                    .transition(.opacity)
            }
            if spread { Spacer(minLength: PlayerLayoutPolicy.landscapeMinRowGap) }
            statusBlock(scene: scene)
            if spread { Spacer(minLength: PlayerLayoutPolicy.landscapeMinRowGap) }
            if scene.media.isActive {
                transport(media: scene.media, controls: scene.controls)
                    .transition(.opacity)
                if spread { Spacer(minLength: PlayerLayoutPolicy.landscapeMinRowGap) }
            }
            PlayerVolumeBar()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Artwork

    private func artworkLabel(_ kind: PlayerArtworkKind) -> String {
        switch kind {
        case .poster: return "Poster"
        case .landscape: return "Artwork"
        case .appIcon: return "App artwork"
        }
    }

    /// Portrait title artwork: edge to edge, under the status bar, filled and centre-cropped (never
    /// stretched), with its lower part fading into the backdrop made from the same picture.
    private func bleedArtwork(scene: PlayerScene, size: CGSize) -> some View {
        ZStack {
            if let art = scene.art {
                CachedArtwork(url: art, contentMode: .fill) { Color.clear }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: PlayerLayoutPolicy.bleedFadeStart),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(Motion.adaptive(Motion.poster), value: scene.art)
        .accessibilityLabel(artworkLabel(scene.kind))
    }

    /// The rounded artwork card (landscape, and portrait without title artwork). No border: only a
    /// soft shadow lifts it off the backdrop.
    private func artworkCard(scene: PlayerScene, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlayerLayoutPolicy.artworkCornerRadius, style: .continuous)
        let hasArt = scene.art != nil
        let scale = PlayerLayoutPolicy.artworkScale(isPlaying: scene.media.isPlaying || !scene.media.isActive,
                                                    reduceMotion: reduceMotion)
        return ZStack {
            if let art = scene.art {
                shape.fill(Color.black.opacity(0.4))
                // Filled and centre-cropped to the card's own proportions: crisp, never stretched.
                CachedArtwork(url: art, contentMode: .fill) { fallbackArt(app: scene.app, media: scene.media, side: size.width) }
            } else {
                fallbackArt(app: scene.app, media: scene.media, side: size.width)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: Color.black.opacity(hasArt ? 0.32 : 0.2), radius: 30, y: 16)
        // Like Apple Music: the artwork eases back slightly while paused.
        .scaleEffect(scale)
        .animation(Motion.unlessReduced(Motion.settle, reduceMotion: reduceMotion), value: scale)
        .animation(Motion.adaptive(Motion.poster), value: scene.art)
        .accessibilityLabel(artworkLabel(scene.kind))
    }

    /// The no-artwork card: a soft wash of the theme accent with the app's own artwork (or a symbol).
    private func fallbackArt(app: TVApp?, media: MediaState, side: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [theme.accent.opacity(0.55), theme.accent.opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.ink.opacity(0.04)
            if let app {
                Image(app.asset == "nuvio" ? "nuvio_nowplaying" : "\(app.asset)_dark")
                    .resizable().scaledToFit()
                    .padding(max(side, 0) * (app.asset == "nuvio" ? 0.28 : 0.24))
            } else {
                Image(systemName: media.isActive ? AppPage.playerSymbolOutline : "tv")
                    .scaledFont(56, .light).foregroundStyle(Color.ink.opacity(0.5))
            }
        }
    }

    // MARK: Title

    /// Left-aligned title and artist line, like Apple Music: same size, the second line lighter.
    private func titleBlock(app: TVApp?, media: MediaState) -> some View {
        let name = app?.name ?? (media.package.split(separator: ".").last.map(String.init) ?? "")
        let title: String = {
            guard media.isActive else { return "Nothing playing" }
            if !media.headline.isEmpty { return media.headline }
            return media.title.isEmpty ? (name.isEmpty ? "Playing" : name) : media.title
        }()
        // Episode information only when the session really reports a subtitle.
        let secondary = media.isActive ? PlayerTitlePolicy.secondaryLine(subtitle: media.subtitle, appName: name, title: title) : ""
        return VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .scaledFont(PlayerLayoutPolicy.titleSize, .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !secondary.isEmpty {
                Text(secondary)
                    .scaledFont(PlayerLayoutPolicy.titleSize)
                    .foregroundStyle(Color.inkAlpha(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Timeline

    /// The timeline and its captions. The clock ticks once a second only while playing, re-checks every
    /// few seconds otherwise, and stops entirely while Now Playing is hidden or the app is inactive.
    private func statusBlock(scene: PlayerScene) -> some View {
        let media = scene.media
        let controls = scene.controls
        let connected = remote.connected
        let connecting = remote.isBusyConnecting
        let interval = PlayerTimeline.refreshInterval(isPlaying: media.state == 3)
        let paused = PlayerTimeline.isPaused(sceneActive: scenePhase == .active, presented: navigator.playerPresented)
        return TimelineView(.animation(minimumInterval: interval, paused: paused)) { context in
            statusContent(media: media, controls: controls,
                          phase: PlayerSessionPhase.resolve(media: media, connected: connected, connecting: connecting, now: context.date),
                          now: context.date)
        }
    }

    @ViewBuilder
    private func statusContent(media: MediaState, controls: PlayerControls, phase: PlayerSessionPhase, now: Date) -> some View {
        if phase.showsSession {
            let position = PlayerTimeline.position(media: media, phase: phase, at: now)
            let total: TimeInterval? = (controls.progress ? media.durationMs : nil).map { Double($0) / 1000 }
            timeline(position: position, total: total,
                     caption: PlayerCaptionPolicy.caption(phase: phase, seek: seekNote(now: now)))
        } else {
            Text(phase.hint)
                .scaledFont(15)
                .foregroundStyle(Color.inkAlpha(0.58))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Thin, display-only timeline with the times under it. It fills only with a real total length
    /// (never today: the box does not report one, see SEEKING_REPORT.md); without one the track stays
    /// empty and only the elapsed time is shown. There is no scrubber because nothing can seek to a
    /// position. The centre caption carries the session state or the last confirmed seek.
    private func timeline(position: TimeInterval, total: TimeInterval?, caption: String) -> some View {
        let fraction = total.map { PlayerTimeline.fraction(position: position, total: $0) } ?? 0
        return VStack(spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(Color.inkAlpha(0.2))
                    Capsule(style: .continuous).fill(Color.inkAlpha(0.85)).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: PlayerLayoutPolicy.timelineHeight)
            ZStack {
                HStack {
                    Text(MediaState.format(position))
                    Spacer()
                    if let total { Text("-" + MediaState.format(max(0, total - position))) }
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.inkAlpha(0.5))
                if !caption.isEmpty {
                    Text(caption)
                        .scaledFont(12, .semibold)
                        .foregroundStyle(Color.inkAlpha(0.6))
                        .lineLimit(1)
                        .padding(.horizontal, 52)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total.map { "Elapsed \(MediaState.format(position)) of \(MediaState.format($0))" }
                            ?? "Elapsed \(MediaState.format(position))")
        .accessibilityValue(caption)
    }

    /// Honest seek feedback: only what the TV's session confirmed, for a few seconds after the key.
    private func seekNote(now: Date) -> String? {
        guard let report = remote.lastSeek, now.timeIntervalSince(report.at) < 8 else { return nil }
        switch report.outcome {
        case .confirmed(let seconds): return PlayerCaptionPolicy.seekText(seconds: seconds)
        case .unchanged: return "No change"
        case .unknown: return nil
        }
    }

    // MARK: Transport (plain glyphs, like Apple Music)

    /// Play / pause is primary. Rewind and fast-forward appear only when the session advertises them;
    /// track skip only for explicit audio-track sessions (never video, never Nuvio). No inert buttons
    /// and no bar behind them: the glyphs sit directly on the artwork backdrop.
    private func transport(media: MediaState, controls: PlayerControls) -> some View {
        let busy = remote.mediaCommandPending
        // Relabelled "10 s" only once BOTH keys have been measured, repeatedly, at about ten seconds.
        let tenSecond = remote.seekLearner.isTenSecond(package: media.package)
        return HStack(spacing: 0) {
            if controls.previousTrack {
                control("backward.end.fill", "Previous track", enabled: !busy) { remote.sendMedia(.previous) }
            }
            if controls.rewind {
                control(tenSecond ? "gobackward.10" : "backward.fill", tenSecond ? "Back 10 seconds" : "Rewind", enabled: !busy) {
                    remote.sendMedia(.rewind)
                }
            }
            playButton(media: media, enabled: controls.playPause && !busy, busy: busy)
            if controls.fastForward {
                control(tenSecond ? "goforward.10" : "forward.fill", tenSecond ? "Forward 10 seconds" : "Fast forward", enabled: !busy) {
                    remote.sendMedia(.fastForward)
                }
            }
            if controls.nextTrack {
                control("forward.end.fill", "Next track", enabled: !busy) { remote.sendMedia(.next) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PlayerLayoutPolicy.transportHeight)
        .padding(.horizontal, PlayerLayoutPolicy.transportInset)
    }

    private func playButton(media: MediaState, enabled: Bool, busy: Bool) -> some View {
        Button { remote.sendMedia(PlayerControls.playPauseCommand(for: media)) } label: {
            ZStack {
                if busy { ProgressView().tint(Color.ink) }
                else {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: PlayerLayoutPolicy.playGlyph, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(maxWidth: .infinity).frame(height: PlayerLayoutPolicy.transportHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .controlDisabled(!(enabled || busy))
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    private func control(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: PlayerLayoutPolicy.secondaryGlyph, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: PlayerLayoutPolicy.transportHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled).controlDisabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Everything one render of the Player needs, resolved once per body.
private struct PlayerScene {
    let media: MediaState
    let app: TVApp?
    let art: URL?
    let kind: PlayerArtworkKind
    let controls: PlayerControls
    let key: String
}

/// The volume row (v5 §3), drawn like Apple Music's: a quiet speaker, a thin neutral track, a loud
/// speaker. It is not a separate volume system: the same slider, the same Samsung target, mapping,
/// commands and feedback as the Remote page, so TV readings never fight a finger and a value shown
/// from a reading is never sent back.
private struct PlayerVolumeBar: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var value: Double = 0.5
    @State private var externalEcho: Double?

    var body: some View {
        GlassVolumeSlider(value: $value, scale: remote.volumeScale, thickness: ThinVolumeMetrics.minimumTouchTarget,
                          appearance: .nowPlaying,
                          onDragChange: { remote.volumeDragChanged($0) })
            .onChange(of: value) { _, newValue in
                if let echo = externalEcho, abs(newValue - echo) < 0.0001 { externalEcho = nil; return }
                remote.setVolumeFraction(newValue)
            }
            .onChange(of: remote.volumeReading) { _, event in
                guard let event, let shown = remote.sliderValue(forReading: event.fraction, showing: value) else { return }
                externalEcho = shown
                value = shown
            }
            .onAppear {
                // Start from the last real reading (the Remote page asks the device on appear).
                if let last = remote.volumeReading?.fraction, abs(last - value) > 0.0001 {
                    externalEcho = last
                    value = last
                }
            }
    }
}
