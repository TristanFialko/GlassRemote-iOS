import Foundation
import SwiftADB

/// Independent virtual HID keyboard subsystem.
///
/// Nothing here shares state with the mouse: separate helper binary, separate remote
/// path, separate ADB stream, separate queue, separate readiness flag, separate errors.
/// `start` never throws, so a keyboard failure cannot affect the mouse or the app's
/// connection state. While the keyboard is not ready, `send` returns false. Arrows and OK
/// have no ADB fallback (RemoteModel.key reports that the helper needs a reconnect);
/// BACK/HOME are not routed here and always use ADB `input keyevent`.
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
        "HOME": .consumer(0x223)                // AC Home
        // No volume or mute usages: the box route sends ADB keyevents, as Phase 7.2 did (VolumeOutput.swift).
    ]

    /// Buttons actually routed through the virtual keyboard. The rest stay on the
    /// existing ADB keyevent path until their Android mapping is verified on the TV.
    /// Once a button is verified, add its name here (e.g. "BACK").
    static let routedKeys: Set<String> = ["UP", "DOWN", "LEFT", "RIGHT", "OK"]

    private static let helperName = "glass_uhid_keyboard"
    private static let remotePath = "/data/local/tmp/glass_uhid_keyboard"

    /// Human-readable keyboard status (shown in the Connection sheet).
    var onStatus: ((String) -> Void)?
    /// Called with a routed button whose write failed after being accepted, so the caller can
    /// report it. Navigation has no ADB fallback; live-typing failures go to `type`'s callback instead.
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
            let helperData = try await loadBundledHelper(adb: adb)
            try await TVShell.install(adb, data: helperData, remote: Self.remotePath, mode: "700") { [weak self] text in
                self?.report("Virtual keyboard: \(text)")
            }
            let newStream = try await launch(adb: adb)

            guard gen == generation else {
                try? await newStream.close()
                return
            }

            stream = newStream
            isReady = true
            report("Virtual keyboard: running · helper verified (\(helperData.count) bytes)" + PersistentHelper.fallbackNote(Self.helperName))
            startReader(newStream, generation: gen)
        } catch {
            isReady = false
            stream = nil
            report("Virtual keyboard unavailable · reconnect the TV box to restore arrows, OK and typing: \(error.localizedDescription)")
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

    /// How long BACK/HOME wait for earlier arrow reports before going out anyway (BUG-023).
    static let orderingDeadline: Double = 0.3

    /// Finishes once every report queued before this call has been written (or has failed).
    func pendingWrites() -> Task<Void, Never> { queue.barrier() }

    /// `name` is nil for live-typing text, which is not a button and has no fallback.
    private func writeFailed(_ error: Error, key name: String?, generation gen: Int) {
        guard gen == generation else { return }
        let wasReady = isReady
        isReady = false
        report("Virtual keyboard stream failed · arrows, OK and typing paused until it reconnects: \(error.localizedDescription)")
        if wasReady {
            if let name { onFallback?(name) }
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
        report("Virtual keyboard: stopped · arrows, OK and typing paused until it reconnects" + (text.isEmpty ? "" : ": \(text)"))
        onStopped?()
    }

    // MARK: - Helper discovery

    private func loadBundledHelper(adb: AdbConnection) async throws -> Data {
        guard let url = await TVShell.bundledHelper(adb, Self.helperName) else {
            let root = Bundle.main.resourceURL?.path ?? "unavailable"
            throw fail(1, "\(Self.helperName) is not inside the app bundle (\(root)). The CI step 'Bundle and verify helpers' must copy it into the .app")
        }

        let data = try Data(contentsOf: url)
        guard data.count > 64 else {
            throw fail(2, "bundled helper is only \(data.count) bytes (placeholder file?)")
        }

        // The TV needs a little-endian ARM ELF executable: 32-bit ARM (0x28) or AArch64 (0xB7).
        guard let elf = TVShell.elfMachine(data),
              (!elf.is64 && elf.machine == 0x28) || (elf.is64 && elf.machine == 0xB7) else {
            let hex = data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
            throw fail(3, "bundled helper is not an ARM ELF (first bytes: \(hex))")
        }
        return data
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
}

// MARK: - Live typing (HID)

extension VirtualKeyboard {
    static let backspaceUsage: UInt8 = 0x2A
    static let enterUsage: UInt8 = 0x28

    /// US-layout HID usage for one character; `shift` is true for capitals and shifted symbols.
    /// Returns nil for anything outside ASCII (the TV keyboard cannot type those).
    nonisolated static func hid(for character: Character) -> (usage: UInt8, shift: Bool)? {
        guard let ascii = character.asciiValue else { return nil }
        let c = Character(UnicodeScalar(ascii))
        switch c {
        case "a"..."z": return (0x04 + UInt8(ascii - 97), false)
        case "A"..."Z": return (0x04 + UInt8(ascii - 65), true)
        case "1"..."9": return (0x1E + UInt8(ascii - 49), false)
        case "0": return (0x27, false)
        case " ": return (0x2C, false)
        case "\n": return (0x28, false)
        case "\t": return (0x2B, false)
        default: break
        }
        let plain: [Character: UInt8] = ["-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30, "\\": 0x31,
                                         ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38]
        if let usage = plain[c] { return (usage, false) }
        let shifted: [Character: UInt8] = ["!": 0x1E, "@": 0x1F, "#": 0x20, "$": 0x21, "%": 0x22, "^": 0x23,
                                           "&": 0x24, "*": 0x25, "(": 0x26, ")": 0x27, "_": 0x2D, "+": 0x2E,
                                           "{": 0x2F, "}": 0x30, "|": 0x31, ":": 0x33, "\"": 0x34, "~": 0x35,
                                           "<": 0x36, ">": 0x37, "?": 0x38]
        if let usage = shifted[c] { return (usage, true) }
        return nil
    }

    /// Protocol lines (`K`/`S <usage>`) that type `text`. Characters the keyboard can't produce are skipped.
    nonisolated static func lines(forTyping text: String) -> [String] {
        text.compactMap { character in
            hid(for: character).map { ($0.shift ? "S " : "K ") + String($0.usage) + "\n" }
        }
    }

    /// Most backspaces and characters one `type` call sends. Callers split longer edits into
    /// steps of this size (LiveTypingDiff.step) so nothing is silently dropped (BUG-019).
    nonisolated static let liveTypingLimit = 400

    /// Types through the virtual keyboard. Returns false when it isn't ready, so the caller keeps
    /// the text as undelivered. `onWriteFailure` runs if the write fails after being accepted.
    func type(_ text: String, backspaces: Int = 0, onWriteFailure: (@MainActor () -> Void)? = nil) -> Bool {
        guard isReady, let stream else { return false }
        var payload = String(repeating: "K \(Self.backspaceUsage)\n", count: min(max(backspaces, 0), Self.liveTypingLimit))
        payload += Self.lines(forTyping: String(text.prefix(Self.liveTypingLimit))).joined()
        guard !payload.isEmpty else { return true }
        let data = Data(payload.utf8)
        let gen = generation
        queue.enqueue { [weak self] in
            do { try await stream.write(data) } catch {
                await MainActor.run {
                    self?.writeFailed(error, key: nil, generation: gen)
                    onWriteFailure?()
                }
            }
        }
        return true
    }
}
