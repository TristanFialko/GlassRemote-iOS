import Foundation

/// Which TV a command is aimed at. Persisted by `RemoteModel.target`.
/// There is no automatic mode: every command goes to the device the user explicitly selected.
enum RemoteTarget: String, CaseIterable, Identifiable {
    case android, samsung
    var id: String { rawValue }
    var title: String { self == .android ? "Android TV" : "Samsung TV" }
    var shortTitle: String { self == .android ? "Android" : "Samsung" }
    var symbol: String { self == .android ? "tv.and.mediabox" : "tv" }

    /// Restores the last explicitly selected device. A value saved by an older build ("auto") or
    /// anything unrecognised resolves to Android TV, the box this app was built around.
    static func restored(from stored: String?) -> RemoteTarget {
        stored.flatMap(RemoteTarget.init(rawValue:)) ?? .android
    }
}

enum RemoteDevice: Equatable { case android, samsung }

/// What kind of command is being sent.
enum RemoteCommandKind { case navigation, media, volume, power, source, channel, guide }

/// Pure routing rules (unit tested). A command is only ever sent to ONE device, and never to a
/// device other than the selected one: when the selected device is down the result is `nil` and
/// the UI shows its connection state instead of silently controlling the other TV.
///
/// - Android TV target: navigation, media and power go to the box. Volume goes to the Samsung
///   TV only (v5 §5: never the Android box; nil while the Samsung link is down). TV-only kinds are
///   not available.
/// - Samsung TV target: everything goes to the TV (nil when the TV link is down).
enum RemoteRouting {
    static func device(for kind: RemoteCommandKind, target: RemoteTarget,
                       androidConnected: Bool, samsungRemoteReady samsungReady: Bool) -> RemoteDevice? {
        switch target {
        case .android:
            switch kind {
            case .navigation, .media, .power: return androidConnected ? .android : nil
            case .volume: return samsungReady ? .samsung : nil
            case .source, .channel, .guide: return nil
            }
        case .samsung:
            return samsungReady ? .samsung : nil
        }
    }
}

/// Keys the Samsung remote WebSocket accepts from this app. Anything not listed is never sent.
/// Names are from Samsung's remote-control key list; not every model supports every key, so the
/// UI marks a key unavailable only when the TV connection is down, and a silent key on a given
/// model is reported in the checklist rather than guessed at.
enum SamsungKey: String, CaseIterable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT"
    case enter = "KEY_ENTER", back = "KEY_RETURN", home = "KEY_HOME", menu = "KEY_MENU"
    case tools = "KEY_TOOLS", info = "KEY_INFO", guide = "KEY_GUIDE", exit = "KEY_EXIT"
    case play = "KEY_PLAY", pause = "KEY_PAUSE", stop = "KEY_STOP"
    case rewind = "KEY_REWIND", fastForward = "KEY_FF"
    case volUp = "KEY_VOLUP", volDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case power = "KEY_POWER", source = "KEY_SOURCE", hdmi = "KEY_HDMI"
    case channelUp = "KEY_CHUP", channelDown = "KEY_CHDOWN"

    static let allowlist: Set<String> = Set(allCases.map(\.rawValue))

    /// Maps the app's existing key names (the ones Android uses) onto Samsung keys.
    /// App-level name for keys that have an ADB equivalent (the only keys with a fallback).
    var legacyVolumeName: String? {
        switch self {
        case .volUp: return "VOLUME_UP"
        case .volDown: return "VOLUME_DOWN"
        case .mute: return "MUTE"
        default: return nil
        }
    }

    static func forAppKey(_ name: String) -> SamsungKey? {
        switch name {
        case "UP": return .up
        case "DOWN": return .down
        case "LEFT": return .left
        case "RIGHT": return .right
        case "OK": return .enter
        case "BACK": return .back
        case "HOME": return .home
        case "MENU": return .menu
        case "VOLUME_UP": return .volUp
        case "VOLUME_DOWN": return .volDown
        case "MUTE": return .mute
        case "TV_POWER": return .power
        case "TV_SOURCE": return .source
        case "TV_HDMI": return .hdmi
        default: return nil
        }
    }
}

/// Connection state of the Samsung remote link, shown as-is in the UI.
enum SamsungLinkState: Equatable {
    case off                 // feature disabled or no IP entered
    case connecting          // paired before; opening the connection
    case pairing             // first time: the TV is asking to allow Glass Remote
    case connected
    case denied              // the TV said no (or the prompt timed out)
    case unreachable         // network error; retrying automatically

    var label: String {
        switch self {
        case .off: return "Off"
        case .connecting: return "Connecting…"
        case .pairing: return "Approve on the TV"
        case .connected: return "Connected"
        case .denied: return "Not allowed"
        case .unreachable: return "Unreachable · retrying"
        }
    }
}
