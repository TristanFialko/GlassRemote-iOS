import AppIntents

// Siri / Shortcuts. These run inside the app (openAppWhenRun) because the ADB connection
// lives in the app process and cannot be reached from a background intent. Foreground-only
// behaviour and Siri phrases need on-device testing.

enum TVAppChoice: String, AppEnum {
    case netflix, youtube, stremio, retroarch, primeVideo, disney, sunshine, spotify, rhenium

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TV App"

    static let caseDisplayRepresentations: [TVAppChoice: DisplayRepresentation] = [
        .netflix: "Netflix", .youtube: "YouTube", .stremio: "Stremio", .retroarch: "RetroArch",
        .primeVideo: "Prime Video", .disney: "Disney+", .sunshine: "Sunshine", .spotify: "Spotify",
        .rhenium: "Rhenium"
    ]

    var assetName: String {
        switch self {
        case .primeVideo: return "prime-video"
        case .sunshine: return "moonlight"
        case .disney: return "disney"
        default: return rawValue
        }
    }
}

struct LaunchTVAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open TV App"
    static let description = IntentDescription("Opens one of your TV apps on the Android TV box.")
    static let openAppWhenRun = true

    @Parameter(title: "App") var app: TVAppChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = RemoteModel.shared
        guard await model.waitUntilConnected(timeout: 20) else { return .result() }
        if let tvApp = model.apps.first(where: { $0.asset == app.assetName }) {
            await model.launchApp(tvApp)
        }
        return .result()
    }
}

/// A Quick Action as Shortcuts / Siri sees it, so the app offers a picker instead of free text.
struct QuickActionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quick Action"
    static let defaultQuery = QuickActionEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct QuickActionEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [QuickActionEntity] {
        QuickActionStore.shared.actions
            .filter { identifiers.contains($0.id.uuidString) }
            .map { QuickActionEntity(id: $0.id.uuidString, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [QuickActionEntity] {
        QuickActionStore.shared.actions.map { QuickActionEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct RunQuickActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Quick Action"
    static let description = IntentDescription("Runs one of your Glass Remote Quick Actions.")
    static let openAppWhenRun = true

    @Parameter(title: "Quick Action") var action: QuickActionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = RemoteModel.shared
        guard await model.waitUntilConnected(timeout: 20) else { return .result() }
        if let match = QuickActionStore.shared.actions.first(where: { $0.id.uuidString == action.id }) {
            model.runQuickAction(match)
        } else {
            model.status = "That Quick Action no longer exists"
        }
        return .result()
    }
}

struct GlassRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LaunchTVAppIntent(),
            phrases: ["Open \(\.$app) with \(.applicationName)"],
            shortTitle: "Open TV App",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: RunQuickActionIntent(),
            phrases: ["Run \(\.$action) in \(.applicationName)", "Run a Quick Action in \(.applicationName)"],
            shortTitle: "Run Quick Action",
            systemImageName: "bolt.fill"
        )
    }
}
