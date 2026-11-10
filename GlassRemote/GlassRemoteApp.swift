import SwiftUI

@main
struct GlassRemoteApp: App {
    @StateObject private var remote = RemoteModel.shared

    var body: some Scene {
        WindowGroup {
            RootPagerView()
                .environmentObject(remote)
                .preferredColorScheme(.dark)
        }
    }
}
