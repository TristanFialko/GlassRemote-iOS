import Foundation

/// Stremio add-on manifest
/// (https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/manifest.md).
/// Only the fields GlassRemote uses are decoded and unknown fields are ignored. A resource may be a
/// plain name ("stream") or an object with its own types and idPrefixes, so both forms decode.
struct AddonManifest: Codable, Equatable {
    struct Resource: Codable, Equatable {
        let name: String
        let types: [String]?
        let idPrefixes: [String]?

        init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
            self.name = name
            self.types = types
            self.idPrefixes = idPrefixes
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
                self.init(name: name)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(name: try c.decode(String.self, forKey: .name),
                      types: try? c.decodeIfPresent([String].self, forKey: .types),
                      idPrefixes: try? c.decodeIfPresent([String].self, forKey: .idPrefixes))
        }

        private enum CodingKeys: String, CodingKey { case name, types, idPrefixes }
    }

    struct Extra: Codable, Equatable {
        let name: String
        let isRequired: Bool?
        let options: [String]?
    }

    struct Catalog: Codable, Equatable {
        let type: String
        let id: String
        let name: String?
        let extra: [Extra]?

        /// Catalogues that can't be browsed without input (for example search-only catalogues).
        var requiresInput: Bool { extra?.contains { $0.isRequired == true } ?? false }
    }

    struct BehaviorHints: Codable, Equatable {
        let adult: Bool?
        let p2p: Bool?
        let configurable: Bool?
        let configurationRequired: Bool?
    }

    let id: String
    let version: String
    let name: String
    let description: String?
    let logo: String?
    let background: String?
    let types: [String]
    let catalogs: [Catalog]
    let resources: [Resource]
    let idPrefixes: [String]?
    let behaviorHints: BehaviorHints?

    init(id: String, version: String = "1.0.0", name: String, description: String? = nil, logo: String? = nil,
         background: String? = nil, types: [String], catalogs: [Catalog] = [], resources: [Resource],
         idPrefixes: [String]? = nil, behaviorHints: BehaviorHints? = nil) {
        self.id = id
        self.version = version
        self.name = name
        self.description = description
        self.logo = logo
        self.background = background
        self.types = types
        self.catalogs = catalogs
        self.resources = resources
        self.idPrefixes = idPrefixes
        self.behaviorHints = behaviorHints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = (try? c.decode(String.self, forKey: .version)) ?? "0.0.0"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        logo = try? c.decodeIfPresent(String.self, forKey: .logo)
        background = try? c.decodeIfPresent(String.self, forKey: .background)
        types = (try? c.decodeIfPresent([String].self, forKey: .types)) ?? []
        catalogs = (try? c.decodeIfPresent(LossyArray<Catalog>.self, forKey: .catalogs))?.items ?? []
        resources = (try? c.decodeIfPresent(LossyArray<Resource>.self, forKey: .resources))?.items ?? []
        idPrefixes = try? c.decodeIfPresent([String].self, forKey: .idPrefixes)
        behaviorHints = try? c.decodeIfPresent(BehaviorHints.self, forKey: .behaviorHints)
    }

    enum CodingKeys: String, CodingKey {
        case id, version, name, description, logo, background, types, catalogs, resources, idPrefixes, behaviorHints
    }
}

/// Resources GlassRemote knows about. Streams are the priority; catalogue and meta support is
/// modelled so later screens can use them; subtitles are recognised but not used.
enum AddonCapability: String, CaseIterable, Identifiable {
    case stream, catalog, meta, subtitles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stream: return "Streams"
        case .catalog: return "Catalogues"
        case .meta: return "Metadata"
        case .subtitles: return "Subtitles"
        }
    }

    var symbol: String {
        switch self {
        case .stream: return "play.rectangle.fill"
        case .catalog: return "square.grid.2x2.fill"
        case .meta: return "info.circle.fill"
        case .subtitles: return "captions.bubble.fill"
        }
    }
}

struct AddonCompatibility: Equatable {
    let capabilities: [AddonCapability]
    /// The add-on can contribute something to GlassRemote as it is installed now.
    let usable: Bool
    let notes: [String]
}

extension AddonManifest {
    var capabilities: [AddonCapability] {
        AddonCapability.allCases.filter { cap in resources.contains { $0.name == cap.rawValue } }
    }

    var needsConfiguration: Bool { behaviorHints?.configurationRequired == true }
    var isConfigurable: Bool { behaviorHints?.configurable == true || needsConfiguration }
    var isP2P: Bool { behaviorHints?.p2p == true }

    /// Whether `resource` is offered for this media type and id. Resource-level types and id
    /// prefixes override the manifest-level ones, as in the Stremio protocol.
    func supports(_ resource: String, type: String, id: String) -> Bool {
        for r in resources where r.name == resource {
            let types = r.types ?? self.types
            guard types.contains(type) else { continue }
            if let prefixes = r.idPrefixes ?? idPrefixes, !prefixes.isEmpty,
               !prefixes.contains(where: { id.hasPrefix($0) }) { continue }
            return true
        }
        return false
    }

    /// GlassRemote's catalogue (Cinemeta) uses IMDb ids, so stream add-ons must accept "tt" ids.
    func supportsIMDb(_ resource: String) -> Bool {
        supports(resource, type: "movie", id: "tt0000001") || supports(resource, type: "series", id: "tt0000001:1:1")
    }

    /// Plain-language report shown in the Add-ons screen.
    var compatibility: AddonCompatibility {
        let caps = capabilities
        var notes: [String] = []
        if needsConfiguration {
            notes.append("Needs to be configured on its website first. Configure it, then add the personal link it gives you.")
        }
        if caps.contains(.stream) {
            if supportsIMDb("stream") {
                notes.append("Finds streams for Discover titles.")
            } else {
                notes.append("Its streams use ids that GlassRemote's catalogue doesn't use, so it may not find anything.")
            }
        }
        if isP2P {
            notes.append("Returns torrent streams. GlassRemote can't send those to the TV; Nuvio can play them if the add-on is installed in Nuvio too.")
        }
        if caps.contains(.catalog) || caps.contains(.meta) {
            notes.append("Catalogue and metadata resources are recognised; Discover currently uses Cinemeta.")
        }
        if caps == [.subtitles] {
            notes.append("Subtitles only. GlassRemote doesn't use subtitle add-ons.")
        }
        if caps.isEmpty {
            notes.append("Doesn't offer any resource GlassRemote understands.")
        }
        let usable = caps.contains(.stream) && !needsConfiguration
        return AddonCompatibility(capabilities: caps, usable: usable, notes: notes)
    }
}

/// Decodes an array and skips elements that fail, instead of rejecting the whole response.
struct LossyArray<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            let before = container.currentIndex
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                _ = try? container.decode(Skip.self)
            }
            if container.currentIndex == before { break }
        }
        self.items = items
    }

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
