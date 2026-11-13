import Foundation

// Pairing ("polo") messages, exchanged over TLS on TCP 6467.
//
// Field numbers and enum values: polo.proto (proto2) as pinned in tronikos/androidtvremote2 v0.3.3
// (commit f95bfb4046668dcd770e569479f645ded4530c28), itself copied from AOSP
// platform/external/google-tv-pairing-protocol with the OuterMessage change from louis49/androidtv-remote.
// Message flow and values sent: androidtvremote2 pairing.py at the same commit.

enum PoloStatus: UInt64 {
    case ok = 200, error = 400, badConfiguration = 401, badSecret = 402
}

enum PoloEncodingType: UInt64 {
    case unknown = 0, alphanumeric = 1, numeric = 2, hexadecimal = 3, qrCode = 4
}

enum PoloRole: UInt64 {
    case unknown = 0, input = 1, output = 2
}

struct PoloEncoding: Equatable {
    var type: UInt64
    var symbolLength: UInt32

    /// The only encoding this client offers: six hexadecimal symbols (what the TV displays).
    static let hexSix = PoloEncoding(type: PoloEncodingType.hexadecimal.rawValue, symbolLength: 6)

    var writer: ProtoWriter {
        var w = ProtoWriter()
        w.uint(1, type)
        w.uint(2, UInt64(symbolLength))
        return w
    }

    init(type: UInt64, symbolLength: UInt32) {
        self.type = type
        self.symbolLength = symbolLength
    }

    init(_ message: ProtoMessage) throws {
        guard let type = try message.uint(1) else { throw ProtoWireError.missingField(1) }
        guard let length = try message.uint32(2) else { throw ProtoWireError.missingField(2) }
        self.init(type: type, symbolLength: length)
    }
}

enum PoloPayload: Equatable {
    case pairingRequest(serviceName: String, clientName: String?)
    case pairingRequestAck(serverName: String?)
    case options(inputEncodings: [PoloEncoding], outputEncodings: [PoloEncoding], preferredRole: UInt64?)
    case configuration(encoding: PoloEncoding, clientRole: UInt64)
    case configurationAck
    case secret([UInt8])
    case secretAck([UInt8])
    /// A status-only message (e.g. an error reply) or a payload this client does not know.
    case none
}

/// OuterMessage. Field numbers: protocol_version 1, status 2, pairing_request 10, pairing_request_ack 11,
/// options 20, configuration 30, configuration_ack 31, secret 40, secret_ack 41.
struct PoloMessage: Equatable {
    /// androidtvremote2 sends protocol_version 2.
    static let clientProtocolVersion: UInt32 = 2
    /// The service name androidtvremote2 pairs with.
    static let serviceName = "atvremote"

    var protocolVersion: UInt32
    /// Raw status so an unknown fault code is still reported as a fault.
    var status: UInt64
    var payload: PoloPayload

    init(protocolVersion: UInt32 = PoloMessage.clientProtocolVersion,
         status: UInt64 = PoloStatus.ok.rawValue, payload: PoloPayload) {
        self.protocolVersion = protocolVersion
        self.status = status
        self.payload = payload
    }

    var isOK: Bool { status == PoloStatus.ok.rawValue }

    func encoded() -> [UInt8] {
        var w = ProtoWriter()
        w.uint(1, UInt64(protocolVersion))
        w.uint(2, status)
        switch payload {
        case let .pairingRequest(serviceName, clientName):
            var inner = ProtoWriter()
            inner.string(1, serviceName)
            if let clientName = clientName { inner.string(2, clientName) }
            w.message(10, inner)
        case let .pairingRequestAck(serverName):
            var inner = ProtoWriter()
            if let serverName = serverName { inner.string(1, serverName) }
            w.message(11, inner)
        case let .options(input, output, role):
            var inner = ProtoWriter()
            for encoding in input { inner.message(1, encoding.writer) }
            for encoding in output { inner.message(2, encoding.writer) }
            if let role = role { inner.uint(3, role) }
            w.message(20, inner)
        case let .configuration(encoding, role):
            var inner = ProtoWriter()
            inner.message(1, encoding.writer)
            inner.uint(2, role)
            w.message(30, inner)
        case .configurationAck:
            w.message(31, ProtoWriter())
        case let .secret(bytes):
            var inner = ProtoWriter()
            inner.data(1, bytes)
            w.message(40, inner)
        case let .secretAck(bytes):
            var inner = ProtoWriter()
            inner.data(1, bytes)
            w.message(41, inner)
        case .none:
            break
        }
        return w.bytes
    }

