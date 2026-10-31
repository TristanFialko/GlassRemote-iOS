import SwiftUI

@main
struct GlassRemoteApp: App {
    @StateObject private var remote = RemoteModel()
    var body: some Scene {
        WindowGroup { RemoteView().environmentObject(remote).preferredColorScheme(.dark) }
    }
}
