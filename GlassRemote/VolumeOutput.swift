import Foundation

// Where volume commands go. Restores the route that reached the soundbar in Phase 7.2.
//
// Phase 7.2 (RemoteModel+Features `volume(_:)` / `setVolumeFraction(_:)`) tried, in order: the TV's
// UPnP level, the Samsung remote keys, then `key(name)`, i.e. `input keyevent 24/25/164` on the TV box
// over ADB. Before Phase 9 recovery §3 the Samsung remote usually could not pair (a stale token was
// answered with ms.channel.unauthorized and no Allow prompt), so in practice 7.2 sent volume through
// the box, which forwards volume keys to the soundbar over HDMI-CEC (the box reports a CEC audio
// system with System Audio Mode on).
//
// The regression: v5 §5 deleted the box route ("Samsung-only volume"), and once §3 fixed pairing every
// command went to the Samsung TV (remote keys or UPnP), which moves the TV's own speakers on this
// setup. The box route is therefore the default again. The Samsung routes stay available as explicit
// choices, and nothing silently switches between them: a route that is down reports unavailable
// instead of sending to different speakers. Pure and unit tested (VolumeRouteRestoreTests); only the
// real TV, box and soundbar can confirm which speakers move.

/// What the volume controls drive (Connection settings → "Volume goes to").
enum VolumeOutput: String, CaseIterable, Identifiable, Sendable {
    /// The TV box's volume keys over ADB; the box passes them to the soundbar over HDMI-CEC (Phase 7.2).
    case soundbarViaBox
    /// The Samsung TV's remote keys over its WebSocket; the TV passes them to its active output.
    case soundbarViaTV
    /// The TV's built-in speakers: UPnP RenderingControl absolute level with read-back.
    case tvSpeakers

    var id: String { rawValue }

    /// A new key: the Phase 9 "Sound comes from" setting (automatic / external / tvSpeakers) chose
    /// among Samsung routes only, so it is deliberately not carried over.
    static let defaultsKey = "glassRemote.volumeOutput"
    static let `default`: VolumeOutput = .soundbarViaBox

    static func restored(from raw: String?) -> VolumeOutput {
        raw.flatMap(VolumeOutput.init(rawValue:)) ?? .default
    }

    var label: String {
        switch self {
        case .soundbarViaBox: return "Soundbar, through the TV box"
        case .soundbarViaTV: return "Soundbar, through the Samsung TV"
        case .tvSpeakers: return "TV speakers"
        }
    }

    /// Whether this output needs the Samsung TV connection at all.
    var usesSamsung: Bool { self != .soundbarViaBox }
}

/// How the slider and the buttons reach the output.
enum VolumeCommandRoute: Equatable, Sendable {
    /// `input keyevent` on the TV box over ADB, one per step.
    case boxKeys
    /// Samsung remote key (KEY_VOLUP / KEY_VOLDOWN / KEY_MUTE), one per step.
    case tvKeys
    /// UPnP RenderingControl absolute level, with read-back.
    case absolute
    /// Nothing is sent; the user is told why.
    case unavailable
}

enum VolumeRoutePolicy {
    /// Box keys per full slider sweep, as in Phase 7.2 (each `input keyevent` is a shell command on
    /// the box, so a 100-step sweep would take tens of seconds).
    static let boxSteps = 20

    /// The route for the chosen output. Never another output's route: a down route is unavailable.
    static func route(output: VolumeOutput, boxConnected: Bool, samsungEnabled: Bool,
                      remoteReady: Bool, upnpReady: Bool) -> VolumeCommandRoute {
        switch output {
        case .soundbarViaBox:
            return boxConnected ? .boxKeys : .unavailable
        case .soundbarViaTV:
            return samsungEnabled && remoteReady ? .tvKeys : .unavailable
        case .tvSpeakers:
            guard samsungEnabled else { return .unavailable }
            if upnpReady { return .absolute }
            return remoteReady ? .tvKeys : .unavailable
        }
    }

    /// Short reason shown in place of the level when the route is down.
    static func unavailableReason(output: VolumeOutput, samsungEnabled: Bool) -> String {
        switch output {
        case .soundbarViaBox: return "Connect the TV box"
        case .soundbarViaTV, .tvSpeakers:
            return samsungEnabled ? "Samsung TV not connected" : "Samsung TV is off"
        }
    }

    /// One line for the Connection sheet: what volume is doing.
    static func summary(route: VolumeCommandRoute, output: VolumeOutput, samsungEnabled: Bool) -> String {
        switch route {
        case .boxKeys:
            return "Volume: the TV box's volume keys (as in Phase 7.2). The box passes them to the soundbar over HDMI-CEC. The soundbar's level cannot be read, so the slider is relative."
        case .tvKeys:
            return "Volume: the Samsung TV's remote keys, which the TV applies to its active output. The level cannot be read, so the slider is relative."
        case .absolute:
            return "Volume: the TV's own level (UPnP), set exactly and read back."
        case .unavailable:
            return "Volume: unavailable · \(unavailableReason(output: output, samsungEnabled: samsungEnabled)). Nothing is sent to other speakers instead."
        }
    }
}

/// Where one volume button press goes.
enum VolumeButtonRoute: Equatable, Sendable {
    /// `input keyevent <code>` on the TV box over ADB.
    case boxKey(String)
    /// The Samsung WebSocket key for this app key name.
    case samsungKey(String)
    /// RenderingControl SetVolume to the last read level ± delta.
    case upnpStep(Int)
    /// RenderingControl GetMute then SetMute to the opposite.
    case upnpMuteToggle
    case unavailable
}

enum VolumeButtonPolicy {
    /// Android keycodes Phase 7.2 sent for volume over ADB.
    static let boxKeycodes: [String: String] = ["VOLUME_UP": "24", "VOLUME_DOWN": "25", "MUTE": "164"]

    static func route(for name: String, command: VolumeCommandRoute) -> VolumeButtonRoute {
        guard VolumeKeyPolicy.isVolumeKey(name) else { return .unavailable }
        switch command {
        case .boxKeys:
            return boxKeycodes[name].map(VolumeButtonRoute.boxKey) ?? .unavailable
        case .tvKeys:
            return .samsungKey(name)
        case .absolute:
            switch name {
            case "VOLUME_UP": return .upnpStep(1)
            case "VOLUME_DOWN": return .upnpStep(-1)
            default: return .upnpMuteToggle
            }
        case .unavailable:
            return .unavailable
        }
    }
}
