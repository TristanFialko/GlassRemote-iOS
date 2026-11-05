import Foundation

// Dual-device routing and the Android Recents control.
// Nothing here touches the helpers, the HID devices or connection recovery.

extension RemoteModel {
    /// D-pad / Back / Home from the Remote page. Goes to exactly one device (see RemoteRouting).
    /// With the Android target and a live box this is the unchanged `key(_:)` path.
    func routedKey(_ name: String) {
        switch RemoteRouting.device(for: .navigation, target: target,
                                    androidConnected: connected, samsungReady: tvVolumeReady) {
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

    var samsungUnavailableMessage: String {
        guard tvVolumeEnabled else { return "Samsung TV is off · enable it in Connection settings" }
        switch samsungState {
        case .pairing: return "Approve Glass Remote on the TV first"
        case .denied: return "The TV didn't allow Glass Remote · tap Reconnect"
        default: return "Samsung TV isn't connected yet"
        }
    }

    /// KEYCODE_APP_SWITCH (187). Returns false when the launcher visibly did nothing, so the caller
    /// can offer something more useful (the Apps page) instead of a dead button. The check compares
    /// the focused window before and after; if the probe itself fails, nothing is claimed either way.
    func openRecents() async -> Bool {
        guard connected, appActive, let connection = adb else { status = "Not connected"; return true }
        let probe = ["sh", "-c", "dumpsys window | grep -m1 mCurrentFocus"]
        let before = ((try? await runShell(connection, probe)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        androidKey(187)
        try? await Task.sleep(nanoseconds: 900_000_000)
        let after = ((try? await runShell(connection, probe)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !before.isEmpty, !after.isEmpty else {
            GRLog.note("recents", "sent 187; focus probe unavailable, result unknown")
            return true
        }
        if before != after {
            GRLog.note("recents", "187 changed window focus")
            return true
        }
        GRLog.note("recents", "187 did not change window focus")
        status = "This box has no Recents screen · opened Apps instead"
        return false
    }
}
