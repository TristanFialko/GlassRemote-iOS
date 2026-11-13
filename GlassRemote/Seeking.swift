import Foundation

/// Measured (never assumed) seeking.
///
/// The box offers no way to jump to an exact position: `dumpsys media_session` prints neither the
/// duration nor accepts a seek, `cmd media_session` has no seek command, and `input keyevent` can only
/// send REWIND / FAST_FORWARD, whose size the playing app chooses. So the app does not claim "10 s".
/// It sends the key, reads the session's position before and after, and reports what really moved.
/// If, repeatedly and consistently, a key turns out to move about 10 s, the Player relabels it.
/// See SEEKING_REPORT.md.
enum SeekMeasurement: Equatable {
    /// The position moved by this many seconds (negative = backwards), beyond normal playback.
    case confirmed(seconds: Double)
    /// The session reported no movement beyond normal playback.
    case unchanged
    /// Not measurable (different item, buffering, no sample).
    case unknown

    /// Compares two session samples. Normal playback between the samples is removed using the
    /// device clock (`deviceUptimeMs`), falling back to the phone clock, so a playing item that merely
    /// advanced is not mistaken for a seek.
    static func measure(before: MediaState, after: MediaState, tolerance: Double = 1.0) -> SeekMeasurement {
        guard before.isActive, after.isActive, before.package == after.package, before.title == after.title,
              [2, 3].contains(before.state), [2, 3].contains(after.state) else { return .unknown }
        var natural = 0.0
        if before.state == 3 {
            if let a = before.deviceUptimeMs, let b = after.deviceUptimeMs, b >= a {
                natural = Double(b - a) / 1000 * before.speed
            } else {
                natural = max(0, after.sampledAt.timeIntervalSince(before.sampledAt)) * before.speed
            }
        }
        let delta = Double(after.positionMs - before.positionMs) / 1000 - natural
        guard abs(delta) >= tolerance else { return .unchanged }
        return .confirmed(seconds: (delta * 10).rounded() / 10)
    }
}

/// What the last Rewind / Fast-forward actually did (shown briefly on the Player).
struct SeekReport: Equatable {
    var command: MediaCommand
    var outcome: SeekMeasurement
    var at: Date
}

/// Learns how far a key really seeks. A step is trusted only after two consecutive confirmed
/// measurements agree within 1.5 s (the same "two confirmed attempts" rule the volume limit uses).
struct SeekStepLearner: Equatable {
    private(set) var samples: [String: [Double]] = [:]

    static func key(package: String, command: MediaCommand) -> String { "\(package)|\(command.rawValue)" }

    /// `seconds` is the signed distance. Wrong-direction or implausible readings are ignored.
    mutating func record(package: String, command: MediaCommand, seconds: Double) {
        guard command == .rewind || command == .fastForward else { return }
        guard (command == .rewind) == (seconds < 0), (1...300).contains(abs(seconds)) else { return }
        let key = Self.key(package: package, command: command)
        samples[key] = Array(((samples[key] ?? []) + [abs(seconds)]).suffix(4))
    }

    func step(package: String, command: MediaCommand) -> Double? {
        guard let last = samples[Self.key(package: package, command: command)]?.suffix(2), last.count == 2,
              abs(last[last.startIndex] - last[last.endIndex - 1]) <= 1.5 else { return nil }
        return (last.reduce(0, +) / 2 * 10).rounded() / 10
    }

    /// Both directions are measured and each is about ten seconds.
    func isTenSecond(package: String) -> Bool {
        guard let back = step(package: package, command: .rewind), let forward = step(package: package, command: .fastForward) else { return false }
        return abs(back - 10) <= 1.5 && abs(forward - 10) <= 1.5
    }

    // Persistence (plain dictionary, tiny).
    static let defaultsKey = "glassRemote.seekSteps.v1"
    static func load() -> SeekStepLearner {
        var learner = SeekStepLearner()
        learner.samples = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [Double]]) ?? [:]
        return learner
    }
    func save() { UserDefaults.standard.set(samples, forKey: Self.defaultsKey) }
}

/// A transport command the TV did not take (audit UX-005). Shown briefly on Now Playing and the
/// mini-player, where it was pressed, instead of only in the Connection sheet's status line.
struct MediaFailureReport: Equatable {
    var text: String
    var at: Date

    static let visibleFor: TimeInterval = 6

    func isVisible(at now: Date) -> Bool { now.timeIntervalSince(at) < Self.visibleFor && now >= at }

    static func notAccepted(_ command: MediaCommand, at: Date = Date()) -> MediaFailureReport {
        MediaFailureReport(text: "TV didn't accept \(command.displayName)", at: at)
    }

    static func notConnected(at: Date = Date()) -> MediaFailureReport {
        MediaFailureReport(text: "Not connected to the TV box", at: at)
    }
}

extension MediaCommand {
    /// Short, readable name for feedback ("Pause", "Fast-forward").
    var displayName: String {
        switch self {
        case .play: return "Play"
        case .pause: return "Pause"
        case .playPause: return "Play/Pause"
        case .next: return "Next"
        case .previous: return "Previous"
        case .rewind: return "Rewind"
        case .fastForward: return "Fast-forward"
        }
    }
}
