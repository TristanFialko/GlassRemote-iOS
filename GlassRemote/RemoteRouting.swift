import Foundation

/// Which TV a command is aimed at. Persisted by `RemoteModel.target`.
enum RemoteTarget: String, CaseIterable, Identifiable {
    case auto, android, samsung
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .android: return "Android TV"
        case .samsung: return "Samsung TV"
        }
    }
    var shortTitle: String { self == .android ? "Android" : (self == .samsung ? "Samsung" : "Auto") }
    var symbol: String {
        switch self {
        case .auto: return "sparkles.tv"
        case .android: return "tv.and.mediabox"
        case .samsung: return "tv"
        }
    }
}

enum RemoteDevice: Equatable { case android, samsung }

/// What kind of command is being sent. Capability decides routing in Auto mode.
enum RemoteCommandKind { case navigation, media, volume, power, source, channel, guide }

/// Pure routing rules (unit tested). A command is only ever sent to ONE device.
///
/// - Android TV target: navigation and media go to the box. Volume keeps its existing routing
///   (Samsung if linked, otherwise ADB). TV-only kinds are not available.
/// - Samsung TV target: everything goes to the TV (nil when the TV link is down).
/// - Auto: navigation and media go to the box while ADB is up, otherwise to the TV if linked.
///   Capabilities only the TV has (source, channel, guide) always go to the TV.
enum RemoteRouting {
    static func device(for kind: RemoteCommandKind, target: RemoteTarget,
                       androidConnected: Bool, samsungReady: Bool) -> RemoteDevice? {
        switch target {
        case .android:
            switch kind {
            case .navigation, .media, .power: return androidConnected ? .android : nil
            case .volume: return samsungReady ? .samsung : (androidConnected ? .android : nil)
            case .source, .channel, .guide: return nil
            }
        case .samsung:
            return samsungReady ? .samsung : nil
        case .auto:
            switch kind {
            case .source, .channel, .guide: return samsungReady ? .samsung : nil
            case .volume: return samsungReady ? .samsung : (androidConnected ? .android : nil)
            case .navigation, .media, .power:
                if androidConnected { return .android }
                return samsungReady ? .samsung : nil
            }
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
