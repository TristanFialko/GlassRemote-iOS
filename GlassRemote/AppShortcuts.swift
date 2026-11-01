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

struct RunQuickActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Quick Action"
    static let description = IntentDescription("Runs one of your Glass Remote Quick Actions by name.")
    static let openAppWhenRun = true

    @Parameter(title: "Quick Action name") var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = RemoteModel.shared
        guard await model.waitUntilConnected(timeout: 20) else { return .result() }
        model.runQuickAction(named: name)
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
            phrases: ["Run a Quick Action in \(.applicationName)"],
            shortTitle: "Run Quick Action",
            systemImageName: "bolt.fill"
        )
    }
}
