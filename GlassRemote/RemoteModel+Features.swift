import Foundation
import SwiftUI
import UIKit

// New features layered on the existing connection, mouse and keyboard code.
// Nothing here changes the UHID protocol, the ADB identity or any Android package state.

enum PowerAction: Identifiable {
    case standby, restartLauncher, restartBox, everythingOff
    var id: Self { self }

    var title: String {
        switch self {
        case .standby: return "Put TV box in standby?"
        case .restartLauncher: return "Restart Glass Launcher?"
        case .restartBox: return "Restart TV box?"
        case .everythingOff: return "Turn off box and TV?"
        }
    }

    var message: String {
        switch self {
        case .standby: return "The box goes to sleep. Glass Remote may lose its connection until the box is awake again."
        case .restartLauncher: return "Only the launcher restarts. Glass Utility Hub is not touched."
        case .restartBox: return "Glass Remote will disconnect and reconnect automatically. This can take about a minute."
        case .everythingOff: return "The Android box goes to standby, then the Samsung TV is switched off. Turning the TV back on needs its own remote."
        }
    }

    var confirmLabel: String {
        switch self {
        case .standby: return "Standby"
        case .restartLauncher: return "Restart Launcher"
        case .restartBox: return "Restart"
        case .everythingOff: return "Turn Off Both"
        }
    }

    var isDestructive: Bool { self == .restartBox }
}

extension RemoteModel {
    // MARK: - Media

