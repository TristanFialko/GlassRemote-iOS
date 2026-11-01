import Foundation
import CryptoKit
import SwiftADB

/// Independent virtual HID keyboard subsystem.
///
/// Nothing here shares state with the mouse: separate helper binary, separate remote
/// path, separate ADB stream, separate queue, separate readiness flag, separate errors.
/// `start` never throws, so a keyboard failure cannot affect the mouse or the app's
/// connection state. While the keyboard is not ready, `send` returns false and the
/// caller keeps using the existing ADB `input keyevent` path.
@MainActor
final class VirtualKeyboard {
    enum HIDUsage {
        case key(UInt8)        // USB HID Keyboard/Keypad page (0x07)
        case consumer(UInt16)  // USB HID Consumer page (0x0C)
    }

    /// Every remote button and the HID usage it would send.
    static let usages: [String: HIDUsage] = [
        "UP": .key(0x52), "DOWN": .key(0x51), "LEFT": .key(0x50), "RIGHT": .key(0x4F),
        "OK": .key(0x28),                       // Enter
        "BACK": .consumer(0x224),               // AC Back
        "HOME": .consumer(0x223),               // AC Home
        "MENU": .consumer(0x40),                // Menu
        "VOLUME_UP": .consumer(0xE9),
        "VOLUME_DOWN": .consumer(0xEA),
        "MUTE": .consumer(0xE2)
    ]

    /// Buttons actually routed through the virtual keyboard. The rest stay on the
    /// existing ADB keyevent path until their Android mapping is verified on the TV.
    /// Once a button is verified, add its name here (e.g. "BACK", "VOLUME_UP").
    static let routedKeys: Set<String> = ["UP", "DOWN", "LEFT", "RIGHT", "OK"]

    private static let helperName = "glass_uhid_keyboard"
    private static let remotePath = "/data/local/tmp/glass_uhid_keyboard"
    private static let uploadPath = "/data/local/tmp/glass_uhid_keyboard.upload"

    /// Human-readable keyboard status (shown in the Connection sheet).
    var onStatus: ((String) -> Void)?
    /// Called when a write fails after being accepted, so the press can be re-sent via ADB.
    var onFallback: ((String) -> Void)?
    /// Called when a running keyboard stream ends or fails on its own (not on stop()).
    var onStopped: (() -> Void)?

    private(set) var isReady = false
    private var stream: AdbStream?
    private var readerTask: Task<Void, Never>?
    private let queue = TaskQueue()
    private var generation = 0

    // MARK: - Lifecycle

    func start(adb: AdbConnection) async {
        await stop()
        generation += 1
        let gen = generation
        report("Virtual keyboard: starting…")

        do {
            // Helper (and its UHID device) outlives the phone connection: reuse it when present.
            if let existing = await PersistentHelper.attach(adb: adb, name: "glass_uhid_keyboard", match: "glass_uhid_keyboard") {
                guard gen == generation else { try? await existing.close(); return }
                stream = existing
                isReady = true
                report("Virtual keyboard: running · TV helper already present")
                startReader(existing, generation: gen)
                return
            }
            let helper = try loadBundledHelper()
            try await ensureUploaded(adb: adb, helper: helper)
            let newStream = try await launch(adb: adb)

            guard gen == generation else {
                try? await newStream.close()
                return
            }

            stream = newStream
            isReady = true
            report("Virtual keyboard: running · helper verified (\(helper.data.count) bytes)" + PersistentHelper.fallbackNote(Self.helperName))
            startReader(newStream, generation: gen)
        } catch {
            isReady = false
            stream = nil
            report("Virtual keyboard unavailable · ADB fallback active: \(error.localizedDescription)")
        }
    }

    /// Reattaches only to an already-running TV helper. Unlike `start`, this never uploads
    /// or launches the binary, so foreground recovery cannot enumerate a new Android keyboard.
    func reattachExisting(adb: AdbConnection) async -> Bool {
        await stop()
        generation += 1
        let gen = generation
        guard let existing = await PersistentHelper.attach(
            adb: adb, name: Self.helperName, match: Self.helperName
        ) else {
            report("Virtual keyboard: TV helper is not running · explicit reconnect required")
            return false
        }
        guard gen == generation else { try? await existing.close(); return false }
        stream = existing
        isReady = true
        report("Virtual keyboard: reattached to existing TV helper")
        startReader(existing, generation: gen)
        return true
    }

