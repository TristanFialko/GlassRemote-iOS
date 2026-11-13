import Foundation

// Remote v2 routing for the Remote page's D-pad, OK, Back and Home.
// With Remote v2 disabled this returns false at once and `key(_:)` is unchanged.
// Volume and mute never reach here (key(_:) sends them to the volume route first) and have no
// Remote v2 code (RemoteV2KeyMap.forbidden). Text, trackpad, app discovery, diagnostics and helpers
// are separate paths that never consult this.

extension RemoteModel {
    /// True when the Remote v2 decision handled the key (sent on v2, or dropped because a held key's
    /// transport went down). False: continue on the existing ADB / keyboard-helper path.
    func sendViaRemoteV2IfRouted(_ key: String) -> Bool {
        let v2 = RemoteV2Controller.shared
        guard v2.enabled, let operation = RemoteV2KeyMap.operation(for: key),
              let code = RemoteV2KeyMap.code(for: key) else { return false }
        let adbReady: Bool
        switch operation {
        case .dpad, .select:
            // Navigation never falls back to the ADB shell; it needs the keyboard helper.
            adbReady = connected && keyboard.isReady
        default:
            adbReady = connected && (keyboard.isReady || commandShellReady)
        }
        switch v2.route(key: key, operation: operation, adbReady: adbReady) {
        case .remoteV2:
            v2.send(.key(code: code, direction: .short))
            return true
        case .droppedHold:
            GRLog.note("remotev2", "dropped \(key) repeat: its transport went down mid-hold")
            return true
        case .adb, .unavailable:
            return false
        }
    }

    /// Discrete media keys (Player, now-playing card, Remote media row) through the same policy.
    /// True: sent once over Remote v2. False: continue on the existing ADB `input keyevent` path.
    /// Codes outside RemoteV2KeyMap.discreteMediaCodes (volume, mute, SLEEP/WAKEUP, text keys) always
    /// return false, as does everything while Remote v2 is disabled.
    func sendAndroidKeyViaRemoteV2IfRouted(_ code: Int) -> Bool {
        let v2 = RemoteV2Controller.shared
        guard v2.enabled, let operation = RemoteV2KeyMap.discreteOperation(forAndroidCode: code),
              let code32 = Int32(exactly: code) else { return false }
        guard v2.routeDiscrete(operation, adbReady: connected) == .remoteV2 else { return false }
        v2.send(.key(code: code32, direction: .short))
        GRLog.note("remotev2", "keyevent \(code) sent over Remote v2")
        return true
    }
}
