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
    /// Why the last persistent start failed, per helper name (shown in the status lines so a
    /// silent fallback to the old, disconnect-sensitive launch is visible on the phone).
    static var failures: [String: String] = [:]

    private static func dir(_ name: String) -> (fifo: String, pid: String, log: String) {
        ("/data/local/tmp/\(name).fifo", "/data/local/tmp/\(name).pid", "/data/local/tmp/\(name).log")
    }

    private static func shell(_ adb: AdbConnection, _ script: String) async throws -> String {
        func quote(_ v: String) -> String { "'" + v.replacingOccurrences(of: "'", with: "'\\''") + "'" }
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

    /// Shell test: the helper's pid file points at a live process whose command line contains `match`.
    private static func aliveTest(name: String, match: String) -> String {
        let p = dir(name)
        return "[ -p \(p.fifo) ] && [ -s \(p.pid) ] && kill -0 $(cat \(p.pid)) 2>/dev/null && grep -q '\(match)' /proc/$(cat \(p.pid))/cmdline 2>/dev/null"
    }

    /// Shell text that stops a helper started by `launch`, including its keeper. With setsid the
    /// helper is its own process-group leader, so the negative pid takes the keeper down too.
    /// With `match`, only a process whose command line contains it is killed (a stale pid file
    /// may point at a recycled, unrelated pid).
    static func killScript(name: String, match: String? = nil) -> String {
        let p = dir(name)
        let guardText = match.map { "grep -q '\($0)' /proc/$P/cmdline 2>/dev/null && " } ?? ""
        return "if [ -s \(p.pid) ]; then P=$(cat \(p.pid)); \(guardText){ kill -- -$P 2>/dev/null; kill $P 2>/dev/null; }; fi; rm -f \(p.fifo) \(p.pid)"
    }

    static func isRunning(adb: AdbConnection, name: String, match: String) async -> Bool {
        let out = try? await shell(adb, "if \(aliveTest(name: name, match: match)); then echo GLASS_ALIVE; fi")
        return out?.contains("GLASS_ALIVE") == true
    }

    /// Starts the helper detached. `command` is the shell text that execs the helper (it may begin
    /// with `export X=...;`). `keeper` is the command whose output holds the pipe open (default: a
    /// sleep that writes nothing). Returns true once the helper printed `ready` (or was already running).
    static func launch(adb: AdbConnection, name: String, match: String, command: String, ready: String,
                       keeper: String = "sleep 2147483647") async -> Bool {
        let p = dir(name)
        let script = """
        if \(aliveTest(name: name, match: match)); then echo GLASS_ALREADY; exit 0; fi
        \(killScript(name: name, match: match))
        rm -f \(p.log)
        mkfifo \(p.fifo) 2>/dev/null || mknod \(p.fifo) p 2>/dev/null || { echo GLASS_FIFO_FAIL; exit 0; }
        SS=; command -v setsid >/dev/null 2>&1 && SS=setsid
        [ -z "$SS" ] && echo GLASS_NO_SETSID
        $SS nohup sh -c "echo \\$\\$ > \(p.pid); \(keeper) > \(p.fifo) & \(command) < \(p.fifo) > \(p.log) 2>&1" </dev/null >/dev/null 2>&1 &
        i=0
        while [ $i -lt 60 ]; do
          if grep -q -E '\(ready)' \(p.log) 2>/dev/null; then echo GLASS_STARTED; exit 0; fi
          if grep -q 'ERROR' \(p.log) 2>/dev/null; then break; fi
          i=$((i+1)); sleep 0.2
        done
        echo GLASS_NOT_READY
        cat \(p.log) 2>/dev/null
        \(killScript(name: name))
        """
        guard let out = try? await shell(adb, script) else {
            failures[name] = "launch shell failed"
            return false
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        GRLog.note("helper", "\(name): \(trimmed.prefix(200))")
        if out.contains("GLASS_STARTED") || out.contains("GLASS_ALREADY") {
            failures[name] = nil
            return true
        }
        failures[name] = out.contains("GLASS_FIFO_FAIL") ? "could not create pipe" : String(trimmed.prefix(80))
        return false
    }

    /// If the helper is already alive, returns a stream that feeds its input pipe. nil otherwise.
    static func attach(adb: AdbConnection, name: String, match: String) async -> AdbStream? {
        guard await isRunning(adb: adb, name: name, match: match) else { return nil }
        return try? await adb.open(destination: "exec:sh -c 'cat > \(dir(name).fifo)'")
    }

    /// Opens the input stream for a helper that `launch` just started.
    static func openInput(adb: AdbConnection, name: String) async -> AdbStream? {
        try? await adb.open(destination: "exec:sh -c 'cat > \(dir(name).fifo)'")
    }

    /// Short suffix for status lines when a helper fell back to the non-persistent launch.
    static func fallbackNote(_ name: String) -> String {
        guard let reason = failures[name] else { return "" }
        return " · NOT persistent (\(reason)); playback may be interrupted on reconnect"
    }
}