    func stop() async {
        generation += 1
        isReady = false
        readerTask?.cancel()
        readerTask = nil
        // Detach first, then close with a deadline: closing a dead stream must never block.
        // This closes only the phone-side TCP client. The TV-side listener keeps the
        // helper stdin pipe open, so the UHID device remains registered across suspension.
        let old = stream
        stream = nil
        if let old {
            _ = await withDeadline(2) { () async -> Void in _ = try? await old.close() }
        }
    }

    // MARK: - Sending

    /// Returns true if the press was queued on the virtual keyboard. Returns false if the
    /// keyboard is not ready or this button is not routed, so the caller uses ADB instead.
    /// The helper emits both the key-down and key-up report for each line.
    func send(_ name: String) -> Bool {
        guard isReady,
              Self.routedKeys.contains(name),
              let usage = Self.usages[name],
              let stream else { return false }

        let line: String
        switch usage {
        case .key(let code): line = "K \(code)\n"
        case .consumer(let code): line = "C \(code)\n"
        }

        let data = Data(line.utf8)
        let gen = generation

        queue.enqueue { [weak self] in
            do {
                try await stream.write(data)
            } catch {
                await MainActor.run {
                    self?.writeFailed(error, key: name, generation: gen)
                }
            }
        }
        return true
    }

    private func writeFailed(_ error: Error, key name: String, generation gen: Int) {
        guard gen == generation else { return }
        let wasReady = isReady
        isReady = false
        report("Virtual keyboard stream failed · ADB fallback active: \(error.localizedDescription)")
        if wasReady {
            onFallback?(name)
            onStopped?()
        }
    }

    private func startReader(_ stream: AdbStream, generation gen: Int) {
        readerTask = Task { [weak self] in
            var tail = ""
            while !Task.isCancelled {
                do {
                    let chunk = try await stream.read()
                    if chunk.isEmpty { break }
                    tail += String(decoding: chunk, as: UTF8.self)
                    tail = String(tail.suffix(400))
                } catch {
                    break
                }
            }
            await self?.streamEnded(generation: gen, lastOutput: tail)
        }
    }

    private func streamEnded(generation gen: Int, lastOutput: String) {
        guard gen == generation else { return }
        isReady = false
        stream = nil
        let text = lastOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        report("Virtual keyboard: stopped · ADB fallback active" + (text.isEmpty ? "" : ": \(text)"))
        onStopped?()
    }

    // MARK: - Helper discovery

    private struct Helper {
        let url: URL
        let data: Data
        let sha1: String
    }

    private func loadBundledHelper() throws -> Helper {
        let bundle = Bundle.main
        var found = bundle.url(forResource: Self.helperName, withExtension: nil)

        if found == nil {
            let roots = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }
            search: for root in roots {
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for case let url as URL in enumerator where url.lastPathComponent == Self.helperName {
                    found = url
                    break search
                }
            }
        }

        guard let url = found else {
            let root = bundle.resourceURL?.path ?? "unavailable"
            throw fail(1, "\(Self.helperName) is not inside the app bundle (\(root)). The CI step 'Bundle and verify helpers' must copy it into the .app")
        }

        let data = try Data(contentsOf: url)
        guard data.count > 64 else {
            throw fail(2, "bundled helper is only \(data.count) bytes (placeholder file?)")
        }

        // The TV needs a 32-bit little-endian ARM ELF executable.
        let head = Array(data.prefix(20))
        let isARM32ELF = head.count == 20
            && head[0] == 0x7F && head[1] == 0x45 && head[2] == 0x4C && head[3] == 0x46
            && head[4] == 1 && head[5] == 1
            && head[18] == 0x28 && head[19] == 0x00
        guard isARM32ELF else {
            let hex = data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
            throw fail(3, "bundled helper is not a 32-bit ARM ELF (first bytes: \(hex))")
        }

