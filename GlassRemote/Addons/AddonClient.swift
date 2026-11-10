import Foundation

enum AddonError: LocalizedError, Equatable {
    case url(AddonURLProblem)
    case unauthorized
    case notFound
    case http(Int)
    case tooLarge
    case invalidManifest(String)
    case network(String)
    case duplicate(String)
    case differentAddon(String)
    case notInstalled
    case noProfile

    var errorDescription: String? {
        switch self {
        case .url(let problem): return problem.errorDescription
        case .unauthorized: return "The add-on refused the request. It may need you to sign in or configure it on its website, then add the new link."
        case .notFound: return "Nothing was found at that address. Check that the link is the add-on's install link."
        case .http(let code): return "The add-on answered with an error (HTTP \(code)). Try again later."
        case .tooLarge: return "The add-on sent an unexpectedly large response, so it was ignored."
        case .invalidManifest(let reason): return reason
        case .network(let reason): return "Couldn't reach the add-on. \(reason)"
        case .duplicate(let name): return "\(name) is already installed with this link."
        case .differentAddon(let name): return "That link is for a different add-on, not \(name). Use Add an add-on to install it separately."
        case .notInstalled: return "That add-on is no longer installed."
        case .noProfile: return "No active profile."
        }
    }
}

/// Minimal Stremio add-on protocol client: ephemeral session (no cookies or disk cache), short
/// timeouts, response size caps and defensive decoding. It never logs URLs, because configured add-on
/// links often embed personal tokens.
struct AddonClient: Sendable {
    let session: URLSession

    static let manifestLimit = 1_000_000
    static let responseLimit = 5_000_000
    static let shared = AddonClient(session: AddonClient.makeSession())

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    func manifest(at url: URL) async throws -> AddonManifest {
        try Self.parseManifest(try await get(url, limit: Self.manifestLimit))
    }

    func streams(type: String, id: String, base: URL) async throws -> [AddonStream] {
        guard let url = AddonURL.resource("stream", type: type, id: id, base: base) else {
            throw AddonError.url(.malformed)
        }
        return Self.parseStreams(try await get(url, limit: Self.responseLimit))
    }

    static func parseManifest(_ data: Data) throws -> AddonManifest {
        let manifest: AddonManifest
        do {
            manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
        } catch {
            throw AddonError.invalidManifest("This link doesn't point to a Stremio add-on manifest.")
        }
        guard !manifest.id.trimmingCharacters(in: .whitespaces).isEmpty,
              !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AddonError.invalidManifest("The add-on's manifest has no id or name.")
        }
        guard !manifest.resources.isEmpty else {
            throw AddonError.invalidManifest("The add-on doesn't list any resources.")
        }
        return manifest
    }

    static func parseStreams(_ data: Data) -> [AddonStream] {
        struct Response: Decodable { let streams: LossyArray<AddonStream>? }
        return (try? JSONDecoder().decode(Response.self, from: data))?.streams?.items ?? []
    }

    private func get(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AddonError.network(error.localizedDescription)
        }
        guard let http = result.1 as? HTTPURLResponse else { throw AddonError.http(0) }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw AddonError.unauthorized
        case 404: throw AddonError.notFound
        default: throw AddonError.http(http.statusCode)
        }
        guard result.0.count <= limit else { throw AddonError.tooLarge }
        return result.0
    }
}
