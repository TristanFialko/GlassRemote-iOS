import Foundation

// Phase 7 playback handoff.
//
// Research (NuvioMedia/NuvioTV source: app/src/main/AndroidManifest.xml and
// core/deeplink/DeepLinkParser.kt): MainActivity is exported with VIEW/BROWSABLE intent filters for
// the `nuvio` and `stremio` schemes only. `nuvio://detail|watch/{type}/{id}` opens a title's detail
// screen ("watch" does not start playback), and `stremio://<host>/manifest.json` opens Nuvio's add-on
// install flow. There is no filter for http(s) or video/* and no extra that carries a stream URL, so a
// specific stream CANNOT be handed to Nuvio. GlassRemote therefore offers:
//   * Open in Nuvio (existing `openInNuvio`): title-level handoff; Nuvio's own sources play it.
//   * Direct http(s) streams from the profile's add-ons: a generic Android VIEW intent with a video
//     MIME type, which opens the TV's default video player (or Android's chooser).
//   * Install in Nuvio: the add-on's `stremio://` link, so Nuvio on the TV gets the same add-on.
// Every path returns a user-facing result line; nothing fails silently. Stream URLs are never logged
// or shown (configured add-ons put personal tokens in them). Nothing here touches helpers or HID.
extension RemoteModel {
    nonisolated static let handoffSchemes: Set<String> = ["https", "http"]

    /// The URL text if it is safe to place inside single quotes in an `am start` command.
    nonisolated static func shellSafeURL(_ url: URL, schemes: Set<String> = handoffSchemes) -> String? {
        let text = url.absoluteString
        guard text.count <= 4096, let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        let forbidden = CharacterSet(charactersIn: "'\"`\\").union(.whitespacesAndNewlines).union(.controlCharacters)
        guard text.rangeOfCharacter(from: forbidden) == nil else { return nil }
        return text
    }

    /// No package: Android picks the TV's default video player, or shows its chooser.
    nonisolated static func videoIntentCommand(url: String) -> String {
        "am start -a android.intent.action.VIEW -d '\(url)' -t 'video/*' 2>&1; rc=$?; echo GLASSREMOTE_INTENT_EXIT:$rc"
    }

    nonisolated static func viewIntentCommand(url: String) -> String {
        "am start -a android.intent.action.VIEW -d '\(url)' 2>&1; rc=$?; echo GLASSREMOTE_INTENT_EXIT:$rc"
    }

    /// Nuvio's DeepLinkParser maps `stremio://<host>/...` to an https add-on install.
    nonisolated static func nuvioAddonInstallLink(manifestURL: URL) -> String? {
        guard manifestURL.scheme?.lowercased() == "https",
              let safe = shellSafeURL(manifestURL, schemes: ["https"]) else { return nil }
        return "stremio://" + String(safe.dropFirst("https://".count))
    }

    nonisolated static func youTubeURL(id: String) -> URL? {
        guard id.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    /// Sends one add-on stream to the TV box.
    func playOnTV(_ stream: AddonStream) async -> String {
        await playOnTVResult(stream).message
    }

    func playOnTVResult(_ stream: AddonStream) async -> HandoffResult {
        switch stream.kind {
        case .direct(let url):
            if stream.behaviorHints?.needsHeaders == true {
                return .failed("This stream needs request headers that can't be passed to the TV. Pick another stream or use Open in Nuvio.")
            }
            guard let safe = Self.shellSafeURL(url) else { return .failed("This stream's address can't be sent safely. Pick another stream.") }
            return await runIntent(Self.videoIntentCommand(url: safe),
                                   success: "Sent to the TV's video player. Android accepted it; the player decides whether the stream plays.",
                                   note: "stream")
        case .external(let url):
            guard let safe = Self.shellSafeURL(url) else { return .failed("This link can't be sent safely.") }
            return await runIntent(Self.viewIntentCommand(url: safe), success: "Opened the link on the TV.", note: "external")
        case .youtube(let id):
            return await youTubeResult(id: id)
        case .torrent:
            return .failed("Torrent streams can't be sent from GlassRemote. Use Open in Nuvio: if this add-on is installed in Nuvio as well, Nuvio can play it.")
        case .unsupported:
            return .failed("This stream has no address the TV can open.")
        }
    }

    /// Trailers: YouTube ids open in the TV's YouTube app (VIEW on the watch URL).
    func playYouTube(id: String) async -> String {
        await youTubeResult(id: id).message
    }

    private func youTubeResult(id: String) async -> HandoffResult {
        guard let url = Self.youTubeURL(id: id), let safe = Self.shellSafeURL(url, schemes: ["https"]) else {
            return .failed("This trailer id isn't valid.")
        }
        return await runIntent(Self.viewIntentCommand(url: safe), success: "Playing the trailer on the TV.", note: "trailer")
    }

    func installAddonInNuvio(manifestURL: URL) async -> String {
        guard let link = Self.nuvioAddonInstallLink(manifestURL: manifestURL) else {
            return "Only https add-ons can be sent to Nuvio."
        }
        return await runIntent(Self.nuvioIntentCommand(link: link),
                               success: "Sent to Nuvio on the TV. Confirm the install there.",
                               note: "addon install").message
    }

    private func runIntent(_ command: String, success: String, note: String) async -> HandoffResult {
        guard connected, let adb else { return .failed("Not connected to the TV box. Connect it in Profile > TV Connections.") }
        do {
            let out = try await runShell(adb, ["sh", "-c", command])
            GRLog.note("handoff", "user-initiated \(note)")
            if Self.intentAccepted(out) { return HandoffResult(message: success, succeeded: true) }
            if out.localizedCaseInsensitiveContains("unable to resolve") || out.localizedCaseInsensitiveContains("no activity") {
                return .failed("The TV has no app that can open this.")
            }
            if out.localizedCaseInsensitiveContains("permission denial") {
                return .failed("Android on the TV refused the request.")
            }
            return .failed("The TV didn't accept the request.")
        } catch {
            return .failed("Couldn't send: \(error.localizedDescription)")
        }
    }
}

/// What a handoff to the TV produced: the user-facing line, and whether Android accepted it, so the UI
/// only offers "Continue on the TV" after a handoff that went through.
struct HandoffResult: Equatable, Sendable {
    let message: String
    let succeeded: Bool

    static func failed(_ message: String) -> HandoffResult { HandoffResult(message: message, succeeded: false) }
}
