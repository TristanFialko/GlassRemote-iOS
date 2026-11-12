import Foundation

// Phase 9 gap fix: which Samsung route actually reaches the speakers that are playing.
//
// The Samsung TV offers two volume routes, and they are NOT interchangeable:
// - Remote keys over the WebSocket (KEY_VOLUP / KEY_VOLDOWN / KEY_MUTE): exactly what the TV's own
//   remote sends. The TV applies them to whichever audio output is active, so a soundbar or receiver
//   on HDMI ARC / eARC / optical follows them.
// - UPnP RenderingControl (port 9197): the TV's MediaRenderer volume. On a TV whose sound goes to an
//   external device this can be the built-in speaker level, which answers 200 OK and changes
//   nothing audible. A successful SOAP reply is therefore not proof that the soundbar moved.
//
// The regression: the slider and (since recovery §5) the buttons used UPnP whenever it answered. The
// route is now chosen from evidence. UPnP is trusted only once a volume key sent over the remote
// socket has been seen to move the UPnP level (so both address the same output), or when the user
// says the TV's own speakers are in use. Until then the remote keys are the only route, and with
// no paired remote socket volume is unavailable. The Android box is never a route.
// Pure and unit tested (Phase9SoundbarVolumeTests). Needs the real TV and soundbar to confirm.

/// What the user says the TV's sound comes out of (Connection settings).
enum SamsungAudioOutput: String, CaseIterable, Identifiable, Sendable {
    /// Decide from what the TV is seen to do.
    case automatic
    /// A soundbar or receiver: remote keys only, UPnP is never used for commands.
    case external
    /// The TV's built-in speakers: UPnP absolute volume is right.
    case tvSpeakers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .external: return "Soundbar or receiver"
        case .tvSpeakers: return "TV speakers"
        }
    }
}

/// What has been observed about the UPnP level compared with the remote volume keys.
enum VolumeOutputEvidence: String, Equatable, Sendable {
    /// Nothing conclusive yet.
    case unknown
    /// A key press moved the UPnP level: both address the output that is playing.
    case tracksKeys
    /// Several key presses left the UPnP level unchanged: UPnP is some other output.
    case ignoresKeys
}

/// How the slider and the buttons reach the TV.
enum VolumeCommandRoute: Equatable, Sendable {
    /// One remote key per step (the TV forwards them to the active output).
    case keys
    /// UPnP RenderingControl absolute level, with read-back.
    case absolute
    /// Nothing is sent; the user is told.
    case unavailable
}

enum VolumeRoutePolicy {
    /// Whether UPnP RenderingControl may be used for commands and shown as the level.
    static func upnpControlsOutput(output: SamsungAudioOutput, evidence: VolumeOutputEvidence) -> Bool {
        switch output {
        case .tvSpeakers: return true
        case .external: return false
        case .automatic: return evidence == .tracksKeys
        }
    }

    /// The slider's route. Absolute only when UPnP is known to address the playing output;
    /// otherwise the remote keys; otherwise nothing (never an unverified UPnP level).
    static func route(enabled: Bool, remoteReady: Bool, upnpReady: Bool,
                      output: SamsungAudioOutput, evidence: VolumeOutputEvidence) -> VolumeCommandRoute {
        guard enabled else { return .unavailable }
        if upnpReady, upnpControlsOutput(output: output, evidence: evidence) { return .absolute }
        if remoteReady { return .keys }
        return .unavailable
    }

