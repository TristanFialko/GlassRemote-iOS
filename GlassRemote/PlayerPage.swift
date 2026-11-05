import SwiftUI

/// Page 2: cinematic player. Independent of the Remote page: it only reads `remote.media`
/// (the shared, read-only `dumpsys media_session` poll) and sends transport commands through
/// `RemoteModel.sendMedia`, which uses explicit Play / Pause and confirms against the session.
///
/// Real data: title, optional subtitle, playback state, position (extrapolated between polls) and
/// the actions the session advertises. NOT available from the box: artwork, duration, seeking
/// to a position (see V0_4_NOTES.md). So there is no scrubber and no remaining time.
struct PlayerPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var artwork = PlayerArtworkStore.shared
    @State private var ambient: Color?

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })
        let sessionTitle = media.headline.isEmpty ? media.title : media.headline
        let poster = artwork.posterURL(forSessionTitle: sessionTitle)

        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                artworkCard(app: app, media: media, poster: poster)
                    .padding(.top, 6)
                Group {
                    titleBlock(app: app, media: media)
                    playbackBlock(media: media)
                }
                .id(sessionTitle + media.package)        // new title = soft cross-fade
                .transition(.opacity)
                transport(media: media)
                if !media.isActive { emptyHint }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, DockMetrics.clearance + 12)
            .animation(.easeInOut(duration: 0.35), value: sessionTitle)
        }
        .background { ambientLight }
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task(id: poster) {
            guard let poster, let image = await ArtworkCache.shared.image(for: poster) else {
                withAnimation(.easeOut(duration: 0.4)) { ambient = nil }
                return
            }
            let colour = ArtworkCache.averageColor(of: image)
            withAnimation(.easeInOut(duration: 0.6)) { ambient = colour }
        }
    }

    /// Soft light pooled behind the artwork, taken from the artwork itself.
    private var ambientLight: some View {
        RadialGradient(colors: [(ambient ?? Color.white).opacity(ambient == nil ? 0.05 : 0.42), .clear],
                       center: .init(x: 0.5, y: 0.22), startRadius: 10, endRadius: 380)
            .blur(radius: 30)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: Artwork

    private func artworkCard(app: TVApp?, media: MediaState, poster: URL?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return ZStack {
            shape.fill(Color.black.opacity(0.55))
            if let poster {
                CachedArtwork(url: poster, contentMode: .fill) { fallbackIcon(app: app, media: media) }
            } else {
                fallbackIcon(app: app, media: media)
            }
        }
        .aspectRatio(poster == nil ? 1 : 2.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: poster == nil ? 240 : 270)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.8))
        .shadow(color: (ambient ?? .black).opacity(0.55), radius: 28, y: 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: poster)
        .accessibilityLabel(poster == nil ? "App artwork" : "Poster")
    }

    @ViewBuilder
    private func fallbackIcon(app: TVApp?, media: MediaState) -> some View {
        if let app {
            Image(app.asset == "stremio" ? "stremio_nowplaying" : "\(app.asset)_dark")
                .resizable().scaledToFit().padding(app.asset == "stremio" ? 64 : 36)
        } else {
            Image(systemName: media.isActive ? "play.rectangle" : "tv")
                .scaledFont(56, .light).foregroundStyle(.white.opacity(0.4))
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
        return VStack(spacing: 6) {
            Text(title).scaledFont(26, .bold).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
            if media.isActive {
                // Episode information only when the session really reports a subtitle.
                if !media.subtitle.isEmpty {
                    Text(media.subtitle).scaledFont(16, .medium).foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                Text(name).scaledFont(13, .medium).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: State, elapsed time

    private func playbackBlock(media: MediaState) -> some View {
        VStack(spacing: 10) {
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
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                            .accessibilityLabel("Elapsed \(MediaState.format(pos))")
                    }
                }
                if media.durationMs == nil {
                    Text("Stremio doesn't report the total length, so there is no progress bar or seeking.")
                        .scaledFont(11).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center)
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
        return GlassGroup(spacing: 12) {
            ZStack {
                Color.clear.frame(height: 92).glassBar(Capsule(), interactive: false)
                HStack(spacing: 6) {
                    control("backward.end.fill", "Previous", enabled: active && media.canPrevious && !busy) { remote.sendMedia(.previous) }
                    control("backward.fill", "Rewind", enabled: active && media.canRewind && !busy) { remote.sendMedia(.rewind) }
                    playButton(media: media, enabled: active && media.canPlayPause && !busy, busy: busy)
                    control("forward.fill", "Fast forward", enabled: active && media.canFastForward && !busy) { remote.sendMedia(.fastForward) }
                    control("forward.end.fill", "Next", enabled: active && media.canNext && !busy) { remote.sendMedia(.next) }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 92)
        }
    }

    private func playButton(media: MediaState, enabled: Bool, busy: Bool) -> some View {
        Button { remote.sendMedia(media.isPlaying ? .pause : .play) } label: {
            ZStack {
                if busy { ProgressView().tint(.white) }
                else { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28, weight: .semibold)) }
            }
            .frame(width: 70, height: 70)
            .glassLens(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled || busy ? 1 : 0.4)
        .accessibilityLabel(media.isPlaying ? "Pause" : "Play")
    }

    private func control(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled).opacity(enabled ? 1 : 0.32)
        .accessibilityLabel(label)
    }

    private var emptyHint: some View {
        Text(remote.connected ? "Start something in Stremio and it appears here." : "Connect to your TV box to see what's playing.")
            .scaledFont(14).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
    }
}
