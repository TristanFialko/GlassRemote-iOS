import Foundation

/// What the box reports as focused / resumed. Parsed from `dumpsys` text; pure and unit tested.
struct RecentsSnapshot: Equatable {
    var window: String      // mCurrentFocus line
    var activity: String    // topResumedActivity / mResumedActivity line(s)
    var isEmpty: Bool { window.isEmpty && activity.isEmpty }
    var combined: String { window + " " + activity }
}

/// Result of pressing KEYCODE_APP_SWITCH. Deliberately four-way: a changed window is NOT proof
/// that a Recents screen opened.
enum RecentsOutcome: Equatable {
    case opened               // the focused / resumed activity now names a Recents screen
    case unchanged            // nothing changed: the launcher ignored the key
    case changedUnrecognised  // something changed but it isn't recognisably Recents: unknown
    case unknown              // the probe returned nothing, so no claim either way
}

enum RecentsProbe {
    /// One shell round trip: focused window, then the resumed activity (Android 10+ names).
    static let command = "dumpsys window | grep -m1 mCurrentFocus; echo '---'; dumpsys activity activities | grep -m2 -E 'topResumedActivity|mResumedActivity'"

    static func parse(_ output: String) -> RecentsSnapshot {
        let parts = output.components(separatedBy: "---")
        let window = (parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = (parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
        return RecentsSnapshot(window: window, activity: activity)
    }

    /// Class / package names AOSP and TV launchers use for the overview screen.
    static func looksLikeRecents(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["recents", "recentapps", "recentapplications", "overview"].contains { t.contains($0) }
    }

    static func outcome(before: RecentsSnapshot, after: RecentsSnapshot) -> RecentsOutcome {
        if before.isEmpty || after.isEmpty { return .unknown }
        if looksLikeRecents(after.combined), !looksLikeRecents(before.combined) { return .opened }
        if before == after { return .unchanged }
        return .changedUnrecognised
    }
}