    /// One line for the Connection sheet: what volume is doing and why.
    static func summary(route: VolumeCommandRoute, output: SamsungAudioOutput,
                        evidence: VolumeOutputEvidence, upnpReady: Bool) -> String {
        switch route {
        case .absolute:
            return output == .tvSpeakers
                ? "Volume: TV speakers, set as an exact level (UPnP)."
                : "Volume: exact level (UPnP). The TV's volume keys were seen to move this level, so it is the output that is playing."
        case .keys:
            if output == .external { return "Volume: remote keys, which the TV passes to the soundbar or receiver." }
            if evidence == .ignoresKeys {
                return "Volume: remote keys. The TV's own level (UPnP) did not follow its volume keys, so sound is going to a soundbar or receiver and that level is not used."
            }
            return upnpReady
                ? "Volume: remote keys. The TV's own level (UPnP) is not used until a volume key is seen to move it."
                : "Volume: remote keys."
        case .unavailable:
            return "Volume: unavailable. The Samsung remote must be paired; the TV's own level (UPnP) is not used without proof that it is the output that is playing."
        }
    }
}

/// Learns whether the UPnP level follows the TV's remote volume keys, from ordinary use: keys sent
/// over the remote socket, then the next settled UPnP reading. Nothing is sent to probe.
struct VolumeOutputProbe: Equatable, Sendable {
    /// A reading counts only this long after the last key (the TV applies keys with a short lag).
    static let settle: TimeInterval = 1.0
    /// Keys older than this are forgotten: something else may have changed the level since.
    static let window: TimeInterval = 20
    /// Net presses in one direction that must leave the level untouched before UPnP is ruled out
    /// (one press can be lost; three cannot all be).
    static let pressesForNegative = 3

    private(set) var baseline: Int?
    private(set) var net = 0
    private(set) var lastKeyAt: Date?

    var isCollecting: Bool { baseline != nil }

    /// A VOLUP (+1) or VOLDOWN (−1) key went out over the remote socket. `lastReading` is the UPnP
    /// level before it (nil when the link has not answered: nothing can be learned).
    mutating func keySent(direction: Int, lastReading: Int?, at now: Date) {
        if let last = lastKeyAt, now.timeIntervalSince(last) > Self.window { reset() }
        if baseline == nil {
            guard let lastReading else { return }
            baseline = lastReading
        }
        net += direction > 0 ? 1 : -1
        lastKeyAt = now
    }

    /// Anything that changes the level by another route (a UPnP set, a new host) voids the sample.
    mutating func reset() {
        baseline = nil
        net = 0
        lastKeyAt = nil
    }

    /// A UPnP reading. Returns a verdict once one is clear, nil while collecting or inconclusive.
    mutating func reading(_ value: Int, at now: Date) -> VolumeOutputEvidence? {
        guard let baseline, let lastKeyAt else { return nil }
        let age = now.timeIntervalSince(lastKeyAt)
        guard age >= Self.settle else { return nil }
        if age > Self.window { reset(); return nil }
        guard net != 0 else { reset(); return nil }           // the presses cancelled out
        let moved = value - baseline
        if moved != 0 {
            // Moved the way the keys pushed: same output. Moved the other way: something else did it.
            let verdict: VolumeOutputEvidence? = (moved > 0) == (net > 0) ? .tracksKeys : nil
            reset()
            return verdict
        }
        // Unchanged. At the end of the range in that direction it could not have moved anyway.
        let pinned = (net > 0 && baseline >= 100) || (net < 0 && baseline <= 0)
        if pinned { reset(); return nil }
        guard abs(net) >= Self.pressesForNegative else { return nil }   // keep collecting
        reset()
        return .ignoresKeys
    }
}

/// The verdict is kept per TV address, so a different TV starts from unknown.
enum VolumeOutputEvidenceStore {
    static let hostKey = "glassRemote.volumeEvidenceHost"
    static let verdictKey = "glassRemote.volumeEvidence"

    static func load(host: String, defaults: UserDefaults = .standard) -> VolumeOutputEvidence {
        let wanted = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, defaults.string(forKey: hostKey) == wanted,
              let raw = defaults.string(forKey: verdictKey) else { return .unknown }
        return VolumeOutputEvidence(rawValue: raw) ?? .unknown
    }

    static func save(_ evidence: VolumeOutputEvidence, host: String, defaults: UserDefaults = .standard) {
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: hostKey)
        defaults.set(evidence.rawValue, forKey: verdictKey)
    }
}
