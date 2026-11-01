import Foundation
import Network

/// Reads and sets the Samsung TV's volume through its UPnP MediaRenderer RenderingControl service
/// (port 9197). Unlike the remote WebSocket (port 8002, key presses only, no way to read anything
/// back) this gives the REAL current volume and ABSOLUTE set, which is what makes slider and TV
/// agree, makes the endpoint land on the true maximum, and lets changes made on the TV be seen.
///
/// Plain HTTP is written over `NWConnection` so iOS App Transport Security (which blocks cleartext
/// HTTP) is never involved and no Info.plist change is needed.
///
/// UNVERIFIED ON HARDWARE (no network access where this was written). If the TV does not answer,
/// `onAvailabilityChanged(false)` fires and the app keeps using the WebSocket/ADB key paths.
@MainActor
final class SamsungVolumeLink {
    /// Real volume read from the TV (0...100 on Samsung's scale).
    var onVolume: ((Int) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Polling only happens while this returns true (app in the foreground).
    var isActive: () -> Bool = { true }

    private(set) var isAvailable = false

    private var host = ""
    private var loop: Task<Void, Never>?
    private var generation = 0
    private var pendingTarget: Int?
    private var wake: CheckedContinuation<Void, Never>?
    private var wakeToken = 0
    private var readbackDue = false
    private var consecutiveFailures = 0

    private static let port: UInt16 = 9197
    private static let path = "/upnp/control/RenderingControl1"
    private static let service = "urn:schemas-upnp-org:service:RenderingControl:1"

    // MARK: Lifecycle

    /// Idempotent: calling it again with the same host while running does nothing (no duplicates).
    func start(host rawHost: String) {
        let newHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if loop != nil, newHost == host { return }
        stop()
        guard !newHost.isEmpty else { return }
        host = newHost
        generation += 1
        let gen = generation
        loop = Task { [weak self] in await self?.run(gen) }
    }

    func stop() {
        generation += 1
        loop?.cancel(); loop = nil
        pendingTarget = nil
        resumeWake()
        setAvailable(false)
    }

    /// Absolute set. Latest value wins; at most one request is ever in flight.
    func setVolume(_ value: Int) {
        guard isAvailable else { return }
        pendingTarget = min(max(value, 0), 100)
        resumeWake()
    }

    /// Ask for an immediate re-read (e.g. after a key press or when the app becomes active).
    func refresh() {
        readbackDue = true
        resumeWake()
    }

    // MARK: Loop

    private func run(_ gen: Int) async {
        while !Task.isCancelled, gen == generation {
            guard isActive() else {
                await sleepOrWake(seconds: 1)
                continue
            }

            if let target = pendingTarget {
                // Collapse everything the slider produced while the last request was running.
                pendingTarget = nil
                do {
                    try await soap("SetVolume", body: "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>\(target)</DesiredVolume>")
                    consecutiveFailures = 0
                    readbackDue = true
                } catch {
                    noteFailure(error)
                }
                // Short pause so the TV applies it before the readback; a new target skips it.
                if pendingTarget == nil { await sleepOrWake(seconds: 0.25) }
                continue
            }

            do {
                let reply = try await soap("GetVolume", body: "<InstanceID>0</InstanceID><Channel>Master</Channel>")
                if gen != generation { return }
                if let value = Self.extract("CurrentVolume", from: reply) {
                    consecutiveFailures = 0
                    setAvailable(true)
                    // A newer slider target arrived while we were reading: do not let a stale
                    // read overwrite what the user is doing.
                    if pendingTarget == nil { onVolume?(value) }
                } else {
                    throw LinkError.badReply
                }
            } catch {
                noteFailure(error)
            }

            readbackDue = false
            // 1 s while reachable (cheap local request); back off when the TV is off/unreachable.
            let delay: Double = consecutiveFailures == 0 ? 1.0 : min(2.0 * Double(consecutiveFailures), 15)
            await sleepOrWake(seconds: delay)
        }
    }

    private func noteFailure(_ error: Error) {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            if isAvailable { onStatus?("TV volume: no answer · using key presses") }
            setAvailable(false)
        }
    }

    private func setAvailable(_ available: Bool) {
        guard isAvailable != available else { return }
        isAvailable = available
        onAvailabilityChanged?(available)
    }

    /// Sleeps, but returns early on `setVolume` / `refresh` / `stop`.
    private func sleepOrWake(seconds: Double) async {
        if pendingTarget != nil || readbackDue { readbackDue = false; return }
        wakeToken += 1
        let token = wakeToken
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            wake = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                // A timer left over from an earlier, already-woken sleep must not cut this one short.
                if self?.wakeToken == token { self?.resumeWake() }
            }
        }
    }

    private func resumeWake() {
        guard let continuation = wake else { return }
        wake = nil
        continuation.resume()
    }

    // MARK: SOAP over a raw TCP connection

    private enum LinkError: Error { case badReply, timeout, http(Int) }

    @discardableResult
    private func soap(_ action: String, body: String) async throws -> String {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(Self.service)">\(body)</u:\(action)></s:Body></s:Envelope>
        """
        let payload = Data(envelope.utf8)
        let head = "POST \(Self.path) HTTP/1.1\r\n"
            + "HOST: \(host):\(Self.port)\r\n"
            + "CONTENT-TYPE: text/xml; charset=\"utf-8\"\r\n"
            + "SOAPACTION: \"\(Self.service)#\(action)\"\r\n"
            + "CONTENT-LENGTH: \(payload.count)\r\n"
            + "CONNECTION: close\r\n\r\n"
        var request = Data(head.utf8)
        request.append(payload)

        let response = try await Self.exchange(host: host, port: Self.port, request: request, timeout: 2.5)
        let text = String(decoding: response, as: UTF8.self)
        guard let statusLine = text.split(separator: "\r\n", maxSplits: 1).first,
              let code = statusLine.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else {
            throw LinkError.badReply
        }
        guard code == 200 else { throw LinkError.http(code) }
        return text
    }

    /// One request, read until the TV closes the connection (or the timeout).
    private nonisolated static func exchange(host: String, port: UInt16, request: Data, timeout: Double) async throws -> Data {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw LinkError.badReply }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let box = ExchangeBox()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            func finish(_ result: Result<Data, Error>) {
                guard box.finish() else { return }
                connection.cancel()
                continuation.resume(with: result)
            }
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                    if let data, !data.isEmpty { box.buffer.append(data) }
                    if let error { finish(box.buffer.isEmpty ? .failure(error) : .success(box.buffer)); return }
                    if isComplete { finish(.success(box.buffer)); return }
                    receive()
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) } else { receive() }
                    })
                case .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(LinkError.timeout))
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(box.buffer.isEmpty ? .failure(LinkError.timeout) : .success(box.buffer))
            }
        }
    }

    private nonisolated static func extract(_ tag: String, from text: String) -> Int? {
        guard let open = text.range(of: "<\(tag)>"),
              let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) else { return nil }
        return Int(text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Thread-safe one-shot guard + receive buffer for a single request.
private final class ExchangeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    var buffer = Data()
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
