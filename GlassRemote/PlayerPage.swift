import SwiftUI

/// Page 2: cinematic player (Phase 9 §A). Independent of the Remote page: it only reads `remote.media`
/// (the shared, read-only `dumpsys media_session` poll) and sends transport commands through
/// `RemoteModel.sendMedia`, which uses explicit Play / Pause and confirms against the session.
///
/// Real data only: title, optional subtitle, playback state, position (extrapolated between polls) and
/// the actions the session advertises. Artwork comes from Cinemeta by title, or from Discover. The box
/// reports no duration and no way to seek to a position, so there is no scrubber: rewind and
/// fast-forward use the app's own relative step (SEEKING_REPORT.md). Layout, controls, session state
/// and the background treatment are decided in PlayerPolicy.swift. The full-screen artwork background
/// is drawn by `RootPagerView` (PlayerBackdrop.swift), so it runs unbroken behind the dock and the rail.
struct PlayerPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    @ObservedObject private var artwork = PlayerArtworkStore.shared
    @ObservedObject private var backdropStore = PlayerBackdropStore.shared
    @Environment(\.glassTheme) private var theme

    @Environment(\.dockClearance) private var dockClearance
    @Environment(\.railClearance) private var railClearance
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
        .background { fallbackLight }
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
                let frame = PlayerLayoutPolicy.portraitArtwork(kind: scene.kind, region: region.size)
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
        .padding(.horizontal, PlayerLayoutPolicy.portraitMargin)
        .padding(.top, 8)
        .padding(.bottom, dockClearance + 6)
    }

    /// Landscape: square artwork region on the leading side; title, time, transport and volume in a
    /// column beside it. The rail stays visible (the page already starts after it).
    private func landscapeLayout(size: CGSize, scene: PlayerScene) -> some View {
        let split = PlayerLayoutPolicy.landscape(page: size, bottomClearance: dockClearance)
        let frame = PlayerLayoutPolicy.landscapeArtwork(kind: scene.kind, side: split.artSide)
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

    private func controlsColumn(scene: PlayerScene) -> some View {
        VStack(spacing: PlayerLayoutPolicy.controlSpacing) {
            ZStack {
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
    }

    /// Theme-aware fallback while there is no artwork background: soft light from the shared theme (the
    /// accent when Adaptive), extended under the landscape rail so the canvas never splits at its edge.
    /// A radial gradient is already soft, so no blur filter.
    @ViewBuilder
    private var fallbackLight: some View {
        if backdropStore.backdrop == nil {
            RadialGradient(colors: [theme.accent.opacity(theme.id == .adaptive ? 0.34 : 0.07), .clear],
                           center: .init(x: 0.5, y: 0.2), startRadius: 10, endRadius: 420)
                .padding(.leading, layoutContext.isLandscape ? -railClearance : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: Artwork

    private func artworkCard(scene: PlayerScene, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: scene.kind == .appIcon ? 30 : 22, style: .continuous)
        let hasArt = scene.art != nil
        let label: String = {
            switch scene.kind {
            case .poster: return "Poster"
            case .landscape: return "Artwork"
            case .appIcon: return "App artwork"
            }
        }()
        return ZStack {
            shape.fill(Color.black.opacity(hasArt ? 0.55 : 0.32))
            if let art = scene.art {
                CachedArtwork(url: art, contentMode: .fill) { fallbackIcon(app: scene.app, media: scene.media, side: size.width) }
            } else {
                fallbackIcon(app: scene.app, media: scene.media, side: size.width)
            }
        }
        // Each kind gets a frame of its own proportions (PlayerLayoutPolicy), so nothing is stretched.
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay { shape.stroke(Color.ink.opacity(0.2), lineWidth: 0.8) }
        .shadow(color: Color.black.opacity(hasArt ? 0.45 : 0.3), radius: 24, y: 14)
        .animation(Motion.adaptive(Motion.poster), value: scene.art)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func fallbackIcon(app: TVApp?, media: MediaState, side: CGFloat) -> some View {
        if let app {
            Image(app.asset == "nuvio" ? "nuvio_nowplaying" : "\(app.asset)_dark")
                .resizable().scaledToFit()
                .padding(max(side, 0) * (app.asset == "nuvio" ? 0.26 : 0.16))
        } else {
            Image(systemName: media.isActive ? AppPage.playerSymbolOutline : "tv")
                .scaledFont(56, .light).foregroundStyle(Color.ink.opacity(0.4))
        }
    }

    // MARK: Title

    private func titleBlock(app: TVApp?, media: MediaState) -> some View {
        let name = app?.name ?? (media.package.split(separator: ".").last.map(String.init) ?? "")
        let title: String = {
            guard media.isActive else { return "Nothing playing" }
            if !media.headline.isEmpty { return media.headline }
            return media.title.isEmpty ? (name.isEmpty ? "Playing" : name) : media.title
        }()
        return VStack(spacing: 4) {
            Text(title).scaledFont(22, .bold).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            if media.isActive {
                // Episode information only when the session really reports a subtitle.
                if !media.subtitle.isEmpty {
                    Text(media.subtitle).scaledFont(15, .medium).foregroundStyle(Color.ink.opacity(0.8))
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                Text(name).scaledFont(13, .medium).foregroundStyle(Color.inkAlpha(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: State, elapsed time

    /// Session state and elapsed time. The timeline redraws once a second only while playing; otherwise
    /// it re-checks every few seconds, just enough to notice a stale session (PlayerTimeline).
    private func statusBlock(scene: PlayerScene) -> some View {
        let media = scene.media
        let controls = scene.controls
        let connected = remote.connected
        let connecting = remote.isBusyConnecting
        let interval = PlayerTimeline.refreshInterval(isPlaying: media.state == 3)
        return TimelineView(.periodic(from: .now, by: interval)) { context in
            statusContent(media: media, controls: controls,
                          phase: PlayerSessionPhase.resolve(media: media, connected: connected, connecting: connecting, now: context.date),
                          now: context.date)
        }
    }

    @ViewBuilder
    private func statusContent(media: MediaState, controls: PlayerControls, phase: PlayerSessionPhase, now: Date) -> some View {
        let position = PlayerTimeline.position(media: media, phase: phase, at: now)
        VStack(spacing: 8) {
            if phase.showsSession {
                if controls.progress, let duration = media.durationMs {
                    progressRows(phase: phase, position: position, total: Double(duration) / 1000)
                } else {
                    HStack(spacing: 12) {
                        stateBadge(phase)
                        Text(MediaState.format(position))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .accessibilityLabel("Elapsed \(MediaState.format(position))")
                    }
                }
                if controls.rewind || controls.fastForward, let line = seekLine(media: media, now: now) {
                    Text(line).scaledFont(12, .medium).foregroundStyle(Color.inkAlpha(0.7))
                        .multilineTextAlignment(.center).lineLimit(2)
                }
            } else {
                Text(phase.hint).scaledFont(14).foregroundStyle(Color.inkAlpha(0.55)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Only with a real total length (never today: the box does not report one).
    private func progressRows(phase: PlayerSessionPhase, position: TimeInterval, total: TimeInterval) -> some View {
        VStack(spacing: 6) {
            stateBadge(phase)
            ProgressView(value: min(position, total), total: total).tint(theme.accent)
            HStack {
                Text(MediaState.format(position))
                Spacer()
                Text("-" + MediaState.format(max(0, total - position)))
            }
            .font(.system(size: 12).monospacedDigit()).foregroundStyle(Color.inkAlpha(0.65))
        }
    }

    private func stateBadge(_ phase: PlayerSessionPhase) -> some View {
        let colour: Color = {
            switch phase {
            case .playing: return .green
            case .buffering: return .yellow
            case .paused: return .orange
            case .stale, .connecting, .disconnected, .idle: return .gray
            }
        }()
        return HStack(spacing: 7) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(phase.label).scaledFont(12, .semibold)
        }
        .padding(.horizontal, 14).frame(height: 28)
        .glassSurface(Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Transport (one glass bar, one prominent lens)

    /// Play / pause is primary. Rewind and fast-forward appear only when the session advertises them;
    /// track skip only for explicit audio-track sessions (never video, never Nuvio). No inert buttons.
    private func transport(media: MediaState, controls: PlayerControls) -> some View {
        let busy = remote.mediaCommandPending
        // Relabelled "10 s" only once BOTH keys have been measured, repeatedly, at about ten seconds.
        let tenSecond = remote.seekLearner.isTenSecond(package: media.package)
        return ZStack {
            // Glass only (bar + centre bubble); the buttons sit above it so they are never refracted.
            GlassGroup(spacing: 12) {
                ZStack {
                    if controls.hasSecondary {
                        Color.clear.frame(height: 80).glassBar(Capsule(), interactive: false)
                    }
                    Color.clear.frame(width: 62, height: 62).glassLens(Circle())
                }
            }
            HStack(spacing: 6) {
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
            .padding(.horizontal, 10)
        }
        .frame(height: 80)
    }

    private func playButton(media: MediaState, enabled: Bool, busy: Bool) -> some View {
        Button { remote.sendMedia(PlayerControls.playPauseCommand(for: media)) } label: {
            ZStack {
                if busy { ProgressView().tint(Color.ink) }
                else { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28, weight: .semibold)) }
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .controlDisabled(!(enabled || busy))
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    private func control(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 56)
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

/// The neutral glass volume slider (the same control as the Remote page): 0–100 % of the target's real
/// range with haptic ticks, routed exactly like the Remote page's slider, so TV readings never fight a
/// finger and a value shown from a reading is never sent back as a command.
private struct PlayerVolumeBar: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var value: Double = 0.5
    @State private var externalEcho: Double?

    var body: some View {
        GlassVolumeSlider(value: $value, scale: remote.volumeScale, thickness: RemoteLayoutPolicy.portraitVolumeThickness,
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
