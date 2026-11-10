import SwiftUI

/// What the Samsung remote shows and where everything else went (pure, unit tested).
enum SamsungRemoteLayout {
    struct Item: Equatable { let key: SamsungKey; let title: String; let symbol: String }

    /// Always visible, in two rows. The trackpad (permanent) replaces the old D-pad, so no arrow
    /// or select key appears here.
    static let primaryRows: [[Item]] = [
        [Item(key: .back, title: "Back", symbol: "arrow.uturn.backward"),
         Item(key: .home, title: "Home", symbol: "house"),
         Item(key: .mute, title: "Mute", symbol: "speaker.slash.fill")],
        [Item(key: .rewind, title: "Rewind", symbol: "backward.fill"),
         Item(key: .play, title: "Play/Pause", symbol: "playpause.fill"),   // one combined button (see keyRow)
         Item(key: .fastForward, title: "Fast forward", symbol: "forward.fill")]
    ]

    /// Less frequent keys, reachable from the global menu (Samsung TV ▸ TV keys).
    static let menuKeys: [Item] = [
        Item(key: .source, title: "Input menu", symbol: "rectangle.on.rectangle"),
        Item(key: .guide, title: "Guide", symbol: "list.bullet.rectangle"),
        Item(key: .info, title: "Info", symbol: "info.circle"),
        Item(key: .menu, title: "TV menu", symbol: "line.3.horizontal"),
        Item(key: .channelUp, title: "Channel up", symbol: "chevron.up"),
        Item(key: .channelDown, title: "Channel down", symbol: "chevron.down"),
        Item(key: .pause, title: "Pause", symbol: "pause.fill"),
        Item(key: .stop, title: "Stop", symbol: "stop.fill")
    ]

    /// TV power is in the header's power menu.
    static let powerMenuKeys: [SamsungKey] = [.power]

    static let removedFromSurface: Set<SamsungKey> = [.up, .down, .left, .right, .enter]
}

/// Samsung TV layout for the Remote page: a large, permanent trackpad and a short key set. Uses
/// only allowlisted `SamsungKey`s over the existing Samsung WebSocket (no second connection).
/// Every control is disabled while the TV link is down, and the banner says exactly why.
struct SamsungRemotePanel: View {
    @EnvironmentObject private var remote: RemoteModel

    private var ready: Bool { remote.samsungRemoteReady }

    var body: some View {
        VStack(spacing: 10) {
            banner
            SamsungTrackpad()
                .disabled(!ready)
                .frame(minHeight: 220, maxHeight: .infinity)
                .layoutPriority(1)
            ForEach(Array(SamsungRemoteLayout.primaryRows.enumerated()), id: \.offset) { _, row in
                keyRow(row)
            }
        }
        .opacity(ready ? 1 : 0.92)
    }

    // MARK: Connection banner

    @ViewBuilder
    private var banner: some View {
        let state = remote.samsungState
        if !remote.tvVolumeEnabled {
            bannerRow("tv.slash", "Samsung TV is off", "Set it up") { remote.showConnection = true }
        } else if state == .pairing {
            bannerRow("hand.tap", "Approve Glass Remote on the TV", nil, nil)
        } else if state == .denied {
            bannerRow("xmark.shield", "The TV didn't allow Glass Remote", "Reconnect") { remote.reconnectTV() }
        } else if state == .unreachable || state == .off {
            bannerRow("wifi.exclamationmark", state.label, "Reconnect") { remote.reconnectTV() }
        } else if state == .connecting {
            bannerRow(nil, "Connecting to the TV…", nil, nil)   // nil symbol: live spinner
        }
    }

    /// `symbol == nil` shows a small spinner instead, for a state that is still in progress.
    private func bannerRow(_ symbol: String?, _ text: String, _ action: String?, _ run: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).scaledFont(15, .medium)
            } else {
                ProgressView().controlSize(.small).tint(Color.ink)
            }
            Text(text).scaledFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let action, let run {
                Button(action: run) {
                    Text(action).scaledFont(13, .semibold).padding(.horizontal, 12).frame(height: 28)
                        .glassSurface(Capsule(), interactive: true, elevated: true)
                }.buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14).frame(height: 40)
        .glassSurface(Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Key rows (one glass group per row, same buttons as the Android remote)

    private func keyRow(_ items: [SamsungRemoteLayout.Item]) -> some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(items, id: \.key) { item in
                    if item.key == .play {
                        playPauseButton
                    } else if item.key == .home {
                        RemoteKeyButton(label: item.title, enabled: ready, action: { remote.samsungKey(item.key) }) { HomeGlyph() }
                    } else {
                        RemoteKeyButton(symbol: item.symbol, label: item.title, enabled: ready) { remote.samsungKey(item.key) }
                    }
                }
            }
        }
    }

    /// Combined Play/Pause. Shows the generic play-pause glyph until a key has been sent; after that
    /// the icon is the NEXT action (pause after Play was sent). It is a local guess and is labelled so.
    private var playPauseButton: some View {
        let guess = remote.samsungPlayPause
        let symbol = guess == .sentPlay ? "pause.fill" : (guess == .sentPause ? "play.fill" : "playpause.fill")
        let label = guess == .sentPlay ? "Pause (last sent: Play)" : (guess == .sentPause ? "Play (last sent: Pause)" : "Play or pause")
        return RemoteKeyButton(label: label, enabled: ready, action: {
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.2)) { remote.samsungTogglePlayPause() }
        }) {
            Image(systemName: symbol).scaledFont(19, .medium)
                .modifier(SymbolReplace())
                .id(symbol)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

private struct SymbolReplace: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) { content.contentTransition(.symbolEffect(.replace)) }
        else { content }
    }
}
