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
    case play, pause, playPause, next, previous, rewind, fastForward

    var keycode: Int {
        switch self {
        case .play: return 126          // KEYCODE_MEDIA_PLAY
        case .pause: return 127         // KEYCODE_MEDIA_PAUSE
        // Toggle, used only by the Remote v2-only Player row, where no session state is known to pick
        // an explicit Play or Pause. Never confirmed, never retried.
        case .playPause: return 85      // KEYCODE_MEDIA_PLAY_PAUSE
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

extension MediaCommandPlan {
    /// The plan for one Player / now-playing command on the links available right now.
    static func make(_ command: MediaCommand, links: RemoteTransportAvailability) -> MediaCommandPlan {
        make(keycode: command.keycode, hasDispatchRetry: command.dispatchName != nil, links: links)
    }
}

extension MediaFailureReport {
    /// A key handed to Remote v2 while no ADB media session can be read: it went out once, and nothing
    /// on the phone can say whether the player took it.
    static func sentUnconfirmed(_ command: MediaCommand, via transport: RemoteTransportKind,
                                at: Date = Date()) -> MediaFailureReport {
        MediaFailureReport(text: "\(command.displayName) sent over \(transport.rawValue) · not confirmed", at: at)
    }
}

extension RemoteModel {
    /// The links as the media router sees them now. ADB readiness is the ADB connection: the same
    /// condition `androidKey(_:)` sends on and `pollMedia()` reads the session with.
    var mediaLinks: RemoteTransportAvailability { RemoteV2Controller.shared.availability(adbReady: connected) }

    /// Which media controls the Player may offer right now.
    var mediaControlMode: MediaControlMode { MediaControlMode.resolve(mediaLinks) }

    /// Sends a transport command on exactly one transport, then confirms play/pause against the session
    /// when ADB can read it. ADB down with Remote v2 ready: the key goes once over v2 and is reported as
    /// sent but not confirmed (no ADB retry). Neither ready: nothing is sent and "Not connected" is shown.
    func sendMedia(_ command: MediaCommand) {
        guard MediaCommandPlan.make(command, links: mediaLinks).transport != nil else {
            status = "Not connected"
            lastMediaFailure = .notConnected()
            return
        }
        guard mediaCommandTask == nil else { return }   // one command at a time; ignore double taps
        lastMediaFailure = nil
        mediaCommandTask = Task { [weak self] in
            await self?.runMedia(command)
            self?.mediaCommandTask = nil
        }
    }

    private func runMedia(_ command: MediaCommand) async {
        let before = media.state
        let beforeSample = media
        let session = sessionID
        GRLog.note("media", "request \(command.rawValue) (session state before: \(before))")
        mediaCommandPending = true
        defer { mediaCommandPending = false }

        // The one send. androidKey re-reads the links, so a link that changed since the tap is honoured.
        let carrier = androidKey(command.keycode)
        switch MediaCommandPlan.verification(carrier: carrier, sessionReadable: connected) {
        case .unavailable:
            GRLog.note("media", "\(command.rawValue) not sent: no transport ready")
            lastMediaFailure = .notConnected()
            return
        case .unconfirmed:
            reportSentUnconfirmed(command, via: carrier)
            return
        case .readSession:
            break
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        await pollMedia()
        // The ADB session this command would be checked against went away or was replaced while it was in
        // flight: a stale sample proves nothing either way.
        let sameSession = connected && session == sessionID
        if MediaCommandPlan.verification(carrier: carrier, sessionReadable: sameSession) == .unconfirmed {
            reportSentUnconfirmed(command, via: carrier)
            return
        }
        guard sameSession else {
            GRLog.note("media", "\(command.rawValue) sent over \(carrier?.rawValue ?? "no transport"); ADB session changed, result not checked")
            return
        }
        guard let wanted = command.satisfied(by: media) else {
            GRLog.note("media", "\(command.rawValue) sent over \(carrier?.rawValue ?? "no transport"); state now \(media.state)")
            if command == .rewind || command == .fastForward { await recordSeek(command, before: beforeSample) }
            return
        }
        if wanted { GRLog.note("media", "\(command.rawValue) confirmed (state \(media.state))"); return }

        // Not confirmed: one retry through the media-session dispatcher, only when the key itself went
        // over ADB. A key handed to Remote v2 is never re-sent on ADB (one transport per command).
        if !MediaRetryPolicy.mayRetryViaDispatch(originalTransport: carrier) {
            GRLog.note("media", "\(command.rawValue) sent over \(carrier?.rawValue ?? "no transport"); not retried on ADB")
        } else if let name = command.dispatchName, let connection = adb {
            GRLog.note("media", "\(command.rawValue) not confirmed; retrying via media_session dispatch")
            _ = try? await runShell(connection, ["sh", "-c", "cmd media_session dispatch \(name)"])
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, session == sessionID else { return }
            await pollMedia()
            if command.satisfied(by: media) == true {
                GRLog.note("media", "\(command.rawValue) confirmed after dispatch (state \(media.state))")
                return
            }
        }
        GRLog.note("media", "\(command.rawValue) NOT accepted (state \(media.state))")
        status = "The player didn't accept \(command.rawValue)"
        lastMediaFailure = .notAccepted(command)
    }

    /// Remote v2 carried the key and no ADB session can check it: say exactly that, once.
    private func reportSentUnconfirmed(_ command: MediaCommand, via carrier: RemoteTransportKind?) {
        let transport = carrier ?? .remoteV2
        GRLog.note("media", "\(command.rawValue) sent once over \(transport.rawValue); not independently confirmed (no ADB media session), not retried")
        status = "\(command.displayName) sent over \(transport.rawValue) · not confirmed"
        lastMediaFailure = .sentUnconfirmed(command, via: transport)
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
