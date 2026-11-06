import Foundation

/// Transport commands for the Player and the Remote's now-playing card.
///
/// Why this exists: Play used to send KEYCODE_MEDIA_PLAY_PAUSE (85), a TOGGLE. The button shown
/// comes from a session snapshot that can be several seconds old, so a toggle sent against a
/// stale state does the opposite of what the button says (Pause worked, Play often did not, since
/// a paused session is also the state players are slowest to refresh). Play and Pause are now
/// explicit, idempotent commands (126 / 127), the result is verified against a fresh session
/// read, and the UI never claims success on its own.
enum MediaCommand: String {
    case play, pause, next, previous, rewind, fastForward

    var keycode: Int {
        switch self {
        case .play: return 126          // KEYCODE_MEDIA_PLAY
        case .pause: return 127         // KEYCODE_MEDIA_PAUSE
        case .next: return 87           // KEYCODE_MEDIA_NEXT
        case .previous: return 88       // KEYCODE_MEDIA_PREVIOUS
        case .rewind: return 89         // KEYCODE_MEDIA_REWIND
        case .fastForward: return 90    // KEYCODE_MEDIA_FAST_FORWARD
        }
    }

    /// `cmd media_session dispatch <name>` equivalents, used as one fallback for play/pause.
    var dispatchName: String? {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        default: return nil
        }
    }

    /// Does this session state show the command took effect? nil for commands with no checkable result.
    func satisfied(by state: MediaState) -> Bool? {
        switch self {
        case .play: return state.state == 3 || state.state == 6
        case .pause: return state.state == 2 || state.state == 1
        default: return nil
        }
    }
}

extension RemoteModel {
    /// Sends a transport command, then confirms play/pause against the session.
    func sendMedia(_ command: MediaCommand) {
        guard connected else { status = "Not connected"; return }
        guard mediaCommandTask == nil else { return }   // one command at a time; ignore double taps
        mediaCommandTask = Task { [weak self] in
            await self?.runMedia(command)
            self?.mediaCommandTask = nil
        }
    }

    private func runMedia(_ command: MediaCommand) async {
        let before = media.state
        let beforeSample = media
        GRLog.note("media", "request \(command.rawValue) (session state before: \(before))")
        mediaCommandPending = true
        defer { mediaCommandPending = false }

        androidKey(command.keycode)
        try? await Task.sleep(nanoseconds: 600_000_000)
        await pollMedia()
        guard let wanted = command.satisfied(by: media) else {
            GRLog.note("media", "\(command.rawValue) sent; state now \(media.state)")
            if command == .rewind || command == .fastForward { await recordSeek(command, before: beforeSample) }
            return
        }
        if wanted { GRLog.note("media", "\(command.rawValue) confirmed (state \(media.state))"); return }

        // Not confirmed: one retry through the media-session dispatcher.
        if let name = command.dispatchName, let connection = adb {
            GRLog.note("media", "\(command.rawValue) not confirmed; retrying via media_session dispatch")
            _ = try? await runShell(connection, ["sh", "-c", "cmd media_session dispatch \(name)"])
            try? await Task.sleep(nanoseconds: 700_000_000)
            await pollMedia()
            if command.satisfied(by: media) == true {
                GRLog.note("media", "\(command.rawValue) confirmed after dispatch (state \(media.state))")
                return
            }
        }
        GRLog.note("media", "\(command.rawValue) NOT accepted (state \(media.state))")
        status = "The player didn't accept \(command.rawValue)"
    }

    /// Reads the position again and reports what the key really did. Nothing is shown as "done"
    /// before the TV's own session confirms it; one extra read covers a slow session update.
    private func recordSeek(_ command: MediaCommand, before: MediaState) async {
        var outcome = SeekMeasurement.measure(before: before, after: media)
        if outcome == .unchanged {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await pollMedia()
            outcome = SeekMeasurement.measure(before: before, after: media)
        }
        lastSeek = SeekReport(command: command, outcome: outcome, at: Date())
        GRLog.note("media", "\(command.rawValue) measured: \(outcome)")
        // A rewind that landed at the very start was clipped, so it says nothing about the step.
        if case .confirmed(let seconds) = outcome, !(command == .rewind && media.positionMs < 1500) {
            seekLearner.record(package: before.package, command: command, seconds: seconds)
            seekLearner.save()
        }
    }
}
