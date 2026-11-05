import Foundation

// Stremio account integration.
//
// VERIFIED FROM SOURCES (not exercised from this build environment, which has no network):
//  - Stremio has NO OAuth / device-code / public developer-key flow. Its own clients (stremio-core)
//    sign in with `POST https://api.strem.io/api/login` {email, password} and receive an `authKey`
//    session token. That is the only account route, so the app uses it: the password goes to
//    api.strem.io over HTTPS and nowhere else, is never stored or logged, and is dropped as soon
//    as the request returns. Only the authKey is kept, in the iOS Keychain.
//  - Library, watch history and playback progress live in the `libraryItem` datastore:
//    `POST https://api.strem.io/api/datastoreGet` {authKey, collection: "libraryItem", ids: [], all: true}.
//    Each item carries `state.timeOffset` / `state.duration` (ms), `state.video_id` and `state.lastWatched`.
//  - Accounts created only with "Continue with Facebook/Apple" have no Stremio password and cannot
//    sign in here until a password is set at stremio.com.
//
// NOT AVAILABLE: Stremio exposes no public way to list a title's streams, and addon-specific
// personalisation needs per-addon requests this app does not make. See the README.

/// One `libraryItem` from the account, decoded leniently (every field optional).
struct StremioLibraryItem: Identifiable, Hashable {
    let id: String              // IMDb id (or another Stremio id, e.g. "yt_id:...")
    let kind: String            // "movie", "series", other
    let name: String
    let posterURL: URL?
    let removed: Bool
    let temp: Bool
    let lastWatched: Date?
    let timeOffsetMs: Int64
    let durationMs: Int64
    let videoID: String?        // "tt123:1:5" for series episodes
    let timesWatched: Int
    let flaggedWatched: Bool

    var title: StremioTitle.Kind? { StremioTitle.Kind(rawValue: kind) }
    var isInLibrary: Bool { !removed && !temp }
    var progress: Double {
        guard timeOffsetMs > 0, durationMs > 0 else { return 0 }
        return min(1, Double(timeOffsetMs) / Double(durationMs))
    }
    /// Started, not finished, and a type this app can open. (Stremio's own list also offers the
    /// next episode of a finished one; this app does not synthesise that.)
    var isContinueWatching: Bool {
        !removed && title != nil && timeOffsetMs > 0 && durationMs > 0 && progress < 0.95
    }

    /// (season, episode) from a series video id such as "tt0944947:1:5".
    var episode: (season: Int, episode: Int)? {
        guard kind == "series", let videoID else { return nil }
        let parts = videoID.split(separator: ":")
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return nil }
        return (s, e)
    }

    var asTitle: StremioTitle? {
        guard let kind = title else { return nil }
        return StremioTitle(id: id, kind: kind, name: name, year: "", posterURL: posterURL, rating: "")
    }
}

enum StremioAccountParser {
    private struct Envelope<T: Decodable>: Decodable {
        let result: T?
        let error: APIError?
    }
    struct APIError: Decodable {
        let message: String?
        let code: Int?
    }
    private struct LoginResult: Decodable { let authKey: String? }
    private struct RawItem: Decodable {
        let _id: String?
        let name: String?
        let type: String?
        let poster: String?
        let removed: Bool?
        let temp: Bool?
        let state: RawState?
    }
    private struct RawState: Decodable {
        let lastWatched: String?
        let timeOffset: Int64?
        let duration: Int64?
        let video_id: String?
        let timesWatched: Int?
        let flaggedWatched: Int?
    }

    static func iso(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Returns the authKey, or throws the API's own error.
    static func parseLogin(_ data: Data) throws -> String {
        guard let env = try? JSONDecoder().decode(Envelope<LoginResult>.self, from: data) else { throw StremioError.badResponse }
        if let error = env.error { throw StremioError.api(message: error.message ?? "Sign-in failed", code: error.code) }
        guard let key = env.result?.authKey, !key.isEmpty else { throw StremioError.badResponse }
        return key
    }

    static func parseLibrary(_ data: Data) throws -> [StremioLibraryItem] {
        guard let env = try? JSONDecoder().decode(Envelope<[RawItem]>.self, from: data) else { throw StremioError.badResponse }
        if let error = env.error { throw StremioError.api(message: error.message ?? "Request failed", code: error.code) }
        return (env.result ?? []).compactMap { raw in
            guard let id = raw._id, let name = raw.name, !name.isEmpty else { return nil }
            let poster = raw.poster.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return StremioLibraryItem(
                id: id, kind: raw.type ?? "", name: name, posterURL: poster,
                removed: raw.removed ?? false, temp: raw.temp ?? false,
                lastWatched: iso(raw.state?.lastWatched),
                timeOffsetMs: raw.state?.timeOffset ?? 0, durationMs: raw.state?.duration ?? 0,
                videoID: raw.state?.video_id, timesWatched: raw.state?.timesWatched ?? 0,
                flaggedWatched: (raw.state?.flaggedWatched ?? 0) > 0)
        }
    }
}

enum StremioError: LocalizedError, Equatable {
    case api(message: String, code: Int?)
    case badResponse
    case network
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .api(let message, _): return message
        case .badResponse: return "Stremio sent an unexpected response."
        case .network: return "Couldn't reach Stremio. Check your internet connection."
        case .sessionExpired: return "Your Stremio session expired. Sign in again."
        }
    }

    /// The API reports a dead session as an error object. The exact code is not documented, so
    /// this matches on the message as well; unmatched errors are shown as-is, never as "expired".
    static func looksLikeExpiredSession(message: String, code: Int?) -> Bool {
        let m = message.lowercased()
        return m.contains("session") || m.contains("authkey") || m.contains("auth key") || m.contains("not authorized")
    }
}

