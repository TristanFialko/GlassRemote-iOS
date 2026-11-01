import Foundation
import os

/// Correlated diagnostics. Filter in Console.app / Xcode with subsystem `GlassRemote`.
/// Every line carries a monotonic millisecond stamp so lifecycle events, ADB teardown/reconnect
/// and media/key commands can be lined up against what Stremio did on the TV.
enum GRLog {
    private static let logger = Logger(subsystem: "GlassRemote", category: "diag")
    private static let t0 = Date()

    static func note(_ tag: String, _ message: String) {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        logger.notice("[\(ms, privacy: .public)ms] \(tag, privacy: .public): \(message, privacy: .public)")
    }
}
