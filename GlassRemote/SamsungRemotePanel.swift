import SwiftUI

/// Samsung TV layout for the Remote page. Uses only allowlisted `SamsungKey`s over the existing
/// Samsung WebSocket (no second connection). Arrow keys repeat with `Click`; every control is
/// disabled while the TV link is down, and the banner says exactly why.
struct SamsungRemotePanel: View {
    @EnvironmentObject private var remote: RemoteModel

    private var ready: Bool { remote.tvVolumeReady }

    var body: some View {
        VStack(spacing: 10) {
            banner
            dpad.frame(minHeight: 170, maxHeight: .infinity)
            keyRow([("arrow.uturn.backward", "Back", .back), ("house", "Home", .home),
                    ("line.3.horizontal", "Menu", .menu), ("info.circle", "Info", .info), ("list.bullet.rectangle", "Guide", .guide)])
            keyRow([("backward.fill", "Rewind", .rewind), ("play.fill", "Play", .play),
                    ("pause.fill", "Pause", .pause), ("forward.fill", "Fast forward", .fastForward), ("stop.fill", "Stop", .stop)])
            keyRow([("chevron.up", "Channel up", .channelUp), ("chevron.down", "Channel down", .channelDown),
                    ("speaker.slash.fill", "Mute", .mute), ("rectangle.on.rectangle", "Source", .source), ("power", "TV power", .power)])
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
            bannerRow("arrow.triangle.2.circlepath", "Connecting to the TV…", nil, nil)
        }
    }

    private func bannerRow(_ symbol: String, _ text: String, _ action: String?, _ run: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).scaledFont(15, .medium)
            Text(text).scaledFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let action, let run {
                Button(action: run) {
                    Text(action).scaledFont(13, .semibold).padding(.horizontal, 12).frame(height: 28)
                        .glassSurface(Capsule(), interactive: true, elevated: true)
                }.buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).frame(height: 40)
        .glassSurface(Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: D-pad

    private var dpad: some View {
        GeometryReader { geo in
            let size = max(150, min(250, min(geo.size.width, geo.size.height) - 12))
            ZStack {
                Color.clear.glassSurface(Circle(), elevated: true)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1.2))
                VStack(spacing: 0) {
                    HStack(spacing: 0) { Color.clear; arrow("chevron.up", .up, "Up"); Color.clear }
                    HStack(spacing: 0) {
                        arrow("chevron.left", .left, "Left")
                        arrow("circle.fill", .enter, "Select", ok: true)
                        arrow("chevron.right", .right, "Right")
                    }
                    HStack(spacing: 0) { Color.clear; arrow("chevron.down", .down, "Down"); Color.clear }
                }
                .padding(10)
                .frame(width: size, height: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(!ready)
    }

    private func arrow(_ icon: String, _ key: SamsungKey, _ label: String, ok: Bool = false) -> some View {
        // Tap = one Click; hold = repeated Clicks (arrows only, so OK never double-selects).
        RepeatKey(onFire: { remote.samsungKey(key) }) {
            Image(systemName: icon)
                .scaledFont(ok ? 12 : 22, .medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if ok { Color.clear.glassSurface(Circle(), interactive: true, elevated: true, accent: true).padding(6) }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { remote.samsungKey(key) }
    }

    // MARK: Key rows (one glass group per row)

    private func keyRow(_ items: [(String, String, SamsungKey)]) -> some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { remote.samsungKey(item.2) } label: {
                        Image(systemName: item.0)
                            .scaledFont(17, .medium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .glassSurface(Capsule(), interactive: ready)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!ready)
                    .accessibilityLabel(item.1)
                }
            }
        }
    }
}
