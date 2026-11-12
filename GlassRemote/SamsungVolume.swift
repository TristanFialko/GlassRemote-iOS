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
/// Phase 9 recovery §5: replies are accepted only when complete and confirmed (UPnPHTTP.swift); a
/// partial reply, an empty 200 or a SOAP fault is a failure, never a silent success. A 200 is also
/// not proof of which speakers moved: this level drives volume only when "Volume goes to" is TV
/// speakers (VolumeOutput.swift).
///
/// UNVERIFIED ON HARDWARE. If the TV does not answer, `onAvailabilityChanged(false)` fires.
@MainActor
final class SamsungVolumeLink {
    /// Real volume read from the TV (0...100 on Samsung's scale).
    var onVolume: ((Int) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Polling only happens while this returns true (app in the foreground).
    var isActive: () -> Bool = { true }

    private(set) var isAvailable = false
    /// The last level the TV confirmed (read back, or a SetVolume it acknowledged). Steps start here.
    private(set) var lastVolume: Int?
    /// The last mute state the TV confirmed, if it has been read or set.
    private(set) var isMuted: Bool?
    var onMute: ((Bool) -> Void)?

    private var host = ""
    private var loop: Task<Void, Never>?
    private var generation = 0
    private var pendingTarget: Int?
    private var wake: CheckedContinuation<Void, Never>?
    private var wakeToken = 0
    private var readbackDue = false
    private var consecutiveFailures = 0
    private var muteToggleRequested = false
    /// Why the last request failed (shown in the Connection sheet diagnostics).
    private(set) var lastFailure: String?

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
        muteToggleRequested = false
        lastVolume = nil
        isMuted = nil
        resumeWake()
        setAvailable(false)
    }

    /// Absolute set. Latest value wins; at most one request is ever in flight.
    func setVolume(_ value: Int) {
        guard isAvailable else { return }
        pendingTarget = min(max(value, 0), 100)
        fastPollUntil = Date().addingTimeInterval(8)
        resumeWake()
    }

    /// One button step (±delta) from the last confirmed level, or from the target still queued so
    /// rapid presses add up. False when the link is not ready (the caller reports it).
    @discardableResult
    func step(by delta: Int) -> Bool {
        guard isAvailable, let base = pendingTarget ?? lastVolume else { return false }
        setVolume(base + delta)
        return true
    }

    /// Mute toggle over RenderingControl: reads the TV's real mute state, then sets the opposite.
    @discardableResult
    func toggleMute() -> Bool {
        guard isAvailable else { return false }
        muteToggleRequested = true
        fastPollUntil = Date().addingTimeInterval(8)
        resumeWake()
        return true
    }

    /// Ask for an immediate re-read (e.g. after a key press or when the app becomes active).
    func refresh() {
        readbackDue = true
        fastPollUntil = Date().addingTimeInterval(8)
        resumeWake()
    }

    /// Poll every second for a few seconds after any interaction, then relax to 3 s.
    private var fastPollUntil = Date.distantPast

    // MARK: Loop

