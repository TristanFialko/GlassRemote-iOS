import Foundation

// Nuvio account integration.
//
// VERIFIED against the official Nuvio Mobile source (NuvioMedia/NuvioMobile @ 0f85c95):
//  - core/auth/DeviceLinkAuthRepository.kt: device-link sign-in. RPC `start_device_login_session`
//    {p_device_nonce, p_redirect_base_url, p_device_name, p_device_type} returns rows of
//    {device_code, user_code, verification_uri_complete, poll_interval_seconds}; the user approves on
//    nuvio.tv; the app polls RPC `poll_tv_login_session` {p_code, p_device_nonce} -> {status}
//    ("pending" | "approved" | anything else = expired); then the edge function `tv-logins-exchange`
//    {code, device_nonce} returns {access_token, refresh_token, token_type, expires_in, user?}.
//  - features/watching/sync/SupabaseProgressSyncAdapter.kt: RPC `sync_pull_watch_progress`
//    {p_profile_id[, p_since_last_watched, p_limit]} returns rows of {content_id, content_type,
//    video_id, season, episode, position, duration, last_watched, progress_key}.
//
// NOT VERIFIED (isolated, fails soft):
//  - The backend URL and anon (publishable) key. Nuvio injects them at build time; a third-party
//    report says https://nuvio.tv/config.js serves them. `NuvioBackendResolver` reads that file at
//    runtime (nothing is hard-coded) and fails with a clear message if it cannot.
//  - `sync_pull_profiles` argument and row shape: tolerant decode, falls back to profile 1.
//  - Token refresh uses the standard Supabase GoTrue endpoint (/auth/v1/token?grant_type=refresh_token).
//  - Library / watchlist sync RPCs were not provided, so no library or watchlist is shown.
//  Nothing here was run against a live Nuvio backend.
//
// This app only READS. It never calls a sync_push_* / sync_delete_* RPC.

// MARK: - Errors

enum NuvioError: LocalizedError, Equatable {
    case backendUnavailable
    case network
    case rejected(Int)
    case badResponse
    case sessionExpired
    case linkExpired
    case linkFailed

    var errorDescription: String? {
        switch self {
        case .backendUnavailable: return "Couldn't read Nuvio's server configuration. Check your internet connection and try again."
        case .network: return "Couldn't reach Nuvio. Check your internet connection."
        case .rejected(let code): return "Nuvio rejected the request (HTTP \(code))."
        case .badResponse: return "Nuvio sent an unexpected response."
        case .sessionExpired: return "Your Nuvio session expired. Sign in again."
        case .linkExpired: return "The sign-in code expired. Start again."
        case .linkFailed: return "Couldn't finish signing in. Start again."
        }
    }
}

// MARK: - Backend configuration

struct NuvioBackend: Equatable {
    let baseURL: URL
    let anonKey: String
}

enum NuvioConfigParser {
    static let fallbackURL = URL(string: "https://api.nuvio.tv")!

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    /// Reads the public configuration file. Looks for a JWT-shaped anon key (or `sb_publishable_…`) and an
    /// https URL assigned to a `*url` property; the URL falls back to Nuvio's API host.
    static func parse(_ js: String) -> NuvioBackend? {
        let key = firstMatch(#"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#, in: js)
            ?? firstMatch(#"sb_publishable_[A-Za-z0-9_\-]{8,}"#, in: js)
        guard let key else { return nil }
        var url = fallbackURL
        if let text = firstMatch(#"(?i)url["']?\s*[:=]\s*["'](https://[^"'\s]+)["']"#, in: js, group: 1),
           let parsed = URL(string: text.hasSuffix("/") ? String(text.dropLast()) : text), parsed.scheme == "https" {
            url = parsed
        }
        return NuvioBackend(baseURL: url, anonKey: key)
    }
}

actor NuvioBackendResolver {
    static let shared = NuvioBackendResolver()
    private static let cacheKey = "glassRemote.nuvio.backend.v1"
    private var cached: NuvioBackend?

    func backend(session: URLSession = .shared) async throws -> NuvioBackend {
        if let cached { return cached }
        var request = URLRequest(url: URL(string: "https://nuvio.tv/config.js")!)
        request.timeoutInterval = 15
        if let (data, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let text = String(data: data, encoding: .utf8), let found = NuvioConfigParser.parse(text) {
            cached = found
            UserDefaults.standard.set(["url": found.baseURL.absoluteString, "key": found.anonKey], forKey: Self.cacheKey)
            return found
        }
        // The anon key is a public client key, not a secret; a previously read copy is reused offline.
        if let saved = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String],
           let u = saved["url"].flatMap(URL.init(string:)), let k = saved["key"], u.scheme == "https" {
            let value = NuvioBackend(baseURL: u, anonKey: k)
            cached = value
            return value
        }
        throw NuvioError.backendUnavailable
    }
}

// MARK: - Wire models (pure, testable)

struct NuvioDeviceLink: Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let pollIntervalSeconds: Int
}

struct NuvioTokens: Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int64
}

struct NuvioProgressEntry: Equatable {
    let progressKey: String
    let contentId: String
    let contentType: String
    let videoId: String
    let season: Int?
    let episode: Int?
    let positionMs: Int64
    let durationMs: Int64
    let lastWatchedMs: Int64
}

enum NuvioParsers {
    /// Accepts the PostgREST row-array form (as the official `decodeList` does) or a single object.
    private static func rows(_ data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let list = json as? [[String: Any]] { return list }
        if let one = json as? [String: Any] { return [one] }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let n as Int64: return n
        case let n as Int: return Int64(n)
        case let n as Double: return n.isFinite ? Int64(n) : nil
        case let s as String: return Int64(s) ?? Double(s).map { Int64($0) }
        default: return nil
        }
    }

