import Foundation

// Control messages, exchanged over TLS on TCP 6466 after pairing.
//
// Field numbers and enum values: remotemessage.proto (proto3) as pinned in tronikos/androidtvremote2
// v0.3.3 (commit f95bfb4046668dcd770e569479f645ded4530c28), copied from louis49/androidtv-remote.
// Handshake replies and feature bits: androidtvremote2 remote.py at the same commit. Only the subset
// this app reads or sends is modelled; every other field is ignored, never guessed at.

/// RemoteConfigure.code1 / RemoteSetActive.active feature bits (androidtvremote2 `Feature`).
struct RemoteV2Features: OptionSet, Equatable {
    let rawValue: Int32
    init(rawValue: Int32) { self.rawValue = rawValue }

    static let ping = RemoteV2Features(rawValue: 1 << 0)
    static let key = RemoteV2Features(rawValue: 1 << 1)
    static let ime = RemoteV2Features(rawValue: 1 << 2)
    static let voice = RemoteV2Features(rawValue: 1 << 3)
    static let power = RemoteV2Features(rawValue: 1 << 5)
    static let volume = RemoteV2Features(rawValue: 1 << 6)
    static let appLink = RemoteV2Features(rawValue: 1 << 9)

    /// What GlassRemote asks for. IME (text) and voice are not requested: text stays on ADB until the
    /// v2 IME path is verified on the ARRIS box, and voice is out of scope. VOLUME is requested only so
    /// the TV reports its volume state; the app never sends volume keys over v2.
    static let requested: RemoteV2Features = [.ping, .key, .power, .volume, .appLink]
}

/// RemoteDirection enum.
enum RemoteV2Direction: UInt64 {
    case unknown = 0, startLong = 1, endLong = 2, short = 3
}

struct RemoteV2DeviceInfo: Equatable {
    var model: String
    var vendor: String
    var unknown1: Int32
    var unknown2: String
    var packageName: String
    var appVersion: String

    /// What androidtvremote2 sends back in its RemoteConfigure reply (model and vendor left empty).
    static let client = RemoteV2DeviceInfo(unknown1: 1, unknown2: "1", packageName: "atvremote", appVersion: "1.0.0")

    init(model: String = "", vendor: String = "", unknown1: Int32 = 0, unknown2: String = "",
         packageName: String = "", appVersion: String = "") {
        self.model = model
        self.vendor = vendor
        self.unknown1 = unknown1
        self.unknown2 = unknown2
        self.packageName = packageName
        self.appVersion = appVersion
    }

    init(_ m: ProtoMessage) throws {
        self.init(model: try m.string(1) ?? "", vendor: try m.string(2) ?? "", unknown1: try m.int32(3) ?? 0,
                  unknown2: try m.string(4) ?? "", packageName: try m.string(5) ?? "",
                  appVersion: try m.string(6) ?? "")
    }

    var writer: ProtoWriter {
        var w = ProtoWriter()
        w.stringIfNonEmpty(1, model)
        w.stringIfNonEmpty(2, vendor)
        w.int32IfNonZero(3, unknown1)
        w.stringIfNonEmpty(4, unknown2)
        w.stringIfNonEmpty(5, packageName)
        w.stringIfNonEmpty(6, appVersion)
        return w
    }
}

struct RemoteV2VolumeInfo: Equatable {
    var level: UInt32
    var max: UInt32
    var muted: Bool
}

/// Messages the TV sends that this app acts on. RemoteMessage field numbers: configure 1, set_active 2,
/// error 3, ping_request 8, ime_key_inject 20, start 40, set_volume_level 50.
enum RemoteV2Inbound: Equatable {
    case configure(features: RemoteV2Features, device: RemoteV2DeviceInfo)
    case setActive
    case error
    case pingRequest(val1: Int32)
    case currentApp(String)
    case started(Bool)
    case volume(RemoteV2VolumeInfo)
    /// Something this app does not handle (field numbers only, for diagnostics; never contents).
    case unhandled([Int])

