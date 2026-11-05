import Foundation

// Experimental Stremio launching. Nothing here runs unless the user turns on the
// "deep link test" switch in Discover AND taps Open. It sends one `am start` VIEW intent for a
// stremio:// detail link. It does not touch helpers, HID devices or recovery, and sends no
// HOME / BACK / PAUSE / STOP.
//
// UNVERIFIED: whether the Stremio build on this box (com.stremio.one) handles
// `stremio:///detail/<type>/<id>` is not confirmed. The result line reports what Android said.

extension RemoteModel {
    nonisolated static let stremioPackage = "com.stremio.one"
    nonisolated static let deepLinkDefaultsKey = "glassRemote.stremioDeepLinkTest"

    /// Strict validation so nothing arbitrary can reach the shell.
    nonisolated static func stremioDetailLink(kind: StremioTitle.Kind, id: String) -> String? {
        guard id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil else { return nil }
        // Documented form: stremio:///detail/{type}/{id}/{videoId}. For a movie the videoId is the id;
        // for a series no episode is chosen, so the show page opens.
        return kind == .movie ? "stremio:///detail/movie/\(id)/\(id)" : "stremio:///detail/series/\(id)"
    }

    nonisolated static func stremioIntentCommand(link: String) -> String {
        "am start -a android.intent.action.VIEW -d '\(link)' -p \(stremioPackage) 2>&1; rc=$?; echo GLASSREMOTE_INTENT_EXIT:$rc"
    }

    /// Returns a short human-readable result.
    @discardableResult
    func openInStremio(_ title: StremioTitle) async -> String {
        guard let link = Self.stremioDetailLink(kind: title.kind, id: title.id) else { return "This title has no usable Stremio id." }
        guard connected, let adb else { return "Not connected to the TV box." }
        do {
            let out = try await runShell(adb, ["sh", "-c", Self.stremioIntentCommand(link: link)])
            GRLog.note("stremio", "user-initiated deep link for \(title.id)")
            if out.contains("GLASSREMOTE_INTENT_EXIT:0"), !out.localizedCaseInsensitiveContains("error") {
                return "Sent to Stremio. If nothing opened, this build may not support detail links."
            }
            return "Stremio didn't accept the link: \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            return "Couldn't send: \(error.localizedDescription)"
        }
    }
}
