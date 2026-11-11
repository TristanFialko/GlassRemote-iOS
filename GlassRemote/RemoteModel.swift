import Foundation
import CryptoKit
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

    /// True until the first successful connect has saved an address: shows the welcome / scan flow.
    let isFirstRun = UserDefaults.standard.object(forKey: "tvHost") == nil

    // Pointer feel. Sensitivity is the base gain (the previous fixed value was 2.0); acceleration
    // adds extra gain on fast swipes while slow movements stay precise.
    @Published var mouseSensitivity: Double = {
        let saved = UserDefaults.standard.double(forKey: "glassRemote.mouseSensitivity")
        return saved == 0 ? 2.0 : min(4.0, max(0.5, saved))
    }() {
        didSet { UserDefaults.standard.set(mouseSensitivity, forKey: "glassRemote.mouseSensitivity") }
    }
    @Published var mouseAcceleration: Bool = (UserDefaults.standard.object(forKey: "glassRemote.mouseAcceleration") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(mouseAcceleration, forKey: "glassRemote.mouseAcceleration") }
    }
    /// Keyboard sheet: forward each keystroke to the TV as it is typed.
    @Published var liveTyping: Bool = UserDefaults.standard.bool(forKey: "glassRemote.liveTyping") {
        didSet { UserDefaults.standard.set(liveTyping, forKey: "glassRemote.liveTyping") }
    }

    enum LinkState { case connected, connecting, reconnectNeeded, offline }

    /// Connection state for the header, derived from real flags instead of parsing `status` text.
    var linkState: LinkState {
        if requiresUserReconnect { return .reconnectNeeded }
        if connected { return .connected }
        if isBusyConnecting { return .connecting }
        return .offline
    }

    // Media, volume routing (see RemoteModel+Features.swift)
    @Published var media = MediaState.idle
    @Published var samsungStatus = "Samsung TV: off"
    /// Samsung remote WebSocket (keys, pairing). Independent of the UPnP volume link below.
    @Published private(set) var samsungRemoteReady = false
    // Real volume read from the TV over UPnP RenderingControl (see SamsungVolume.swift).
    /// Samsung UPnP RenderingControl (real TV volume). Independent of the WebSocket above.
    @Published var volumeLinkReady = false
    var samsungVolumeReady: Bool { volumeLinkReady }
    @Published private(set) var samsungDiagnostics = "No Samsung keys sent yet"
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
    /// Every device reading, numbered, so the slider settles on it even when the value repeats.
    @Published var volumeReading: VolumeReadingEvent?
    var volumeReadingSerial = 0
    /// Who owns the slider: the finger, the hold-off after it, or the device (VolumeScale.swift).
    var volumeSync = VolumeSync()
    var volumeReconcileTask: Task<Void, Never>?
    var tvSupervisorTask: Task<Void, Never>?

    let apps: [TVApp] = [
        .init(name: "Netflix", package: "com.netflix.ninja", asset: "netflix"),
        .init(name: "YouTube", package: "com.google.android.youtube.tv", asset: "youtube"),
        .init(name: "Nuvio", package: "com.nuvio.app", asset: "nuvio"),
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
    var mouseStream: AdbStream?
    var mouseReady = false

    // Custom white pointer on the TV (glass_cursor_setter.jar + glass_cursor_white.png).
    // Independent of the mouse: its failure never affects mouse or keyboard startup.
    /// TCP client attached to the persistent cursor helper; writes "R" to reapply the icon.
    var cursorInput: AdbStream?
    var cursorQueue = TaskQueue()
    var lastCursorNudge = Date.distantPast
    var cursorTrailTask: Task<Void, Never>?
    @Published var cursorStatus = "Cursor: not started"
    @Published var playbackDiagnostics = "No diagnostics captured yet. Reproduce the playback interruption, then capture diagnostics before reconnecting if possible."
    private var commandQueue = TaskQueue()
    var reportQueue = TaskQueue()

    // Pointer motion is coalesced: touch moves only add to these counters, and one queued drain
    // writes whatever has accumulated. The ADB write queue can therefore never build a backlog
    // of stale single-pixel reports (the cause of lag, rubber-banding and late jumps).
    var pendingMoveDX = 0
    var pendingMoveDY = 0
    var moveDrainQueued = false
    var mouseButtonsHeld = 0

    // Virtual HID keyboard: fully independent subsystem (see VirtualKeyboard.swift).
    let keyboard = VirtualKeyboard()
    @Published var keyboardStatus = "Virtual keyboard: not started"

    // Connection lifecycle. `sessionID` changes on every connect/disconnect so a slow or
    // superseded task can never overwrite the state of a newer session.
    var wantsConnection = false
    var sessionID = 0
    var connectingSession: Int?
    private var recoveryTask: Task<Void, Never>?
    var mediaTask: Task<Void, Never>?
    // v0.4: transport command in flight (see RemoteModel+Playback.swift)
    var mediaCommandTask: Task<Void, Never>?
    @Published var mediaCommandPending = false
    /// What the last Rewind / Fast-forward measurably did, and what each key has been learned to do.
    @Published var lastSeek: SeekReport?
    @Published var seekLearner = SeekStepLearner.load()

    // v0.4: dual-device remote
    @Published var target: RemoteTarget = RemoteTarget.restored(from: UserDefaults.standard.string(forKey: "glassRemote.target")) {
        didSet {
            UserDefaults.standard.set(target.rawValue, forKey: "glassRemote.target")
            if target != oldValue { samsungPlayPause = .unknown }
        }
    }
    @Published private(set) var samsungState: SamsungLinkState = .off {
        didSet { if samsungState != .connected { samsungPlayPause = .unknown } }
    }
    /// What the Samsung Play/Pause button last SENT. The TV exposes no playback state over the
    /// remote WebSocket, so this is never confirmed playback state; it resets to unknown whenever
    /// the target changes or the TV link leaves `.connected`.
    @Published var samsungPlayPause: SamsungPlayPauseGuess = .unknown

    // v0.4: volume range calibration and drag protection (see VolumeCalibration.swift)
    @Published var volumeCalibration = VolumeCalibration.loaded()
    var endpointLearner = EndpointLearner()
    var volumeDragActive = false
    var rebootRecoveryTask: Task<Void, Never>?
    var appActive = true
    let tv = SamsungTV()
    private var lastKeyboardRestart = Date.distantPast
    /// Recovery requests raised while iOS is inactive are held until foreground.
    var recoveryPending = false
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
        tv.onState = { [weak self] state in self?.samsungState = state }
        tv.onStats = { [weak self] stats in self?.samsungDiagnostics = stats.summary }
        // v5 §5: a key the TV connection accepted and then failed is reported, never re-sent over ADB.
        tv.onSendFailed = { [weak self] name in self?.samsungSendFailed(name) }
        tv.onReadyChanged = { [weak self] ready in
            self?.samsungRemoteReady = ready
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
                // The package list only labels app tiles. Re-running `pm list packages` on
                // every reconnect adds avoidable load while a video may be playing.
                if installed.isEmpty { await refreshApps() }
                guard session == sessionID else { return }
                applyTVSettings()
                // Independent startups: a failed or stuck mouse helper must never keep the
                // keyboard from starting (startMouse also handles its own errors).
                _ = await withDeadline(30) { await self.startMouse() }
                guard session == sessionID else { return }
                await startKeyboard()
                guard session == sessionID else { return }
                // Media status is independent of the cursor. Start it before the optional
                // cursor setup so a slow cursor helper cannot delay Now Playing recovery.
                startMediaPolling()
                reconnectAttempt = 0
                // The optional cursor step is bounded and must not hold the session in
                // "connecting" or delay the media poller.
                if connectingSession == session { connectingSession = nil }
                _ = await withDeadline(40) { await self.startCursor() }
                guard session == sessionID else { return }

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
        // The tile's PressStyle already gave haptic feedback.
        Task { await launchApp(app) }
    }

    /// Force-stops and relaunches one selected app without rebooting the TV box.
    func restartApp(_ app: TVApp) {
        Task {
            guard let connection = adb, connected else {
                status = "Cannot restart \(app.name) · not connected"
                return
            }
            status = "Restarting \(app.name)…"
            do {
                let command = "am force-stop '\(app.package)' && sleep 1 && monkey -p '\(app.package)' 1 2>&1; rc=$?; echo GLASSREMOTE_RESTART_EXIT:$rc"
                let output = try await runShell(connection, ["sh", "-c", command])
                if output.contains("GLASSREMOTE_RESTART_EXIT:0") {
                    status = "\(app.name) restarted"
                    GRLog.note("apps", "user restarted \(app.package)")
                } else {
                    status = "Restart response · \(app.name): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            } catch {
                status = "Restart failed · \(app.name): \(error.localizedDescription)"
            }
            Haptics.medium()
        }
    }

    /// Captures a bounded, read-only Android logcat slice plus persistent-helper state.
    /// Run after a playback interruption so the TV-side process/activity events are still in the ring buffer.
    func capturePlaybackDiagnostics() {
        Task {
            guard let connection = adb, connected else {
                playbackDiagnostics = "Connect to the TV box before capturing diagnostics."
                return
            }
            playbackDiagnostics = "Collecting recent TV logs…"
            let command = """
            echo '=== ANDROID TCP HELPER ENVIRONMENT ==='
            echo "id=$(id 2>&1)"
            echo "shell=$SHELL"
            echo "nc-path=$(command -v nc 2>&1)"
            echo "tmp-dir=$(ls -ld /data/local/tmp 2>&1)"
            echo "tcp-server=$(ls -l /data/local/tmp/glass_tcp_input_server 2>&1)"
            echo '=== PERSISTENT TCP HELPERS ==='
            for entry in 'glass_uhid_bridge 47631' 'glass_uhid_keyboard 47632' 'glass_cursor 47633'; do
              set -- $entry; n=$1; port=$2
              echo "--- $n port=$port ---"
              if [ -s /data/local/tmp/$n.pid ]; then
                P=$(cat /data/local/tmp/$n.pid); echo "pid=$P"
                if [ -r /proc/$P/cmdline ]; then tr '\000' ' ' < /proc/$P/cmdline; echo; else echo 'process=not-running'; fi
              else echo 'pid-file=missing'; fi
              if nc -z -w 1 127.0.0.1 "$port" 2>/dev/null; then echo 'tcp-listener=PASS'; else echo 'tcp-listener=FAIL'; fi
              if [ -f /data/local/tmp/$n.log ]; then tail -n 22 /data/local/tmp/$n.log; else echo 'helper-log=missing'; fi
            done
            echo '=== RECENT PLAYBACK / INPUT / ACTIVITY LOG ==='
            logcat -d -v threadtime -t 1400 2>&1 | grep -i -E 'nuvio|InputReader|InputDispatcher|InputManager|ActivityTaskManager|ActivityManager|WindowManager|MediaSession|am_proc_died|Start proc|Displayed|Configuration' | tail -n 220
            """
            do {
                let output = try await runShell(connection, ["sh", "-c", command])
                playbackDiagnostics = output.isEmpty ? "No matching log lines were returned. Reproduce the issue and capture immediately afterwards." : output
                GRLog.note("diagnostics", "captured TV helper state and filtered logcat (\(output.count) chars)")
            } catch {
                playbackDiagnostics = "Diagnostics capture failed: \(error.localizedDescription)"
            }
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
        // v5 §5: volume and mute never reach the Android box; they go to the Samsung TV or nowhere.
        if VolumeKeyPolicy.isVolumeKey(key) { volume(key, haptic: false); return }
        // Samsung-only keys (power, source) go to the TV, not the Android box.
        if SamsungTV.tvOnlyKeys.contains(key) {
            if !tv.send(key) { status = "TV key needs the Samsung link · enable it in Settings" }
            return
        }
        let adbCodes: [String: String] = [
            "UP": "19", "DOWN": "20", "LEFT": "21", "RIGHT": "22",
            "OK": "23", "BACK": "4", "HOME": "3"
        ]

        guard connected else {
            status = "Button failed · not connected"
            return
        }

        // Keep frequent navigation on persistent virtual HID. Only use ADB for
        // controls that are not currently routed through the verified HID path.
        // Buttons give their own haptic on press (PressStyle); keys sent programmatically stay silent.
        if keyboard.send(key) { return }

        guard let code = adbCodes[key] else {
            status = "Unknown button: \(key)"
            return
        }

        // ADB fallback is deliberately limited to system/media controls. D-pad and
        // OK never fall back to ADB, avoiding extra shell input traffic during playback.
        let adbOnlyControls: Set<String> = [
            "BACK", "HOME"
        ]
        guard adbOnlyControls.contains(key) else {
            status = "Virtual keyboard unavailable · reconnect to restore navigation"
            GRLog.note("keyboard", "ignored \(key): HID required; ADB fallback disabled for navigation")
            return
        }

        sendPersistentCommand("input keyevent \(code)")
    }

    /// Types text on the TV. Handles spaces, newlines, quotes, URLs and a literal "%s"
    /// (which Android's `input text` would otherwise turn into a space). Android's
    /// `input text` can only type ASCII.
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        let lines = text.components(separatedBy: .newlines)
        let hasNonASCII = !text.allSatisfy { $0.isASCII }

        guard connected, commandStream != nil else {
            status = "Text entry failed · not connected"
            return
        }

        // One already-open shell runs every chunk in order (no new ADB stream per chunk).
        for (index, line) in lines.enumerated() {
            for chunk in Self.textChunks(line, maxLength: 160) {
                sendPersistentCommand("input text \(TVShell.quote(Self.escapeInputText(chunk)))")
            }
            if index < lines.count - 1 {
                sendPersistentCommand("input keyevent 66")
            }
        }
        status = hasNonASCII
            ? "Text sent · characters outside ASCII can't be typed over ADB"
            : "Text sent"
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

    /// Runs a command on the TV box and returns its output (see `TVShell`).
    func runShell(_ connection: AdbConnection, _ args: [String]) async throws -> String {
        try await TVShell.run(connection, args)
    }

    private func startKeyboard() async {
        guard let adb else { return }
        // Bounded so a dead transport can never stall connect() or recovery forever.
        _ = await withDeadline(30) { await self.keyboard.start(adb: adb) }
    }

    // MARK: - Lifecycle: teardown and recovery

    /// Detaches every session object first, then closes the old (possibly dead) ones with a
    /// deadline each. Close calls on a broken socket can otherwise block indefinitely.
    private func teardownSession() async {
        GRLog.note("adb", "teardownSession: closing phone-side ADB streams + transport; persistent TV helpers should retain UHID devices")
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
    func recoverIfNeeded() {
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

        // ADB can remain healthy while iOS has dropped one of its shell streams. Check the
        // mouse stream's explicit closed state as well as its readiness flag; it has no reader
        // task, so a dead stream may otherwise remain marked ready until the next pointer move.
        if let mouseStream, await mouseStream.getIsClosed() {
            self.mouseStream = nil
            mouseReady = false
            GRLog.note("mouse", "phone-side input stream was closed while backgrounded")
        }

        // Reattach ONLY to helpers that are already alive on the TV; never launch a new UHID
        // device during automatic foreground recovery, because Android may treat enumeration
        // as a configuration change and interrupt the foreground video app.
        if !mouseReady {
            if let input = await PersistentHelper.attach(adb: connection, name: "glass_uhid_bridge", match: "glass_uhid_bridge") {
                mouseStream = input
                pendingMoveDX = 0; pendingMoveDY = 0; mouseButtonsHeld = 0
                mouseReady = true
                status = "Connected · mouse reattached to existing TV helper"
                GRLog.note("mouse", "reattached to existing helper without UHID recreation")
            } else {
                requiresUserReconnect = true
                status = "Connected · mouse helper missing on TV; tap Connect to recreate it"
                GRLog.note("mouse", "persistent helper missing; automatic recovery stopped to avoid playback disruption")
                return
            }
        }
        if !keyboard.isReady {
            let restored = await keyboard.reattachExisting(adb: connection)
            guard restored else {
                requiresUserReconnect = true
                status = "Connected · keyboard helper missing on TV; tap Connect to recreate it"
                GRLog.note("keyboard", "persistent helper missing; automatic recovery stopped to avoid HID recreation")
                return
            }
        }
        // Reopen the phone-side cursor feed on every foreground recovery. This is cheap when
        // the TV helper is alive and repairs a stale TCP client left by iOS suspension.
        _ = await withDeadline(15) { await self.startCursor() }
        recoveryPending = false
    }
}
