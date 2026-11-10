import SwiftUI

/// Page 2: cinematic player. Independent of the Remote page: it only reads `remote.media`
/// (the shared, read-only `dumpsys media_session` poll) and sends standard media keys.
///
/// What is real here (see V0_3_PHASE1.md): title, optional subtitle, playback state, position
/// (extrapolated between polls) and which transport actions the session advertises.
/// What is NOT available from the box: artwork, duration, and any ADB route to SEEK_TO.
/// So there is no scrubber and no remaining time unless a real duration ever appears.
struct PlayerPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var artwork = PlayerArtworkStore.shared
    @State private var cinematic = false

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })
        let poster = artwork.posterURL(forSessionTitle: media.headline.isEmpty ? media.title : media.headline)

        GeometryReader { proxy in
            ZStack {
                if let poster, cinematic {
                    CachedArtwork(url: poster, contentMode: .fill) { Color.clear }
                        .blur(radius: 40).opacity(0.35).ignoresSafeArea().allowsHitTesting(false)
                        .transition(.opacity)
                }
                if proxy.size.width > proxy.size.height {
                    landscapePlayer(proxy, app: app, media: media, poster: poster)
                } else {
                    portraitPlayer(app: app, media: media, poster: poster)
                }
            }
        }
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background { AmbientBackdrop() }
    }

    @ViewBuilder
    private func portraitPlayer(app: TVApp?, media: MediaState, poster: URL?) -> some View {
        VStack(spacing: cinematic ? 14 : 20) {
            artworkCard(app: app, media: media, poster: poster).padding(.top, 8)
            titleBlock(app: app, media: media)
            playbackBlock(media: media)
            transport(media: media)
            if !media.isActive { emptyHint }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.top, 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: cinematic)
    }

    /// Landscape turns the player into a cinema control room: artwork/backdrop on the left, useful
    /// playback context and transport controls on the right.
    @ViewBuilder
    private func landscapePlayer(_ proxy: GeometryProxy, app: TVApp?, media: MediaState, poster: URL?) -> some View {
        HStack(spacing: 28) {
            artworkCard(app: app, media: media, poster: poster)
                .frame(maxWidth: proxy.size.width * 0.42, maxHeight: proxy.size.height - 28)
            VStack(alignment: .leading, spacing: 16) {
                titleBlock(app: app, media: media)
                playbackBlock(media: media)
                transport(media: media)
                if !media.isActive { emptyHint }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: cinematic)
    }

    // MARK: Artwork

    private func artworkCard(app: TVApp?, media: MediaState, poster: URL?) -> some View {
        let shape = RoundedRectangle(cornerRadius: cinematic ? 26 : 34, style: .continuous)
        return Button {
            guard media.isActive else { return }
            Haptics.soft()
            cinematic.toggle()
        } label: {
            ZStack {
                shape.fill(Color.black.opacity(0.6))
                if let poster {
                    CachedArtwork(url: poster, contentMode: cinematic ? .fill : .fit) { fallbackIcon(app: app, media: media) }
                } else {
                    fallbackIcon(app: app, media: media)
                }
            }
            .aspectRatio(cinematic ? 2.0 / 3.0 : 1, contentMode: .fit)
            .frame(maxWidth: cinematic ? 250 : 300)
            .clipShape(shape)
            .glassSurface(shape, elevated: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cinematic ? "Collapse artwork" : "Expand artwork")
        .accessibilityHint(media.isActive ? "Toggles the expanded cinematic view" : "")
    }

    @ViewBuilder
    private func fallbackIcon(app: TVApp?, media: MediaState) -> some View {
        if let app {
            Image(app.asset == "stremio" ? "stremio_nowplaying" : "\(app.asset)_dark")
                .resizable().scaledToFit().padding(app.asset == "stremio" ? 70 : 40)
        } else {
            Image(systemName: media.isActive ? "play.rectangle" : "tv")
                .scaledFont(56).foregroundStyle(.white.opacity(0.4))
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
        return VStack(spacing: 5) {
            Text(title).scaledFont(22, .bold).multilineTextAlignment(.center).lineLimit(3)
            if media.isActive {
                // Episode information only when the session really reports a subtitle.
                if !media.subtitle.isEmpty {
                    Text(media.subtitle).scaledFont(15, .medium).foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                Text(name).scaledFont(13).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Playback state, position, (no) progress

    private func playbackBlock(media: MediaState) -> some View {
        VStack(spacing: 8) {
            if media.isActive {
                stateBadge(media: media)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let pos = media.position(at: context.date)
                    if let dur = media.durationMs, dur > 0 {
                        let total = Double(dur) / 1000
                        ProgressView(value: min(pos, total), total: total).tint(.white)
                        HStack {
                            Text(MediaState.format(pos))
                            Spacer()
                            Text("-" + MediaState.format(max(0, total - pos)))
                        }
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                    } else {
                        Text(MediaState.format(pos))
                            .font(.system(size: 30, weight: .semibold).monospacedDigit())
                            .accessibilityLabel("Elapsed \(MediaState.format(pos))")
                    }
                }
                if media.durationMs == nil {
                    Text("Total length isn't reported by this app, so there's no progress bar or seeking.")
                        .scaledFont(12).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
                }
            }
        }
    }

    private func stateBadge(media: MediaState) -> some View {
        let label: String = media.state == 6 ? "Buffering" : (media.isPlaying ? "Playing" : "Paused")
        let symbol = media.state == 6 ? "ellipsis" : (media.isPlaying ? "waveform" : "pause.fill")
        return HStack(spacing: 6) {
            Image(systemName: symbol).scaledFont(11, .semibold)
            Text(label).scaledFont(12, .semibold)
        }
        .padding(.horizontal, 12).frame(height: 26)
        .glassSurface(Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Transport

    private func transport(media: MediaState) -> some View {
        let active = media.isActive
        return GlassGroup(spacing: 14) {
            HStack(spacing: 14) {
                control("backward.end.fill", "Previous", 48, enabled: active && media.canPrevious) { remote.mediaKey(88) }
                control("gobackward", "Rewind", 48, enabled: active && media.canRewind) { remote.mediaKey(89) }
                control(media.isPlaying ? "pause.fill" : "play.fill", media.isPlaying ? "Pause" : "Play", 72,
                        enabled: active && media.canPlayPause, elevated: true) { remote.mediaKey(85) }
                control("goforward", "Fast forward", 48, enabled: active && media.canFastForward) { remote.mediaKey(90) }
                control("forward.end.fill", "Next", 48, enabled: active && media.canNext) { remote.mediaKey(87) }
            }
        }
        .padding(.top, 4)
    }

    private func control(_ icon: String, _ label: String, _ size: CGFloat, enabled: Bool,
                         elevated: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.34, weight: .semibold))
                .frame(width: size, height: size)
                .glassSurface(Circle(), interactive: enabled, elevated: elevated)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled).opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var emptyHint: some View {
        Text(remote.connected ? "Start something in Stremio and it appears here." : "Connect to your TV box to see what's playing.")
            .scaledFont(14).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            .padding(.top, 6)
    }
}