    func startMediaPolling() {
        guard mediaTask == nil else { return }
        mediaTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollMedia()
                // `dumpsys media_session` is relatively expensive on this small TV box. The elapsed
                // time is extrapolated between polls, so a playing app needs only a slow refresh and
                // an idle box an even slower one; a button press triggers its own quick re-poll.
                let playing = self?.media.isPlaying ?? false
                try? await Task.sleep(nanoseconds: (playing ? 8 : 10) * 1_000_000_000)
            }
        }
    }

    func stopMediaPolling() {
        mediaTask?.cancel()
        mediaTask = nil
        media = .idle
    }

    func pollMedia() async {
        // Strictly read-only (`dumpsys media_session`), and never while the transport is being
        // rebuilt or the app is not active.
        guard connected, appActive, !isBusyConnecting, let connection = adb else { return }
        let output = await withDeadline(6) { () async -> String in
            (try? await self.runShell(connection, ["sh", "-c", "cat /proc/uptime; dumpsys media_session"])) ?? ""
        } ?? ""
        guard connected, !output.isEmpty else { return }
        // Phase 9 recovery §4: an unreadable PlaybackState no longer resets Now Playing to idle.
        let sample = MediaParser.read(output)
        if sample == .unreadable {
            let line = output.split(whereSeparator: { $0.isNewline })
                .first(where: { $0.contains("PlaybackState {") })
                .map { String($0.trimmingCharacters(in: .whitespaces).prefix(160)) } ?? ""
            GRLog.note("media", "active session with an unreadable PlaybackState: \(line)")
        }
        let next = MediaPollPolicy.next(current: media, read: sample)
        if next != media { media = next }
    }

    /// Android media key codes: 85 play/pause, 87 next, 88 previous, 89 rewind, 90 fast-forward.
    func mediaKey(_ code: Int) {
        androidKey(code)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await pollMedia()
        }
    }

    /// Sends an Android keycode over the persistent ADB command shell.
    func androidKey(_ code: Int) {
        GRLog.note("media", "user-initiated keyevent \(code)")
        guard connected else { status = "Button failed · not connected"; return }
        sendPersistentCommand("input keyevent \(code)")   // the pressed button already gave haptic feedback
    }

    // MARK: - Volume routing

    /// Volume and mute go to the chosen output (VolumeOutput.swift). The default is Phase 7.2's
    /// soundbar route: `input keyevent 24/25/164` on the TV box over ADB, which the box forwards to
    /// the soundbar over HDMI-CEC. The Samsung remote keys and the TV's UPnP level are used only when
    /// chosen; a route that is down is reported, never swapped for one that moves other speakers.
    /// Returns whether the command was handed to its route (not proof the speakers changed).
    @discardableResult
    func volume(_ name: String, haptic: Bool = true, readBack: Bool = true) -> Bool {
        endpointLearner.invalidate()   // a volume key is a newer command: discard any pending endpoint attempt
        let route = VolumeButtonPolicy.route(for: name, command: volumeCommandRoute)
        let taken: Bool
        switch route {
        case .boxKey(let code):
            taken = commandShellReady
            if taken { sendPersistentCommand("input keyevent \(code)") }
        case .samsungKey(let key): taken = tv.send(key)
        case .upnpStep(let delta): taken = volumeLink.step(by: delta)
        case .upnpMuteToggle: taken = volumeLink.toggleMute()
        case .unavailable: taken = false
        }
        guard taken else {
            reportVolumeUnavailable()
            return false
        }
        if haptic { Haptics.soft() }
        if readBack, case .upnpStep = route { scheduleVolumeReadback() }
        if readBack, case .upnpMuteToggle = route { scheduleVolumeReadback() }
        return true
    }

    /// Whether volume +/−/mute can reach the chosen output right now.
    var volumeButtonsAvailable: Bool { volumeCommandRoute != .unavailable }

    // MARK: - Which output the volume drives (VolumeOutput.swift)

    /// The slider's and buttons' route right now.
    var volumeCommandRoute: VolumeCommandRoute {
        VolumeRoutePolicy.route(output: volumeOutput, boxConnected: connected && commandShellReady,
                                samsungEnabled: tvVolumeEnabled, remoteReady: samsungRemoteReady,
                                upnpReady: volumeLinkReady)
    }

    /// Shown in the Connection sheet.
    var volumeRouteSummary: String {
        VolumeRoutePolicy.summary(route: volumeCommandRoute, output: volumeOutput, samsungEnabled: tvVolumeEnabled)
    }

    /// Short reason for the volume row when nothing can be sent.
    var volumeUnavailableReason: String {
        VolumeRoutePolicy.unavailableReason(output: volumeOutput, samsungEnabled: tvVolumeEnabled,
                                            remoteReady: samsungRemoteReady)
    }

    /// Which output the volume rows move, shown on every row (never only in settings).
    var volumeOutputLabel: String { volumeOutput.shortLabel }

    /// The output changed: drop the assumed key position and, on the absolute route, read the real level.
    func volumeRouteChanged() {
        volumePendingSteps = 0
        volumeStateReset()
        volumeStateRoute = volumeCommandRoute
        if volumeCommandRoute == .absolute { volumeLink.refresh() }
    }

    /// A connection observation (Samsung socket, UPnP link) changed. The assumed key position is
    /// dropped only when that actually changed the active route; an unrelated device coming or going
    /// must not make the next slider touch jump.
    func volumeRouteMayHaveChanged() {
        guard VolumeStatePolicy.shouldReset(stateRoute: volumeStateRoute, currentRoute: volumeCommandRoute) else { return }
        volumeRouteChanged()
    }

    func reportVolumeUnavailable() {
        status = "Volume unavailable · \(volumeUnavailableReason)"
        GRLog.note("volume", "volume command not sent: \(volumeOutput.rawValue) route is down")
    }

    /// A Samsung key the socket accepted and then failed to deliver: reported. It is not re-sent over
    /// the box, which would move the soundbar a second time on setups where the TV key did land.
    func samsungSendFailed(_ name: String) {
        GRLog.note("samsung", "send failed for \(name); not re-sent")
        if VolumeKeyPolicy.isVolumeKey(name) { reportVolumeUnavailable() } else { status = samsungUnavailableMessage }
    }

    // MARK: - Real TV volume (UPnP RenderingControl)

    func configureVolumeLink() {
        volumeLink.isActive = { [weak self] in self?.appActive ?? false }
        volumeLink.onStatus = { [weak self] text in self?.volumeStatus = text }
        volumeLink.onAvailabilityChanged = { [weak self] available in
            guard let self else { return }
            self.volumeLinkReady = available
            self.volumeRouteMayHaveChanged()
            if !available { self.tvVolumeFraction = nil }
        }
        volumeLink.onMute = { [weak self] muted in
            self?.volumeStatus = muted ? "TV volume: muted (confirmed by the TV)" : "TV volume: unmuted (confirmed by the TV)"
        }
        volumeLink.onVolume = { [weak self] value in
            guard let self else { return }
            // Learn where this TV really stops (only after an end was commanded and the TV
            // repeatedly settles just short of it), then map through the calibration.
            // A reading outside the learned range proves the calibration wrong: go back to 0...100.
            if self.volumeCalibration != .standard, value < self.volumeCalibration.lo || value > self.volumeCalibration.hi {
                self.volumeCalibration = .standard
                VolumeCalibration.standard.save()
                self.endpointLearner.resetAll()
                GRLog.note("volume", "reading \(value) outside learned range; calibration reset")
            }
            switch self.endpointLearner.reading(value, dragging: self.volumeDragActive, calibration: self.volumeCalibration) {
            case .none: break
            case .tentative(let learned):
                self.volumeCalibration = learned   // this session only; not saved yet
                GRLog.note("volume", "TV limit seen once: \(learned.lo)...\(learned.hi) (tentative, not saved)")
            case .confirmed(let learned):
                self.volumeCalibration = learned
                learned.save()
                GRLog.note("volume", "TV limit confirmed twice: \(learned.lo)...\(learned.hi) (saved)")
            }
            let cal = self.volumeCalibration
            self.volumeStatus = self.volumeCommandRoute == .absolute
                ? "TV volume: \(value) (range \(cal.lo)–\(cal.hi), read from the TV)"
                : "TV's own level (UPnP): \(value) · not the chosen volume output"
            self.tvVolumeFraction = cal.fraction(forRaw: value)
            if self.volumeScale.route == .samsungAbsolute {
                self.publishVolumeReading(self.volumeScale.fraction(forRaw: value))
            }
        }
        if tvVolumeEnabled { volumeLink.start(host: samsungHost) }
    }

    /// Re-read the TV volume shortly after a key press so the slider follows it.
    private func scheduleVolumeReadback() {
        guard volumeLinkReady else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.volumeLink.refresh()
        }
    }

    /// False for a moment after the user touches the slider, so a reading that was already in
    /// flight cannot yank it back.
    /// Called by the slider when a finger lands / lifts. A touch discards any pending endpoint attempt.
    func volumeDragChanged(_ active: Bool) {
        volumeDragActive = active
        if active {
            endpointLearner.invalidate()
            volumeSync.dragBegan()
            volumeReconcileTask?.cancel()
        } else {
            volumeSync.dragEnded()
            scheduleVolumeReconcile()
        }
    }

    func resetVolumeCalibration() {
        volumeCalibration = .standard
        VolumeCalibration.standard.save()
        endpointLearner.resetAll()
    }

    /// Readings from the TV never move the slider while a finger is on it, nor for 2 s after the
    /// last change (the TV can lag behind a command, and a stale reading would pull the thumb back).
    var volumeSliderAcceptsExternal: Bool { volumeSync.acceptsReading() }

    /// Continuation §C2: a device reading, gated by `VolumeSync`. Returns the slider value to show,
    /// or nil while the user owns the slider (or when it would not move the thumb).
    func sliderValue(forReading fraction: Double, showing current: Double) -> Double? {
        volumeSync.reading(fraction, showing: current)
    }

    /// Continuation §C2: once the hold-off after the user's last change has passed, read the device
    /// again so the slider settles on what it really did (readings inside the window were ignored).
    func scheduleVolumeReconcile() {
        volumeReconcileTask?.cancel()
        let delay = volumeSync.holdoff + 0.1
        volumeReconcileTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.volumeSync.reconcileDue() else { return }
            self.refreshDeviceVolume()
        }
    }

    /// Reads the current target's real level, where it can report one.
    func refreshDeviceVolume() {
        switch volumeScale.route {
        case .samsungAbsolute: volumeLink.refresh()
        case .samsungKeys, .boxKeys: break   // key routes: the soundbar does not report its level
        case .unavailable: break
        }
    }

    func publishVolumeReading(_ fraction: Double) {
        volumeReadingSerial &+= 1
        volumeReading = VolumeReadingEvent(fraction: fraction, serial: volumeReadingSerial)
        // Only a real read-back moves the shared slider, and never while the user owns it.
        if let shown = volumeSync.reading(fraction, showing: volumeSliderFraction) {
            volumeSliderFraction = shown
        }
    }

    /// The user moved a volume row (drag or VoiceOver). Both rows show `volumeSliderFraction`, so
    /// this is the only way a slider value becomes a command.
    func userMovedVolumeSlider(to fraction: Double) {
        let previous = volumeSliderFraction
        let clamped = min(max(fraction, 0), 1)
        volumeSliderFraction = clamped
        setVolumeFraction(clamped, previous: previous)
    }

    // MARK: - Slider -> volume mapping

    /// Number of volume-key presses a full slider sweep spans. Through the TV this is the
    /// soundbar's own scale (`tvVolumeMax`); through the box, Phase 7.2's 20 steps.
    var volumeLevels: Int { volumeScale.steps }

    /// Continuation §C2: the current target's real range (VolumeScale.swift). Same routing as the
    /// commands (VolumeRoutePolicy): box keys, the TV's keys or the TV's absolute level, otherwise
    /// unavailable.
    var volumeScale: VolumeScale {
        switch volumeCommandRoute {
        case .absolute: return .samsungAbsolute(volumeCalibration)
        case .tvKeys: return .samsungKeys(max: tvVolumeMax)
        case .boxKeys: return .boxKeys(max: VolumeRoutePolicy.boxSteps)
        case .unavailable: return .unavailable
        }
    }

    /// Forget what we assumed about the real volume (range or route changed).
    func volumeStateReset() {
        volumeLevelKnown = false
        volumeLevelsInUse = 0
    }

    /// Maps the 0...1 slider to key presses. The slider is relative on key routes (the soundbar's
    /// level cannot be read), so its position is an estimate (`VolumeStepPlan`): reaching 0 from an
    /// unknown position presses the full range down once so the estimate becomes exact at that end,
    /// and going up only ever sends the distance the thumb moved.
    func setVolumeFraction(_ fraction: Double, previous: Double? = nil) {
        lastUserVolumeInput = Date()
        volumeSync.userChanged()
        if !volumeDragActive { scheduleVolumeReconcile() }   // VoiceOver increments settle too
        volumeRouteMayHaveChanged()
        // Absolute (0...100) only when the chosen output is the TV speakers and UPnP answers
        // (VolumeOutput.swift). The slider's full travel is then exactly that output's range.
        if volumeCommandRoute == .absolute {
            let raw = volumeScale.raw(forFraction: fraction)
            if fraction <= 0 { endpointLearner.commandSent(raw: raw, isMax: false) }
            else if fraction >= 1 { endpointLearner.commandSent(raw: raw, isMax: true) }
            else { endpointLearner.invalidate() }   // a mid-range command can never teach an end
            volumeLink.setVolume(raw)
            return
        }
        let scale = volumeScale
        // A route that is down sends nothing (never another output) and the user is told.
        guard scale.isAvailable else { reportVolumeUnavailable(); return }
        let levels = scale.steps
        // The real level this fraction commands (only the very ends reach 0 and the top).
        let target = scale.step(forFraction: fraction)

        if volumeLevelsInUse != levels {
            // Range changed: rescale the assumed position, and stop trusting it. A first use starts
            // from where the thumb was before this move, not from a fixed 50 %.
            if volumeLevelsInUse > 0 {
                volumeAssumedLevel = Int((Double(volumeAssumedLevel) / Double(volumeLevelsInUse) * Double(levels)).rounded())
            } else {
                volumeAssumedLevel = VolumeStepPlan.seed(fraction: previous ?? volumeSliderFraction, levels: levels)
            }
            volumeLevelsInUse = levels
            volumeLevelKnown = false
        }

        let plan = VolumeStepPlan.plan(target: target, assumed: volumeAssumedLevel, levels: levels,
                                       levelKnown: volumeLevelKnown)
        volumeLevelKnown = plan.levelKnown
        guard plan.delta != 0 else { return }
        volumeAssumedLevel = target
        volumePendingSteps = VolumeStepPlan.clampPending(volumePendingSteps + plan.delta, levels: levels)
        drainVolumeSteps()
    }

    private func drainVolumeSteps() {
        guard volumeDrainTask == nil else { return }
        volumeDrainTask = Task { [weak self] in
            while let self, self.volumePendingSteps != 0, !Task.isCancelled {
                let up = self.volumePendingSteps > 0
                self.volumePendingSteps += up ? -1 : 1
                // The slider already ticked each level the finger crossed (VolumeHapticPolicy), so the
                // presses stay silent; the reconcile after the drag reads the result back.
                guard self.volume(up ? "VOLUME_UP" : "VOLUME_DOWN", haptic: false, readBack: false) else {
                    // The route dropped mid-sweep: stop and forget the assumed level.
                    self.volumePendingSteps = 0
                    self.volumeLevelKnown = false
                    break
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            self?.volumeDrainTask = nil
        }
    }

    // MARK: - Samsung TV connection

    func applyTVSettings() {
        if tvVolumeEnabled, !samsungHost.trimmingCharacters(in: .whitespaces).isEmpty {
            volumeLink.start(host: samsungHost)   // idempotent; also re-reads when the app resumes
            volumeLink.refresh()
            // Never replace an attempt that is already in flight (that created duplicates).
            if !samsungRemoteReady, !tv.isAttempting, !tv.pairingBlocked { tv.connect(host: samsungHost) }
        } else {
            volumeLink.stop()
            tv.stop(report: false)
            samsungStatus = tvVolumeEnabled ? "Samsung TV: enter the TV's IP address" : "Samsung TV: off"
        }
    }

    /// Connects on launch and keeps retrying with a growing delay (2 s up to 30 s) whenever the
    /// TV is unreachable or the connection drops. Exactly one supervisor runs; it never starts
    /// a second connection while one is connecting or ready.
    func startTVSupervisor() {
        guard tvSupervisorTask == nil else { return }
        tvSupervisorTask = Task { [weak self] in
            var delay: Double = 2
            while !Task.isCancelled {
                guard let self else { return }
                let wanted = self.tvVolumeEnabled
                    && !self.samsungHost.trimmingCharacters(in: .whitespaces).isEmpty
                    && self.appActive

                if !wanted || self.tv.isReady || self.tv.pairingBlocked {
                    if self.tv.isReady { delay = 2 }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                } else if self.tv.isAttempting {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    GRLog.note("samsung", "auto-connect to \(self.samsungHost) (next retry in \(Int(delay)) s if it fails)")
                    self.tv.connect(host: self.samsungHost)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, 30)
                }
            }
        }
    }

    /// The address changed (typed, scanned or restored): after a short pause for typing, move BOTH
    /// the remote socket and the UPnP volume link to the new TV, so they never point at different
    /// TVs. The pairing token stays bound to the TV that issued it (SamsungPairingPolicy).
    func scheduleSamsungHostChange() {
        samsungHostChangeTask?.cancel()
        samsungHostChangeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            self.applySamsungHostChange()
        }
    }

    func applySamsungHostChange() {
        samsungHostChangeTask?.cancel()
        samsungHostChangeTask = nil
        GRLog.note("samsung", "TV address changed; reconnecting the remote and the volume link")
        tv.stop(report: false)
        volumeLink.stop()
        volumeRouteMayHaveChanged()
        if tvVolumeEnabled, !SamsungHostDefaults.normalized(samsungHost).isEmpty {
            volumeLink.start(host: samsungHost)
            volumeLink.refresh()
            tv.connect(host: samsungHost, userInitiated: true)
        } else {
            applyTVSettings()
        }
    }

    /// Reconnects ONLY the remote WebSocket (explicit: may ask for approval again). The UPnP
    /// volume link keeps running untouched, unless an address change is pending (then both move).
    func reconnectTV() {
        // A pending address change moves both links; doing only the socket here would split them.
        if samsungHostChangeTask != nil { applySamsungHostChange(); return }
        guard tvVolumeEnabled, !samsungHost.trimmingCharacters(in: .whitespaces).isEmpty else { applyTVSettings(); return }
        tv.connect(host: samsungHost, userInitiated: true)
    }

    /// Phase 9 recovery §3: explicit, confirmed reset (Connection sheet). Forgets ONLY the Samsung
    /// pairing token and the TV it was issued by, then connects without a token so the TV shows its
    /// Allow prompt again. ADB keys, the TV address, volume calibration and all other settings stay.
    func resetSamsungPairing() {
        GRLog.note("samsung", "user reset Samsung pairing (Samsung token only)")
        tv.resetPairing()
        reconnectTV()
    }

    /// Restarts ONLY the UPnP volume link; the remote WebSocket is not touched.
    func reconnectVolumeLink() {
        guard tvVolumeEnabled, !samsungHost.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        volumeLink.stop()
        volumeLink.start(host: samsungHost)
    }

    // MARK: - Power and device

    func standby() {
        guard connected else { status = "Standby failed · not connected"; return }
        sendPersistentCommand("input keyevent 223")   // KEYCODE_SLEEP
        status = "Standby requested"
    }

    /// Wake needs the box to still accept ADB while asleep; not verified on this device.
    func wake() {
        Task {
            if !connected {
                status = "Reconnecting to wake the box…"
                connect()
                guard await waitUntilConnected(timeout: 25) else { return }
            }
            sendPersistentCommand("input keyevent 224")   // KEYCODE_WAKEUP
            status = "Wake requested"
        }
    }

    /// Restarts only com.glasslauncher. The utility hub is a different package and is not touched.
    func restartLauncher() {
        Task {
            guard let adb else { status = "Restart failed · not connected"; return }
            status = "Restarting Glass Launcher…"
            let command = "am force-stop com.glasslauncher; am start -a android.intent.action.MAIN -c android.intent.category.HOME -n com.glasslauncher/.MainActivity"
            _ = try? await runShell(adb, ["sh", "-c", command])
            status = "Glass Launcher restarted"
        }
    }

    func restartBox() {
        Task {
            guard let adb else { status = "Restart failed · not connected"; return }
            status = "Restarting TV box…"
            _ = await withDeadline(6) { () async -> Void in
                _ = try? await self.runShell(adb, ["sh", "-c", "reboot"])
            }
            beginRebootRecovery()
        }
    }

    /// After a box restart, wait for it to come back and reconnect (single flight).
    private func beginRebootRecovery() {
        rebootRecoveryTask?.cancel()
        wantsConnection = true
        connected = false
        stopMediaPolling()
        status = "TV box restarting · will reconnect automatically"

        rebootRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)   // the box needs time to go down and boot
            var attempts = 0
            while let self, !Task.isCancelled, attempts < 30, !self.connected {
                attempts += 1
                self.connect()
                try? await Task.sleep(nanoseconds: 500_000_000)
                while self.connectingSession != nil, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                if self.connected { break }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
            if let self {
                if !self.connected { self.status = "TV box did not come back · tap the status pill to retry" }
                self.rebootRecoveryTask = nil
            }
        }
    }

    // MARK: - Helpers

    func waitUntilConnected(timeout: Double) async -> Bool {
        if connected { return true }
        if connectingSession == nil { connect() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connected { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return connected
    }

    func appName(forPackage package: String) -> String {
        apps.first(where: { $0.package == package })?.name ?? package
    }
}

// MARK: - Samsung TV keys, combined power, screenshot, live typing, discovery

extension RemoteModel {
    /// Sends one Samsung-only key (power, source). Needs the Samsung link to be connected.
    func tvKey(_ name: String) {
        key(name)
    }

    /// Box to standby, then the TV off. (A Samsung TV can't be switched ON by this app: that needs Wake-on-LAN.)
    func turnEverythingOff() {
        standby()
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !tv.send("TV_POWER") {
                status = "Box in standby · TV power needs the Samsung link"
            }
        }
    }

    /// Full-resolution PNG of what the box is showing (protected video comes back black).
    func captureScreenshot() async -> UIImage? {
        guard let connection = adb, connected else {
            status = "Screenshot failed · not connected"
            return nil
        }
        status = "Taking screenshot…"
        // `exec:` keeps the PNG byte-exact; `shell:` could rewrite line endings and corrupt it.
        let data = await withDeadline(25) { () async -> Data? in
            try? await TVShell.runData(connection, destination: "exec:screencap -p")
        } ?? nil
        guard let data, !data.isEmpty, let image = UIImage(data: data) else {
            status = "Screenshot failed · the box returned no image"
            return nil
        }
        status = "Screenshot captured"
        return image
    }

    /// Live typing: forwards a text change to the TV through the virtual keyboard.
    /// Returns false when the virtual keyboard isn't ready.
    func typeLive(_ text: String, backspaces: Int = 0) -> Bool {
        guard connected else { return false }
        return keyboard.type(text, backspaces: backspaces)
    }

    var liveTypingAvailable: Bool { connected && keyboard.isReady }

    /// Candidate hosts for the Android box (ADB on 5555) or Samsung TV (8002) on this Wi-Fi network.
    func discover(port: UInt16) async -> [String] {
        await NetworkScanner.scan(port: port)
    }
}