    static func decode(_ bytes: [UInt8]) throws -> PoloMessage {
        let m = try ProtoMessage(bytes)
        guard let version = try m.uint32(1) else { throw ProtoWireError.missingField(1) }
        guard let status = try m.uint(2) else { throw ProtoWireError.missingField(2) }
        let payload: PoloPayload
        if let inner = try m.message(10) {
            guard let service = try inner.string(1) else { throw ProtoWireError.missingField(1) }
            payload = .pairingRequest(serviceName: service, clientName: try inner.string(2))
        } else if let inner = try m.message(11) {
            payload = .pairingRequestAck(serverName: try inner.string(1))
        } else if let inner = try m.message(20) {
            var input: [PoloEncoding] = []
            for item in try inner.messages(1) { input.append(try PoloEncoding(item)) }
            var output: [PoloEncoding] = []
            for item in try inner.messages(2) { output.append(try PoloEncoding(item)) }
            payload = .options(inputEncodings: input, outputEncodings: output, preferredRole: try inner.uint(3))
        } else if let inner = try m.message(30) {
            guard let encoding = try inner.message(1) else { throw ProtoWireError.missingField(1) }
            guard let role = try inner.uint(2) else { throw ProtoWireError.missingField(2) }
            payload = .configuration(encoding: try PoloEncoding(encoding), clientRole: role)
        } else if try m.message(31) != nil {
            payload = .configurationAck
        } else if let inner = try m.message(40) {
            guard let secret = try inner.data(1) else { throw ProtoWireError.missingField(1) }
            payload = .secret(secret)
        } else if let inner = try m.message(41) {
            guard let secret = try inner.data(1) else { throw ProtoWireError.missingField(1) }
            payload = .secretAck(secret)
        } else {
            payload = .none
        }
        return PoloMessage(protocolVersion: version, status: status, payload: payload)
    }
}

enum RemoteV2PairingFailure: Error, Equatable {
    /// The TV replied with a non-OK status (raw value kept for diagnostics).
    case deviceStatus(UInt64)
    /// The TV sent a message out of order or one this client does not understand.
    case unexpectedMessage
    /// The code is not six hexadecimal digits.
    case malformedCode
    /// The code's check byte does not match: mistyped, or the TV's key is not the one in this session.
    case codeMismatch
    case timedOut
    case connectionLost
    case identityUnavailable
    case cancelled

    /// Factual, user-facing text. Never contains the code or secret.
    var message: String {
        switch self {
        case let .deviceStatus(status) where status == PoloStatus.badSecret.rawValue:
            return "The TV rejected the code. Start pairing again."
        case .deviceStatus: return "The TV ended pairing with an error."
        case .unexpectedMessage: return "The TV answered in an unexpected way."
        case .malformedCode: return "Enter the 6 characters shown on the TV (0-9, A-F)."
        case .codeMismatch: return "That code doesn't match. Check the TV and try again."
        case .timedOut: return "The TV stopped responding."
        case .connectionLost: return "The connection to the TV closed."
        case .identityUnavailable: return "This iPhone's remote identity couldn't be created or read."
        case .cancelled: return "Pairing cancelled."
        }
    }
}

enum RemoteV2PairingPhase: Equatable {
    case idle
    case awaitingRequestAck
    case awaitingOptions
    case awaitingConfigurationAck
    /// The TV is showing a code; waiting for the user.
    case awaitingCode
    case awaitingSecretAck
    case paired
    case failed(RemoteV2PairingFailure)
}

/// The pairing handshake as a pure state machine (unit tested). The connection layer feeds it
/// decoded messages and writes whatever it returns. It mirrors androidtvremote2's pairing.py:
/// request -> ack, options -> options, configuration -> ack (code shown), secret -> ack.
struct RemoteV2PairingMachine {
    private(set) var phase: RemoteV2PairingPhase = .idle

    mutating func start(clientName: String) -> PoloMessage {
        phase = .awaitingRequestAck
        return PoloMessage(payload: .pairingRequest(serviceName: PoloMessage.serviceName, clientName: clientName))
    }

    /// Handles one message from the TV and returns the reply to send, if any.
    mutating func receive(_ message: PoloMessage) -> PoloMessage? {
        if case .failed = phase { return nil }
        guard message.isOK else {
            phase = .failed(.deviceStatus(message.status))
            return nil
        }
        switch (phase, message.payload) {
        case (.awaitingRequestAck, .pairingRequestAck):
            phase = .awaitingOptions
            return PoloMessage(payload: .options(inputEncodings: [.hexSix], outputEncodings: [],
                                                 preferredRole: PoloRole.input.rawValue))
        case (.awaitingOptions, .options):
            phase = .awaitingConfigurationAck
            return PoloMessage(payload: .configuration(encoding: .hexSix, clientRole: PoloRole.input.rawValue))
        case (.awaitingConfigurationAck, .configurationAck):
            phase = .awaitingCode
            return nil
        case (.awaitingSecretAck, .secretAck):
            phase = .paired
            return nil
        default:
            phase = .failed(.unexpectedMessage)
            return nil
        }
    }

    /// The secret computed from the code the user typed. Only valid while the TV shows the code.
    mutating func submit(secret: [UInt8]) -> PoloMessage? {
        guard phase == .awaitingCode else { return nil }
        phase = .awaitingSecretAck
        return PoloMessage(payload: .secret(secret))
    }

    mutating func fail(_ failure: RemoteV2PairingFailure) {
        if phase != .paired { phase = .failed(failure) }
    }
}
