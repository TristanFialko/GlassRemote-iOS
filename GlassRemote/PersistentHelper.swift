import Foundation
import SwiftADB

/// Runs a TV-side helper (UHID mouse, UHID keyboard, cursor setter) so that it SURVIVES the phone
/// disconnecting.
///
/// Before, each helper was `exec`'d directly in an ADB shell. When the phone locked, the app was
/// backgrounded or the session was rebuilt, that shell closed, the helper hit end-of-input and
/// destroyed its UHID device; the next connect created it again. Android sees a keyboard/mouse
/// being unplugged and plugged back in, which can make a foreground app (Stremio) re-layout,
/// rebuffer or even restart playback.
///
/// Now the helper is started detached (setsid/nohup) reading from a named pipe, with a keeper
/// process holding the pipe's write end open so the helper never sees end-of-input. The phone
/// only ever attaches a `cat > pipe` stream, which can come and go freely.
@MainActor
enum PersistentHelper {
    /// Why the most recent persistent start failed, keyed by helper name.
    /// Exposed in connection status so fallback to a disconnect-sensitive launch is visible.
    static var failures: [String: String] = [:]

    private static func dir(_ name: String) -> (fifo: String, pid: String, log: String) {
        ("/data/local/tmp/\(name).fifo", "/data/local/tmp/\(name).pid", "/data/local/tmp/\(name).log")
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func shell(_ adb: AdbConnection, _ script: String) async throws -> String {
        let stream = try await adb.open(destination: "shell:" + ["sh", "-c", script].map(quote).joined(separator: " "))
        var result = Data()
        while !(await stream.getIsClosed()) {
            do {
                let chunk = try await stream.read()
                if chunk.isEmpty { break }
                result.append(chunk)
            } catch {
                if await stream.getIsClosed() { break }
                throw error
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// The PID file tracks the helper itself (the launcher shell execs into it).
    private static func aliveTest(name: String, match: String) -> String {
        let p = dir(name)
        return "[ -p \(p.fifo) ] && [ -s \(p.pid) ] && P=$(cat \(p.pid)) && [ -r /proc/$P/cmdline ] && grep -q '\(match)' /proc/$P/cmdline 2>/dev/null"
    }

    /// Stops only a process whose live command line still matches this helper. When setsid was
    /// available, the helper PID is also its process-group ID, so its keeper is stopped with it.
    static func killScript(name: String, match: String) -> String {
        let p = dir(name)
        return "if [ -s \(p.pid) ]; then P=$(cat \(p.pid)); if [ -r /proc/$P/cmdline ] && grep -q '\(match)' /proc/$P/cmdline 2>/dev/null; then kill -- -$P 2>/dev/null || kill $P 2>/dev/null; fi; fi; rm -f \(p.fifo) \(p.pid)"
    }

    static func stop(adb: AdbConnection, name: String, match: String) async {
        _ = try? await shell(adb, killScript(name: name, match: match))
    }

    static func isRunning(adb: AdbConnection, name: String, match: String) async -> Bool {
        let out = try? await shell(adb, "if \(aliveTest(name: name, match: match)); then echo GLASS_ALIVE; fi")
        return out?.contains("GLASS_ALIVE") == true
    }

    /// Starts a helper detached from the ADB transport. `keeper` is a shell command whose
    /// stdout is connected to the FIFO. The default long sleep keeps the FIFO writer open;
    /// cursor watch mode supplies a heartbeat loop that periodically writes its `R` command.
    static func launch(
        adb: AdbConnection,
        name: String,
        match: String,
        command: String,
        ready: String,
        keeper: String? = nil
    ) async -> Bool {
        let p = dir(name)
        let writer = keeper ?? "sleep 2147483647"
        let script = """
        if \(aliveTest(name: name, match: match)); then echo GLASS_ALREADY; exit 0; fi
        \(killScript(name: name, match: match))
        rm -f \(p.log)
        FIFO_ERR=$(mkfifo \(p.fifo) 2>&1); FIFO_RC=$?
        if [ ! -p \(p.fifo) ]; then
          TOYBOX_ERR=$(toybox mkfifo \(p.fifo) 2>&1); TOYBOX_RC=$?
        else TOYBOX_RC=0; fi
        if [ ! -p \(p.fifo) ]; then
          MKNOD_ERR=$(mknod \(p.fifo) p 2>&1); MKNOD_RC=$?
        else MKNOD_RC=0; fi
        if [ ! -p \(p.fifo) ]; then
          echo "GLASS_FIFO_FAIL mkfifo_rc=$FIFO_RC mkfifo_err=$FIFO_ERR toybox_rc=$TOYBOX_RC toybox_err=$TOYBOX_ERR mknod_rc=$MKNOD_RC mknod_err=$MKNOD_ERR"
          exit 0
        fi
        command -v setsid >/dev/null 2>&1 || { echo GLASS_NO_SETSID; exit 0; }
        command -v nohup >/dev/null 2>&1 || { echo GLASS_NO_NOHUP; exit 0; }
        setsid nohup sh -c "echo \\$\\$ > \(p.pid); \(writer) > \(p.fifo) & \(command) < \(p.fifo) > \(p.log) 2>&1" </dev/null >/dev/null 2>&1 &
        i=0
        while [ $i -lt 60 ]; do
          if grep -F -q '\(ready)' \(p.log) 2>/dev/null; then echo GLASS_STARTED; exit 0; fi
          if grep -q 'ERROR' \(p.log) 2>/dev/null; then break; fi
          i=$((i+1)); sleep 0.2
        done
        echo GLASS_NOT_READY
        cat \(p.log) 2>/dev/null
        \(killScript(name: name, match: match))
        """
        guard let out = try? await shell(adb, script) else {
            failures[name] = "launch shell failed"
            return false
        }
        let summary = out.trimmingCharacters(in: .whitespacesAndNewlines)
        GRLog.note("helper", "\(name): \(summary.prefix(240))")
        if out.contains("GLASS_STARTED") || out.contains("GLASS_ALREADY") {
            failures[name] = nil
            return true
        }
        if out.contains("GLASS_NO_SETSID") {
            failures[name] = "setsid is unavailable; detached helper cannot be guaranteed"
        } else if out.contains("GLASS_NO_NOHUP") {
            failures[name] = "nohup is unavailable"
        } else if out.contains("GLASS_FIFO_FAIL") {
            failures[name] = "could not create FIFO"
        } else if out.contains("GLASS_NOT_READY") {
            failures[name] = String(summary.replacingOccurrences(of: "GLASS_NOT_READY", with: "").trimmingCharacters(in: .whitespacesAndNewlines).suffix(180))
        } else {
            failures[name] = String(summary.prefix(180))
        }
        return false
    }

    /// If the helper is alive, attach a new phone-side writer. Closing this stream does not
    /// destroy the helper because its independent keeper keeps the FIFO open.
    static func attach(adb: AdbConnection, name: String, match: String) async -> AdbStream? {
        guard await isRunning(adb: adb, name: name, match: match) else { return nil }
        guard let stream = try? await adb.open(destination: "exec:sh -c 'cat > \(dir(name).fifo)'") else { return nil }
        failures[name] = nil
        return stream
    }

    /// Compact status suffix when the helper could not be detached persistently.
    static func fallbackNote(_ name: String) -> String {
        guard let reason = failures[name] else { return "" }
        return " · NOT persistent (\(reason)); reconnect may interrupt playback"
    }

    static func openInput(adb: AdbConnection, name: String) async -> AdbStream? {
        try? await adb.open(destination: "exec:sh -c 'cat > \(dir(name).fifo)'")
    }
}