    static func formatUserCode(_ value: String) -> String {
        let normalized = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
        return normalized.count <= 3 ? normalized : "\(normalized.prefix(3))-\(normalized.dropFirst(3))"
    }

    static func deviceLink(_ data: Data) throws -> NuvioDeviceLink {
        guard let row = rows(data)?.first,
              let device = row["device_code"] as? String, !device.isEmpty,
              let user = row["user_code"] as? String, !user.isEmpty,
              let urlText = row["verification_uri_complete"] as? String, !urlText.isEmpty,
              let url = URL(string: urlText), url.scheme == "https" else { throw NuvioError.linkFailed }
        let interval = Int(int64(row["poll_interval_seconds"]) ?? 3)
        return NuvioDeviceLink(deviceCode: device, userCode: user, verificationURL: url, pollIntervalSeconds: interval)
    }

    static func pollStatus(_ data: Data) throws -> String {
        guard let status = rows(data)?.first?["status"] as? String else { throw NuvioError.badResponse }
        return status.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func tokens(_ data: Data) throws -> NuvioTokens {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty,
              let refresh = object["refresh_token"] as? String, !refresh.isEmpty,
              let expires = int64(object["expires_in"]), expires > 0 else { throw NuvioError.badResponse }
        return NuvioTokens(accessToken: access, refreshToken: refresh, expiresIn: expires)
    }

    static func progress(_ data: Data) throws -> [NuvioProgressEntry] {
        guard let list = rows(data) else { throw NuvioError.badResponse }
        return list.compactMap { row in
            guard let content = row["content_id"] as? String, !content.isEmpty else { return nil }
            return NuvioProgressEntry(
                progressKey: row["progress_key"] as? String ?? "",
                contentId: content,
                contentType: (row["content_type"] as? String ?? "").lowercased(),
                videoId: row["video_id"] as? String ?? "",
                season: int64(row["season"]).map { Int($0) },
                episode: int64(row["episode"]).map { Int($0) },
                positionMs: int64(row["position"]) ?? 0,
                durationMs: int64(row["duration"]) ?? 0,
                lastWatchedMs: int64(row["last_watched"]) ?? 0)
        }
    }

    /// `sync_pull_profiles` row shape is not verified: use the lowest numeric id-like field, else 1.
    static func profileID(_ data: Data) -> Int {
        guard let list = rows(data) else { return 1 }
        let ids = list.compactMap { row -> Int? in
            for key in ["profile_index", "profile_id", "id"] { if let v = int64(row[key]) { return Int(v) } }
            return nil
        }
        return ids.min() ?? 1
    }
}

// MARK: - Watch items

/// One title with recorded playback, from the account's synced watch progress.
struct NuvioWatchItem: Identifiable, Hashable {
    let id: String              // content id (IMDb id for Cinemeta-resolvable titles)
    let kind: String            // "movie" / "series"
    let name: String
    let posterURL: URL?
    let backgroundURL: URL?
    let year: String
    let lastWatched: Date?
    let timeOffsetMs: Int64
    let durationMs: Int64
    let videoID: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    var title: MediaTitle.Kind? { MediaTitle.Kind(rawValue: kind) }
    var progress: Double {
        guard timeOffsetMs > 0, durationMs > 0 else { return 0 }
        return min(1, Double(timeOffsetMs) / Double(durationMs))
    }
    var hasWatchHistory: Bool { timeOffsetMs > 0 }
    var isCompleted: Bool { progress >= 0.95 }
    /// Started, not finished, a movie or series. (The 95 % cut-off is this app's choice, not Nuvio's.)
    var isContinueWatching: Bool { title != nil && timeOffsetMs > 0 && durationMs > 0 && progress < 0.95 }
    var episode: (season: Int, episode: Int)? {
        guard kind == "series", let s = seasonNumber, let e = episodeNumber else { return nil }
        return (s, e)
    }
    var asTitle: MediaTitle? {
        guard let kind = title else { return nil }
        return MediaTitle(id: id, kind: kind, name: name, year: year, posterURL: posterURL, rating: "", backgroundURL: backgroundURL)
    }

