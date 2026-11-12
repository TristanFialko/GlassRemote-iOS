import Foundation

/// What the TV box's active media session can do and what it is playing, parsed from
/// `dumpsys media_session`. Only capabilities the session actually advertises are enabled.
struct MediaState: Equatable {
    var package: String
    var title: String
    var state: Int              // PlaybackState: 2 paused, 3 playing, 6 buffering
    var positionMs: Int64
    var speed: Double
    var sampledAt: Date
    var actions: Int64
    /// Parsed from the same `description=` field as `title`. Android prints MediaDescription as
    /// "title, subtitle, description"; both extras are empty when the app sets none. Unverified
    /// against a live Nuvio session: check on device.
    var headline: String = ""
    var subtitle: String = ""
    /// The box's uptime (ms) when this sample was read; lets seek measurements remove normal playback.
    var deviceUptimeMs: Int64? = nil

    static let idle = MediaState(package: "", title: "", state: 0, positionMs: 0, speed: 1, sampledAt: .distantPast, actions: 0)

    var isActive: Bool { !package.isEmpty }
    var isPlaying: Bool { state == 3 || state == 6 }

    // PlaybackState action bits
    var canPlayPause: Bool { actions & (2 | 4 | 512) != 0 }
    var canPrevious: Bool { actions & 16 != 0 }
    var canNext: Bool { actions & 32 != 0 }
    var canRewind: Bool { actions & 8 != 0 }
    var canFastForward: Bool { actions & 64 != 0 }
    /// ACTION_SEEK_TO is advertised, but no shell route can invoke it with a position (see SEEKING_REPORT.md).
    var advertisesSeekTo: Bool { actions & 256 != 0 }
    /// Total length. `dumpsys media_session` prints only the description, never METADATA_KEY_DURATION,
    /// so this stays nil and the player never shows a scrubber. Set only if a real source appears.
    var durationMs: Int64? { nil }

