import SwiftUI

@main
struct GlassRemoteApp: App {
    // One shared model so Shortcuts / Siri intents use the same ADB connection as the UI.
    @StateObject private var remote = RemoteModel.shared

    var body: some Scene {
        WindowGroup {
            RootPagerView()
                .environmentObject(remote)
                .task {
                    // Decode app artwork once, off the main thread, so the Apps grid opens instantly.
                    AppIconCache.shared.prewarm(remote.apps.map { "\($0.asset)_dark" } + ["stremio_nowplaying"])
                }
                .preferredColorScheme(.dark)   // permanent Dark Mode
        }
    }
}
