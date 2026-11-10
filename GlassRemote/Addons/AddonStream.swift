import Foundation

/// One stream from an add-on's `stream` resource
/// (https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md).
struct AddonStream: Decodable, Hashable, Sendable {
    struct Hints: Decodable, Hashable, Sendable {
        var notWebReady: Bool?
        var bingeGroup: String?
        var filename: String?
        var videoSize: Double?
        /// The stream only plays with custom HTTP headers (`proxyHeaders`). Android's generic video
        /// intent can't carry headers, so these streams are not sent to the TV.
        var needsHeaders = false

        init(notWebReady: Bool? = nil, bingeGroup: String? = nil, filename: String? = nil,
             videoSize: Double? = nil, needsHeaders: Bool = false) {
            self.notWebReady = notWebReady
            self.bingeGroup = bingeGroup
            self.filename = filename
            self.videoSize = videoSize
            self.needsHeaders = needsHeaders
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            notWebReady = try? c.decodeIfPresent(Bool.self, forKey: .notWebReady)
            bingeGroup = try? c.decodeIfPresent(String.self, forKey: .bingeGroup)
            filename = try? c.decodeIfPresent(String.self, forKey: .filename)
            videoSize = try? c.decodeIfPresent(Double.self, forKey: .videoSize)
            needsHeaders = c.contains(.proxyHeaders)
        }

        private enum CodingKeys: String, CodingKey { case notWebReady, bingeGroup, filename, videoSize, proxyHeaders }
    }

    enum Kind: Equatable {
        case direct(URL)
        case external(URL)
        case youtube(String)
        case torrent
        case unsupported
    }

    var name: String?
    var title: String?
    var description: String?
    var url: String?
    var ytId: String?
    var infoHash: String?
    var fileIdx: Int?
    var externalUrl: String?
    var behaviorHints: Hints?

    var kind: Kind {
        if let url, let parsed = URL(string: url), Self.isWeb(parsed) { return .direct(parsed) }
        if let infoHash, !infoHash.isEmpty { return .torrent }
        if let ytId, !ytId.isEmpty { return .youtube(ytId) }
        if let externalUrl, let parsed = URL(string: externalUrl), Self.isWeb(parsed) { return .external(parsed) }
        return .unsupported
    }

    static func isWeb(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    /// Add-ons put the provider and quality summary in `name`, file details in `title`/`description`.
    var headline: String {
        let first = (name ?? "").split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Stream" : first
    }

    var details: String {
        (title ?? description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var quality: StreamQuality {
        StreamQuality.parse([name, title, description, behaviorHints?.filename].compactMap { $0 }.joined(separator: " "))
    }

    var sizeText: String? {
        let text = [title, description, name].compactMap { $0 }.joined(separator: " ")
        if let r = text.range(of: #"\d+(?:[.,]\d+)?\s?(?:GB|MB)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(text[r])
        }
        if let bytes = behaviorHints?.videoSize, bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        return nil
    }

    /// Whether GlassRemote can hand this stream to the TV box at all.
    var canSendToTV: Bool {
        switch kind {
        case .direct: return behaviorHints?.needsHeaders != true
        case .external, .youtube: return true
        case .torrent, .unsupported: return false
        }
    }

    /// Short reason shown on streams that can't be sent.
    var unavailableReason: String? {
        switch kind {
        case .torrent: return "Torrent: open the title in Nuvio instead"
        case .unsupported: return "No playable address"
        case .direct where behaviorHints?.needsHeaders == true: return "Needs request headers the TV intent can't send"
        default: return nil
        }
    }
}

enum StreamQuality: Int, Comparable, CaseIterable, Sendable {
    case unknown, sd, hd720, hd1080, uhd

    static func < (a: StreamQuality, b: StreamQuality) -> Bool { a.rawValue < b.rawValue }

    static func parse(_ text: String) -> StreamQuality {
        let t = text.lowercased()
        if t.range(of: #"2160p|\b4k\b|\buhd\b"#, options: .regularExpression) != nil { return .uhd }
        if t.contains("1080") { return .hd1080 }
        if t.contains("720") { return .hd720 }
        if t.range(of: #"480p|360p|\bsd\b"#, options: .regularExpression) != nil { return .sd }
        return .unknown
    }

    var badge: String? {
        switch self {
        case .uhd: return "4K"
        case .hd1080: return "1080p"
        case .hd720: return "720p"
        case .sd: return "SD"
        case .unknown: return nil
        }
    }
}
