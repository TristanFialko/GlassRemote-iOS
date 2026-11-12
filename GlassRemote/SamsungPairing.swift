import Foundation

// Phase 9 recovery §3: Samsung TV pairing.
//
// Root causes found in the v6 code (SamsungTV.swift before this change):
//  1. The saved token was presented on every connection, to whatever TV address was configured.
//     A token the TV no longer accepts (TV reset, Glass Remote removed from the TV's device list,
//     or a token issued by another TV) makes the TV answer `ms.channel.unauthorized` at once and
//     it never shows its Allow prompt. Reconnect presented the same token again, so the user was
//     stuck in "not allowed" with no prompt and no way to clear the token.
//  2. `ms.channel.unauthorized` left the socket and the 45 s deadline running. The deadline then
//     overwrote the denial with "unreachable / no response", and the TV closing the socket
//     replaced the status with "remote not connected (retrying)" although nothing was retrying.
//
// Everything that decides something lives here as pure functions so it is unit-tested without a
// TV. SamsungTV.swift only wires sockets to these decisions.

/// Why the TV refused the remote link. Kept apart from `SamsungLinkState` so every existing switch
/// over the link state stays exhaustive and unchanged.
enum SamsungDenialReason: Equatable, CaseIterable {
    /// `ms.channel.unauthorized` to a connection that presented the saved token: the TV no longer
    /// accepts that token. It will not prompt again until the token is reset.
    case savedTokenRejected
    /// `ms.channel.unauthorized` with no token: Deny was chosen on the prompt, or Glass Remote is on
    /// the TV's blocked list (Device Connection Manager).
    case refusedOnTV
    /// The Allow prompt was not answered in time (`ms.channel.timeout` or the app's own deadline).
    case approvalTimedOut

    /// Short banner line on the Remote page.
    var bannerText: String {
        switch self {
        case .savedTokenRejected: return "The TV no longer accepts the saved approval"
        case .refusedOnTV: return "The TV didn't allow Glass Remote"
        case .approvalTimedOut: return "The TV's Allow prompt timed out"
        }
    }

    /// Full status line (Connection sheet / status pill). Says exactly what fixes it.
    var statusText: String {
        switch self {
        case .savedTokenRejected:
            return "Samsung TV: the saved approval was refused · Reset Samsung pairing in Connection settings, then choose Allow on the TV"
        case .refusedOnTV:
            return "Samsung TV: not allowed · on the TV open Settings › General › External Device Manager › Device Connection Manager › Device List, allow or delete Glass Remote, then tap Reconnect"
        case .approvalTimedOut:
            return "Samsung TV: approval timed out · tap Reconnect and choose Allow on the TV"
        }
    }

    /// Whether resetting the saved pairing is the useful next step (rather than just Reconnect).
    var suggestsReset: Bool { self != .approvalTimedOut }
}

/// What the TV said on the remote channel (only the events the pairing logic cares about).
enum SamsungChannelEvent: Equatable {
    case connected(token: String?)
    case unauthorized
    case timeout
    case other(String)
}

/// Pure decisions for the Samsung pairing handshake. No sockets, no Keychain.
enum SamsungPairingPolicy {
    static let appName = "GlassRemote"
    static let port = 8002
    static let path = "/api/v2/channels/samsung.remote.control"
    /// The app's own deadline for the first answer (the TV's prompt itself stays up ~30 s).
    static let approvalDeadline: Double = 45

    /// Base64 of the app name, as the TV expects in the `name` query item.
    static var encodedName: String { Data(appName.utf8).base64EncodedString() }

    static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The saved token is presented only to the TV that issued it. A token saved by an older build
    /// (no issuing host recorded) is still presented, and the host is recorded on the next success;
    /// if that TV refuses it the user is told to reset it.
    static func tokenToPresent(storedToken: String?, tokenHost: String?, host: String) -> String? {
        guard let token = storedToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        guard let tokenHost, !normalizedHost(tokenHost).isEmpty else { return token }
        return normalizedHost(tokenHost) == normalizedHost(host) ? token : nil
    }

    /// `wss://<host>:8002/api/v2/channels/samsung.remote.control?name=<base64>[&token=<token>]`.
    /// The token item is present only when a token is given.
    static func url(host rawHost: String, token: String?) -> URL? {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = port
        components.path = path
        var items = [URLQueryItem(name: "name", value: encodedName)]
        if let token, !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        components.queryItems = items
        return components.url
    }

