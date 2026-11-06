import SwiftUI

@main
struct GlassRemoteApp: App {
    // One shared model so Shortcuts / Siri intents use the same ADB connection as the UI.
    @StateObject private var remote = RemoteModel.shared

    var body: some Scene {
        WindowGroup {
            // The models live above ThemedRoot, so changing theme restyles views only: it can never
            // recreate RemoteModel or touch ADB, helpers or playback state.
            ThemedRoot {
                RootPagerView()
                    .environmentObject(remote)
                    .task {
                        // Decode app artwork once, off the main thread, so the Apps grid opens instantly.
                        AppIconCache.shared.prewarm(remote.apps.map { "\($0.asset)_dark" } + ["stremio_nowplaying"])
                    }
            }
        }
    }
}
