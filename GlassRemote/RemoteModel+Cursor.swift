import Foundation
import SwiftADB

// Custom white pointer on the TV (glass_cursor_setter.jar + glass_cursor_white.png).
// Independent of the mouse: its failure never affects mouse or keyboard startup.
extension RemoteModel {
    /// Tip of the arrow inside the 128x128 `glass_cursor_white.png` (pixels).
    private static let cursorHotspot = (x: 18, y: 8)

    /// Persistent cursor helper. The `watch` command accepts `R` on stdin to reapply its icon.
    private static let cursorHelperName = "glass_cursor"
    private static let cursorMatch = "glass_cursor"

    func retryCursorHelper() {
        guard connected else {
            cursorStatus = "Cursor: connect to the TV first"
            return
        }
        Task { _ = await withDeadline(20) { await self.startCursor() } }
    }

    func startCursor() async {
        guard let adb else { return }
        await stopCursor()

        // Migrate away from the old helper name, whose TCP listener never sent reapply commands.
        await PersistentHelper.stop(adb: adb, name: "glass_cursor_setter", match: "com.glassremote.cursor")

        if await PersistentHelper.isRunning(adb: adb, name: Self.cursorHelperName, match: Self.cursorMatch) {
            cursorInput = await PersistentHelper.openInput(adb: adb, name: Self.cursorHelperName)
            if cursorInput != nil {
                cursorStatus = "Cursor: custom white cursor active · persistent helper"
                nudgeCursor()
            } else {
                cursorStatus = "Cursor: helper running · input feed reconnect pending"
            }
            return
        }

        guard let jarURL = TVShell.bundled("glass_cursor_setter.jar"),
              let pngURL = TVShell.bundled("glass_cursor_white.png") else {
            cursorStatus = "Cursor: helper files are not inside the app bundle"
            return
        }

        do {
            cursorStatus = "Cursor: uploading…"
            let jar = try Data(contentsOf: jarURL)
            let png = try Data(contentsOf: pngURL)
            try await TVShell.install(adb, data: jar, remote: "/data/local/tmp/glass_cursor_setter.jar", mode: "644")
            try await TVShell.install(adb, data: png, remote: "/data/local/tmp/glass_cursor_white.png", mode: "644")

            let hotspot = Self.cursorHotspot
            let launched = await PersistentHelper.launch(
                adb: adb,
                name: Self.cursorHelperName,
                match: Self.cursorMatch,
                command: "export CLASSPATH=/data/local/tmp/glass_cursor_setter.jar; exec app_process /system/bin com.glassremote.cursor.Main watch /data/local/tmp/glass_cursor_white.png \(hotspot.x) \(hotspot.y)",
                ready: "READY",
                // The jar only reapplies when it receives R. Keep sending a low-rate heartbeat
                // while the phone is suspended, and let phone-side nudges cover active movement.
                keeper: "while :; do echo R; sleep 1; done"
            )
            guard launched else {
                let reason = PersistentHelper.failures[Self.cursorHelperName] ?? "TV helper did not report READY"
                cursorStatus = "Cursor: persistent helper failed · \(reason)"
                GRLog.note("cursor", "persistent cursor helper failed to start: \(reason)")
                return
            }

            cursorInput = await PersistentHelper.openInput(adb: adb, name: Self.cursorHelperName)
            guard cursorInput != nil else {
                cursorStatus = "Cursor: helper started · input feed unavailable"
                return
            }
            cursorStatus = "Cursor: custom white cursor applied · persistent reapply active" + PersistentHelper.fallbackNote(Self.cursorHelperName)
            GRLog.note("cursor", "persistent white cursor helper running with 1 s reapply heartbeat")
            nudgeCursor()
        } catch {
            cursorInput = nil
            cursorStatus = "Cursor failed: \(error.localizedDescription)"
            GRLog.note("cursor", "start failed: \(error.localizedDescription)")
        }
    }

    /// Throttled while the pointer moves, with a trailing reapply after hover state settles.
    func nudgeCursor() {
        guard let input = cursorInput else { return }
        let now = Date()
        if now.timeIntervalSince(lastCursorNudge) >= 0.08 {
            lastCursorNudge = now
            cursorQueue.enqueue { [weak self] in
                do {
                    try await input.write(Data("R\n".utf8))
                } catch {
                    await MainActor.run {
                        guard let self, self.cursorInput === input else { return }
                        self.cursorInput = nil
                        self.cursorStatus = "Cursor: reapply feed disconnected · will retry on resume"
                        GRLog.note("cursor", "reapply feed write failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        cursorTrailTask?.cancel()
        cursorTrailTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self, let current = self.cursorInput else { return }
            self.cursorQueue.enqueue {
                do { try await current.write(Data("R\n".utf8)) }
                catch {
                    await MainActor.run {
                        guard self.cursorInput === current else { return }
                        self.cursorInput = nil
                        self.cursorStatus = "Cursor: reapply feed disconnected · will retry on resume"
                        GRLog.note("cursor", "trailing reapply failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func stopCursor() async {
        cursorTrailTask?.cancel()
        cursorTrailTask = nil
        let input = cursorInput
        cursorInput = nil
        // In persistent mode, closing the phone-side writer does NOT send STOP to the helper.
        // The TV-side heartbeat keeps it alive and continues restoring the white cursor.
        if let input {
            _ = await withDeadline(2) { () async -> Void in _ = try? await input.close() }
        }
    }
}