    /// Token from `ms.channel.connect` data. Most models send a string, some a number; both become
    /// the same decimal string. Booleans, empty strings and anything else are ignored.
    static func token(fromConnectData data: Any?) -> String? {
        guard let payload = data as? [String: Any], let raw = payload["token"] else { return nil }
        if let text = raw as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.stringValue
        }
        return nil
    }

    /// Parses one text frame from the remote channel. Returns nil for anything that is not JSON
    /// with an `event` field.
    static func event(from text: String) -> SamsungChannelEvent? {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = json["event"] as? String else { return nil }
        switch name {
        case "ms.channel.connect": return .connected(token: token(fromConnectData: json["data"]))
        case "ms.channel.unauthorized": return .unauthorized
        case "ms.channel.timeout": return .timeout
        default: return .other(name)
        }
    }

    static func denialReason(unauthorizedWithTokenPresented presented: Bool) -> SamsungDenialReason {
        presented ? .savedTokenRejected : .refusedOnTV
    }

    /// The link state when the app's own deadline passes without `ms.channel.connect`. A first
    /// pairing that got no answer counts as timed out; a denial the TV already reported is kept
    /// (never overwritten by "unreachable"); anything else is a network problem.
    static func stateAfterDeadline(_ current: SamsungLinkState) -> (state: SamsungLinkState, reason: SamsungDenialReason?, blocksAutoConnect: Bool) {
        switch current {
        case .pairing: return (.denied, .approvalTimedOut, true)
        case .denied: return (.denied, nil, true)
        default: return (.unreachable, nil, false)
        }
    }

    /// Whether a socket that closed (or failed) should be shown as a network drop. After a denial
    /// the TV closes the socket itself; that must not hide the denial behind "retrying".
    static func reportsDropAsUnreachable(state: SamsungLinkState, pairingBlocked: Bool) -> Bool {
        !pairingBlocked && state != .denied
    }

    /// One diagnostics line. Built from booleans and event names only: it can never contain the
    /// token or the TV address.
    static func diagnostics(tokenSaved: Bool, tokenPresented: Bool, lastAnswer: String?, attempts: Int) -> String {
        let answer = lastAnswer.map { $0.isEmpty ? "none" : $0 } ?? "none yet"
        return "Pairing: saved approval \(tokenSaved ? "yes" : "no") · sent with last attempt \(tokenPresented ? "yes" : "no") · last TV answer \(answer) · attempts \(attempts)"
    }

    /// What the confirmation for the explicit reset says.
    static let resetExplanation = "This forgets only the Samsung TV's approval saved on this iPhone. The Android TV box, its ADB key, the TV address and all other settings stay as they are. Glass Remote then connects again and the TV should show its Allow prompt."
}

/// Where the Samsung pairing token lives. `reset()` removes exactly these entries and nothing else.
struct SamsungTokenStore {
    /// Keychain account of the token (an older build kept it in UserDefaults under the same key).
    static let tokenKey = "glassRemote.samsungToken"
    /// UserDefaults key of the TV address that issued the token (an address is not a secret).
    static let tokenHostKey = "glassRemote.samsungTokenHost"

    /// Keychain access, injectable for tests: read(account), write(account, value), remove(account).
    var readSecret: (String) -> String?
    var writeSecret: (String, String) -> Void
    var removeSecret: (String) -> Void
    var defaults: UserDefaults

    static var live: SamsungTokenStore {
        SamsungTokenStore(readSecret: { KeychainStore.string(for: $0) },
                          writeSecret: { account, value in KeychainStore.set(value, for: account) },
                          removeSecret: { KeychainStore.remove($0) },
                          defaults: .standard)
    }

    /// The saved token. A token an older build saved in UserDefaults is moved to the Keychain.
    func token() -> String? {
        if let token = readSecret(Self.tokenKey), !token.isEmpty { return token }
        if let legacy = defaults.string(forKey: Self.tokenKey), !legacy.isEmpty {
            writeSecret(Self.tokenKey, legacy)
            defaults.removeObject(forKey: Self.tokenKey)
            return legacy
        }
        return nil
    }

    var tokenHost: String? { defaults.string(forKey: Self.tokenHostKey) }

    func save(token: String, host: String) {
        guard !token.isEmpty else { return }
        writeSecret(Self.tokenKey, token)
        let normalized = SamsungPairingPolicy.normalizedHost(host)
        if !normalized.isEmpty { defaults.set(normalized, forKey: Self.tokenHostKey) }
    }

    /// Records the issuing TV for a legacy token once that TV has accepted it.
    func recordHostIfMissing(_ host: String) {
        guard tokenHost == nil, token() != nil else { return }
        let normalized = SamsungPairingPolicy.normalizedHost(host)
        if !normalized.isEmpty { defaults.set(normalized, forKey: Self.tokenHostKey) }
    }

    /// Forgets the Samsung approval only: the Keychain token, a legacy UserDefaults copy and the
    /// issuing host. No other Keychain item or setting is touched.
    func reset() {
        removeSecret(Self.tokenKey)
        defaults.removeObject(forKey: Self.tokenKey)
        defaults.removeObject(forKey: Self.tokenHostKey)
    }
}