        let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Helper(url: url, data: data, sha1: sha1)
    }

    // MARK: - Upload and verification

    private func ensureUploaded(adb: AdbConnection, helper: Helper) async throws {
        let expected = helper.data.count

        // Fast path: an identical helper is already on the TV.
        report("Virtual keyboard: checking helper on TV…")
        let existingSize = parseSize(try await shell(adb, sizeCommand(Self.remotePath)))
        if existingSize == expected,
           let remoteSum = parseSHA1(try await shell(adb, "sha1sum \(Self.remotePath) 2>&1")),
           remoteSum == helper.sha1 {
            let chmodOut = try await shell(adb, "chmod 700 \(Self.remotePath) && echo GLASSKB_CHMOD_OK")
            if chmodOut.contains("GLASSKB_CHMOD_OK") { return }
        }

        // Upload to a temporary name so a partial file can never be executed.
        report("Virtual keyboard: uploading \(expected) bytes…")
        let upload = try await adb.open(destination: "exec:sh -c 'cat > \(Self.uploadPath)'")
        try await upload.write(helper.data)
        try await upload.close()

        // close() returns before the TV has necessarily finished writing, so poll the
        // real remote size instead of assuming the upload is complete.
        var remoteBytes: Int?
        for _ in 0..<50 {
            remoteBytes = parseSize(try await shell(adb, sizeCommand(Self.uploadPath)))
            if remoteBytes == expected { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard remoteBytes == expected else {
            let listing = (try? await shell(adb, "ls -l /data/local/tmp 2>&1 | grep -i glass")) ?? ""
            throw fail(10, "upload incomplete: local \(expected) bytes, TV has \(remoteBytes.map(String.init) ?? "none"). \(listing.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Checksum when the TV provides sha1sum; the size match above is the fallback.
        if let remoteSum = parseSHA1(try await shell(adb, "sha1sum \(Self.uploadPath) 2>&1")),
           remoteSum != helper.sha1 {
            throw fail(11, "checksum mismatch after upload (local \(helper.sha1.prefix(8)), TV \(remoteSum.prefix(8)))")
        }

        let finalOut = try await shell(
            adb,
            "chmod 700 \(Self.uploadPath) && mv -f \(Self.uploadPath) \(Self.remotePath) && echo GLASSKB_FINAL_OK"
        )
        guard finalOut.contains("GLASSKB_FINAL_OK") else {
            throw fail(12, "could not finalise helper: \(finalOut.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: - Launch

    private func launch(adb: AdbConnection) async throws -> AdbStream {
        report("Virtual keyboard: starting persistent TCP helper…")
        guard await PersistentHelper.launch(
            adb: adb,
            name: Self.helperName,
            match: Self.helperName,
            command: "exec \(Self.remotePath)",
            ready: "READY"
        ), let input = await PersistentHelper.openInput(adb: adb, name: Self.helperName) else {
            throw fail(22, "persistent TCP keyboard helper failed: \(PersistentHelper.fallbackNote(Self.helperName))")
        }
        return input
    }

    // MARK: - Small helpers

    private func report(_ text: String) {
        onStatus?(text)
    }

    private func fail(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "GlassRemoteKeyboard", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func sizeCommand(_ path: String) -> String {
        "if [ -f \(path) ]; then wc -c < \(path); else echo MISSING; fi"
    }

    private func parseSize(_ output: String) -> Int? {
        output
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Int($0) }
            .first
    }

    private func parseSHA1(_ output: String) -> String? {
        guard let token = output.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        let candidate = String(token).lowercased()
        let isHex = candidate.count == 40 && candidate.allSatisfy { $0.isHexDigit }
        return isHex ? candidate : nil
    }

    /// Runs `shell:<command>` and reads until the TV closes the stream.
    /// Kept separate from the model's runShell so the two cannot affect each other.
    private func shell(_ adb: AdbConnection, _ command: String) async throws -> String {
        let stream = try await adb.open(destination: "shell:\(command)")
        var result = Data()

        while true {
            let streamClosed = await stream.getIsClosed()
            if streamClosed { break }

            do {
                let chunk = try await stream.read()
                if chunk.isEmpty { break }
                result.append(chunk)
            } catch {
                let closedAfterError = await stream.getIsClosed()
                if closedAfterError { break }
                throw error
            }
        }

        return String(decoding: result, as: UTF8.self)
    }
}