    static func == (a: NuvioWatchItem, b: NuvioWatchItem) -> Bool { a.id == b.id && a.videoID == b.videoID && a.timeOffsetMs == b.timeOffsetMs }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(videoID) }
}

enum NuvioWatchAggregator {
    /// Latest entry per content id (most recently watched episode for a series). Entries without a
    /// usable IMDb-style id are skipped: Cinemeta cannot name them.
    static func latestPerTitle(_ entries: [NuvioProgressEntry]) -> [NuvioProgressEntry] {
        var best: [String: NuvioProgressEntry] = [:]
        for e in entries where RemoteModel.isIMDbID(e.contentId) {
            if let current = best[e.contentId], current.lastWatchedMs >= e.lastWatchedMs { continue }
            best[e.contentId] = e
        }
        return best.values.sorted { $0.lastWatchedMs > $1.lastWatchedMs }
    }

    static func kind(for entry: NuvioProgressEntry) -> MediaTitle.Kind? {
        switch entry.contentType {
        case "movie": return .movie
        case "series", "tv", "show": return .series
        default: return entry.season != nil ? .series : nil
        }
    }

    static func item(_ entry: NuvioProgressEntry, meta: MediaTitle) -> NuvioWatchItem {
        NuvioWatchItem(
            id: entry.contentId, kind: meta.kind.rawValue, name: meta.name, posterURL: meta.posterURL,
            backgroundURL: meta.backgroundURL, year: meta.year,
            lastWatched: entry.lastWatchedMs > 0 ? Date(timeIntervalSince1970: Double(entry.lastWatchedMs) / 1000) : nil,
            timeOffsetMs: entry.positionMs, durationMs: entry.durationMs,
            videoID: entry.videoId.isEmpty ? nil : entry.videoId, seasonNumber: entry.season, episodeNumber: entry.episode)
    }
}

// MARK: - Session storage and refresh

struct NuvioSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    private static let account = "nuvio.session"
    static func load() -> NuvioSession? {
        KeychainStore.string(for: account).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(NuvioSession.self, from: $0) }
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return }
        KeychainStore.set(text, for: Self.account)
    }
    static func clear() { KeychainStore.remove(account) }
}

