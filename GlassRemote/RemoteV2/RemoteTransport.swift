import Foundation

/// Which link carries a command to the Android TV box.
enum RemoteTransportKind: String, Equatable {
    case remoteV2 = "Remote v2"
    case adb = "ADB"
}

/// Operations the router decides per command. Each has a fixed set of transports that may carry it.
enum RemoteOperation: String, CaseIterable {
    case dpad, select, back, home, menu
    case media, power, appLaunch
    // ADB-only: no equivalent on the ordinary Android TV remote, or they depend on ADB helpers.
    case text, mouse, scroll, appDiscovery, diagnostics, helpers, soundbarVolume

    /// Transports that may carry this operation, most preferred first.
    var allowedTransports: [RemoteTransportKind] {
        switch self {
        case .dpad, .select, .back, .home, .menu, .media, .power, .appLaunch:
            return [.remoteV2, .adb]
        case .text, .mouse, .scroll, .appDiscovery, .diagnostics, .helpers, .soundbarVolume:
            return [.adb]
        }
    }

    /// The v2 feature the TV must have negotiated for this operation.
    var requiredV2Feature: RemoteV2Features? {
        switch self {
        case .dpad, .select, .back, .home, .menu, .media, .power: return .key
        case .appLaunch: return .appLink
        default: return nil
        }
    }
}

/// What the router knows about each link at the moment a command is sent.
struct RemoteTransportAvailability: Equatable {
    var v2Ready: Bool
    var v2Features: RemoteV2Features
    var adbReady: Bool
    /// User setting: off keeps every command on ADB exactly as before v2 existed.
    var preferV2: Bool

    static let adbOnly = RemoteTransportAvailability(v2Ready: false, v2Features: [], adbReady: true, preferV2: false)
}

/// Pure routing (unit tested). One command goes to exactly one transport; nothing is ever sent twice.
/// Fallback from v2 to ADB is explicit: it happens only when v2 is not ready or lacks the feature at
/// the moment the command starts, never after a command was handed to v2.
enum RemoteTransportPolicy {
    static func route(_ operation: RemoteOperation, _ links: RemoteTransportAvailability) -> RemoteTransportKind? {
        for transport in operation.allowedTransports {
            switch transport {
            case .remoteV2:
                guard links.preferV2, links.v2Ready else { continue }
                if let feature = operation.requiredV2Feature, !links.v2Features.contains(feature) { continue }
                return .remoteV2
            case .adb:
                if links.adbReady { return .adb }
            }
        }
        return nil
    }
}

/// Pins every touch-driven gesture (a held, repeating key) to the transport that started it.
/// Repeats and the release follow the owner; if the owner goes down mid-gesture the gesture ends
/// instead of continuing on the other link (no mid-gesture switching, no duplicate input).
struct GestureTransportLedger: Equatable {
    private var owners: [String: RemoteTransportKind] = [:]

    var heldKeys: Set<String> { Set(owners.keys) }
    var hasHeldKeys: Bool { !owners.isEmpty }

    /// A new press. Returns the owner, or nil when no transport can carry it.
    mutating func begin(_ key: String, operation: RemoteOperation, links: RemoteTransportAvailability) -> RemoteTransportKind? {
        if let owner = owners[key] { return owner }
        guard let transport = RemoteTransportPolicy.route(operation, links) else { return nil }
        owners[key] = transport
        return transport
    }

    /// A repeat tick of a held key. Nil means stop the gesture (its owner is no longer usable).
    mutating func repeatTick(_ key: String, links: RemoteTransportAvailability) -> RemoteTransportKind? {
        guard let owner = owners[key] else { return nil }
        guard Self.isUsable(owner, links) else {
            owners[key] = nil
            return nil
        }
        return owner
    }

    /// The finger lifted. Returns the transport any release must be sent on (nil: nothing to release).
    mutating func end(_ key: String) -> RemoteTransportKind? {
        owners.removeValue(forKey: key)
    }

    /// A link went down: its gestures are dropped (sending the release on the other link would be a
    /// stray key). Returns the keys that were dropped.
    mutating func transportLost(_ transport: RemoteTransportKind) -> Set<String> {
        var lost = Set<String>()
        for (key, owner) in owners where owner == transport { lost.insert(key) }
        for key in lost { owners[key] = nil }
        return lost
    }

    mutating func cancelAll() -> [String: RemoteTransportKind] {
        let held = owners
        owners.removeAll()
        return held
    }

