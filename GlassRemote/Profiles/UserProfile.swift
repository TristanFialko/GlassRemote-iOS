import Foundation

/// Preferred artwork orientation for poster surfaces (Discover cards, collections, search results).
enum PosterOrientation: String, Codable, CaseIterable, Identifiable {
    case automatic, portrait, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }
}

/// Settings that belong to a person rather than to the device. TV pairing is deliberately NOT here:
/// a TV is shared hardware, so its keys and tokens are stored once for the whole app.
struct ProfileSettings: Codable, Equatable {
    /// `ThemeID` raw value. Nil keeps whichever theme is currently active.
    var themeID: String?
    /// `AmbientStyle` raw value (Continuation §G3). Nil keeps whichever ambient is currently active.
    var ambientID: String?
    var posterOrientation: PosterOrientation = .automatic
    var reduceInterfaceMotion = false
    var showContinueWatching = true

    init() {}

    /// The profile's ambient with the Phase 8 Mountains to Dusk migration applied; nil keeps the current one.
    var ambient: AmbientStyle? { ambientID.map { AmbientStyle.migrated($0) } }

    // Tolerant decoding: settings added in later versions fall back to their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        themeID = try? c.decodeIfPresent(String.self, forKey: .themeID)
        ambientID = try? c.decodeIfPresent(String.self, forKey: .ambientID)
        posterOrientation = (try? c.decodeIfPresent(PosterOrientation.self, forKey: .posterOrientation)) ?? .automatic
        reduceInterfaceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reduceInterfaceMotion)) ?? false
        showContinueWatching = (try? c.decodeIfPresent(Bool.self, forKey: .showContinueWatching)) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case themeID, ambientID, posterOrientation, reduceInterfaceMotion, showContinueWatching
    }
}

struct UserProfile: Codable, Identifiable, Equatable {
    static let tintCount = 6
    static let maxNameLength = 32

    let id: UUID
    var name: String
    var hasImage: Bool
    /// Index of the gradient used for the initials avatar when there is no photo.
    var tint: Int
    var createdAt: Date
    var settings: ProfileSettings

    init(id: UUID = UUID(), name: String, hasImage: Bool = false, tint: Int = 0,
         createdAt: Date = Date(), settings: ProfileSettings = ProfileSettings()) {
        self.id = id
        self.name = name
        self.hasImage = hasImage
        self.tint = tint
        self.createdAt = createdAt
        self.settings = settings
    }

    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// Trimmed, length-limited name, or nil when nothing usable was entered.
    static func cleanedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }
}