/// Serialises token refresh: Nuvio refresh tokens are single-use, so two concurrent refreshes would
/// invalidate each other and sign the user out.
actor NuvioSessionManager {
    static let shared = NuvioSessionManager()
    private var refreshing: Task<NuvioSession, Error>?

    func accessToken(backend: NuvioBackend, session: URLSession = .shared) async throws -> String {
        guard let current = NuvioSession.load() else { throw NuvioError.sessionExpired }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        return try await refresh(current, backend: backend, session: session).accessToken
    }

    func forceRefresh(backend: NuvioBackend, session: URLSession = .shared) async throws -> String {
        guard let current = NuvioSession.load() else { throw NuvioError.sessionExpired }
        return try await refresh(current, backend: backend, session: session).accessToken
    }

    private func refresh(_ current: NuvioSession, backend: NuvioBackend, session: URLSession) async throws -> NuvioSession {
        if let refreshing { return try await refreshing.value }
        let task = Task<NuvioSession, Error> {
            let data: Data
            do {
                data = try await NuvioHTTP.send(backend: backend, path: "/auth/v1/token?grant_type=refresh_token",
                                                json: ["refresh_token": current.refreshToken], bearer: nil, session: session)
            } catch NuvioError.rejected(let code) where [400, 401, 403].contains(code) {
                NuvioSession.clear()
                throw NuvioError.sessionExpired
            }
            let t = try NuvioParsers.tokens(data)
            let next = NuvioSession(accessToken: t.accessToken, refreshToken: t.refreshToken, expiresAt: Date().addingTimeInterval(Double(t.expiresIn)))
            next.save()                       // the new single-use refresh token is stored before anything else runs
            return next
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }
}

// MARK: - HTTP

enum NuvioHTTP {
    /// POST JSON to the Nuvio backend. `bearer` nil means the anon key is used. Bodies, tokens and
    /// responses are never logged.
    static func send(backend: NuvioBackend, path: String, json: [String: Any], bearer: String?,
                     session: URLSession = .shared, method: String = "POST") async throws -> Data {
        guard let url = URL(string: backend.baseURL.absoluteString + path) else { throw NuvioError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(backend.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer ?? backend.anonKey)", forHTTPHeaderField: "Authorization")
        if method != "GET" { request.httpBody = try JSONSerialization.data(withJSONObject: json) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NuvioError.badResponse }
            guard (200..<300).contains(http.statusCode) else { throw NuvioError.rejected(http.statusCode) }
            return data
        } catch let error as NuvioError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw NuvioError.network
        }
    }

    static func rpc(_ name: String, _ params: [String: Any], backend: NuvioBackend, bearer: String?, session: URLSession = .shared) async throws -> Data {
        try await send(backend: backend, path: "/rest/v1/rpc/\(name)", json: params, bearer: bearer, session: session)
    }
}

// MARK: - Account model

@MainActor
final class NuvioAccount: ObservableObject {
    static let shared = NuvioAccount()

    enum State: Equatable { case signedOut, signedIn, expired }
    enum LinkPhase: Equatable {
        case idle, starting
        case waiting(code: String, url: URL, completing: Bool)
        case failed(String)
    }
    enum LibraryPhase: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var state: State
    @Published private(set) var linkPhase: LinkPhase = .idle
    @Published private(set) var libraryPhase: LibraryPhase = .idle
    @Published private(set) var items: [NuvioWatchItem] = []

    private var linkTask: Task<Void, Never>?
    private static let maxPollAttempts = 120
    private static let maxConsecutivePollFailures = 3
    private static let resolveLimit = 40

    init() { state = NuvioSession.load() == nil ? .signedOut : .signedIn }

