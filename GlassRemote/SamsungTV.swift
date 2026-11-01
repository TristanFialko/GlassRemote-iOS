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

/// Samsung Tizen TV remote WebSocket (port 8002) used only for volume and mute.
///
/// UNVERIFIED on the actual TV. Whether the TV forwards volume to the soundbar over ARC/CEC
/// must be confirmed on hardware; the ADB volume path stays available as the fallback.
@MainActor
final class SamsungTV {
    static let keyNames = ["VOLUME_UP": "KEY_VOLUP", "VOLUME_DOWN": "KEY_VOLDOWN", "MUTE": "KEY_MUTE"]

    var onStatus: ((String) -> Void)?
    var onReadyChanged: ((Bool) -> Void)?
    /// A key accepted for sending failed afterwards; the caller re-sends it over ADB.
    var onSendFailed: ((String) -> Void)?

    private(set) var isReady = false
    /// True from connect() until the attempt succeeds, fails, times out or is stopped.
    /// Lets the auto-connect supervisor avoid creating a duplicate connection.
    private(set) var isAttempting = false
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = 0
    private let tokenKey = "glassRemote.samsungToken"

    func connect(host rawHost: String) {
        stop(report: false)
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { report("Samsung TV: enter the TV's IP address"); return }

        generation += 1
        let gen = generation

        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var items = [URLQueryItem(name: "name", value: Data("GlassRemote".utf8).base64EncodedString())]
        if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        guard let url = components.url else { report("Samsung TV: invalid address"); return }

        let urlSession = URLSession(configuration: .default, delegate: TVTrustDelegate(host: host), delegateQueue: nil)
        let socket = urlSession.webSocketTask(with: url)
        session = urlSession
        task = socket
        isAttempting = true
        socket.resume()
        report("Samsung TV: connecting… approve Glass Remote on the TV if it asks")

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
                    self.report("Samsung TV: not connected · using ADB volume (retrying)")
                    return
                }
            }
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self, self.generation == gen, !self.isReady else { return }
            self.report("Samsung TV: no response · using ADB volume (retrying)")
            self.stop(report: false)
        }
    }

    func stop(report shouldReport: Bool = true) {
        generation += 1
        receiveTask?.cancel(); receiveTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        session?.invalidateAndCancel(); session = nil
        isAttempting = false
        setReady(false)
        if shouldReport { report("Samsung TV: off") }
    }

    /// Returns true if the key was queued on the TV connection.
    func send(_ name: String) -> Bool {
        guard isReady, let task, let tvKey = Self.keyNames[name] else { return false }
        let payload = #"{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"\#(tvKey)","Option":"false","TypeOfRemote":"SendRemoteKey"}}"#
        let gen = generation
        Task { [weak self] in
            do {
                try await task.send(.string(payload))
            } catch {
                guard let self, self.generation == gen else { return }
                self.setReady(false)
                self.report("Samsung TV: send failed · using ADB volume")
                self.onSendFailed?(name)
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
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }

        switch event {
        case "ms.channel.connect":
            if let payload = json["data"] as? [String: Any], let token = payload["token"] {
                let value = "\(token)"
                if !value.isEmpty { UserDefaults.standard.set(value, forKey: tokenKey) }
            }
            timeoutTask?.cancel()
            isAttempting = false
            setReady(true)
            report("Samsung TV: connected · volume routed through the TV to the soundbar")
        case "ms.channel.unauthorized":
            report("Samsung TV: not allowed · accept Glass Remote on the TV")
        case "ms.channel.timeout":
            report("Samsung TV: approval timed out")
        default:
            break
        }
    }

    private func setReady(_ ready: Bool) {
        guard isReady != ready else { return }
        isReady = ready
        onReadyChanged?(ready)
    }

    private func report(_ text: String) { onStatus?(text) }
}
