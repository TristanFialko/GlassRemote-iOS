import SwiftUI

/// Now Playing (v5 §3), laid out like the Apple Music player. Independent of the Remote page: it only
/// reads `remote.media` (the shared, read-only `dumpsys media_session` poll) and sends transport
/// commands through `RemoteModel.sendMedia`, which uses explicit Play / Pause and confirms against the
/// session.
///
/// Portrait: a large near-square artwork dominates the upper screen; below it one compact, left-aligned
/// group holds the title and artist line, a thin timeline, plain transport glyphs and the compact
/// volume row (the same Samsung volume pipeline as the Remote slider). Landscape: two columns, the
/// artwork on the left and that group on the right, with the rail still visible.
///
/// Real data only: title, optional subtitle, playback state, position (extrapolated between polls) and
/// the actions the session advertises. The box reports no duration and no way to seek to a position,
/// so the timeline is display-only and appears only with a real duration; rewind and fast-forward use
/// the app's own relative step (SEEKING_REPORT.md). The full-screen artwork background, and its
/// no-artwork fallback, are drawn once by `RootPagerView` (PlayerBackdrop.swift), so they run unbroken
/// behind the dock and the rail and are never redrawn by the playback clock.
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

        VStack(spacing: 0) {
            // v5 §2: Now Playing is presented over the pages; this closes it (so does any dock item).
            if !layoutContext.isLandscape {
                closeButton.frame(maxWidth: .infinity)
            }
            GeometryReader { proxy in
                if layoutContext.isLandscape {
                    landscapeLayout(size: proxy.size, scene: scene)
                } else {
                    portraitLayout(scene: scene)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if layoutContext.isLandscape { closeButton.padding(.trailing, 4) }
        }
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

    private var closeButton: some View {
        Button { navigator.closePlayer() } label: {
            Image(systemName: "chevron.down")
                .scaledFont(18, .semibold)
                .foregroundStyle(Color.inkAlpha(0.78))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(DockButtonStyle())
        .accessibilityLabel("Close Now Playing")
    }

    // MARK: Layouts

    /// Portrait: the artwork takes everything above the controls, so it dominates; the controls are
    /// measured at their natural height and sit just above the dock.
    private func portraitLayout(scene: PlayerScene) -> some View {
        VStack(spacing: PlayerLayoutPolicy.portraitGap) {
            GeometryReader { region in
                let frame = PlayerLayoutPolicy.nowPlayingArtwork(kind: scene.kind, region: region.size)
                ZStack {
                    artworkCard(scene: scene, size: frame)
                        .id(scene.key)                       // artwork and metadata change together
                        .transition(.opacity)
                }
                .frame(width: region.size.width, height: region.size.height)
            }
            controlsColumn(scene: scene)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.adaptive(Motion.content), value: scene.key)
        .padding(.horizontal, PlayerLayoutPolicy.nowPlayingMargin)
        .padding(.top, 4)
        .padding(.bottom, dockClearance + 8)
    }

    /// Landscape: a square artwork region on the leading side; the same compact group beside it. The
    /// rail stays visible (the page already starts after it). Not a rotated portrait layout.
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
            .frame(width: split.artSide, height: split.artSide)
            controlsColumn(scene: scene)
                .frame(width: split.column)
        }
        .animation(Motion.adaptive(Motion.content), value: scene.key)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, dockClearance)
    }

    /// The compact group under (or beside) the artwork: title, timeline, transport, volume.
    private func controlsColumn(scene: PlayerScene) -> some View {
        VStack(alignment: .leading, spacing: PlayerLayoutPolicy.controlSpacing) {
            ZStack(alignment: .leading) {
                titleBlock(app: scene.app, media: scene.media)
                    .id(scene.key)
                    .transition(.opacity)
            }
            statusBlock(scene: scene)
            if scene.media.isActive {
                transport(media: scene.media, controls: scene.controls)
                    .transition(.opacity)
            }
            PlayerVolumeBar()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Artwork

    private func artworkCard(scene: PlayerScene, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlayerLayoutPolicy.artworkCornerRadius, style: .continuous)
        let hasArt = scene.art != nil
        let label: String = {
            switch scene.kind {
            case .poster: return "Poster"
            case .landscape: return "Artwork"
            case .appIcon: return "App artwork"
            }
        }()
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
        .overlay { shape.stroke(Color.ink.opacity(0.14), lineWidth: 0.6) }
        .shadow(color: Color.black.opacity(hasArt ? 0.38 : 0.22), radius: 26, y: 14)
        // Like Apple Music: the artwork eases back slightly while paused.
        .scaleEffect(scale)
        .animation(Motion.unlessReduced(Motion.settle, reduceMotion: reduceMotion), value: scale)
        .animation(Motion.adaptive(Motion.poster), value: scene.art)
        .accessibilityLabel(label)
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

    /// Left-aligned title and artist line, like Apple Music.
    private func titleBlock(app: TVApp?, media: MediaState) -> some View {
        let name = app?.name ?? (media.package.split(separator: ".").last.map(String.init) ?? "")
        let title: String = {
            guard media.isActive else { return "Nothing playing" }
            if !media.headline.isEmpty { return media.headline }
            return media.title.isEmpty ? (name.isEmpty ? "Playing" : name) : media.title
        }()
        // Episode information only when the session really reports a subtitle.
        let secondary = media.isActive ? PlayerTitlePolicy.secondaryLine(subtitle: media.subtitle, appName: name, title: title) : ""
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .scaledFont(21, .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !secondary.isEmpty {
                Text(secondary)
                    .scaledFont(17)
                    .foregroundStyle(Color.inkAlpha(0.62))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: State, elapsed time

    /// Session state and elapsed time. The clock ticks once a second only while playing, re-checks every
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
        let position = PlayerTimeline.position(media: media, phase: phase, at: now)
        VStack(alignment: .leading, spacing: 6) {
            if phase.showsSession {
                if controls.progress, let duration = media.durationMs {
                    timeline(position: position, total: Double(duration) / 1000)
                } else {
                    elapsedRow(phase: phase, position: position)
                }
                if controls.rewind || controls.fastForward, let line = seekLine(media: media, now: now) {
                    Text(line).scaledFont(12, .medium).foregroundStyle(Color.inkAlpha(0.62)).lineLimit(2)
                }
            } else {
                Text(phase.hint).scaledFont(14).foregroundStyle(Color.inkAlpha(0.58))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Thin, display-only timeline: only with a real total length (never today: the box does not
    /// report one, see SEEKING_REPORT.md). There is no scrubber because nothing can seek to a position.
    private func timeline(position: TimeInterval, total: TimeInterval) -> some View {
        let fraction = PlayerTimeline.fraction(position: position, total: total)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.inkAlpha(0.18))
                    Capsule().fill(Color.inkAlpha(0.82)).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: PlayerLayoutPolicy.timelineHeight)
            HStack {
                Text(MediaState.format(position))
                Spacer()
                Text("-" + MediaState.format(max(0, total - position)))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.inkAlpha(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed \(MediaState.format(position)) of \(MediaState.format(total))")
    }

    /// Without a duration: the session state and the elapsed time on one quiet row.
    private func elapsedRow(phase: PlayerSessionPhase, position: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Circle().fill(stateColour(phase)).frame(width: 7, height: 7)
            Text(phase.label).scaledFont(13, .semibold)
            Spacer(minLength: 8)
            Text(MediaState.format(position))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Color.inkAlpha(0.68))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phase.label), elapsed \(MediaState.format(position))")
    }

    private func stateColour(_ phase: PlayerSessionPhase) -> Color {
        switch phase {
        case .playing: return .green
        case .buffering: return .yellow
        case .paused: return .orange
        case .stale, .connecting, .disconnected, .idle: return .gray
        }
    }

    // MARK: Transport (plain glyphs, like Apple Music)

    /// Play / pause is primary. Rewind and fast-forward appear only when the session advertises them;
    /// track skip only for explicit audio-track sessions (never video, never Nuvio). No inert buttons
    /// and no glass bar: the glyphs sit directly on the artwork backdrop.
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

    /// Honest seek feedback: only what the TV's session confirmed, for a few seconds after the key.
    private func seekLine(media: MediaState, now: Date) -> String? {
        if let report = remote.lastSeek, now.timeIntervalSince(report.at) < 8 {
            let name = report.command == .rewind ? "Rewind" : "Fast-forward"
            switch report.outcome {
            case .confirmed(let seconds): return "\(name): \(seconds < 0 ? "−" : "+")\(Int(abs(seconds).rounded())) s, confirmed by the TV"
            case .unchanged: return "\(name): the TV reported no position change"
            case .unknown: break
            }
        }
        let back = remote.seekLearner.step(package: media.package, command: .rewind)
        let forward = remote.seekLearner.step(package: media.package, command: .fastForward)
        guard back != nil || forward != nil else { return nil }
        func text(_ v: Double?) -> String { v.map { "≈\(Int($0.rounded())) s" } ?? "not measured" }
        return "Measured steps: rewind \(text(back)), fast-forward \(text(forward))"
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

/// The compact volume row (v5 §3), like Apple Music's small volume slider. It is not a separate volume
/// system: the same thin slider, the same Samsung target, mapping, commands and feedback as the Remote
/// page, so TV readings never fight a finger and a value shown from a reading is never sent back.
private struct PlayerVolumeBar: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var value: Double = 0.5
    @State private var externalEcho: Double?

    var body: some View {
        GlassVolumeSlider(value: $value, scale: remote.volumeScale, thickness: ThinVolumeMetrics.minimumTouchTarget,
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
