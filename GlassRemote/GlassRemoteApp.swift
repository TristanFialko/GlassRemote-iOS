import SwiftUI

@main
struct GlassRemoteApp: App {
    // One shared model so Shortcuts / Siri intents use the same ADB connection as the UI.
    @StateObject private var remote = RemoteModel.shared

    var body: some Scene {
        WindowGroup {
            RemoteView()
                .environmentObject(remote)
                .preferredColorScheme(.dark)   // permanent Dark Mode
        }
    }
}
