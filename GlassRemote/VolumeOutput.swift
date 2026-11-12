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

    /// Short name for the volume row, so every row says which output it moves.
    var shortLabel: String {
        switch self {
        case .soundbarViaBox: return "Soundbar · box"
        case .soundbarViaTV: return "Soundbar · TV"
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
            // Only the TV's own level. Its remote keys would reach whatever output the TV is using
            // (possibly an ARC soundbar), so a silent UPnP outage is reported, never swapped for them.
            return samsungEnabled && upnpReady ? .absolute : .unavailable
        }
    }

    /// Short reason shown in place of the level when the route is down.
    static func unavailableReason(output: VolumeOutput, samsungEnabled: Bool, remoteReady: Bool = false) -> String {
        switch output {
        case .soundbarViaBox: return "Connect the TV box"
        case .soundbarViaTV:
            return samsungEnabled ? "Samsung TV not connected" : "Samsung TV is off"
        case .tvSpeakers:
            guard samsungEnabled else { return "Samsung TV is off" }
            return remoteReady ? "TV volume link not answering" : "Samsung TV not connected"
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

/// When the assumed key position is thrown away (pure, unit tested): only when the active route
/// differs from the route it was built on. Socket or UPnP changes that leave the route alone keep it.
enum VolumeStatePolicy {
    static func shouldReset(stateRoute: VolumeCommandRoute?, currentRoute: VolumeCommandRoute) -> Bool {
        stateRoute != currentRoute
    }
}

/// How many key presses a slider move sends on a relative (key) route (pure, unit tested).
///
/// The soundbar's level cannot be read, so the position is an estimate. The first time the slider
/// reaches 0 from an unknown position the full range is pressed down once: the soundbar clamps at
/// its true minimum and the estimate becomes exact. The upward direction never does that: going up
/// sends only the distance the thumb visibly moved, so reaching the top from an unknown position can
/// never fire a full-range burst of volume-up presses.
enum VolumeStepPlan {
    struct Result: Equatable {
        var delta: Int
        var levelKnown: Bool
    }

    static func plan(target: Int, assumed: Int, levels: Int, levelKnown: Bool) -> Result {
        let levels = max(levels, 1)
        let target = min(max(target, 0), levels)
        if !levelKnown, target <= 0 {
            return Result(delta: -levels, levelKnown: true)
        }
        let delta = min(max(target - assumed, -levels), levels)
        return Result(delta: delta, levelKnown: levelKnown)
    }

    /// Pending presses never exceed one full range in either direction, however fast the moves come.
    static func clampPending(_ pending: Int, levels: Int) -> Int {
        let levels = max(levels, 1)
        return min(max(pending, -levels), levels)
    }

    /// Where the estimate starts when a route is first used: the thumb the user is looking at.
    static func seed(fraction: Double, levels: Int) -> Int {
        let levels = max(levels, 1)
        return min(max(Int((min(max(fraction, 0), 1) * Double(levels)).rounded()), 0), levels)
    }
}

/// Samsung TV address and link defaults (pure, unit tested). There is no built-in address: a fresh
/// install stays unconfigured until the user scans or types one. An existing install keeps its saved
/// address, or recovers the address of the TV that issued the saved pairing token.
enum SamsungHostDefaults {
    static func normalized(_ host: String?) -> String {
        (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func restoredHost(saved: String?, tokenHost: String?) -> String {
        let saved = normalized(saved)
        if !saved.isEmpty { return saved }
        return normalized(tokenHost)
    }

    /// An explicit user choice is kept; otherwise the link is on only when an address is known.
    static func restoredLinkEnabled(stored: Bool?, host: String) -> Bool {
        stored ?? !normalized(host).isEmpty
    }
}