    private func newestFirst(_ list: [NuvioWatchItem]) -> [NuvioWatchItem] {
        list.sorted { ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast) }
    }
    var watchHistory: [NuvioWatchItem] { newestFirst(items.filter(\.hasWatchHistory)) }
    var continueWatching: [NuvioWatchItem] { newestFirst(items.filter(\.isContinueWatching)) }
    var completed: [NuvioWatchItem] { newestFirst(items.filter { $0.hasWatchHistory && $0.isCompleted }) }
    func item(id: String) -> NuvioWatchItem? { items.first { $0.id == id } }

    // MARK: Device-link sign-in

    func startLink() {
        if case .starting = linkPhase { return }
        if case .waiting = linkPhase { return }
        linkTask?.cancel()
        linkTask = Task { [weak self] in await self?.runLink() }
    }

    func cancelLink() {
        linkTask?.cancel(); linkTask = nil
        linkPhase = .idle
    }

    private func runLink() async {
        linkPhase = .starting
        let nonce = UUID().uuidString
        do {
            let backend = try await NuvioBackendResolver.shared.backend()
            let startData = try await NuvioHTTP.rpc("start_device_login_session", [
                "p_device_nonce": nonce,
                "p_redirect_base_url": "https://nuvio.tv/link",
                "p_device_name": "Glass Remote (iPhone)",
                "p_device_type": "mobile"
            ], backend: backend, bearer: nil)
            let link = try NuvioParsers.deviceLink(startData)
            let code = NuvioParsers.formatUserCode(link.userCode)
            linkPhase = .waiting(code: code, url: link.verificationURL, completing: false)

            let interval = UInt64(min(max(link.pollIntervalSeconds, 2), 10)) * 1_000_000_000
            var attempts = 0, failures = 0
            while attempts < Self.maxPollAttempts {
                try await Task.sleep(nanoseconds: interval)
                attempts += 1
                let status: String
                do {
                    let data = try await NuvioHTTP.rpc("poll_tv_login_session", ["p_code": link.deviceCode, "p_device_nonce": nonce], backend: backend, bearer: nil)
                    status = try NuvioParsers.pollStatus(data)
                    failures = 0
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures += 1
                    if failures >= Self.maxConsecutivePollFailures { throw error }
                    continue
                }
                if status == "pending" { continue }
                guard status == "approved" else { throw NuvioError.linkExpired }
                linkPhase = .waiting(code: code, url: link.verificationURL, completing: true)
                try await complete(deviceCode: link.deviceCode, nonce: nonce, backend: backend)
                return
            }
            throw NuvioError.linkExpired
        } catch is CancellationError {
            return
        } catch {
            linkPhase = .failed((error as? LocalizedError)?.errorDescription ?? NuvioError.linkFailed.errorDescription ?? "Sign-in failed.")
        }
    }

    private func complete(deviceCode: String, nonce: String, backend: NuvioBackend) async throws {
        let data = try await NuvioHTTP.send(backend: backend, path: "/functions/v1/tv-logins-exchange",
                                            json: ["code": deviceCode, "device_nonce": nonce], bearer: nil)
        let tokens: NuvioTokens
        do { tokens = try NuvioParsers.tokens(data) } catch { throw NuvioError.linkFailed }
        NuvioSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
                     expiresAt: Date().addingTimeInterval(Double(tokens.expiresIn))).save()
        linkPhase = .idle
        state = .signedIn
        await refresh()
    }

    // MARK: Sign out

    func signOut() async {
        linkTask?.cancel(); linkTask = nil
        let token = NuvioSession.load()?.accessToken
        NuvioSession.clear()
        items = []; libraryPhase = .idle; linkPhase = .idle; state = .signedOut
        // Best effort, THIS session only (scope=local), so Nuvio on the TV and phone stay signed in.
        if let token, let backend = try? await NuvioBackendResolver.shared.backend() {
            _ = try? await NuvioHTTP.send(backend: backend, path: "/auth/v1/logout?scope=local", json: [:], bearer: token)
        }
    }

    // MARK: Pull watch progress

    func refresh() async {
        guard NuvioSession.load() != nil else { return }
        if libraryPhase == .loading { return }
        libraryPhase = .loading
        do {
            let backend = try await NuvioBackendResolver.shared.backend()
            let token = try await withAuthRetry(backend: backend)
            let profile = await profileID(backend: backend, token: token)
            let data = try await NuvioHTTP.rpc("sync_pull_watch_progress", ["p_profile_id": profile], backend: backend, bearer: token)
            let latest = Array(NuvioWatchAggregator.latestPerTitle(try NuvioParsers.progress(data)).prefix(Self.resolveLimit))
            items = await Self.resolve(latest)
            libraryPhase = .loaded
            state = .signedIn
        } catch NuvioError.sessionExpired {
            NuvioSession.clear()
            items = []; libraryPhase = .idle; state = .expired
        } catch is CancellationError {
            libraryPhase = .idle
        } catch {
            libraryPhase = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't load your Nuvio progress.")
        }
    }

    private func withAuthRetry(backend: NuvioBackend) async throws -> String {
        try await NuvioSessionManager.shared.accessToken(backend: backend)
    }

    private func profileID(backend: NuvioBackend, token: String) async -> Int {
        guard let data = try? await NuvioHTTP.rpc("sync_pull_profiles", [:], backend: backend, bearer: token) else { return 1 }
        return NuvioParsers.profileID(data)
    }

    /// Names, posters and landscape artwork come from Cinemeta (progress rows carry only ids).
    private static func resolve(_ entries: [NuvioProgressEntry]) async -> [NuvioWatchItem] {
        await withTaskGroup(of: (Int, NuvioWatchItem?).self) { group in
            var running = 0
            var results: [(Int, NuvioWatchItem)] = []
            for (index, entry) in entries.enumerated() {
                guard let kind = NuvioWatchAggregator.kind(for: entry) else { continue }
                if running >= 6, let done = await group.next() { running -= 1; if let item = done.1 { results.append((done.0, item)) } }
                group.addTask {
                    guard let meta = await CinemetaMetaCache.shared.title(kind: kind, id: entry.contentId) else { return (index, nil) }
                    return (index, NuvioWatchAggregator.item(entry, meta: meta))
                }
                running += 1
            }
            for await done in group { if let item = done.1 { results.append((done.0, item)) } }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