    private static func isUsable(_ transport: RemoteTransportKind, _ links: RemoteTransportAvailability) -> Bool {
        switch transport {
        case .remoteV2: return links.v2Ready
        case .adb: return links.adbReady
        }
    }
}

/// Maps the app's key names to Android KeyEvent codes for Remote v2 (RemoteKeyCode values in
/// remotemessage.proto match android/keycodes.h). Volume and mute are deliberately absent: volume
/// follows the "Volume goes to" setting (Samsung TV, or soundbar via ADB 24/25/164), never v2.
/// OK is DPAD_CENTER, never a repeated ENTER.
enum RemoteV2KeyMap {
    static let codes: [String: Int32] = [
        "UP": 19, "DOWN": 20, "LEFT": 21, "RIGHT": 22, "OK": 23,
        "BACK": 4, "HOME": 3, "MENU": 82,
        "PLAY_PAUSE": 85, "STOP": 86, "NEXT": 87, "PREVIOUS": 88,
        "REWIND": 89, "FAST_FORWARD": 90, "PLAY": 126, "PAUSE": 127,
        "POWER": 26
    ]

    /// VOLUME_UP, VOLUME_DOWN, VOLUME_MUTE, MUTE (microphone).
    static let forbidden: Set<Int32> = [24, 25, 164, 91]

    static func code(for key: String) -> Int32? {
        guard let code = codes[key], !forbidden.contains(code) else { return nil }
        return code
    }

    /// Android key codes that a discrete (tapped, never held) command may send over Remote v2:
    /// the media transport keys only. Everything else `androidKey(_:)` sends (text-editing keys from the
    /// keyboard sheet, SLEEP 223 / WAKEUP 224 for standby and wake, volume) stays on ADB.
    static let discreteMediaCodes: Set<Int32> = [85, 86, 87, 88, 89, 90, 126, 127]

    /// The operation for a discrete Android key code, or nil when that code must stay on ADB.
    static func discreteOperation(forAndroidCode code: Int) -> RemoteOperation? {
        guard let code32 = Int32(exactly: code), !forbidden.contains(code32),
              discreteMediaCodes.contains(code32) else { return nil }
        return .media
    }

    static func operation(for key: String) -> RemoteOperation? {
        switch key {
        case "UP", "DOWN", "LEFT", "RIGHT": return .dpad
        case "OK": return .select
        case "BACK": return .back
        case "HOME": return .home
        case "MENU": return .menu
        case "POWER": return .power
        case "PLAY_PAUSE", "STOP", "NEXT", "PREVIOUS", "REWIND", "FAST_FORWARD", "PLAY", "PAUSE": return .media
        default: return nil
        }
    }
}

enum RemoteV2LinkState: Equatable {
    case off
    case notPaired
    case pairing
    case connecting
    case connected
    case unreachable(retryIn: Int)
    case failed(String)

    var label: String {
        switch self {
        case .off: return "Remote v2 off"
        case .notPaired: return "Remote v2 not paired"
        case .pairing: return "Remote v2 pairing…"
        case .connecting: return "Remote v2 connecting…"
        case .connected: return "Remote v2 connected"
        case let .unreachable(seconds): return "Remote v2 unreachable · retry in \(seconds)s"
        case let .failed(reason): return "Remote v2 unavailable · \(reason)"
        }
    }
}

/// Factual status text for the connection sheet.
enum RemoteV2StatusText {
    static func summary(v2: RemoteV2LinkState, adbReady: Bool) -> String {
        let adbText = adbReady ? "Input via ADB available" : "ADB not connected"
        return "\(v2.label) · \(adbText)"
    }
}

/// Bounded reconnect delays (pure, unit tested): 1, 2, 4, 8, 16, then 30 s, with no jitter so the
/// schedule is predictable.
enum RemoteV2Backoff {
    static let cap: TimeInterval = 30

    static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let exponent = Double(min(failures - 1, 10))
        return min(cap, pow(2, exponent))
    }
}

/// Whether an unconfirmed play/pause may be retried with `cmd media_session dispatch` (pure, unit
/// tested). The retry is an ADB shell command, so it is allowed only when the original key also went
/// over ADB: a command already handed to Remote v2 is never re-sent on the other link.
enum MediaRetryPolicy {
    static func mayRetryViaDispatch(originalTransport: RemoteTransportKind?) -> Bool {
        originalTransport == .adb
    }
}
