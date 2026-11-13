import Combine
import Foundation

/// What to do with one key fire when Remote v2 is enabled.
enum RemoteV2KeyDecision: Equatable {
    case remoteV2
    case adb
    /// No transport can carry it right now (the existing path reports why).
    case unavailable
    /// The fire continues a held key whose transport went down: dropped, never moved to the other link.
    case droppedHold
}

/// Pins held keys to the transport that started them (pure, unit tested). RepeatKey reports a hold as
/// a series of fires; a fire of the same key within `holdWindow` of the previous one continues that
/// gesture. If the gesture's transport goes down, the rest of the gesture is dropped until the user
/// pauses, so input never switches links mid-gesture and is never sent twice.
struct RemoteV2KeyGestureRouter {
    static let holdWindow: TimeInterval = 0.5

    private(set) var ledger = GestureTransportLedger()
    private var lastFire: [String: Date] = [:]
    private var stopped: Set<String> = []

    mutating func route(_ key: String, operation: RemoteOperation, links: RemoteTransportAvailability,
                        now: Date) -> RemoteV2KeyDecision {
        let continuing = lastFire[key].map { now.timeIntervalSince($0) < Self.holdWindow } ?? false
        lastFire[key] = now
        if continuing {
            if stopped.contains(key) { return .droppedHold }
            if ledger.heldKeys.contains(key) {
                guard let owner = ledger.repeatTick(key, links: links) else {
                    stopped.insert(key)
                    return .droppedHold
                }
                return Self.decision(owner)
            }
        }
        stopped.remove(key)
        _ = ledger.end(key)
        guard let owner = ledger.begin(key, operation: operation, links: links) else { return .unavailable }
        return Self.decision(owner)
    }

    mutating func transportLost(_ transport: RemoteTransportKind) {
        for key in ledger.transportLost(transport) { stopped.insert(key) }
    }

    mutating func cancelAll() {
        _ = ledger.cancelAll()
        stopped.removeAll()
        lastFire.removeAll()
    }

    private static func decision(_ transport: RemoteTransportKind) -> RemoteV2KeyDecision {
        transport == .remoteV2 ? .remoteV2 : .adb
    }
}

/// Owns the Remote v2 pairing and control connection for the TV box at the ADB address.
/// Off by default: while disabled nothing connects and every command takes the ADB path as before.
@MainActor
final class RemoteV2Controller: ObservableObject {
    static let shared = RemoteV2Controller()
    static let enabledKey = "remoteV2.enabled"

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: RemoteV2Controller.enabledKey) {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { cancelPairing() }
            restart()
        }
    }
    @Published private(set) var link: RemoteV2LinkState = .off
    @Published private(set) var features: RemoteV2Features = []
    @Published private(set) var pairingPhase: RemoteV2PairingPhase = .idle
    @Published private(set) var pairingActive = false
    @Published private(set) var pairingMessage: String?
    @Published private(set) var isPaired = false

    private(set) var host = ""
    private var control: RemoteV2ControlConnection?
    private var pairing: RemoteV2PairingSession?
    private var router = RemoteV2KeyGestureRouter()

    var ready: Bool { link == .connected }

    func setHost(_ newHost: String) {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != host else { return }
        host = trimmed
        cancelPairing()
        restart()
    }

    func availability(adbReady: Bool) -> RemoteTransportAvailability {
        RemoteTransportAvailability(v2Ready: ready, v2Features: features, adbReady: adbReady, preferV2: enabled)
    }

    func route(key: String, operation: RemoteOperation, adbReady: Bool) -> RemoteV2KeyDecision {
        router.route(key, operation: operation, links: availability(adbReady: adbReady), now: Date())
    }

    /// One discrete command (a tap, never a hold): the policy picks exactly one transport.
    func routeDiscrete(_ operation: RemoteOperation, adbReady: Bool) -> RemoteTransportKind? {
        RemoteTransportPolicy.route(operation, availability(adbReady: adbReady))
    }

    func send(_ outbound: RemoteV2Outbound) {
        control?.send(outbound)
    }

    // MARK: Pairing

    func startPairing() {
        guard enabled else { return }
        guard !host.isEmpty else {
            pairingMessage = "Enter the TV box address first."
            return
        }
        pairing?.cancel()
        stopControl()
        link = .pairing
        pairingMessage = nil
        pairingPhase = .idle
        pairingActive = true
        let session = RemoteV2PairingSession(host: host)
        session.onPhase = { [weak self, weak session] phase in
            guard let self = self, let session = session, self.pairing === session else { return }
            self.pairingPhase = phase
            switch phase {
            case .paired:
                self.pairing = nil
                self.pairingActive = false
                self.pairingMessage = "Paired with the TV box."
                GRLog.note("remotev2", "pairing succeeded")
                self.restart()
            case let .failed(failure):
                self.pairing = nil
                self.pairingActive = false
                self.pairingMessage = failure == .cancelled ? nil : failure.message
                GRLog.note("remotev2", "pairing ended: \(failure)")
                self.restart()
            default:
                break
            }
        }
        session.onCodeRejected = { [weak self] failure in self?.pairingMessage = failure.message }
        pairing = session
        GRLog.note("remotev2", "pairing started")
        session.start()
    }

    func submitCode(_ code: String) {
        pairingMessage = nil
        pairing?.submit(code: code)
    }

    func cancelPairing() {
        pairing?.cancel()
    }

    /// Forgets this TV box. The TV keeps its own entry until removed in its settings; pairing again
    /// replaces it.
    func forgetPairing() {
        cancelPairing()
        pairing = nil
        pairingActive = false
        RemoteV2PairingRecord.forget(host)
        pairingPhase = .idle
        pairingMessage = nil
        restart()
    }

    // MARK: Control connection

    private func stopControl() {
        control?.stop()
        control = nil
        features = []
        router.transportLost(.remoteV2)
    }

    private func restart() {
        stopControl()
        isPaired = !host.isEmpty && RemoteV2PairingRecord.isPaired(host)
        guard enabled, !host.isEmpty else {
            link = .off
            return
        }
        guard pairing == nil else {
            link = .pairing
            return
        }
        guard isPaired else {
            link = .notPaired
            return
        }
        let connection = RemoteV2ControlConnection(host: host)
        connection.onState = { [weak self, weak connection] state, features in
            guard let self = self, let connection = connection, self.control === connection else { return }
            self.apply(state, features)
        }
        control = connection
        connection.start()
    }

    private func apply(_ state: RemoteV2LinkState, _ newFeatures: RemoteV2Features) {
        if state != link { GRLog.note("remotev2", state.label) }
        link = state
        features = newFeatures
        if state != .connected { router.transportLost(.remoteV2) }
    }
}
