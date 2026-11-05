import Foundation

// Opens Stremio on the TV box with documented `stremio://` deep links
// (https://stremio.github.io/stremio-addon-sdk/deep-links.html):
//   stremio:///detail/{type}/{id}/{videoId}?autoPlay={bool}
//   stremio:///search?search={query}
// Each action sends one `am start` VIEW intent and reports what Android answered. It does not touch
// the helpers, HID devices or recovery, and sends no HOME / BACK / PAUSE / STOP. The link formats
// come from Stremio's documentation; their behaviour on THIS box's Stremio build is unconfirmed
// until tried on the device, so the result line never claims more than "Android accepted the intent".

extension RemoteModel {
    nonisolated static let stremioPackage = "com.stremio.one"

    nonisolated static func isIMDbID(_ id: String) -> Bool {
        id.range(of: #"^tt[0-9]{5,10}$"#, options: .regularExpression) != nil
    }

    /// Strict validation so nothing arbitrary can reach the shell.
    nonisolated static func stremioDetailLink(kind: StremioTitle.Kind, id: String, videoID: String? = nil, autoPlay: Bool = false) -> String? {
        guard isIMDbID(id) else { return nil }
        var path: String
        switch kind {
        case .movie: path = "stremio:///detail/movie/\(id)/\(id)"
        case .series:
            if let videoID {
                guard videoID.range(of: #"^tt[0-9]{5,10}:[0-9]{1,3}:[0-9]{1,4}$"#, options: .regularExpression) != nil,
                      videoID.hasPrefix(id + ":") else { return nil }
                path = "stremio:///detail/series/\(id)/\(videoID)"
            } else {
                path = "stremio:///detail/series/\(id)"
            }
        }
        if autoPlay { path += "?autoPlay=true" }
        return path
    }

    nonisolated static func stremioSearchLink(query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 80 else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "stremio:///search?search=\(encoded)"
    }

    nonisolated static func stremioIntentCommand(link: String) -> String {
        "am start -a android.intent.action.VIEW -d '\(link)' -p \(stremioPackage) 2>&1; rc=$?; echo GLASSREMOTE_INTENT_EXIT:$rc"
    }

    nonisolated static func intentAccepted(_ output: String) -> Bool {
        output.contains("GLASSREMOTE_INTENT_EXIT:0") && !output.localizedCaseInsensitiveContains("error")
    }

    @discardableResult
    func openInStremio(_ title: StremioTitle, videoID: String? = nil, autoPlay: Bool = false) async -> String {
        guard let link = Self.stremioDetailLink(kind: title.kind, id: title.id, videoID: videoID, autoPlay: autoPlay) else {
            return "This title has no Stremio-openable id."
        }
        PlayerArtworkStore.shared.remember(title: title.name, posterURL: title.posterURL)
        return await sendStremioLink(link, note: "detail \(title.id)")
    }

    @discardableResult
    func searchInStremio(_ query: String) async -> String {
        guard let link = Self.stremioSearchLink(query: query) else { return "Type at least two characters to search in Stremio." }
        return await sendStremioLink(link, note: "search")
    }

    private func sendStremioLink(_ link: String, note: String) async -> String {
        guard connected, let adb else { return "Not connected to the TV box." }
        do {
            let out = try await runShell(adb, ["sh", "-c", Self.stremioIntentCommand(link: link)])
            GRLog.note("stremio", "user-initiated deep link (\(note))")
            if Self.intentAccepted(out) { return "Sent to Stremio on the TV box." }
            return "Stremio didn't accept the link: \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            return "Couldn't send: \(error.localizedDescription)"
        }
    }
}
