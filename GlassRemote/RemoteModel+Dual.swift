import Foundation

// Dual-device routing.
// Nothing here touches the helpers, the HID devices or connection recovery.

extension RemoteModel {
    /// D-pad / Back / Home from the Remote page. Goes to exactly one device (see RemoteRouting).
    /// With the Android target and a live box this is the unchanged `key(_:)` path.
    func routedKey(_ name: String) {
        switch RemoteRouting.device(for: .navigation, target: target,
                                    androidConnected: connected, samsungRemoteReady: samsungRemoteReady) {
        case .android:
            key(name)
        case .samsung:
            guard let samsung = SamsungKey.forAppKey(name) else { status = "No Samsung key for \(name)"; return }
            samsungKey(samsung)
        case nil:
            status = target == .samsung ? samsungUnavailableMessage : "Button failed · not connected"
        }
    }

    /// Sends one allowlisted key to the Samsung TV; reports honestly when the link is down.
    @discardableResult
    func samsungKey(_ key: SamsungKey) -> Bool {
        if tv.sendKey(key) { return true }
        status = samsungUnavailableMessage
        return false
    }

    /// Hold experiment for the Connection sheet: Right arrow, Press then Release after 0.8 s.
    /// Watch the TV: one step = Press/Release acts like a click; repeated steps = a real hold.
    func samsungHoldTest() {
        guard samsungRemoteReady else { status = samsungUnavailableMessage; return }
        GRLog.note("samsung", "hold test: KEY_RIGHT press/release 0.8 s (user-initiated)")
        Task { await tv.holdTest(.right) }
    }

    var samsungUnavailableMessage: String {
        guard tvVolumeEnabled else { return "Samsung TV is off · enable it in Connection settings" }
        switch samsungState {
        case .pairing: return "Approve Glass Remote on the TV first"
        case .denied: return (samsungDenial?.bannerText ?? "The TV didn't allow Glass Remote") + " · tap Reconnect"
        default: return "Samsung TV isn't connected yet"
        }
    }

    /// One button for both Samsung keys. Unknown -> sends Play (idempotent); afterwards alternates.
    /// The guess only advances when the key was actually handed to the socket (not proof the TV acted).
    func samsungTogglePlayPause() {
        let next: SamsungKey = samsungPlayPause == .sentPlay ? .pause : .play
        if samsungKey(next) { samsungPlayPause = next == .play ? .sentPlay : .sentPause }
    }
}

/// Last Play/Pause key sent to the Samsung TV (a guess, not TV state).
enum SamsungPlayPauseGuess: Equatable { case unknown, sentPlay, sentPause }
