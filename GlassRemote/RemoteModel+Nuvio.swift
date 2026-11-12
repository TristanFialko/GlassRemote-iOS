import Foundation

// Opens Nuvio on the TV box.
//
// What is VERIFIED: Nuvio TV's Continue Watching launcher channel starts MainActivity with intent
// extras `contentId` / `contentType` (from the project's own feature request #2235, which also says
// there is no public documented deep-link contract). What is NOT verified: that `nuvio://detail/{type}/{id}`
// or `nuvio://search?q=` are handled by the build installed on the box (#2235 proposes them; a third
// party reports `nuvio://movie|series/<imdb id>` works) and that the activity is exported to the ADB
// shell. So each action sends ONE VIEW intent restricted to Nuvio's package and reports exactly what
// Android answered. If Android refuses it, Nuvio is simply launched and the result line says so; the
// app never claims the title opened. No deep link auto-starts playback (the proposal excludes it).
// Nothing here touches helpers, HID devices or recovery, and sends no HOME / BACK / PAUSE / STOP.

extension RemoteModel {
    nonisolated static let nuvioPackage = "com.nuvio.app"
    /// Media sessions from Nuvio (including debug/other flavours) use this package prefix.
    nonisolated static let nuvioPackagePrefix = "com.nuvio."

    nonisolated static func isIMDbID(_ id: String) -> Bool {
        id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil
    }

    /// Strict validation so nothing arbitrary can reach the shell.
    nonisolated static func nuvioDetailLink(kind: MediaTitle.Kind, id: String) -> String? {
        guard isIMDbID(id) else { return nil }
        return "nuvio://detail/\(kind.rawValue)/\(id)"
    }

    nonisolated static func nuvioSearchLink(query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 80 else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "nuvio://search?q=\(encoded)"
    }

    nonisolated static func nuvioIntentCommand(link: String) -> String {
        "am start -a android.intent.action.VIEW -d '\(link)' -p \(nuvioPackage) 2>&1; rc=$?; echo GLASSREMOTE_INTENT_EXIT:$rc"
    }

    nonisolated static func intentAccepted(_ output: String) -> Bool {
        output.contains("GLASSREMOTE_INTENT_EXIT:0") && !intentReportedFailure(output)
    }

    /// `am start` echoes the intent (link included, e.g. `q=terror`) on its "Starting:" line, so only
    /// the lines `am` uses to report a failure count, never a substring of the echoed data.
    nonisolated static func intentReportedFailure(_ output: String) -> Bool {
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Starting:") { continue }
            if line.hasPrefix("Error:") || line.hasPrefix("Error type") || line.hasPrefix("Permission Denial") { return true }
            if line.contains("unable to resolve Intent") || line.contains("Exception") { return true }
        }
        return false
    }

    @discardableResult
    func openInNuvio(_ title: MediaTitle) async -> String {
        await openInNuvioResult(title).message
    }

    func openInNuvioResult(_ title: MediaTitle) async -> HandoffResult {
        guard let link = Self.nuvioDetailLink(kind: title.kind, id: title.id) else {
            return .failed("This title has no Nuvio-openable id.")
        }
        PlayerArtworkStore.shared.remember(title: title.name, posterURL: title.posterURL, landscapeURL: title.backgroundURL)
        return await sendNuvioLink(link, note: "detail \(title.id)")
    }

    @discardableResult
    func searchInNuvio(_ query: String) async -> String {
        await searchInNuvioResult(query).message
    }

    func searchInNuvioResult(_ query: String) async -> HandoffResult {
        guard let link = Self.nuvioSearchLink(query: query) else { return .failed("Type at least two characters to search in Nuvio.") }
        return await sendNuvioLink(link, note: "search")
    }

    private func sendNuvioLink(_ link: String, note: String) async -> HandoffResult {
        guard connected, let adb else { return .failed("Not connected to the TV box.") }
        do {
            let out = try await runShell(adb, ["sh", "-c", Self.nuvioIntentCommand(link: link)])
            GRLog.note("nuvio", "user-initiated link (\(note))")
            if Self.intentAccepted(out) {
                return HandoffResult(message: "Sent to Nuvio on the TV box. Android accepted the link; it doesn't confirm what Nuvio shows.",
                                     succeeded: true)
            }
            // Link not handled or not exported: open Nuvio itself so the tap isn't wasted. Nuvio is then on
            // screen, so continuing with the remote still makes sense.
            if let app = apps.first(where: { $0.package == Self.nuvioPackage }), await launchApp(app) {
                return HandoffResult(message: "This Nuvio build didn't accept the link, so Nuvio was opened instead.", succeeded: true)
            }
            return .failed("Nuvio didn't accept the link: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            return .failed("Couldn't send: \(error.localizedDescription)")
        }
    }
}
