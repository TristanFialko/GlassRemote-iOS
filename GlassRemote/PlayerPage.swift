import SwiftUI

/// Page 2: cinematic player. Independent of the Remote page: it only reads `remote.media`
/// (the shared, read-only `dumpsys media_session` poll) and sends transport commands through
/// `RemoteModel.sendMedia`, which uses explicit Play / Pause and confirms against the session.
///
/// Real data: title, optional subtitle, playback state, position (extrapolated between polls) and
/// the actions the session advertises. Artwork is looked up from Cinemeta by title. NOT available from the box: duration and
/// seeking to a position. So there is no scrubber and no remaining time.
struct PlayerPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var artwork = PlayerArtworkStore.shared
    @Environment(\.glassTheme) private var theme

    @Environment(\.dockClearance) private var dockClearance

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })
        let sessionTitle = media.headline.isEmpty ? media.title : media.headline
        let poster = media.isActive ? artwork.posterURL(forSessionTitle: sessionTitle) : nil

        GeometryReader { proxy in
            // The poster takes roughly 38 % of the height on tall phones (31 % on small ones), between
            // 160 and 320 pt: bigger than Phase 4 (0.33, max 280), well short of the oversized Phase 3.
            // The transport bar is pinned just above the dock so nothing can sit under it.
            let posterHeight = min(max(proxy.size.height * (proxy.size.height < 700 ? 0.31 : 0.38), 160), 320)
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        artworkCard(app: app, media: media, poster: poster, height: posterHeight)
                            .padding(.top, 4)
                        Group {
                            titleBlock(app: app, media: media)
                            playbackBlock(media: media)
                        }
                        .id(sessionTitle + media.package)        // new title = soft cross-fade
                        .transition(.opacity)
                        if !media.isActive { emptyHint }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.35), value: sessionTitle)
                }
                transport(media: media)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, dockClearance + 6)
            }
        }
        .background { ambientLight }
        .foregroundStyle(Color.ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Stremio's session has no artwork: look the title up so playback started in Stremio itself
        // (not just from Discover) still gets its poster.
        .task(id: sessionTitle + "|" + media.subtitle) {
            guard media.isActive, media.package == RemoteModel.stremioPackage, !sessionTitle.isEmpty else { return }
            await artwork.resolve(sessionTitle: sessionTitle, subtitle: media.subtitle)
        }
        // Adaptive theme: this page only reports its artwork; the shared palette decides the colours.
        .onChange(of: poster) { ThemeStore.shared.submitArtwork($0, for: .player) }
        .onAppear { ThemeStore.shared.submitArtwork(poster, for: .player) }
    }

    /// Soft light pooled behind the artwork, from the shared theme (the accent when Adaptive).
    private var ambientLight: some View {
        RadialGradient(colors: [theme.accent.opacity(theme.id == .adaptive ? 0.34 : 0.07), .clear],
                       center: .init(x: 0.5, y: 0.2), startRadius: 10, endRadius: 360)
            .blur(radius: 30)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: Artwork

    private func artworkCard(app: TVApp?, media: MediaState, poster: URL?, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let portrait = poster != nil
        return ZStack {
            shape.fill(Color.black.opacity(0.55))
            if let poster {
                CachedArtwork(url: poster, contentMode: .fill) { fallbackIcon(app: app, media: media) }
            } else {
                fallbackIcon(app: app, media: media)
            }
        }
        // Portrait 2:3 for posters; a smaller square for app artwork (no stretching either way).
        .frame(width: portrait ? height * 2 / 3 : height * 0.72, height: portrait ? height : height * 0.72)
        .clipShape(shape)
        .overlay(shape.stroke(Color.ink.opacity(0.22), lineWidth: 0.8))
        .shadow(color: (portrait ? theme.accent : Color.black).opacity(portrait ? 0.35 : 0.5), radius: 22, y: 12)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: poster)
        .accessibilityLabel(portrait ? "Poster" : "App artwork")
    }

    @ViewBuilder
    private func fallbackIcon(app: TVApp?, media: MediaState) -> some View {
        if let app {
            Image(app.asset == "stremio" ? "stremio_nowplaying" : "\(app.asset)_dark")
                .resizable().scaledToFit().padding(app.asset == "stremio" ? 64 : 36)
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

    private func playbackBlock(media: MediaState) -> some View {
        VStack(spacing: 8) {
            if media.isActive {
                stateBadge(media: media)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let pos = media.position(at: context.date)
                    if let dur = media.durationMs, dur > 0 {
                        let total = Double(dur) / 1000
                        ProgressView(value: min(pos, total), total: total).tint(theme.accent)
                        HStack {
                            Text(MediaState.format(pos))
                            Spacer()
                            Text("-" + MediaState.format(max(0, total - pos)))
                        }
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Color.inkAlpha(0.65))
                    } else {
                        Text(MediaState.format(pos))
                            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                            .accessibilityLabel("Elapsed \(MediaState.format(pos))")
                    }
                }
                if media.durationMs == nil {
                    Text("No total length is reported, so there is no progress bar or exact seeking. Rewind and fast-forward move by the app's own step.")
                        .scaledFont(11).foregroundStyle(Color.inkAlpha(0.5)).multilineTextAlignment(.center)
                }
                if let line = seekLine(media: media) {
                    Text(line).scaledFont(12, .medium).foregroundStyle(Color.inkAlpha(0.7))
                        .multilineTextAlignment(.center).transition(.opacity)
                }
            }
        }
    }

    private func stateBadge(media: MediaState) -> some View {
        let buffering = media.state == 6
        let label = buffering ? "Buffering" : (media.isPlaying ? "Playing" : "Paused")
        let colour: Color = buffering ? .yellow : (media.isPlaying ? .green : .orange)
        return HStack(spacing: 7) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(label).scaledFont(12, .semibold)
        }
        .padding(.horizontal, 14).frame(height: 28)
        .glassSurface(Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Transport (one glass bar, one prominent lens)

    private func transport(media: MediaState) -> some View {
        let active = media.isActive
        let busy = remote.mediaCommandPending
        // Relabelled "10 s" only once BOTH keys have been measured, repeatedly, at about ten seconds.
        let tenSecond = remote.seekLearner.isTenSecond(package: media.package)
        return ZStack {
            // Glass only (bar + centre bubble); the buttons sit above it so they are never refracted.
            GlassGroup(spacing: 12) {
                ZStack {
                    Color.clear.frame(height: 80).glassBar(Capsule(), interactive: false)
                    Color.clear.frame(width: 62, height: 62).glassLens(Circle())
                }
            }
            HStack(spacing: 6) {
                control("backward.end.fill", "Previous", enabled: active && media.canPrevious && !busy) { remote.sendMedia(.previous) }
                control(tenSecond ? "gobackward.10" : "backward.fill", tenSecond ? "Back 10 seconds" : "Rewind", enabled: active && media.canRewind && !busy) { remote.sendMedia(.rewind) }
                playButton(media: media, enabled: active && media.canPlayPause && !busy, busy: busy)
                control(tenSecond ? "goforward.10" : "forward.fill", tenSecond ? "Forward 10 seconds" : "Fast forward", enabled: active && media.canFastForward && !busy) { remote.sendMedia(.fastForward) }
                control("forward.end.fill", "Next", enabled: active && media.canNext && !busy) { remote.sendMedia(.next) }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 80)
    }

    private func playButton(media: MediaState, enabled: Bool, busy: Bool) -> some View {
        Button { remote.sendMedia(media.isPlaying ? .pause : .play) } label: {
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
    private func seekLine(media: MediaState) -> String? {
        if let report = remote.lastSeek, Date().timeIntervalSince(report.at) < 8 {
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

    private var emptyHint: some View {
        Text(remote.connected ? "Start something in Stremio and it appears here." : "Connect to your TV box to see what's playing.")
            .scaledFont(14).foregroundStyle(Color.inkAlpha(0.55)).multilineTextAlignment(.center)
    }
}