/// Network layer. Only ever talks to api.strem.io.
enum StremioAPI {
    static let base = URL(string: "https://api.strem.io/api")!

    private static func post(_ path: String, body: [String: Any], session: URLSession) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw StremioError.badResponse }
            if http.statusCode == 401 { throw StremioError.sessionExpired }
            guard (200..<300).contains(http.statusCode) else { throw StremioError.badResponse }
            return data
        } catch let error as StremioError {
            throw error
        } catch {
            throw StremioError.network
        }
    }

    /// The password exists only as this function's argument.
    static func login(email: String, password: String, session: URLSession = .shared) async throws -> String {
        let data = try await post("login", body: ["type": "Login", "email": email, "password": password, "facebook": false], session: session)
        return try StremioAccountParser.parseLogin(data)
    }

    static func logout(authKey: String, session: URLSession = .shared) async {
        _ = try? await post("logout", body: ["type": "Logout", "authKey": authKey], session: session)
    }

    static func library(authKey: String, session: URLSession = .shared) async throws -> [StremioLibraryItem] {
        let data = try await post("datastoreGet",
                                  body: ["type": "DatastoreGet", "authKey": authKey, "collection": "libraryItem", "ids": [String](), "all": true],
                                  session: session)
        do { return try StremioAccountParser.parseLibrary(data) }
        catch StremioError.api(let message, let code) {
            throw StremioError.looksLikeExpiredSession(message: message, code: code) ? StremioError.sessionExpired : StremioError.api(message: message, code: code)
        }
    }
}

/// Signed-in state, library and Continue Watching. The authKey lives in the Keychain only.
@MainActor
final class StremioAccount: ObservableObject {
    static let shared = StremioAccount()
    private static let keychainAccount = "stremio.authKey"

    enum State: Equatable { case signedOut, signingIn, signedIn, expired }
    enum LibraryPhase: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var state: State
    @Published private(set) var libraryPhase: LibraryPhase = .idle
    @Published private(set) var items: [StremioLibraryItem] = []
    @Published var signInError: String?

    private var authKey: String? { KeychainStore.string(for: Self.keychainAccount) }

    init() { state = KeychainStore.string(for: Self.keychainAccount) == nil ? .signedOut : .signedIn }

    var library: [StremioLibraryItem] {
        items.filter(\.isInLibrary).sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
    }
    var continueWatching: [StremioLibraryItem] {
        items.filter(\.isContinueWatching).sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
    }
    var recentlyWatched: [StremioLibraryItem] {
        items.filter { !$0.removed && $0.lastWatched != nil && ($0.timesWatched > 0 || $0.flaggedWatched || $0.timeOffsetMs > 0) }
            .sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
    }
    func item(id: String) -> StremioLibraryItem? { items.first { $0.id == id } }

    func signIn(email: String, password: String) async {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mail.isEmpty, !password.isEmpty else { signInError = "Enter your Stremio email and password."; return }
        state = .signingIn; signInError = nil
        do {
            let key = try await StremioAPI.login(email: mail, password: password)
            KeychainStore.set(key, for: Self.keychainAccount)
            state = .signedIn
            await refresh()
        } catch {
            state = .signedOut
            signInError = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed."
        }
    }

    func signOut() async {
        let key = authKey
        KeychainStore.remove(Self.keychainAccount)
        items = []; libraryPhase = .idle; state = .signedOut
        if let key { await StremioAPI.logout(authKey: key) }
    }

    func refresh() async {
        guard let key = authKey else { state = .signedOut; return }
        if libraryPhase == .loading { return }
        libraryPhase = .loading
        do {
            items = try await StremioAPI.library(authKey: key)
            libraryPhase = .loaded
            state = .signedIn
        } catch StremioError.sessionExpired {
            // The stored key is dead: remove it so nothing keeps sending it.
            KeychainStore.remove(Self.keychainAccount)
            items = []; libraryPhase = .idle; state = .expired
        } catch {
            libraryPhase = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't load your library.")
        }
    }
}
