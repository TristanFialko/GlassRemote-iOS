import Foundation
import SwiftADB

/// Detached TV-side helpers use a loopback TCP listener rather than named pipes.
/// A client disconnect only closes its socket; the listener keeps the helper's stdin
/// pipe open and accepts the next ADB client without destroying the UHID device.
@MainActor
enum PersistentHelper {
    static var failures: [String: String] = [:]

    /// Bump when the TV-side server or a helper protocol changes. A helper that was launched under
    /// an older revision is stopped and relaunched once, so updated binaries actually take effect
    /// (otherwise the old process would be re-attached forever). The relaunch re-creates that
    /// helper's virtual input device once.
    static let revision = 2
    private static func revisionKey(_ name: String) -> String { "glassRemote.helperRevision.\(name)" }
    private static func isCurrent(_ name: String) -> Bool {
        UserDefaults.standard.integer(forKey: revisionKey(name)) == revision
    }
    private static func markCurrent(_ name: String) {
        UserDefaults.standard.set(revision, forKey: revisionKey(name))
    }

    private static let serverName = "glass_tcp_input_server"
    private static let serverRemote = "/data/local/tmp/glass_tcp_input_server"

    private static func port(_ name: String) -> Int {
        switch name {
        case "glass_uhid_bridge": return 47631
        case "glass_uhid_keyboard": return 47632
        case "glass_cursor": return 47633
        default: return 47639
        }
    }
    private static func pidPath(_ name: String) -> String { "/data/local/tmp/\(name).pid" }
    private static func logPath(_ name: String) -> String { "/data/local/tmp/\(name).log" }

    private static func ensureServer(adb: AdbConnection) async throws {
        guard let url = await TVShell.bundledHelper(adb, serverName) else {
            throw NSError(domain: "GlassRemoteHelper", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "TCP input server missing from app bundle; rebuild with updated workflow"])
        }
        let data = try Data(contentsOf: url)
        guard data.count > 100 else {
            throw NSError(domain: "GlassRemoteHelper", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "TCP input server binary is invalid"])
        }
        try await TVShell.install(adb, data: data, remote: serverRemote, mode: "700")
    }

    private static func processTest(_ name: String, _ match: String) -> String {
        let p = pidPath(name)
        return "[ -s \(p) ] && P=$(cat \(p)) && kill -0 $P 2>/dev/null && [ -r /proc/$P/cmdline ] && grep -q '\(match)' /proc/$P/cmdline 2>/dev/null"
    }

    private static func killScript(_ name: String, _ match: String) -> String {
        let p = pidPath(name)
        return "if [ -s \(p) ]; then P=$(cat \(p)); if [ -r /proc/$P/cmdline ] && grep -q '\(match)' /proc/$P/cmdline 2>/dev/null; then kill -- -$P 2>/dev/null || kill $P 2>/dev/null; fi; fi; rm -f \(p)"
    }

    /// True only for a live helper started under the current `revision`.
    static func isRunning(adb: AdbConnection, name: String, match: String) async -> Bool {
        guard isCurrent(name) else { return false }
        // Verify the endpoint as well as PID metadata. With a shell pipeline, Android
        // may expose the supervisor's cmdline rather than the final helper executable.
        let processProbe = "if \(processTest(name, match)); then echo GLASS_ALIVE; fi"
        let tcpProbe = "/system/bin/nc -z -w 1 127.0.0.1 \(port(name)) >/dev/null 2>&1 && echo GLASS_TCP_ALIVE"
        let output = (try? await TVShell.script(adb, "\(processProbe); \(tcpProbe)")) ?? ""
        return output.contains("GLASS_ALIVE") || output.contains("GLASS_TCP_ALIVE")
    }

    static func stop(adb: AdbConnection, name: String, match: String) async {
        _ = try? await TVShell.script(adb, killScript(name, match))
    }

    /// `keeper != nil` enables cursor idle-heartbeat mode; it no longer creates a FIFO.
    static func launch(adb: AdbConnection, name: String, match: String, command: String, ready: String, keeper: String? = nil) async -> Bool {
        do { try await ensureServer(adb: adb) } catch {
            failures[name] = error.localizedDescription
            GRLog.note("helper", "\(name) server install failed: \(error.localizedDescription)")
            return false
        }
        if await isRunning(adb: adb, name: name, match: match) { failures[name] = nil; return true }

        let port = port(name), pid = pidPath(name), log = logPath(name), marker = "glassremote_persist_\(name)"
        let hb = keeper == nil ? "" : " --heartbeat"
        let script = """
        \(killScript(name, match))
        rm -f \(log)
        command -v setsid >/dev/null 2>&1 || { echo GLASS_NO_SETSID; exit 1; }
        setsid nohup sh -c "echo \\$\\$ > \(pid); exec \(serverRemote) --port \(port)\(hb) 2>>\(log) | sh -c 'echo \(marker) >&2; \(command)' >>\(log) 2>&1" </dev/null >/dev/null 2>&1 &
        i=0
        while [ $i -lt 80 ]; do
          if grep -q 'TCP_LISTENING' \(log) 2>/dev/null && grep -q -E '\(ready)' \(log) 2>/dev/null; then echo GLASS_STARTED; exit 0; fi
          if grep -q 'ERROR' \(log) 2>/dev/null; then break; fi
          i=$((i+1)); sleep 0.2
        done
        echo GLASS_NOT_READY
        cat \(log) 2>/dev/null
        \(killScript(name, match))
        """
        let output = (try? await TVShell.script(adb, script)) ?? "launch shell failed"
        let summary = output.trimmingCharacters(in: .whitespacesAndNewlines)
        GRLog.note("helper", "\(name): \(summary.prefix(300))")
        if output.contains("GLASS_STARTED") {
            failures[name] = nil
            markCurrent(name)
            return true
        }
        failures[name] = String(summary.prefix(180))
        return false
    }

    static func attach(adb: AdbConnection, name: String, match: String) async -> AdbStream? {
        guard await isRunning(adb: adb, name: name, match: match) else { return nil }
        guard let s = try? await adb.open(destination: "exec:/system/bin/nc 127.0.0.1 \(port(name))") else { return nil }
        failures[name] = nil
        return s
    }

    static func openInput(adb: AdbConnection, name: String) async -> AdbStream? {
        try? await adb.open(destination: "exec:/system/bin/nc 127.0.0.1 \(port(name))")
    }

    static func fallbackNote(_ name: String) -> String {
        guard let reason = failures[name] else { return "" }
        return " · persistent TCP helper unavailable (\(reason))"
    }
}
