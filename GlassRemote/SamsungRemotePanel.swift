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

    // MARK: Landscape key rails (Phase 9 gap fix)

    /// Leading rail, first group: navigation.
    static let landscapeNavigation: [Item] = [
        Item(key: .back, title: "Back", symbol: "arrow.uturn.backward"),
        Item(key: .home, title: "Home", symbol: "house")
    ]

    /// Leading rail, second group: channel, up above down.
    static let landscapeChannels: [Item] = [
        Item(key: .channelUp, title: "Channel up", symbol: "chevron.up"),
        Item(key: .channelDown, title: "Channel down", symbol: "chevron.down")
    ]

    /// Trailing rail, first group: transport (one combined Play/Pause).
    static let landscapeMedia: [Item] = [
        Item(key: .rewind, title: "Rewind", symbol: "backward.fill"),
        Item(key: .play, title: "Play/Pause", symbol: "playpause.fill"),
        Item(key: .fastForward, title: "Fast forward", symbol: "forward.fill")
    ]

    /// Trailing rail, second group: mute, beside the volume deck's loud end.
    static let landscapeAudio: [Item] = [
        Item(key: .mute, title: "Mute", symbol: "speaker.slash.fill")
    ]

    /// Key groups per rail, top to bottom. Four keys each side, so the rails balance.
    static let landscapeLeadingRail: [[Item]] = [landscapeNavigation, landscapeChannels]
    static let landscapeTrailingRail: [[Item]] = [landscapeMedia, landscapeAudio]

    /// Every key on the landscape surface, in rail order. Each appears once.
    static var landscapeKeys: [SamsungKey] {
        (landscapeLeadingRail + landscapeTrailingRail).flatMap { $0 }.map(\.key)
    }

    /// The status banner is shown whenever the TV link is not fully up (or the TV is not set up).
    /// Phase 9 §1.1: Samsung keys are icon-only like the Android cluster. Only the channel keys keep
    /// a short caption, because a bare chevron does not say "channel". Titles stay the VoiceOver names.
    static func caption(for key: SamsungKey) -> String? {
        switch key {
        case .channelUp: return "Ch +"
        case .channelDown: return "Ch −"
        default: return nil
        }
    }

    static func showsBanner(enabled: Bool, state: SamsungLinkState) -> Bool {
        !enabled || state != .connected
    }
}

/// Samsung TV layout for the Remote page: a large, permanent trackpad and a short key set. Uses
/// only allowlisted `SamsungKey`s over the existing Samsung WebSocket (no second connection).
/// Every control is disabled while the TV link is down, and the banner says exactly why.
struct SamsungRemotePanel: View {
    @EnvironmentObject private var remote: RemoteModel
    var padMinHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 10) {
            if SamsungRemoteLayout.showsBanner(enabled: remote.tvVolumeEnabled, state: remote.samsungState) {
                SamsungLinkBanner()
            }
            SamsungTrackpad()
                .disabled(!remote.samsungRemoteReady)
                .frame(minHeight: padMinHeight, maxHeight: .infinity)
                .layoutPriority(1)
            ForEach(Array(SamsungRemoteLayout.primaryRows.enumerated()), id: \.offset) { _, row in
                SamsungKeyRow(items: row)
            }
        }
        .opacity(remote.samsungRemoteReady ? 1 : 0.92)
    }
}

/// Says exactly why the Samsung controls are unavailable, with the one action that fixes it.
struct SamsungLinkBanner: View {
    @EnvironmentObject private var remote: RemoteModel
    /// Landscape column: the action sits under the message instead of squeezing it.
    var stacked: Bool = false

