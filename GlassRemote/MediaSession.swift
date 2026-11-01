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

    static let idle = MediaState(package: "", title: "", state: 0, positionMs: 0, speed: 1, sampledAt: .distantPast, actions: 0)

    var isActive: Bool { !package.isEmpty }
    var isPlaying: Bool { state == 3 || state == 6 }

    // PlaybackState action bits
    var canPlayPause: Bool { actions & (2 | 4 | 512) != 0 }
    var canPrevious: Bool { actions & 16 != 0 }
    var canNext: Bool { actions & 32 != 0 }
    var canRewind: Bool { actions & 8 != 0 }
    var canFastForward: Bool { actions & 64 != 0 }
    /// ACTION_SEEK_TO is advertised, but Android offers no ADB route to invoke it with an arbitrary position.
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

enum MediaParser {
    /// `output` is `cat /proc/uptime` followed by `dumpsys media_session`.
    /// Returns nil when no session is active.
    static func parse(_ output: String, now: Date = Date()) -> MediaState? {
        let lines = output.split(whereSeparator: { $0.isNewline }).map { String($0) }
        guard !lines.isEmpty else { return nil }

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
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            let block = lines[start..<end].joined(separator: "\n")

            guard let active = match(#"active=(true|false)"#, block), active[1] == "true",
                  let package = match(#"package=(\S+)"#, block)?[1],
                  let st = match(#"PlaybackState \{state=(\d+), position=(\d+), buffered position=\d+, speed=([-0-9.]+), updated=(\d+), actions=(\d+)"#, block),
                  let state = Int(st[1]), [2, 3, 6].contains(state)
            else { continue }

            var position = Int64(st[2]) ?? 0
            let speed = Double(st[3]) ?? 1
            let updated = Int64(st[4]) ?? 0
            let actions = Int64(st[5]) ?? 0

            if state == 3, let uptimeMs, updated > 0, uptimeMs > updated {
                position += Int64(Double(uptimeMs - updated) * speed)
            }

            var title = ""
            if let md = match(#"metadata: size=\d+, description=([^\n]*)"#, block)?[1] {
                title = md.trimmingCharacters(in: .whitespaces)
                while title.hasSuffix(", null") { title = String(title.dropLast(6)) }
                if title == "null" { title = "" }
            }

            let candidate = MediaState(package: package, title: title, state: state,
                                       positionMs: position, speed: speed, sampledAt: now, actions: actions)
            // Sessions are listed by priority; prefer the first, but a playing one beats a paused one.
            if best == nil || (!best!.isPlaying && candidate.isPlaying) { best = candidate }
        }
        return best
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
