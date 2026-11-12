import Foundation

/// Trusts the TV's self-signed certificate, but only for the one configured TV address.
private final class TVTrustDelegate: NSObject, URLSessionDelegate {
    let host: String
    init(host: String) { self.host = host }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == host,
           let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Samsung Tizen TV remote WebSocket (port 8002): TV keys, power, and volume when chosen.
///
/// UNVERIFIED on the actual TV. Whether the TV forwards volume to the soundbar over ARC/CEC
/// must be confirmed on hardware; it is used for volume only when "Volume goes to" picks the TV.
/// Pairing decisions (token, events, deadline, reset) live in SamsungPairing.swift.
@MainActor
final class SamsungTV {
    static let keyNames = [
        "VOLUME_UP": "KEY_VOLUP", "VOLUME_DOWN": "KEY_VOLDOWN", "MUTE": "KEY_MUTE",
        "TV_POWER": "KEY_POWER", "TV_SOURCE": "KEY_SOURCE", "TV_HDMI": "KEY_HDMI"
    ]
    /// Keys that exist only on the TV (never routed to the Android box).
    static let tvOnlyKeys: Set<String> = ["TV_POWER", "TV_SOURCE", "TV_HDMI"]

    var onStatus: ((String) -> Void)?
    /// Structured connection state for the UI (pairing / denied / unreachable ...).
    var onState: ((SamsungLinkState) -> Void)?
    /// Command bookkeeping for diagnostics. "Written" means the message was handed to the socket;
    /// the TV never confirms that a key was executed.
    private(set) var stats = SamsungCommandStats()
    var onStats: ((SamsungCommandStats) -> Void)?
    var onReadyChanged: ((Bool) -> Void)?
    /// A key accepted for sending failed afterwards. The caller reports it; it is never re-sent over ADB.
    var onSendFailed: ((String) -> Void)?

    private(set) var isReady = false
    /// True from connect() until the attempt succeeds, fails, times out or is stopped.
    /// Lets the auto-connect supervisor avoid creating a duplicate connection.
    private(set) var isAttempting = false
    /// Set when the TV refused or never answered the approval prompt. The auto-connect supervisor
    /// leaves the TV alone until the user asks to reconnect, so the prompt is not re-shown over
    /// and over. Cleared by an explicit `connect(host:userInitiated: true)`.
    private(set) var pairingBlocked = false
    var hasStoredToken: Bool { !(tokens.token() ?? "").isEmpty }
    /// Why the TV refused (nil unless the state is `.denied`). Phase 9 recovery §3.
    private(set) var denialReason: SamsungDenialReason?
    var onDenial: ((SamsungDenialReason?) -> Void)?
    /// Whether the saved token was sent with the current/last attempt.
    private(set) var tokenPresented = false
    /// Last channel event name from the TV (diagnostics only; never the token).
    private(set) var lastAnswer: String?
    private(set) var attempts = 0
    private var currentHost = ""
    private let tokens: SamsungTokenStore

    init(tokens: SamsungTokenStore = .live) {
        self.tokens = tokens
    }

    /// Token-free diagnostics line for the Connection sheet.
    var pairingDiagnostics: String {
        SamsungPairingPolicy.diagnostics(tokenSaved: hasStoredToken, tokenPresented: tokenPresented,
                                         lastAnswer: lastAnswer, attempts: attempts)
    }
    private(set) var state: SamsungLinkState = .off
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = 0