    var body: some View {
        let state = remote.samsungState
        if !remote.tvVolumeEnabled {
            bannerRow("tv.slash", "Samsung TV is off", "Set it up") { remote.showConnection = true }
        } else if state == .pairing {
            bannerRow("hand.tap", "Approve Glass Remote on the TV", nil, nil)
        } else if state == .denied {
            let reason = remote.samsungDenial
            if reason?.suggestsReset == true {
                // Phase 9 recovery §3: a refused saved approval cannot be fixed by Reconnect alone; the
                // confirmed reset lives in the Connection sheet.
                bannerRow("xmark.shield", reason?.bannerText ?? "The TV didn't allow Glass Remote", "Fix") { remote.showConnection = true }
            } else {
                bannerRow("xmark.shield", reason?.bannerText ?? "The TV didn't allow Glass Remote", "Reconnect") { remote.reconnectTV() }
            }
        } else if state == .unreachable || state == .off {
            bannerRow("wifi.exclamationmark", state.label, "Reconnect") { remote.reconnectTV() }
        } else if state == .connecting {
            bannerRow(nil, "Connecting to the TV…", nil, nil)   // nil symbol: live spinner
        }
    }

    /// `symbol == nil` shows a small spinner instead, for a state that is still in progress.
    private func bannerRow(_ symbol: String?, _ text: String, _ action: String?, _ run: (() -> Void)?) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).scaledFont(15, .medium)
                } else {
                    ProgressView().controlSize(.small).tint(Color.ink)
                }
                Text(text).scaledFont(13, .semibold).lineLimit(stacked ? 3 : 2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            if let action, let run {
                Button(action: run) {
                    Text(action).scaledFont(13, .semibold).lineLimit(1).padding(.horizontal, 12).frame(height: 28)
                        .glassSurface(Capsule(), interactive: true, elevated: true)
                }.buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, stacked ? 10 : 6)
        .frame(minHeight: 40)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One glass group of Samsung keys, drawn with the Remote's cluster keys. Disabled while the TV
/// link is down.
struct SamsungKeyRow: View {
    @EnvironmentObject private var remote: RemoteModel
    let items: [SamsungRemoteLayout.Item]
    var height: CGFloat = 54
    var captions: Bool = false
    /// `.vertical` stacks the keys for a landscape rail.
    var axis: Axis = .horizontal

    private var ready: Bool { remote.samsungRemoteReady }

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        GlassGroup(spacing: 10) {
            layout {
                ForEach(items, id: \.key) { item in
                    if item.key == .play {
                        playPauseButton
                    } else if item.key == .home {
                        RemoteClusterKey(label: item.title, caption: caption(item), enabled: ready, height: height,
                                         action: { remote.samsungKey(item.key) }) { HomeGlyph() }
                    } else {
                        RemoteClusterKey(symbol: item.symbol, label: item.title, caption: caption(item),
                                         enabled: enabled(item.key), height: height) { remote.samsungKey(item.key) }
                    }
                }
            }
        }
    }

    /// Volume keys stay usable over the UPnP volume link while the remote socket is down (§5).
    private func enabled(_ key: SamsungKey) -> Bool {
        key.legacyVolumeName != nil ? remote.volumeButtonsAvailable : ready
    }

    private func caption(_ item: SamsungRemoteLayout.Item) -> String? {
        captions ? SamsungRemoteLayout.caption(for: item.key) : nil
    }

    /// Combined Play/Pause. Shows the generic play-pause glyph until a key has been sent; after that
    /// the icon is the NEXT action (pause after Play was sent). It is a local guess and is labelled so.
    private var playPauseButton: some View {
        let guess = remote.samsungPlayPause
        let symbol = guess == .sentPlay ? "pause.fill" : (guess == .sentPause ? "play.fill" : "playpause.fill")
        let label = guess == .sentPlay ? "Pause (last sent: Play)" : (guess == .sentPause ? "Play (last sent: Pause)" : "Play or pause")
        return RemoteClusterKey(label: label, caption: captions ? SamsungRemoteLayout.caption(for: .play) : nil, enabled: ready, height: height, action: {
            Haptics.light()
            withAnimation(Motion.adaptive(Motion.snappy)) { remote.samsungTogglePlayPause() }
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
        content.contentTransition(.symbolEffect(.replace))
    }
}