    private func run(_ gen: Int) async {
        while !Task.isCancelled, gen == generation {
            guard isActive() else {
                await sleepOrWake(seconds: 1)
                continue
            }

            if muteToggleRequested {
                muteToggleRequested = false
                do {
                    let reply = try await soap("GetMute", arguments: UPnPRenderingControl.master)
                    guard let current = UPnPRenderingControl.currentMute(in: reply) else { throw LinkError.badReply }
                    try await soap("SetMute", arguments: UPnPRenderingControl.setMuteArguments(!current))
                    if gen != generation { return }
                    consecutiveFailures = 0
                    isMuted = !current
                    onMute?(!current)
                    readbackDue = true
                } catch {
                    noteFailure(error)
                }
                continue
            }

            if let target = pendingTarget {
                // Collapse everything the slider produced while the last request was running.
                pendingTarget = nil
                do {
                    // Throws unless the TV returned a complete 200 SetVolumeResponse without a fault.
                    try await soap("SetVolume", arguments: UPnPRenderingControl.setVolumeArguments(target))
                    if gen != generation { return }
                    consecutiveFailures = 0
                    lastVolume = target
                    readbackDue = true
                } catch {
                    noteFailure(error)
                }
                // Short pause so the TV applies it before the readback; a new target skips it.
                if pendingTarget == nil { await sleepOrWake(seconds: 0.25) }
                continue
            }

            do {
                let reply = try await soap("GetVolume", arguments: UPnPRenderingControl.master)
                if gen != generation { return }
                if let value = UPnPRenderingControl.currentVolume(in: reply) {
                    consecutiveFailures = 0
                    lastFailure = nil
                    lastVolume = value
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
            let delay: Double = consecutiveFailures == 0 ? (Date() < fastPollUntil ? 1.0 : 3.0) : min(2.0 * Double(consecutiveFailures), 15)
            await sleepOrWake(seconds: delay)
        }
    }

    private func noteFailure(_ error: Error) {
        consecutiveFailures += 1
        lastFailure = String(describing: error)
        GRLog.note("volume", "UPnP RenderingControl request failed (\(consecutiveFailures)): \(error)")
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
        if pendingTarget != nil || readbackDue || muteToggleRequested { readbackDue = false; return }
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

    enum LinkError: Error, Equatable {
        case badReply, timeout, incomplete, http(Int), fault(Int?)
    }

    /// One RenderingControl action. Returns the reply body only when the TV confirmed the action
    /// (complete reply, HTTP 200, no SOAP fault, `<Action>Response` present).
    @discardableResult
    private func soap(_ action: String, arguments: String) async throws -> String {
        let request = UPnPRenderingControl.request(host: host, action: action, arguments: arguments)
        let response = try await Self.exchange(host: host, port: UPnPRenderingControl.port,
                                               request: request, timeout: 2.5)
        try Self.check(response, action: action)
        return response.body
    }

    /// Pure acceptance rule for one reply (unit tested).
    nonisolated static func check(_ response: UPnPHTTPResponse, action: String) throws {
        if response.isSOAPFault { throw LinkError.fault(response.upnpErrorCode) }
        guard response.status == 200 else { throw LinkError.http(response.status) }
        guard response.confirms(action) else { throw LinkError.badReply }
    }

    /// One request. Finishes as soon as the reply is complete by its framing; a reply cut short by
    /// an error, the timeout or an early close is a failure (never partial-data success).
    private nonisolated static func exchange(host: String, port: UInt16, request: Data,
                                             timeout: Double) async throws -> UPnPHTTPResponse {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw LinkError.badReply }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let box = ExchangeBox()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UPnPHTTPResponse, Error>) in
            func finish(_ result: Result<UPnPHTTPResponse, Error>) {
                guard box.finish() else { return }
                connection.cancel()
                continuation.resume(with: result)
            }
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                    if let data, !data.isEmpty { box.append(data) }
                    let closedCleanly = isComplete && error == nil
                    switch UPnPHTTPResponse.parse(box.snapshot, connectionClosed: closedCleanly) {
                    case .complete(let response): finish(.success(response)); return
                    case .malformed: finish(.failure(LinkError.badReply)); return
                    case .incomplete:
                        if let error {
                            if box.isEmpty { finish(.failure(error)) } else { finish(.failure(LinkError.incomplete)) }
                            return
                        }
                        if isComplete { finish(.failure(LinkError.incomplete)); return }
                        receive()
                    }
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
                finish(.failure(box.isEmpty ? LinkError.timeout : LinkError.incomplete))
            }
        }
    }
}

/// Thread-safe one-shot guard + receive buffer for a single request.
private final class ExchangeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var buffer = Data()

    // The receive callback and the timeout timer run on different queues, so the buffer is locked too.
    func append(_ data: Data) { lock.lock(); buffer.append(data); lock.unlock() }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return buffer.isEmpty }
    var snapshot: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
