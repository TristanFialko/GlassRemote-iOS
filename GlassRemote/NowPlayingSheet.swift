import SwiftUI

/// Expanded Now Playing player. Shows only what the active media session really reports.
/// There is no scrubber unless a genuine duration exists (`MediaState.durationMs`), because the
/// box's media session exposes none for Nuvio and Android has no ADB command to seek to a position.
struct NowPlayingSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let media = remote.media
        let app = remote.apps.first(where: { $0.package == media.package })

        ZStack {
            AmbientBackdrop()

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").scaledFont(15, .semibold)
                            .foregroundStyle(Color.ink).frame(width: 40, height: 40)
                            .glassSurface(Circle(), interactive: true)
                    }
                    .buttonStyle(PressStyle()).accessibilityLabel("Close player")
                }

                artwork(app: app, media: media)

                VStack(spacing: 6) {
                    Text(media.isActive ? (media.title.isEmpty ? (app?.name ?? "Playing") : media.title) : "Nothing playing")
                        .scaledFont(22, .bold).multilineTextAlignment(.center).lineLimit(3)
                    Text(app?.name ?? media.package).scaledFont(14).foregroundStyle(Color.ink.opacity(0.6))
                }

                timeline(media: media)

                // Phase 9 §A4: the same capability rules as the Player page. Track skip only for explicit
                // audio-track sessions (never video, never Nuvio episode navigation); otherwise relative seek.
                let controls = PlayerControls.resolve(media: media)
                HStack(spacing: 26) {
                    if controls.previousTrack {
                        control("backward.end.fill", "Previous track", 56) { remote.sendMedia(.previous) }
                    } else if controls.rewind {
                        control("backward.fill", "Rewind", 56) { remote.sendMedia(.rewind) }
                    }
                    control(media.isPlaying ? "pause.fill" : "play.fill", media.isPlaying ? "Pause" : "Play", 76, enabled: controls.playPause, elevated: true) {
                        remote.sendMedia(PlayerControls.playPauseCommand(for: media))
                    }
                    if controls.nextTrack {
                        control("forward.end.fill", "Next track", 56) { remote.sendMedia(.next) }
                    } else if controls.fastForward {
                        control("forward.fill", "Fast forward", 56) { remote.sendMedia(.fastForward) }
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 12)
        }
        .themedSheet()
        .onChange(of: media.isActive) { _, active in if !active { dismiss() } }
    }

    private func artwork(app: TVApp?, media: MediaState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.black.opacity(0.6))
            if let app {
                // No poster is exposed by the media session, so the app artwork is shown, centred, uncropped.
                Image(app.asset == "nuvio" ? "nuvio_nowplaying" : "\(app.asset)_dark")
                    .resizable().scaledToFit().padding(app.asset == "nuvio" ? 70 : 40)
            } else {
                Image(systemName: "play.rectangle").scaledFont(60).foregroundStyle(Color.ink.opacity(0.4))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .glassSurface(RoundedRectangle(cornerRadius: 34, style: .continuous), elevated: true)
    }

    @ViewBuilder
    private func timeline(media: MediaState) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let pos = media.position(at: context.date)
            VStack(spacing: 8) {
                if let durMs = media.durationMs, durMs > 0 {
                    // Only reachable with a genuine duration; seeking itself would still need a verified route.
                    ProgressView(value: min(pos, Double(durMs) / 1000), total: Double(durMs) / 1000).tint(Color.ink)
                    HStack {
                        Text(MediaState.format(pos))
                        Spacer()
                        Text("-" + MediaState.format(max(0, Double(durMs) / 1000 - pos)))
                    }
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Color.ink.opacity(0.65))
                } else {
                    Text(MediaState.format(pos)).font(.system(size: 28, weight: .semibold).monospacedDigit())
                    Text("Elapsed · this app doesn't report total length, so seeking isn't available")
                        .scaledFont(12).foregroundStyle(Color.ink.opacity(0.5)).multilineTextAlignment(.center)
                }
            }
        }
    }

    private func control(_ icon: String, _ label: String, _ size: CGFloat, enabled: Bool = true, elevated: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.34, weight: .semibold))
                .frame(width: size, height: size)
                .glassSurface(Circle(), interactive: enabled, elevated: elevated)
        }
        .buttonStyle(PressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.4).accessibilityLabel(label)
    }
}