    func connect(host rawHost: String, userInitiated: Bool = false) {
        if userInitiated {
            pairingBlocked = false
            setDenial(nil)
        }
        stop(report: false, keepState: true)
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { report("Samsung TV: enter the TV's IP address"); return }

        generation += 1
        let gen = generation

        // Phase 9 recovery §3: the saved token goes only to the TV that issued it.
        let token = SamsungPairingPolicy.tokenToPresent(storedToken: tokens.token(), tokenHost: tokens.tokenHost, host: host)
        guard let url = SamsungPairingPolicy.url(host: host, token: token) else { report("Samsung TV: invalid address"); return }
        tokenPresented = token != nil
        currentHost = host
        attempts += 1
        GRLog.note("samsung", "connect attempt \(attempts) userInitiated=\(userInitiated) savedApproval=\(hasStoredToken) sent=\(tokenPresented)")

        let urlSession = URLSession(configuration: .default, delegate: TVTrustDelegate(host: host), delegateQueue: nil)
        let socket = urlSession.webSocketTask(with: url)
        session = urlSession
        task = socket
        isAttempting = true
        socket.resume()
        let firstPairing = token == nil
        setState(firstPairing ? .pairing : .connecting)
        report(firstPairing ? "Samsung TV: approve Glass Remote on the TV" : "Samsung TV: connecting…")

        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard let self, self.generation == gen else { return }
                    self.handle(message)
                } catch {
                    guard let self, self.generation == gen else { return }
                    self.isAttempting = false
                    self.setReady(false)
                    // After a denial the TV closes the socket itself: keep the denial visible.
                    if SamsungPairingPolicy.reportsDropAsUnreachable(state: self.state, pairingBlocked: self.pairingBlocked) {
                        self.setState(.unreachable)
                        self.report("Samsung TV: remote not connected (retrying)")
                    }
                    return
                }
            }
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SamsungPairingPolicy.approvalDeadline * 1_000_000_000))
            guard let self, self.generation == gen, !self.isReady else { return }
            // No answer while a first pairing prompt was showing counts as timed out (so the prompt
            // is not re-raised every few seconds); a denial already reported is never overwritten.
            let outcome = SamsungPairingPolicy.stateAfterDeadline(self.state)
            if outcome.blocksAutoConnect { self.pairingBlocked = true }
            if let reason = outcome.reason { self.setDenial(reason) }
            self.setState(outcome.state)
            if let reason = outcome.reason { self.report(reason.statusText) }
            else if outcome.state == .unreachable { self.report("Samsung TV: no response from the remote service") }
            self.stop(report: false, keepState: true)
        }
    }

    func stop(report shouldReport: Bool = true, keepState: Bool = false) {
        generation += 1
        receiveTask?.cancel(); receiveTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        session?.invalidateAndCancel(); session = nil
        isAttempting = false
        setReady(false)
        if !keepState { setState(.off) }
        if shouldReport { report("Samsung TV: off") }
    }

    /// Hold experiment (Press, wait, Release). Used only by the Connection sheet's test button;
    /// normal controls keep repeating `Click`. Always sends Release, even if the wait is cancelled.
    func holdTest(_ key: SamsungKey, seconds: Double = 0.8) async {
        guard sendKey(key, command: .press) else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        sendKey(key, command: .release)
    }

    enum Command: String { case click = "Click", press = "Press", release = "Release" }

    /// Legacy entry point: the app's own key names (VOLUME_UP, TV_POWER ...).
    func send(_ name: String) -> Bool {
        guard let key = SamsungKey.forAppKey(name) else { return false }
        return sendKey(key)
    }

    /// Returns true if the key was queued on the TV connection. Only allowlisted key names are
    /// ever put on the wire. `Click` is a full press+release. `Press`/`Release` exist in the
    /// protocol for holding a key; the app repeats `Click` instead, which every model accepts.
    @discardableResult
    func sendKey(_ key: SamsungKey, command: Command = .click) -> Bool {
        guard isReady, let task, SamsungKey.allowlist.contains(key.rawValue) else { return false }
        let object: [String: Any] = [
            "method": "ms.remote.control",
            "params": ["Cmd": command.rawValue, "DataOfCmd": key.rawValue,
                       "Option": "false", "TypeOfRemote": "SendRemoteKey"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let payload = String(data: data, encoding: .utf8) else { return false }
        let gen = generation
        stats.queued += 1
        stats.lastKey = key.rawValue
        stats.lastCommand = command.rawValue
        stats.lastAt = Date()
        onStats?(stats)
        Task { [weak self] in
            do {
                try await task.send(.string(payload))
                guard let self, self.generation == gen else { return }
                self.stats.written += 1
                self.onStats?(self.stats)
            } catch {
                guard let self, self.generation == gen else { return }
                self.stats.failed += 1
                self.stats.lastFailureAt = Date()
                self.onStats?(self.stats)
                GRLog.note("samsung", "\(key.rawValue) \(command.rawValue): socket write failed")
                self.setReady(false)
                self.setState(.unreachable)
                self.report("Samsung TV: send failed (retrying connection)")
                // Only volume keys have a safe fallback (the same action over ADB). Navigation keys
                // are never re-sent anywhere: a retry could double-press or reach the wrong device.
                if let legacy = key.legacyVolumeName { self.onSendFailed?(legacy) }
            }
        }
        return true
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let event = SamsungPairingPolicy.event(from: text) else { return }

        switch event {
        case .connected(let token):
            lastAnswer = "ms.channel.connect"
            if let token { tokens.save(token: token, host: currentHost) }
            else if tokenPresented { tokens.recordHostIfMissing(currentHost) }
            timeoutTask?.cancel()
            isAttempting = false
            pairingBlocked = false
            setDenial(nil)
            setState(.connected)
            setReady(true)
            report("Samsung TV: remote connected")
        case .unauthorized:
            lastAnswer = "ms.channel.unauthorized"
            let reason = SamsungPairingPolicy.denialReason(unauthorizedWithTokenPresented: tokenPresented)
            GRLog.note("samsung", "unauthorized (saved approval sent=\(tokenPresented)) -> \(reason)")
            deny(reason)
        case .timeout:
            lastAnswer = "ms.channel.timeout"
            deny(.approvalTimedOut)
        case .other(let name):
            lastAnswer = name
        }
    }

    /// The TV refused: stop this attempt completely (socket and deadline), so nothing later can
    /// overwrite the denial, and keep the auto-connect supervisor away until the user acts.
    private func deny(_ reason: SamsungDenialReason) {
        pairingBlocked = true
        setDenial(reason)
        setState(.denied)
        report(reason.statusText)
        stop(report: false, keepState: true)
    }

    /// Phase 9 recovery §3: explicit, user-confirmed reset. Forgets only the Samsung token (and the
    /// TV it was issued by); the next connection carries no token, so the TV shows its Allow prompt.
    func resetPairing() {
        stop(report: false)
        tokens.reset()
        pairingBlocked = false
        tokenPresented = false
        lastAnswer = nil
        setDenial(nil)
        report("Samsung TV: pairing reset · connecting; choose Allow on the TV")
    }

    private func setDenial(_ reason: SamsungDenialReason?) {
        guard denialReason != reason else { return }
        denialReason = reason
        onDenial?(reason)
    }

    private func setReady(_ ready: Bool) {
        guard isReady != ready else { return }
        isReady = ready
        onReadyChanged?(ready)
    }

    private func setState(_ new: SamsungLinkState) {
        guard state != new else { return }
        state = new
        onState?(new)
    }

    private func report(_ text: String) { onStatus?(text) }
}


/// Counters for the Samsung command diagnostics line. No tokens or addresses are ever stored here.
struct SamsungCommandStats: Equatable {
    var queued = 0
    var written = 0
    var failed = 0
    var lastKey = ""
    var lastCommand = ""
    var lastAt: Date?
    var lastFailureAt: Date?

    var summary: String {
        guard queued > 0 else { return "No Samsung keys sent yet" }
        return "Last: \(lastKey) (\(lastCommand.lowercased())) · handed to the TV connection \(written) of \(queued) · socket errors \(failed) · the TV does not confirm key presses"
    }
}