    static func decode(_ bytes: [UInt8]) throws -> RemoteV2Inbound {
        let m = try ProtoMessage(bytes)
        if let c = try m.message(1) {
            var device = RemoteV2DeviceInfo()
            if let info = try c.message(2) { device = try RemoteV2DeviceInfo(info) }
            return .configure(features: RemoteV2Features(rawValue: try c.int32(1) ?? 0), device: device)
        }
        if try m.message(2) != nil { return .setActive }
        if try m.message(3) != nil { return .error }
        if let p = try m.message(8) { return .pingRequest(val1: try p.int32(1) ?? 0) }
        if let ime = try m.message(20) {
            // RemoteImeKeyInject.app_info (1) -> RemoteAppInfo.app_package (12)
            var app = ""
            if let info = try ime.message(1) { app = try info.string(12) ?? "" }
            return .currentApp(app)
        }
        if let s = try m.message(40) { return .started(try s.bool(1) ?? false) }
        if let v = try m.message(50) {
            // RemoteSetVolumeLevel: volume_max 6, volume_level 7, volume_muted 8
            return .volume(RemoteV2VolumeInfo(level: try v.uint32(7) ?? 0, max: try v.uint32(6) ?? 0,
                                              muted: try v.bool(8) ?? false))
        }
        return .unhandled(m.fieldNumbers)
    }
}

/// Messages this app sends. RemoteMessage field numbers: configure 1, set_active 2, ping_response 9,
/// key_inject 10, app_link_launch_request 90.
enum RemoteV2Outbound: Equatable {
    case configure(features: RemoteV2Features, device: RemoteV2DeviceInfo)
    case setActive(RemoteV2Features)
    case pingResponse(val1: Int32)
    case key(code: Int32, direction: RemoteV2Direction)
    case appLink(String)

    func encoded() -> [UInt8] {
        var w = ProtoWriter()
        var inner = ProtoWriter()
        switch self {
        case let .configure(features, device):
            inner.int32IfNonZero(1, features.rawValue)
            inner.message(2, device.writer)
            w.message(1, inner)
        case let .setActive(features):
            inner.int32IfNonZero(1, features.rawValue)
            w.message(2, inner)
        case let .pingResponse(val1):
            inner.int32IfNonZero(1, val1)
            w.message(9, inner)
        case let .key(code, direction):
            inner.int32IfNonZero(1, code)
            inner.uintIfNonZero(2, direction.rawValue)
            w.message(10, inner)
        case let .appLink(link):
            inner.stringIfNonEmpty(1, link)
            w.message(90, inner)
        }
        return w.bytes
    }

    /// Safe for logs: never includes app links or any text.
    var logDescription: String {
        switch self {
        case .configure: return "configure"
        case .setActive: return "set_active"
        case .pingResponse: return "ping_response"
        case let .key(code, direction): return "key \(code) \(direction)"
        case .appLink: return "app_link"
        }
    }
}

/// Session state after the TLS connection opens (pure, unit tested). The TV speaks first:
/// RemoteConfigure -> reply with our features and device info; RemoteSetActive -> reply with features;
/// RemotePingRequest -> echo val1; RemoteStart -> the TV is ready for commands.
struct RemoteV2Session {
    /// androidtvremote2 closes a connection with no traffic for 16 s (the TV pings every ~5 s when idle).
    static let idleTimeout: TimeInterval = 16

    let requested: RemoteV2Features
    private(set) var active: RemoteV2Features
    private(set) var device: RemoteV2DeviceInfo?
    private(set) var ready = false
    private(set) var isOn: Bool?
    private(set) var currentApp: String?
    private(set) var volume: RemoteV2VolumeInfo?
    private(set) var errorsReceived = 0

    init(requested: RemoteV2Features = .requested) {
        self.requested = requested
        active = requested
    }

    mutating func handle(_ inbound: RemoteV2Inbound) -> RemoteV2Outbound? {
        switch inbound {
        case let .configure(supported, device):
            self.device = device
            active = requested.intersection(supported)
            return .configure(features: active, device: .client)
        case .setActive:
            return .setActive(active)
        case let .pingRequest(val1):
            return .pingResponse(val1: val1)
        case let .started(on):
            ready = true
            isOn = on
            return nil
        case let .currentApp(app):
            currentApp = app.isEmpty ? nil : app
            return nil
        case let .volume(info):
            volume = info
            return nil
        case .error:
            errorsReceived += 1
            return nil
        case .unhandled:
            return nil
        }
    }

    /// Whether the TV has negotiated and enabled a feature for this session.
    func supports(_ feature: RemoteV2Features) -> Bool { ready && active.contains(feature) }
}