    /// Playback position now, extrapolated from the last sample while playing.
    func position(at date: Date) -> TimeInterval {
        var ms = Double(positionMs)
        if state == 3 { ms += max(0, date.timeIntervalSince(sampledAt)) * 1000 * speed }
        return max(0, ms / 1000)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Phase 9 recovery §4: the outcome of one `dumpsys media_session` read. `unreadable` means an
/// active session is listed but its PlaybackState is in a shape the parser does not understand; the
/// poller then keeps the last good sample (it goes stale and hides on its own) instead of reporting
/// "nothing playing".
enum MediaRead: Equatable {
    case session(MediaState)
    case none
    case unreadable
}

/// Phase 9 recovery §4: the fields of one printed PlaybackState.
struct PlaybackFields: Equatable {
    var state: Int
    var position: Int64
    var speed: Double
    var updated: Int64
    var actions: Int64
}

/// Phase 9 recovery §4: how a poll result replaces the published media state (pure, unit tested).
enum MediaPollPolicy {
    static func next(current: MediaState, read: MediaRead) -> MediaState {
        switch read {
        case .session(let state): return state
        case .none: return .idle
        // An unreadable sample is not evidence that playback stopped. The last good sample keeps
        // its own `sampledAt`, so it still expires after `PlayerSessionPhase.staleAfter`.
        case .unreadable: return current
        }
    }
}

enum MediaParser {
    /// `output` is `cat /proc/uptime` followed by `dumpsys media_session`.
    /// Returns nil when no session is active (or none could be read).
    static func parse(_ output: String, now: Date = Date()) -> MediaState? {
        if case .session(let state) = read(output, now: now) { return state }
        return nil
    }

    /// Reads one sample. Android 13 and earlier print `PlaybackState {state=3, position=...}`; Android 14
    /// and later print `PlaybackState {state=PLAYING(3), position=...}`. Both are accepted, and each field
    /// is read on its own so added or reordered fields do not hide a session.
    static func read(_ output: String, now: Date = Date()) -> MediaRead {
        let lines = output.split(whereSeparator: { $0.isNewline }).map { String($0) }
        guard !lines.isEmpty else { return .none }

        // Device elapsedRealtime (ms) ~ /proc/uptime, used to extrapolate position.
        var uptimeMs: Int64?
        if let first = lines.first?.split(separator: " ").first, let seconds = Double(first) {
            uptimeMs = Int64(seconds * 1000)
        }

        // A session block starts with a "name package/Service (userId=N)" line followed by ownerPid=.
        var starts: [Int] = []
        for i in 0..<(lines.count - 1) {
            let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
            if next.hasPrefix("ownerPid="), lines[i].contains("(userId=") { starts.append(i) }
        }

        var best: MediaState?
        var unreadable = false
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            let block = lines[start..<end].joined(separator: "\n")

            guard let active = match(#"active=(true|false)"#, block), active[1] == "true",
                  let package = match(#"package=(\S+)"#, block)?[1]
            else { continue }
            guard let fields = playbackFields(in: block) else {
                if block.contains("PlaybackState {") { unreadable = true }
                continue
            }
            let state = fields.state
            guard [2, 3, 6].contains(state) else { continue }

            var position = fields.position
            let speed = fields.speed
            let updated = fields.updated
            let actions = fields.actions

            if state == 3, let uptimeMs, updated > 0, uptimeMs > updated {
                position += Int64(Double(uptimeMs - updated) * speed)
            }

            var title = ""
            if let md = match(#"metadata: size=\d+, description=([^\n]*)"#, block)?[1] {
                title = md.trimmingCharacters(in: .whitespaces)
                while title.hasSuffix(", null") { title = String(title.dropLast(6)) }
                if title == "null" { title = "" }
            }

            var candidate = MediaState(package: package, title: title, state: state,
                                       positionMs: position, speed: speed, sampledAt: now, actions: actions)
            candidate.deviceUptimeMs = uptimeMs
            if let md = match(#"metadata: size=\d+, description=([^\n]*)"#, block)?[1] {
                let parts = splitDescription(md)
                candidate.headline = parts.headline
                candidate.subtitle = parts.subtitle
            }
            // Sessions are listed by priority; prefer the first, but a playing one beats a paused one.
            if best == nil || (!best!.isPlaying && candidate.isPlaying) { best = candidate }
        }
        if let best { return .session(best) }
        return unreadable ? .unreadable : .none
    }

    /// The fields of the block's printed PlaybackState, or nil when there is none or its state cannot
    /// be read. Fields are matched one by one inside the braces (`buffered position` never counts as
    /// `position`).
    static func playbackFields(in block: String) -> PlaybackFields? {
        guard let body = match(#"PlaybackState \{([^}\n]*)"#, block)?[1],
              let stateText = match(#"(?:^|,\s*)state=(?:[A-Za-z_]+\()?(\d+)"#, body)?[1],
              let state = Int(stateText)
        else { return nil }
        func field(_ name: String, _ value: String) -> String? {
            match("(?:^|,\\s*)" + name + "=(" + value + ")", body)?[1]
        }
        return PlaybackFields(state: state,
                              position: field("position", "-?\\d+").flatMap { Int64($0) }.map { max(0, $0) } ?? 0,
                              speed: field("speed", "-?[0-9.]+(?:[eE][-+]?[0-9]+)?").flatMap { Double($0) } ?? 1,
                              updated: field("updated", "\\d+").flatMap { Int64($0) } ?? 0,
                              actions: field("actions", "\\d+").flatMap { Int64($0) } ?? 0)
    }

    /// Splits "title, subtitle, description". Needs the three-part shape to treat anything as a
    /// subtitle; otherwise the whole text is the headline. Titles containing ", " stay intact.
    static func splitDescription(_ raw: String) -> (headline: String, subtitle: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let parts = text.components(separatedBy: ", ")
        func clean(_ s: String) -> String { s == "null" ? "" : s.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return (clean(text), "") }
        let subtitle = clean(parts[parts.count - 2])
        let headline = clean(parts.dropLast(2).joined(separator: ", "))
        return (headline, subtitle)
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
        }
    }
}
