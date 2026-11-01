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
enum PersistentHelper {
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
        return "[ -p \(p.fifo) ] && [ -s \(p.pid) ] && grep -q '\(match)' /proc/$(cat \(p.pid))/cmdline 2>/dev/null"
    }

    static func isRunning(adb: AdbConnection, name: String, match: String) async -> Bool {
        let out = try? await shell(adb, "if \(aliveTest(name: name, match: match)); then echo GLASS_ALIVE; fi")
        return out?.contains("GLASS_ALIVE") == true
    }

    /// Starts the helper detached. `command` is the shell text that execs the helper (it may begin
    /// with `export X=...;`). Returns true once the helper printed `ready` (or was already running).
    static func launch(adb: AdbConnection, name: String, match: String, command: String, ready: String) async -> Bool {
        let p = dir(name)
        let script = """
        if \(aliveTest(name: name, match: match)); then echo GLASS_ALREADY; exit 0; fi
        [ -s \(p.pid) ] && kill $(cat \(p.pid)) 2>/dev/null
        rm -f \(p.fifo) \(p.log) \(p.pid)
        mkfifo \(p.fifo) || { echo GLASS_FIFO_FAIL; exit 0; }
        SS=; command -v setsid >/dev/null 2>&1 && SS=setsid
        $SS nohup sh -c "echo \\$\\$ > \(p.pid); sleep 2147483647 > \(p.fifo) & \(command) < \(p.fifo) > \(p.log) 2>&1" </dev/null >/dev/null 2>&1 &
        i=0
        while [ $i -lt 60 ]; do
          if grep -q '\(ready)' \(p.log) 2>/dev/null; then echo GLASS_STARTED; exit 0; fi
          if grep -q 'ERROR' \(p.log) 2>/dev/null; then break; fi
          i=$((i+1)); sleep 0.2
        done
        echo GLASS_NOT_READY
        cat \(p.log) 2>/dev/null
        [ -s \(p.pid) ] && kill $(cat \(p.pid)) 2>/dev/null
        rm -f \(p.fifo)
        """
        guard let out = try? await shell(adb, script) else { return false }
        GRLog.note("helper", "\(name): \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
        return out.contains("GLASS_STARTED") || out.contains("GLASS_ALREADY")
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
}
