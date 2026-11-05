import Foundation

/// One step of a Quick Action macro. Only whitelisted remote keys can be used.
struct QuickActionStep: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case launch   // launch one of the nine apps (`package`)
        case key      // whitelisted remote key (`key`)
        case delay    // wait `seconds`
        case volume   // `key` is VOLUME_UP or VOLUME_DOWN, repeated `count` times
    }

    var id = UUID()
    var kind: Kind
    var package = ""
    var key = "HOME"
    var seconds = 1.0
    var count = 1

    static func launch(_ package: String) -> QuickActionStep { .init(kind: .launch, package: package) }
    static func key(_ key: String) -> QuickActionStep { .init(kind: .key, key: key) }
    static func delay(_ seconds: Double) -> QuickActionStep { .init(kind: .delay, seconds: seconds) }
    static func volume(_ key: String, count: Int) -> QuickActionStep { .init(kind: .volume, key: key, count: count) }
}

struct QuickAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var steps: [QuickActionStep]

    /// Short human-readable description of the steps (for the editor list).
    func summary(appName: (String) -> String) -> String {
        steps.map { step in
            switch step.kind {
            case .launch: return "Open \(appName(step.package))"
            case .key: return QuickActionStore.keyTitles[step.key] ?? step.key
            case .delay: return "Wait \(String(format: "%g", step.seconds))s"
            case .volume: return (step.key == "VOLUME_UP" ? "Vol +" : "Vol −") + " ×\(step.count)"
            }
        }.joined(separator: " → ")
    }
}

/// Local-only storage for Quick Actions (UserDefaults, JSON). Nothing leaves the phone.
@MainActor
final class QuickActionStore: ObservableObject {
    static let shared = QuickActionStore()

    /// Keys a macro may press. Volume is a separate step kind; power keys are never allowed.
    static let allowedKeys = ["HOME", "BACK", "UP", "DOWN", "LEFT", "RIGHT", "OK", "MUTE", "TV_SOURCE"]
    static let keyTitles: [String: String] = [
        "HOME": "Home", "BACK": "Back", "UP": "Up", "DOWN": "Down",
        "LEFT": "Left", "RIGHT": "Right", "OK": "Select", "MUTE": "Mute", "TV_SOURCE": "TV input menu"
    ]

    /// Keys that used to be allowed and no longer exist on the remote. A saved action that still
    /// contains one is migrated rather than left to fail silently.
    nonisolated static let deprecatedKeys: Set<String> = ["MENU"]

    private let defaultsKey = "glassRemote.quickActions.v1"

    @Published var actions: [QuickAction] {
        didSet { persist() }
    }

    /// Set when a saved action contained a removed key. Shown once in the Quick Action editor.
    @Published var migrationNotice: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([QuickAction].self, from: data) {
            let result = Self.migrate(saved)
            actions = result.actions
            if !result.affected.isEmpty {
                migrationNotice = Self.notice(for: result.affected)
                persist()   // `didSet` does not run for assignments made inside `init`
            }
        } else {
            actions = Self.defaults
        }
    }

    /// Pure migration (unit tested). The removed Android Menu key steps are dropped from every
    /// action; the rest of each action is kept exactly as saved. Returns the names of the actions
    /// that changed so the user can be told. An action is never deleted, even if it ends up empty.
    nonisolated static func migrate(_ saved: [QuickAction]) -> (actions: [QuickAction], affected: [String]) {
        var affected: [String] = []
        let migrated = saved.map { action -> QuickAction in
            let kept = action.steps.filter { !($0.kind == .key && deprecatedKeys.contains($0.key)) }
            guard kept.count != action.steps.count else { return action }
            var copy = action
            copy.steps = kept
            affected.append(action.name)
            return copy
        }
        return (migrated, affected)
    }

    nonisolated static func notice(for names: [String]) -> String {
        let list = names.joined(separator: ", ")
        return "The Android Menu key was removed from the remote, so its step was taken out of: \(list). Check that \(names.count == 1 ? "it still does" : "they still do") what you expect."
    }

    /// Starter examples. Edit or delete them freely; they are ordinary Quick Actions.
    static let defaults: [QuickAction] = [
        QuickAction(name: "Movie Night", steps: [.key("HOME"), .delay(1.0), .launch("com.stremio.one")]),
        QuickAction(name: "Music", steps: [.launch("com.spotify.tv.android")]),
        QuickAction(name: "TV Home", steps: [.key("HOME")])
    ]

    func add() -> QuickAction {
        let action = QuickAction(name: "New Action", steps: [.key("HOME")])
        actions.append(action)
        return action
    }

    func find(named name: String) -> QuickAction? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return actions.first { $0.name.lowercased() == wanted }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
