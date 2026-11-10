import Foundation

enum AddonURLProblem: Error, Equatable, LocalizedError {
    case empty
    case malformed
    case insecure
    case credentials

    var errorDescription: String? {
        switch self {
        case .empty: return "Paste an add-on link first."
        case .malformed: return "That doesn't look like an add-on link. It usually ends in /manifest.json."
        case .insecure: return "Add-ons must use https. Plain http is only allowed on your local network."
        case .credentials: return "Links with a user name or password in them aren't accepted. Use the add-on's configured link instead."
        }
    }
}

/// Manifest URL handling, following the Stremio conventions: `stremio://` is `https://`, the
/// manifest lives at `{base}/manifest.json` and resources at `{base}/{resource}/{type}/{id}.json`.
enum AddonURL {
    static func normalise(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AddonURLProblem.empty }
        let lower = text.lowercased()
        if lower.hasPrefix("stremio://") {
            text = "https://" + String(text.dropFirst("stremio://".count))
        } else if !lower.hasPrefix("https://") && !lower.hasPrefix("http://") {
            if lower.contains("://") { throw AddonURLProblem.malformed }
            text = "https://" + text
        }
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty,
              host.contains(".") || isLocal(host) else { throw AddonURLProblem.malformed }
        if parts.user != nil || parts.password != nil { throw AddonURLProblem.credentials }
        if scheme == "http" && !isLocal(host) { throw AddonURLProblem.insecure }
        parts.scheme = scheme
        parts.fragment = nil
        var path = parts.percentEncodedPath
        if !path.hasSuffix("/manifest.json") {
            path += path.hasSuffix("/") ? "manifest.json" : "/manifest.json"
        }
        parts.percentEncodedPath = path
        guard let url = parts.url else { throw AddonURLProblem.malformed }
        return url
    }

    /// Hosts where plain http is acceptable: this device and private LAN ranges.
    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") { return true }
        let pieces = h.split(separator: ".")
        let octets = pieces.compactMap { Int($0) }
        guard pieces.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168): return true
        case (172, let b): return (16...31).contains(b)
        default: return false
        }
    }

    /// The add-on's base (transport) URL: the manifest URL without `/manifest.json` or a query.
    static func base(of manifest: URL) -> URL? {
        guard var parts = URLComponents(url: manifest, resolvingAgainstBaseURL: false) else { return nil }
        parts.query = nil
        parts.fragment = nil
        var path = parts.percentEncodedPath
        if path.hasSuffix("/manifest.json") { path.removeLast("/manifest.json".count) }
        parts.percentEncodedPath = path
        return parts.url
    }

    static func resource(_ resource: String, type: String, id: String, base: URL) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~:"))
        guard let t = type.addingPercentEncoding(withAllowedCharacters: allowed),
              let i = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: "\(root)/\(resource)/\(t)/\(i).json")
    }

    /// Stremio's configuration page for configurable add-ons.
    static func configure(base: URL) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + "/configure")
    }

    /// What the UI shows. Configured links often carry a personal token in the path, so only the
    /// host is shown, with an ellipsis when there is more.
    static func display(_ url: URL) -> String {
        let host = url.host ?? "add-on"
        let segments = url.path.split(separator: "/").filter { $0 != "manifest.json" }
        return segments.isEmpty ? host : host + "/\u{2026}"
    }
}
