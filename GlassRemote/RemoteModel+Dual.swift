import Foundation

// Dual-device routing and the Android Recents control.
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
        case .denied: return "The TV didn't allow Glass Remote · tap Reconnect"
        default: return "Samsung TV isn't connected yet"
        }
    }

    /// KEYCODE_APP_SWITCH (187). Reports what could actually be observed (see RecentsProbe); only
    /// `.unchanged` is treated as "the launcher ignored it". Samples twice, 0.9 s apart, in case the
    /// overlay is slow. Task-level state (`dumpsys activity recents`) is not used: it is heavy and its
    /// format varies by Android version, so detection stays best-effort.
    func openRecents() async -> RecentsOutcome {
        guard connected, appActive, let connection = adb else { status = "Not connected"; return .unknown }
        let probe = ["sh", "-c", RecentsProbe.command]
        func snapshot() async -> RecentsSnapshot {
            RecentsProbe.parse((try? await runShell(connection, probe)) ?? "")
        }
        let before = await snapshot()
        androidKey(187)
        var outcome = RecentsOutcome.unknown
        for _ in 0..<2 {
            try? await Task.sleep(nanoseconds: 900_000_000)
            outcome = RecentsProbe.outcome(before: before, after: await snapshot())
            if outcome != .unchanged { break }
        }
        GRLog.note("recents", "187 outcome: \(outcome)")
        switch outcome {
        case .opened: break
        case .unchanged: status = "This box has no Recents screen · showing your apps instead"
        case .changedUnrecognised: status = "Sent Recent Apps · the screen changed but I can't confirm it's Recents"
        case .unknown: status = "Sent Recent Apps · couldn't check the result"
        }
        return outcome
    }
}
