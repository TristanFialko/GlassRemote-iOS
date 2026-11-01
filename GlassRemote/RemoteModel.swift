import Foundation
import SwiftUI
import SwiftADB
import UIKit

struct TVApp: Identifiable {
    let name: String
    let package: String
    let asset: String
    var id: String { package }
}

@MainActor
final class RemoteModel: ObservableObject {
    /// Shared so Siri / Shortcuts intents drive the same connection as the UI.
    static let shared = RemoteModel()

    @Published var host = UserDefaults.standard.string(forKey: "tvHost") ?? "192.168.1.70"
    @Published var port = UserDefaults.standard.integer(forKey: "tvPort") == 0
        ? "5555"
        : String(UserDefaults.standard.integer(forKey: "tvPort"))
    @Published var status = "Not connected"
    @Published var connected = false
    @Published var installed = Set<String>()
    @Published var showConnection = false
    @Published var isTrackpad = true

    // Media, quick actions, volume routing (see RemoteModel+Features.swift)
    @Published var media = MediaState.idle
    @Published var runningQuickActionID: UUID?
    @Published var samsungStatus = "Samsung TV: off"
    @Published private(set) var tvVolumeReady = false
    // Real volume read from the TV over UPnP RenderingControl (see SamsungVolume.swift).
    @Published var volumeLinkReady = false
    @Published var tvVolumeFraction: Double?
    @Published var volumeStatus = "TV volume: not read yet"
    let volumeLink = SamsungVolumeLink()
    /// Last time the user touched the slider; TV readings are not pushed onto it right after.
    var lastUserVolumeInput = Date.distantPast
    // On by default: the TV route is what controls the soundbar. Only an explicit "off" is kept.
    @Published var tvVolumeEnabled: Bool = {
        let d = UserDefaults.standard
        return d.object(forKey: "glassRemote.tvVolumeEnabled") == nil ? true : d.bool(forKey: "glassRemote.tvVolumeEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(tvVolumeEnabled, forKey: "glassRemote.tvVolumeEnabled")
            applyTVSettings()
        }
    }
    static let defaultSamsungHost = "192.168.1.166"
    @Published var samsungHost: String = {
        let saved = (UserDefaults.standard.string(forKey: "glassRemote.samsungHost") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? RemoteModel.defaultSamsungHost : saved
    }() {
        didSet { UserDefaults.standard.set(samsungHost, forKey: "glassRemote.samsungHost") }
    }

    /// Highest level of the soundbar's own volume scale (what one full slider sweep covers).
    /// Each VOLUP/VOLDOWN press moves the soundbar one level, so the slider must span this
    /// many presses to reach the soundbar's real maximum. Match it to your soundbar's display.
    @Published var tvVolumeMax: Int = {
        let saved = UserDefaults.standard.integer(forKey: "glassRemote.tvVolumeMax")
        return saved > 0 ? saved : 100
    }() {
        didSet {
            let clamped = min(max(tvVolumeMax, 5), 200)
            if clamped != tvVolumeMax { tvVolumeMax = clamped; return }
            UserDefaults.standard.set(tvVolumeMax, forKey: "glassRemote.tvVolumeMax")
            volumeStateReset()
        }
    }

    // Slider -> volume key mapping state (logic in RemoteModel+Features.swift).
    var volumeLevelsInUse = 0
    var volumeAssumedLevel = 0
    var volumeLevelKnown = false
    var volumePendingSteps = 0
    var volumeDrainTask: Task<Void, Never>?
    var tvSupervisorTask: Task<Void, Never>?

    let apps: [TVApp] = [
        .init(name: "Netflix", package: "com.netflix.ninja", asset: "netflix"),
        .init(name: "YouTube", package: "com.google.android.youtube.tv", asset: "youtube"),
        .init(name: "Stremio", package: "com.stremio.one", asset: "stremio"),
        .init(name: "RetroArch", package: "com.retroarch", asset: "retroarch"),
        .init(name: "Prime Video", package: "com.amazon.amazonvideo.livingroom", asset: "prime-video"),
        .init(name: "Disney+", package: "com.disney.disneyplus", asset: "disney"),
        .init(name: "Sunshine", package: "com.limelight", asset: "moonlight"),
        .init(name: "Spotify", package: "com.spotify.tv.android", asset: "spotify"),
        .init(name: "Rhenium", package: "com.nitesh.rhenium", asset: "rhenium")
    ]

    var adb: AdbConnection?
    private var commandStream: AdbStream?
    private var commandReaderTask: Task<Void, Never>?
    private var mouseStream: AdbStream?
    private var mouseReady = false

    // Custom white pointer on the TV (glass_cursor_setter.jar + glass_cursor_white.png).
    // Independent of the mouse: its failure never affects mouse or keyboard startup.
    private var cursorStream: AdbStream?
    private var cursorReaderTask: Task<Void, Never>?
    @Published var cursorStatus = "Cursor: not started"
    private var commandQueue = TaskQueue()
    private var reportQueue = TaskQueue()

    // Pointer motion is coalesced: touch moves only add to these counters, and one queued drain
    // writes whatever has accumulated. The ADB write queue can therefore never build a backlog
    // of stale single-pixel reports (the cause of lag, rubber-banding and late jumps).
    private var pendingMoveDX = 0
    private var pendingMoveDY = 0
    private var moveDrainQueued = false
    private var mouseButtonsHeld = 0

    // Virtual HID keyboard: fully independent subsystem (see VirtualKeyboard.swift).
    private let keyboard = VirtualKeyboard()
    @Published var keyboardStatus = "Virtual keyboard: not started"

    // Connection lifecycle. `sessionID` changes on every connect/disconnect so a slow or
    // superseded task can never overwrite the state of a newer session.
    var wantsConnection = false
    var sessionID = 0
    var connectingSession: Int?
    private var recoveryTask: Task<Void, Never>?
    var mediaTask: Task<Void, Never>?
    var quickActionTask: Task<Void, Never>?
    var rebootRecoveryTask: Task<Void, Never>?
    var appActive = true
    let tv = SamsungTV()
    private var lastKeyboardRestart = Date.distantPast
    /// Recovery requests raised while iOS is inactive are held until foreground.
    private var recoveryPending = false
    /// Set after an automatic recovery cannot validate the transport; only an explicit
    /// user reconnect may then close/recreate the UHID streams.
    private(set) var requiresUserReconnect = false

    init() {
        keyboard.onStatus = { [weak self] text in self?.keyboardStatus = text }
        // If a keyboard write fails after being accepted, re-send that press over ADB.
        keyboard.onFallback = { [weak self] name in self?.key(name) }
        // A keyboard stream that ended on its own is repaired automatically.
        keyboard.onStopped = { [weak self] in self?.keyboardStopped() }

        tv.onStatus = { [weak self] text in self?.samsungStatus = text }
        // A volume key accepted by the TV connection that then failed is re-sent over ADB.
        tv.onSendFailed = { [weak self] name in self?.key(name) }
        tv.onReadyChanged = { [weak self] ready in
            self?.tvVolumeReady = ready
            self?.volumeStateReset()
        }
        // Connect to the Samsung TV on launch and keep it connected, independent of ADB.
        startTVSupervisor()
        configureVolumeLink()

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Log-only. Leaving the app must never send anything to the TV box.
            GRLog.note("lifecycle", "willResignActive (no device commands sent)")
            Task { @MainActor in
                self?.appActive = false
                self?.recoveryPending = true
            }
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            GRLog.note("lifecycle", "didEnterBackground")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            GRLog.note("lifecycle", "willEnterForeground")
        }

        // iOS may suspend the app and drop its sockets. Check the session whenever the app
        // becomes active again and repair only what is actually broken.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                GRLog.note("lifecycle", "didBecomeActive connected=\(self.connected) mouseReady=\(self.mouseReady) recovering=\(self.isBusyConnecting)")
                self.appActive = true
                GRLog.note("lifecycle", "foreground recovery check pending=\(self.recoveryPending)")
                self.recoverIfNeeded()
                self.applyTVSettings()
                // Do not race a read-only media poll against a health check / reconnect on a
                // socket iOS may just have killed. The 3 s polling loop resumes by itself.
            }
        }
    }

    /// True while a connect or recovery is in flight. Used to keep optional traffic off the transport.
    var isBusyConnecting: Bool { connectingSession != nil || recoveryTask != nil || rebootRecoveryTask != nil }

    func connect() {
        wantsConnection = true
        requiresUserReconnect = false
        sessionID += 1
        let session = sessionID
        connectingSession = session
        GRLog.note("adb", "connect() session=\(session)")

        Task {
            defer {
                if connectingSession == session { connectingSession = nil }
            }

            status = "Connecting…"
            keyboardStatus = "Virtual keyboard: waiting for connection"
            connected = false
            UserDefaults.standard.set(host, forKey: "tvHost")
            UserDefaults.standard.set(Int(port) ?? 5555, forKey: "tvPort")

            // Detach and close any previous (possibly dead) session first, with deadlines,
            // so a broken socket cannot stall the new connection.
            await teardownSession()
            guard session == sessionID else { return }

            do {
                let identity = try ADBIdentity.loadOrCreate()

                var builder = AdbConnection.Builder()
                builder.setHost(host.trimmingCharacters(in: .whitespacesAndNewlines))
                builder.setPort(UInt16(port) ?? 5555)
                builder.setKeyPair(identity)
                builder.setDeviceName("Glass Remote iPhone")

                let connection = try builder.build()
                let ok = try await connection.connect(timeout: 35, throwOnUnauthorised: false)

                guard session == sessionID else {
                    // Superseded by a newer connect/disconnect while connecting.
                    _ = await withDeadline(3) { await connection.close() }
                    return
                }

                guard ok else {
                    throw NSError(
                        domain: "GlassRemote",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "TV did not accept the ADB connection"]
                    )
                }

                adb = connection
                connected = true
                status = "Connected · testing ADB"

                let test = try await runShell(connection, ["echo", "GLASSREMOTE_OK"])
                guard test.contains("GLASSREMOTE_OK") else {
                    throw NSError(
                        domain: "GlassRemote",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "ADB connected, but shell test returned: \(test)"]
                    )
                }

                try await startCommandShell(connection)
                status = "Connected · low-latency shell ready"
                await refreshApps()
                guard session == sessionID else { return }
                applyTVSettings()
                // Independent startups: a failed or stuck mouse helper must never keep the
                // keyboard from starting (startMouse also handles its own errors).
                _ = await withDeadline(30) { await self.startMouse() }
                guard session == sessionID else { return }
                await startKeyboard()
                guard session == sessionID else { return }
                // Cursor appearance only: bounded and non-fatal, runs after mouse + keyboard.
                _ = await withDeadline(40) { await self.startCursor() }
                guard session == sessionID else { return }
                // Polling starts only after the mouse/keyboard helpers have finished their
                // startup handshakes, so no extra ADB stream competes with them.
                startMediaPolling()
                reconnectAttempt = 0

            } catch {
                guard session == sessionID else { return }
                connected = false
                status = "Connection failed: \(error.localizedDescription) · retrying"
                scheduleAutoReconnect()
            }
        }
    }

    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    /// Retries a failed connect with a growing delay (3 s ... 20 s) until it works or the user
    /// disconnects. Never starts a second connect while one is in flight.
    private func scheduleAutoReconnect() {
        guard wantsConnection, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = min(Double(reconnectAttempt) * 3, 20)
        GRLog.note("adb", "auto-reconnect attempt \(reconnectAttempt) in \(Int(delay)) s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.reconnectTask = nil
            guard !Task.isCancelled, self.wantsConnection, !self.connected, !self.isBusyConnecting else { return }
            if self.appActive { self.connect() } else { self.recoveryPending = true }
        }
    }

    func disconnect() {
        GRLog.note("adb", "disconnect() requested by user")
        reconnectTask?.cancel(); reconnectTask = nil
        wantsConnection = false
        sessionID += 1
        let session = sessionID
        connectingSession = nil
        connected = false
        status = "Disconnecting…"

        Task {
            await teardownSession()
            guard session == sessionID else { return }
            installed.removeAll()
            media = .idle
            status = "Disconnected"
            keyboardStatus = "Virtual keyboard: stopped"
        }
    }

    // One persistent shell is used for frequent remote key presses. This avoids
    // opening and closing an ADB shell stream for every button tap.
    private func startCommandShell(_ connection: AdbConnection) async throws {
        await stopCommandShell()

        let stream = try await connection.open(destination: "shell:sh")
        commandStream = stream

        commandReaderTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let data = try await stream.read()
                    if data.isEmpty { break }
                } catch {
                    break
                }
            }

            guard let self else { return }
            if self.commandStream === stream {
                self.commandStream = nil
                if self.connected {
                    self.status = "ADB command shell closed · reconnect to restore controls"
                }
            }
        }
    }

    private func stopCommandShell() async {
        commandReaderTask?.cancel()
        commandReaderTask = nil

        if let commandStream {
            try? await commandStream.close()
        }
        commandStream = nil
    }

    func sendPersistentCommand(_ command: String) {
        guard let stream = commandStream else {
            status = "Command shell unavailable · reconnect"
            return
        }

        // Typed text is never logged.
        GRLog.note("cmd", command.hasPrefix("input text") ? "input text <redacted>" : command)
        commandQueue.enqueue { [weak self] in
            do {
                try await stream.write(Data((command + "\n").utf8))
            } catch {
                await MainActor.run {
                    self?.status = "Command send failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // Package discovery is informational only. It never controls whether app tiles
    // are displayed, dimmed, enabled, or clickable.
    func refreshApps() async {
        guard let adb else { return }

        do {
            let output = try await runShell(adb, ["pm", "list", "packages"])
            installed = Set(
                output.components(separatedBy: .newlines).compactMap { line in
                    guard line.hasPrefix("package:") else { return nil }
                    return String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                }
            )
            status = "Connected · \(installed.count) apps found"
        } catch {
            status = "ADB connected · app scan failed: \(error.localizedDescription)"
        }
    }

    func launch(_ app: TVApp) {
        Task {
            await launchApp(app)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @discardableResult
    func launchApp(_ app: TVApp) async -> Bool {
        guard let adb else {
            status = "Cannot launch · not connected"
            return false
        }

        do {
            let output = try await runShell(
                adb,
                ["sh", "-c", "monkey -p \(app.package) 1 2>&1; rc=$?; echo GLASSREMOTE_LAUNCH_EXIT:$rc"]
            )

            // Trust the actual process exit marker before interpreting Monkey's
            // human-readable output, which can be misleading on some TV builds.
            if output.contains("GLASSREMOTE_LAUNCH_EXIT:0") {
                status = "Android accepted launch request · \(app.name)"
                return true
            } else if output.localizedCaseInsensitiveContains("no activities found") ||
                        output.localizedCaseInsensitiveContains("monkey aborted") {
                status = "Launch response · \(app.name): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
            } else {
                status = "Launch result · \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        } catch {
            status = "Launch failed: \(error.localizedDescription)"
        }
        return false
    }

    func key(_ key: String) {
        let codes: [String: String] = [
            "UP": "19", "DOWN": "20", "LEFT": "21", "RIGHT": "22",
            "OK": "23", "BACK": "4", "HOME": "3", "MENU": "82",
            "VOLUME_DOWN": "25", "MUTE": "164", "VOLUME_UP": "24"
        ]

        guard let code = codes[key] else {
            status = "Unknown button: \(key)"
            return
        }

        guard connected else {
            status = "Button failed · not connected"
            return
        }

        // Virtual HID keyboard when ready and verified for this button; otherwise ADB keyevent.
        if keyboard.send(key) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        sendPersistentCommand("input keyevent \(code)")
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Types text on the TV. Handles spaces, newlines, quotes, URLs and a literal "%s"
    /// (which Android's `input text` would otherwise turn into a space). Android's
    /// `input text` can only type ASCII.
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        let lines = text.components(separatedBy: .newlines)
        let hasNonASCII = !text.allSatisfy { $0.isASCII }

        Task {
            guard let adb else {
                status = "Text entry failed · not connected"
                return
            }

            do {
                for (index, line) in lines.enumerated() {
                    for chunk in Self.textChunks(line, maxLength: 160) {
                        _ = try await runShell(adb, ["input", "text", Self.escapeInputText(chunk)])
                    }
                    if index < lines.count - 1 {
                        _ = try await runShell(adb, ["input", "keyevent", "66"])
                    }
                }
                status = hasNonASCII
                    ? "Text sent · characters outside ASCII can't be typed over ADB"
                    : "Text sent"
            } catch {
                status = "Text entry failed: \(error.localizedDescription)"
            }
        }
    }

    /// `input text` turns "%s" into a space; spaces must therefore be written as "%s".
    nonisolated static func escapeInputText(_ chunk: String) -> String {
        chunk.replacingOccurrences(of: " ", with: "%s")
    }

    /// Splits a line so no chunk is too long and no chunk contains a literal "%s".
    nonisolated static func textChunks(_ line: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in line {
            if current.count >= maxLength || (character == "s" && current.last == "%") {
                chunks.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // SwiftADB's LocalServices.shell concatenates its argument array without
    // spaces. Build the shell destination directly and quote each argument.
    func runShell(_ connection: AdbConnection, _ args: [String]) async throws -> String {
        func shellQuote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        let command = args.map(shellQuote).joined(separator: " ")
        let stream = try await connection.open(destination: "shell:\(command)")
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

        return String(data: result, encoding: .utf8) ?? ""
    }

    private func findMouseHelper() -> URL? {
        let bundle = Bundle.main
        let roots = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }

        if let direct = bundle.url(forResource: "glass_uhid_bridge", withExtension: nil),
            FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.lastPathComponent == "glass_uhid_bridge",
                    FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }

    private func startMouse() async {
        guard let adb else { return }
        // The helper (and its UHID device) outlives the phone connection: reuse it when present.
        if let input = await PersistentHelper.attach(adb: adb, name: "glass_uhid_bridge", match: "glass_uhid_bridge") {
            mouseStream = input
            pendingMoveDX = 0; pendingMoveDY = 0; mouseButtonsHeld = 0
            mouseReady = true
            status = "Mouse ready · TV helper already running"
            return
        }
        await stopMouse()

        guard let helperURL = findMouseHelper() else {
            mouseReady = false
            let root = Bundle.main.resourceURL?.path ?? "unavailable"
            status = "Mouse helper not found · bundle resources: \(root)"
            return
        }

        do {
            let data = try Data(contentsOf: helperURL)
            guard !data.isEmpty else {
                throw NSError(
                    domain: "GlassRemote",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Bundled mouse helper is empty"]
                )
            }

            status = "Mouse helper found · uploading \(data.count) bytes"

            let upload = try await adb.open(
                destination: "exec:sh -c 'cat > /data/local/tmp/glass_uhid_bridge.upload'"
            )
            try await upload.write(data)
            try await upload.close()

            // close() returns before the TV has necessarily finished writing the file, so a
            // single `test -s` can run too early, fail silently (the && chain prints nothing)
            // and look like "TV did not confirm helper upload:". Poll the real remote size
            // instead, exactly as the keyboard uploader does.
            let expected = data.count
            var remoteBytes: Int?
            var lastOutput = ""
            for attempt in 0..<50 {
                lastOutput = try await runShell(
                    adb,
                    ["sh", "-c", "if [ -f /data/local/tmp/glass_uhid_bridge.upload ]; then wc -c < /data/local/tmp/glass_uhid_bridge.upload; else echo MISSING; fi"]
                )
                remoteBytes = lastOutput
                    .split(whereSeparator: { $0.isWhitespace })
                    .compactMap { Int($0) }
                    .first
                if remoteBytes == expected {
                    GRLog.note("mouse", "helper upload verified after \(attempt + 1) check(s)")
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard remoteBytes == expected else {
                throw NSError(
                    domain: "GlassRemote",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "helper upload incomplete: local \(expected) bytes, TV has \(remoteBytes.map(String.init) ?? "none") (last reply: \(lastOutput.trimmingCharacters(in: .whitespacesAndNewlines)))"]
                )
            }

            let chmodOutput = try await runShell(
                adb,
                ["sh", "-c", "chmod 700 /data/local/tmp/glass_uhid_bridge.upload && mv -f /data/local/tmp/glass_uhid_bridge.upload /data/local/tmp/glass_uhid_bridge && echo GLASSREMOTE_CHMOD_OK"]
            )
            guard chmodOutput.contains("GLASSREMOTE_CHMOD_OK") else {
                throw NSError(
                    domain: "GlassRemote",
                    code: 13,
                    userInfo: [NSLocalizedDescriptionKey: "could not make helper executable: \(chmodOutput.trimmingCharacters(in: .whitespacesAndNewlines))"]
                )
            }

            // Disable shell echo before exec. Read until READY rather than assuming
            // the first ADB packet contains the helper's startup message. The upload's
            // `cat` may still hold the file open for a moment after the size matches, which
            // makes exec fail with "Text file busy", so retry that case briefly.
            var launched: AdbStream?
            var lastStartupText = ""

            if await PersistentHelper.launch(adb: adb, name: "glass_uhid_bridge", match: "glass_uhid_bridge",
                                             command: "exec /data/local/tmp/glass_uhid_bridge", ready: "READY") {
                launched = await PersistentHelper.openInput(adb: adb, name: "glass_uhid_bridge")
            }

            for _ in 0..<(launched == nil ? 12 : 0) {
                let stream = try await adb.open(destination: "shell:sh")
                try await stream.write(Data("stty -echo 2>/dev/null; exec /data/local/tmp/glass_uhid_bridge\n".utf8))

                // If the helper never answers, closing the stream unblocks the read below.
                let watchdog = Task { [stream] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if !Task.isCancelled { try? await stream.close() }
                }

                var startupData = Data()
                var ready = false

                while !ready {
                    let streamClosed = await stream.getIsClosed()
                    if streamClosed { break }

                    let chunk: Data
                    do {
                        chunk = try await stream.read()
                    } catch {
                        break
                    }
                    if chunk.isEmpty { break }
                    startupData.append(chunk)

                    let response = String(data: startupData, encoding: .utf8) ?? ""
                    ready = response.contains("READY")

                    if response.contains("ERROR") || response.contains("Text file busy") {
                        break
                    }
                }

                watchdog.cancel()
                lastStartupText = String(data: startupData, encoding: .utf8) ?? ""

                if ready {
                    launched = stream
                    break
                }

                try? await stream.close()
                if lastStartupText.contains("Text file busy") {
                    GRLog.note("mouse", "helper file still busy; retrying launch")
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                break
            }

            guard let stream = launched else {
                throw NSError(
                    domain: "GlassRemote",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: lastStartupText.isEmpty
                        ? "Mouse helper exited without a READY response"
                        : "Mouse helper did not start: \(lastStartupText.trimmingCharacters(in: .whitespacesAndNewlines))"]
                )
            }

            mouseStream = stream
            pendingMoveDX = 0; pendingMoveDY = 0; mouseButtonsHeld = 0
            mouseReady = true
            status = "Mouse ready · Android UHID created"

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
        pendingMoveDX += dx
        pendingMoveDY += dy
        guard !moveDrainQueued else { return }
        moveDrainQueued = true
        reportQueue.enqueue { [weak self] in await self?.drainPointerMotion() }
    }

    /// Sets the mouse button state (1 = left down, 0 = all up), ordered with respect to motion.
    func mouseButton(_ buttons: Int) {
        guard connected, mouseReady else { return }
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

    private func startKeyboard() async {
        guard let adb else { return }
        // Bounded so a dead transport can never stall connect() or recovery forever.
        _ = await withDeadline(30) { await self.keyboard.start(adb: adb) }
    }

    // MARK: - Custom white cursor

    /// Tip of the arrow inside the 128x128 `glass_cursor_white.png` (pixels).
    private static let cursorHotspot = (x: 18, y: 8)

    private func findBundledFile(_ name: String) -> URL? {
        let bundle = Bundle.main
        if let direct = bundle.url(forResource: name, withExtension: nil),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        for root in [bundle.resourceURL, bundle.bundleURL].compactMap({ $0 }) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    /// Uploads to `<remote>.upload`, waits until the TV reports the full size (close() returns
    /// before the TV has finished writing), then moves it into place.
    private func uploadToTV(_ connection: AdbConnection, data: Data, remote: String, mode: String) async throws {
        let temp = remote + ".upload"
        let upload = try await connection.open(destination: "exec:sh -c 'cat > \(temp)'")
        try await upload.write(data)
        try await upload.close()

        var remoteBytes: Int?
        for _ in 0..<50 {
            let out = try await runShell(
                connection,
                ["sh", "-c", "if [ -f \(temp) ]; then wc -c < \(temp); else echo MISSING; fi"]
            )
            remoteBytes = out.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }.first
            if remoteBytes == data.count { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard remoteBytes == data.count else {
            throw NSError(
                domain: "GlassRemote", code: 30,
                userInfo: [NSLocalizedDescriptionKey: "\((remote as NSString).lastPathComponent) upload incomplete: local \(data.count) bytes, TV has \(remoteBytes.map(String.init) ?? "none")"]
            )
        }
        let done = try await runShell(
            connection,
            ["sh", "-c", "chmod \(mode) \(temp) && mv -f \(temp) \(remote) && echo GLASSREMOTE_FILE_OK"]
        )
        guard done.contains("GLASSREMOTE_FILE_OK") else {
            throw NSError(
                domain: "GlassRemote", code: 31,
                userInfo: [NSLocalizedDescriptionKey: "could not install \((remote as NSString).lastPathComponent): \(done.trimmingCharacters(in: .whitespacesAndNewlines))"]
            )
        }
    }

    private func startCursor() async {
        guard let adb else { return }
        await stopCursor()

        // Already running from an earlier connection: nothing to upload or restart.
        if await PersistentHelper.isRunning(adb: adb, name: "glass_cursor_setter", match: "com.glassremote.cursor") {
            cursorStatus = "Cursor: custom white cursor active (helper already running)"
            return
        }

        guard let jarURL = findBundledFile("glass_cursor_setter.jar"),
              let pngURL = findBundledFile("glass_cursor_white.png") else {
            cursorStatus = "Cursor: helper files are not inside the app bundle"
            return
        }

        do {
            cursorStatus = "Cursor: uploading…"
            let jar = try Data(contentsOf: jarURL)
            let png = try Data(contentsOf: pngURL)
            try await uploadToTV(adb, data: jar, remote: "/data/local/tmp/glass_cursor_setter.jar", mode: "644")
            try await uploadToTV(adb, data: png, remote: "/data/local/tmp/glass_cursor_white.png", mode: "644")

            let hotspot = Self.cursorHotspot
            if await PersistentHelper.launch(
                adb: adb, name: "glass_cursor_setter", match: "com.glassremote.cursor",
                command: "export CLASSPATH=/data/local/tmp/glass_cursor_setter.jar; exec app_process /system/bin com.glassremote.cursor.Main watch /data/local/tmp/glass_cursor_white.png \(hotspot.x) \(hotspot.y)",
                ready: "READY|GLASS_CURSOR_SET_OK") {
                cursorStatus = "Cursor: custom white cursor applied"
                GRLog.note("cursor", "persistent helper running")
                return
            }

            // `watch` keeps re-applying the icon so it stays white and is not reset by the
            // system while the pointer moves, hovers, clicks or drags.
            let stream = try await adb.open(destination: "shell:sh")
            let hot = Self.cursorHotspot
            let command = "stty -echo 2>/dev/null; CLASSPATH=/data/local/tmp/glass_cursor_setter.jar exec app_process /system/bin com.glassremote.cursor.Main watch /data/local/tmp/glass_cursor_white.png \(hot.x) \(hot.y)\n"
            try await stream.write(Data(command.utf8))

            let watchdog = Task { [stream] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { try? await stream.close() }
            }

            var output = Data()
            var applied = false
            while !applied {
                if await stream.getIsClosed() { break }
                let chunk: Data
                do { chunk = try await stream.read() } catch { break }
                if chunk.isEmpty { break }
                output.append(chunk)
                let text = String(decoding: output, as: UTF8.self)
                if text.contains("GLASS_CURSOR_SET_OK") || text.contains("READY") { applied = true }
                else if text.contains("GLASS_CURSOR_ERROR") { break }
            }
            watchdog.cancel()

            guard applied else {
                try? await stream.close()
                let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "GlassRemote", code: 32,
                    userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "cursor helper gave no response" : text]
                )
            }

            cursorStream = stream
            cursorStatus = "Cursor: custom white cursor applied"
            GRLog.note("cursor", "custom white cursor applied")

            // Keep draining the helper's output so its pipe never fills; note when it ends.
            cursorReaderTask = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let chunk = try await stream.read()
                        if chunk.isEmpty { break }
                    } catch { break }
                }
                await MainActor.run {
                    guard let self, self.cursorStream === stream else { return }
                    self.cursorStream = nil
                    self.cursorStatus = "Cursor: helper stopped"
                    GRLog.note("cursor", "helper stream ended")
                }
            }
        } catch {
            cursorStream = nil
            cursorStatus = "Cursor failed: \(error.localizedDescription)"
            GRLog.note("cursor", "start failed: \(error.localizedDescription)")
        }
    }

    private func stopCursor() async {
        cursorReaderTask?.cancel()
        cursorReaderTask = nil
        let old = cursorStream
        cursorStream = nil
        if let old {
            _ = await withDeadline(2) { () async -> Void in
                try? await old.write(Data("STOP\n".utf8))
                _ = try? await old.close()
            }
        }
    }

    // MARK: - Lifecycle: teardown and recovery

    /// Detaches every session object first, then closes the old (possibly dead) ones with a
    /// deadline each. Close calls on a broken socket can otherwise block indefinitely.
    private func teardownSession() async {
        GRLog.note("adb", "teardownSession: closing mouse/keyboard/command streams + ADB connection (UHID devices on the box are destroyed)")
        stopMediaPolling()
        mouseReady = false
        let oldMouse = mouseStream
        mouseStream = nil

        commandReaderTask?.cancel()
        commandReaderTask = nil
        let oldCommand = commandStream
        commandStream = nil

        let oldConnection = adb
        adb = nil

        await keyboard.stop()
        await stopCursor()

        _ = await withDeadline(2) { () async -> Void in _ = try? await oldMouse?.close() }
        _ = await withDeadline(2) { () async -> Void in _ = try? await oldCommand?.close() }
        _ = await withDeadline(3) { () async -> Void in _ = await oldConnection?.close() }
    }

    private func keyboardStopped() {
        guard wantsConnection else { return }
        // iOS may suspend or invalidate ADB streams while backgrounded. Do not start a
        // reconnect from that callback: connect() tears down both UHID streams, which
        // removes the Android input devices. Defer all repair until didBecomeActive.
        guard appActive else {
            recoveryPending = true
            GRLog.note("keyboard", "stream ended while app inactive; recovery deferred (no HID teardown)")
            return
        }
        // Back off so a helper that dies immediately cannot cause a restart loop.
        guard Date().timeIntervalSince(lastKeyboardRestart) > 5 else { return }
        lastKeyboardRestart = Date()
        recoverIfNeeded()
    }

    /// Single-flight health check. Does nothing while the user wants to be disconnected
    /// or while a connect is already in progress.
    private func recoverIfNeeded() {
        guard wantsConnection, !requiresUserReconnect else { return }
        guard appActive else {
            recoveryPending = true
            GRLog.note("adb", "recovery deferred while app inactive; keeping existing HID streams untouched")
            return
        }
        guard connectingSession == nil, recoveryTask == nil, rebootRecoveryTask == nil else { return }
        recoveryPending = false
        recoveryTask = Task { [weak self] in
            await self?.performRecovery()
            self?.recoveryTask = nil
        }
    }

    private func performRecovery() async {
        let session = sessionID

        guard appActive else {
            recoveryPending = true
            GRLog.note("adb", "recovery task entered while inactive; deferred")
            return
        }

        guard let connection = adb, connected else {
            connect()
            return
        }

        // Right after iOS resumes the app the socket can be slow rather than dead. A full
        // rebuild destroys and recreates the UHID mouse/keyboard on the box (which Android can
        // treat as an input-configuration change), so give the transport two fair chances first.
        var healthy = false
        for attempt in 1...2 {
            healthy = await withDeadline(8) { () async -> Bool in
                let output = (try? await self.runShell(connection, ["echo", "GLASSREMOTE_OK"])) ?? ""
                return output.contains("GLASSREMOTE_OK")
            } ?? false
            GRLog.note("adb", "recovery health check attempt \(attempt): \(healthy ? "ok" : "failed")")
            if !appActive {
                recoveryPending = true
                GRLog.note("adb", "app became inactive during health check; aborting before any teardown")
                return
            }
            if healthy || session != sessionID || !wantsConnection { break }
        }

        guard session == sessionID, wantsConnection else { return }
        guard appActive else {
            recoveryPending = true
            GRLog.note("adb", "app inactive before recovery action; no teardown performed")
            return
        }

        guard healthy else {
            // The TV-side helpers now outlive the phone connection (PersistentHelper), so a full
            // reconnect re-attaches to them instead of recreating the virtual input devices.
            GRLog.note("adb", "transport health checks failed; reconnecting automatically")
            connect()
            return
        }

        connected = true
        status = "Connected · low-latency shell ready"

        // The transport is healthy. Restore the shell if needed, but never recreate
        // either UHID device during automatic recovery (see guard below).
        if commandStream == nil {
            do {
                try await startCommandShell(connection)
            } catch {
                guard session == sessionID, wantsConnection else { return }
                GRLog.note("adb", "command shell repair failed; reconnecting automatically")
                connect()
                return
            }
        }
        guard session == sessionID, wantsConnection else { return }

        // Never recreate a UHID device as part of automatic resume recovery. Even if
        // ADB itself is healthy, starting a missing helper causes Android to enumerate
        // a new input device. Keep playback-facing recovery non-invasive and let the
        // user choose when to re-enumerate devices via the explicit reconnect action.
        if !mouseReady || !keyboard.isReady {
            GRLog.note("adb", "HID helper stream missing (mouse=\(mouseReady) keyboard=\(keyboard.isReady)); reconnecting automatically")
            connect()
            return
        }
        recoveryPending = false
    }
}

/// Runs `operation` but stops waiting after `seconds`. A hung operation is abandoned rather
/// than awaited, so one dead socket cannot freeze connect, disconnect or recovery.
func withDeadline<T>(_ seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = DeadlineGate<T>(continuation)
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            gate.finish(nil)
        }
        Task {
            let value = await operation()
            timer.cancel()
            gate.finish(value)
        }
    }
}

private final class DeadlineGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

final class TaskQueue {
    private var tail: Task<Void, Never> = Task {}

    func enqueue(_ operation: @escaping () async -> Void) {
        let previous = tail
        tail = Task {
            await previous.value
            await operation()
        }
    }
}
