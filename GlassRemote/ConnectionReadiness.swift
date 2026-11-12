import Foundation

/// What the header says about the Android TV box (pure, unit tested). Audit UX-001: an open ADB
/// socket is not the same as a working remote. The D-pad needs the keyboard helper, the trackpad the
/// mouse helper, and Back / Home / volume the command shell; any of them can fail on its own.
struct ConnectionReadiness: Equatable {
    var adbConnected: Bool
    var commandShellReady: Bool
    var keyboardReady: Bool
    var mouseReady: Bool
    var busy: Bool
    var requiresUserReconnect: Bool

    enum State: Equatable {
        case connected
        case connecting
        /// The box answers, but at least one input path is not ready (see `missing`).
        case degraded
        case reconnectNeeded
        case offline
    }

    var state: State {
        if requiresUserReconnect { return .reconnectNeeded }
        if adbConnected {
            if missing.isEmpty { return .connected }
            return busy ? .connecting : .degraded
        }
        return busy ? .connecting : .offline
    }

    /// The input paths that are down, in the order the user notices them.
    var missing: [String] {
        guard adbConnected else { return [] }
        var list: [String] = []
        if !keyboardReady { list.append("D-pad") }
        if !mouseReady { list.append("trackpad") }
        if !commandShellReady { list.append("Back, Home and volume") }
        return list
    }

    /// One actionable line for the menu and VoiceOver.
    var guidance: String? {
        switch state {
        case .degraded:
            return "Not working yet: \(missing.joined(separator: ", ")). Reconnect the TV box to restart them."
        case .reconnectNeeded:
            return "A TV helper stopped. Reconnect the TV box to recreate it."
        case .offline:
            return "Not connected. Check the TV box is on, on the same Wi-Fi, with network debugging allowed."
        case .connected, .connecting:
            return nil
        }
    }
}

/// ADB refused us (audit UX-015): the TV shows an "Allow USB debugging?" prompt the user must accept.
enum ADBAuthorisationGuidance {
    static let message = "The TV box didn't accept the connection. On the TV, choose Allow on the “Allow USB debugging?” prompt (tick “Always allow from this computer”), then tap Connect."
}
