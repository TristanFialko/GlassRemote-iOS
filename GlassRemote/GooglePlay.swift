import Foundation

/// Google Play support, limited to what is genuinely possible on the ARRIS VIP7802 / Android TV.
///
/// What this does:
/// - **Search**: opens Google Play's own search on the TV (`market://search?q=…&c=apps`), handled
///   by the Play Store app (`com.android.vending`) through one `am start` VIEW intent over the
///   existing ADB connection.
/// - **Open a listing**: opens `market://details?id=<package>` on the TV.
///
/// What this deliberately does NOT do:
/// - **In-app result lists.** Google Play has no public catalogue-search API. The only ways to
///   list results on the phone are scraping the Play website or an unofficial third-party
///   scraper. Both break without notice and may violate Google's terms, so neither is used.
/// - **Remote install.** There is no supported way to start an installation from outside the
///   Play Store app (installing needs the signed-in TV account and Play's own UI). The listing
///   opens on the TV and the person presses Install there.
///
/// Everything here is pure so it can be unit tested without a device. Nothing sends HOME / BACK /
/// playback keys, touches helpers, or runs during connection recovery.
enum GooglePlay {
    static let storePackage = "com.android.vending"
    static let exitMarker = "GLASSREMOTE_INTENT_EXIT"

    // MARK: Validation and links

    /// Trims, collapses whitespace and strips control characters. nil when it is not searchable.
    static func normalisedQuery(_ text: String) -> String? {
        let cleaned = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let collapsed = String(String.UnicodeScalarView(cleaned))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count >= 2, collapsed.count <= 80 else { return nil }
        return collapsed
    }

    /// Percent-encodes everything except unreserved characters, so the link can never contain a
    /// quote, `&`, `;`, `$` or space that would change meaning in the TV's shell.
    static func encode(_ query: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func searchLink(query: String) -> String? {
        guard let q = normalisedQuery(query) else { return nil }
        let encoded = encode(q)
        return encoded.isEmpty ? nil : "market://search?q=\(encoded)&c=apps"
    }

    /// Android application ids: dot-separated segments, each starting with a letter.
    static func isValidPackage(_ id: String) -> Bool {
        guard id.count <= 150 else { return false }
        return id.range(of: #"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$"#, options: .regularExpression) != nil
    }

    static func detailsLink(package: String) -> String? {
        isValidPackage(package) ? "market://details?id=\(package)" : nil
    }

    /// Official web address of a listing (used for "Share link"; never fetched or scraped).
    static func webURL(package: String) -> URL? {
        isValidPackage(package) ? URL(string: "https://play.google.com/store/apps/details?id=\(package)") : nil
    }

    /// The single shell command sent to the TV. `link` must come from `searchLink` / `detailsLink`.
    static func intentCommand(link: String) -> String {
        "am start -a android.intent.action.VIEW -d '\(link)' -p \(storePackage) 2>&1; rc=$?; echo \(exitMarker):$rc"
    }

    // MARK: Result

    enum Outcome: Equatable {
        case accepted            // Android accepted the intent
        case storeUnavailable    // Play Store not installed / nothing handles the link
        case rejected(String)    // Android refused it; text is what it said
    }

    /// Reads `am start` output without overclaiming: `.accepted` means Android accepted the
    /// request, not that the listing is on screen.
    static func outcome(from output: String) -> Outcome {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.contains("unable to resolve intent") || lower.contains("does not exist")
            || lower.contains("no activity found") || lower.contains("unknown package") {
            return .storeUnavailable
        }
        if text.contains("\(exitMarker):0"), !lower.contains("error") { return .accepted }
        let cleaned = text.replacingOccurrences(of: "\(exitMarker):[0-9]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .rejected(cleaned.isEmpty ? "No response from the TV box." : cleaned)
    }

    // MARK: Suggestions

    /// A hand-curated list of well-known Android TV apps. These are fixed package ids, not search
    /// results: the page labels them as suggestions, and a wrong id simply shows Play's own
    /// "not found" screen on the TV.
    struct Suggestion: Identifiable, Hashable {
        let name: String
        let package: String
        let symbol: String
        let blurb: String
        var id: String { package }
    }

    static let suggestions: [Suggestion] = [
        .init(name: "Netflix", package: "com.netflix.ninja", symbol: "play.rectangle.fill", blurb: "Streaming"),
        .init(name: "YouTube", package: "com.google.android.youtube.tv", symbol: "play.rectangle", blurb: "Video"),
        .init(name: "Disney+", package: "com.disney.disneyplus", symbol: "sparkles.tv", blurb: "Streaming"),
        .init(name: "Prime Video", package: "com.amazon.amazonvideo.livingroom", symbol: "play.tv", blurb: "Streaming"),
        .init(name: "Apple TV", package: "com.apple.atve.androidtv.appletv", symbol: "appletv", blurb: "Streaming"),
        .init(name: "Spotify", package: "com.spotify.tv.android", symbol: "music.note", blurb: "Music"),
        .init(name: "Plex", package: "com.plexapp.android", symbol: "externaldrive.connected.to.line.below", blurb: "Media server"),
        .init(name: "Jellyfin", package: "org.jellyfin.androidtv", symbol: "server.rack", blurb: "Media server"),
        .init(name: "Kodi", package: "org.xbmc.kodi", symbol: "play.square", blurb: "Media centre"),
        .init(name: "VLC", package: "org.videolan.vlc", symbol: "play.circle", blurb: "Player"),
        .init(name: "Stremio", package: "com.stremio.one", symbol: "film", blurb: "Discovery"),
        .init(name: "Twitch", package: "tv.twitch.android.app", symbol: "dot.radiowaves.left.and.right", blurb: "Live"),
        .init(name: "Crunchyroll", package: "com.crunchyroll.crunchyroid", symbol: "tv", blurb: "Anime"),
        .init(name: "Moonlight", package: "com.limelight", symbol: "gamecontroller", blurb: "Game streaming"),
        .init(name: "RetroArch", package: "com.retroarch", symbol: "gamecontroller.fill", blurb: "Emulation")
    ]

    /// Case-insensitive local match against the curated list (instant, offline).
    static func matches(_ query: String) -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return suggestions }
        return suggestions.filter { $0.name.lowercased().contains(q) || $0.blurb.lowercased().contains(q) }
    }
}

extension RemoteModel {
    /// Opens Google Play's search for `query` on the TV box. Returns what Android actually said.
    func openPlaySearch(_ query: String) async -> GooglePlay.Outcome? {
        guard let link = GooglePlay.searchLink(query: query) else { return nil }
        return await sendPlayIntent(link, note: "search")
    }

    /// Opens the Play listing for `package` on the TV box.
    func openPlayListing(package: String) async -> GooglePlay.Outcome? {
        guard let link = GooglePlay.detailsLink(package: package) else { return nil }
        return await sendPlayIntent(link, note: "listing \(package)")
    }

    private func sendPlayIntent(_ link: String, note: String) async -> GooglePlay.Outcome {
        guard connected, let adb else { return .rejected("Not connected to the TV box.") }
        do {
            let output = try await runShell(adb, ["sh", "-c", GooglePlay.intentCommand(link: link)])
            GRLog.note("play", "user-initiated Play \(note)")
            return GooglePlay.outcome(from: output)
        } catch {
            return .rejected("Couldn't send: \(error.localizedDescription)")
        }
    }
}
