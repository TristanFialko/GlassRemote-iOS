import Foundation
import SwiftADB

// Virtual HID mouse: helper upload/launch and pointer reports.
extension RemoteModel {
    func startMouse() async {
        guard let adb else { return }
        // The helper (and its UHID device) outlives the phone connection: reuse it when present.
        if let input = await PersistentHelper.attach(adb: adb, name: "glass_uhid_bridge", match: "glass_uhid_bridge") {
            mouseStream = input
            pendingMoveDX = 0; pendingMoveDY = 0; mouseButtonsHeld = 0
            mouseReady = true
            clearStaleMouseButtonOnTV()
            status = "Mouse ready · TV helper already running"
            return
        }
        await stopMouse()

        guard let helperURL = await TVShell.bundledHelper(adb, "glass_uhid_bridge") else {
            mouseReady = false
            let root = Bundle.main.resourceURL?.path ?? "unavailable"
            status = "Mouse helper not found · bundle resources: \(root)"
            return
        }

        do {
            let data = try Data(contentsOf: helperURL)
            guard !data.isEmpty else {
                throw NSError(domain: "GlassRemote", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: "Bundled mouse helper is empty"])
            }

            status = "Mouse helper found · checking installed binary…"
            let uploaded = try await TVShell.install(
                adb, data: data, remote: "/data/local/tmp/glass_uhid_bridge", mode: "700"
            ) { [weak self] text in self?.status = "Mouse " + text }
            GRLog.note("mouse", uploaded ? "mouse helper uploaded (\(data.count) bytes)" : "reusing existing verified mouse helper (\(data.count) bytes)")

            // Start the detached TCP bridge and connect a client. Closing this client never
            // closes the helper's stdin: the TV-side listener accepts the next connection.
            guard await PersistentHelper.launch(
                adb: adb,
                name: "glass_uhid_bridge",
                match: "glass_uhid_bridge",
                command: "exec /data/local/tmp/glass_uhid_bridge",
                ready: "READY"
            ), let stream = await PersistentHelper.openInput(adb: adb, name: "glass_uhid_bridge") else {
                let reason = PersistentHelper.fallbackNote("glass_uhid_bridge")
                throw NSError(domain: "GlassRemote", code: 14,
                              userInfo: [NSLocalizedDescriptionKey: "Persistent mouse TCP helper failed to start or accept a connection\(reason)"])
            }

            mouseStream = stream
            pendingMoveDX = 0; pendingMoveDY = 0; mouseButtonsHeld = 0
            mouseReady = true
            status = "Mouse ready · Android UHID created" + PersistentHelper.fallbackNote("glass_uhid_bridge")
        } catch {
            mouseReady = false
            mouseStream = nil
            status = "Mouse startup failed: \(error.localizedDescription)"
        }
    }

    func mouse(
        buttons: Int = 0,
        dx: Int = 0,
        dy: Int = 0,
        wheel: Int = 0,
        hscroll: Int = 0
    ) {
        guard connected, mouseReady, let mouseStream else { return }
        nudgeCursor()

        let line = "M \(buttons) \(max(-127, min(127, dx))) \(max(-127, min(127, dy))) \(max(-127, min(127, wheel))) \(max(-127, min(127, hscroll)))\n"

        reportQueue.enqueue {
            do {
                try await mouseStream.write(Data(line.utf8))
            } catch {
                GRLog.note("mouse", "input stream write failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.mouseReady = false
                    self.recoveryPending = true
                    self.status = "Mouse input stream failed: \(error.localizedDescription)"
                    self.recoverIfNeeded()
                }
            }
        }
    }

    /// Pointer motion (never changes button state; a held button stays held while dragging).
    func mouseMove(dx: Int, dy: Int) {
        guard connected, mouseReady, dx != 0 || dy != 0 else { return }
        nudgeCursor()
        pendingMoveDX += dx
        pendingMoveDY += dy
        guard !moveDrainQueued else { return }
        moveDrainQueued = true
        reportQueue.enqueue { [weak self] in await self?.drainPointerMotion() }
    }

    /// Sets the mouse button state (1 = left down, 0 = all up), ordered with respect to motion.
    func mouseButton(_ buttons: Int) {
        guard connected, mouseReady else { return }
        nudgeCursor()
        reportQueue.enqueue { [weak self] in await self?.sendButtonReport(buttons) }
    }

    private func drainPointerMotion() async {
        moveDrainQueued = false
        guard mouseReady, let stream = mouseStream else {
            pendingMoveDX = 0; pendingMoveDY = 0
            return
        }
        while pendingMoveDX != 0 || pendingMoveDY != 0 {
            // A report carries at most +-127 per axis; send the remainder next, never discard it.
            let sx = max(-127, min(127, pendingMoveDX))
            let sy = max(-127, min(127, pendingMoveDY))
            pendingMoveDX -= sx
            pendingMoveDY -= sy
            let line = "M \(mouseButtonsHeld) \(sx) \(sy) 0 0\n"
            do {
                try await stream.write(Data(line.utf8))
            } catch {
                mouseWriteFailed(error)
                return
            }
        }
    }

    /// Audit BUG-008: a drag the phone lost track of (the app left the foreground, the touch was
    /// cancelled) must not leave the TV's virtual mouse button down. Sends nothing unless a button
    /// is actually held, so leaving the app stays silent otherwise.
    func releaseHeldMouseButton(reason: String) {
        guard mouseReady, mouseButtonsHeld != 0 else { return }
        GRLog.note("mouse", "releasing held button: \(reason)")
        reportQueue.enqueue { [weak self] in await self?.sendButtonReport(0) }
    }

    /// After (re)attaching to a helper that outlived the phone's connection, clear any button an
    /// earlier session left down: a button-up with no motion moves nothing on the TV.
    func clearStaleMouseButtonOnTV() {
        guard mouseReady else { return }
        reportQueue.enqueue { [weak self] in await self?.sendButtonReport(0) }
    }

    private func sendButtonReport(_ buttons: Int) async {
        guard mouseReady, let stream = mouseStream else { return }
        mouseButtonsHeld = buttons
        do {
            try await stream.write(Data("M \(buttons) 0 0 0 0\n".utf8))
        } catch {
            mouseWriteFailed(error)
        }
    }

    private func mouseWriteFailed(_ error: Error) {
        GRLog.note("mouse", "input stream write failed: \(error.localizedDescription)")
        pendingMoveDX = 0; pendingMoveDY = 0
        mouseButtonsHeld = 0
        mouseReady = false
        recoveryPending = true
        status = "Mouse input stream failed: \(error.localizedDescription)"
        recoverIfNeeded()
    }

    private func stopMouse() async {
        mouseReady = false
        if let mouseStream {
            try? await mouseStream.close()
        }
        mouseStream = nil
    }
}
