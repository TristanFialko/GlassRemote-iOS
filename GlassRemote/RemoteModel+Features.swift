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

    /// v5 §5: volume and mute go only to the Samsung TV. The route is `VolumeButtonPolicy`: the
    /// TV's remote-socket key first (what its own remote sends, so a soundbar on ARC / optical
    /// follows). A UPnP RenderingControl step / mute toggle is used with the socket down only when
    /// UPnP is known to address the output that is playing (VolumeOutput.swift); otherwise it would
    /// move the TV's built-in speaker level while the soundbar plays. The Android TV volume path is
    /// gone: with no Samsung route nothing is sent and the soundbar is reported unavailable.
    /// Returns whether a Samsung route took it.
    @discardableResult
    func volume(_ name: String, haptic: Bool = true, readBack: Bool = true) -> Bool {
        endpointLearner.invalidate()   // a volume key is a newer command: discard any pending endpoint attempt
        let route = VolumeButtonPolicy.route(for: name, tvVolumeEnabled: tvVolumeEnabled,
                                             remoteReady: samsungRemoteReady, upnpReady: volumeLinkReady,
                                             upnpControlsOutput: upnpControlsOutput)
        let taken: Bool
        switch route {
        case .samsungKey(let key): taken = tv.send(key)
        case .upnpStep(let delta): taken = volumeLink.step(by: delta)
        case .upnpMuteToggle: taken = volumeLink.toggleMute()
        case .unavailable: taken = false
        }
        guard taken else {
            reportSoundbarUnavailable()
            return false
        }
        if case .samsungKey = route {
            // Evidence for the route: does the TV's UPnP level follow its own volume keys?
            if name == "VOLUME_UP" || name == "VOLUME_DOWN" {
                volumeOutputProbe.keySent(direction: name == "VOLUME_UP" ? 1 : -1,
                                          lastReading: volumeLinkReady ? volumeLink.lastVolume : nil, at: Date())
            }
        } else {
            volumeOutputProbe.reset()   // a UPnP set moves the level by itself
            GRLog.note("volume", "\(name) sent over UPnP (remote socket not ready)")
        }
        if haptic { Haptics.soft() }
        if readBack { scheduleVolumeReadback() }
        return true
    }

    /// Whether volume +/−/mute can reach the TV right now (remote socket or UPnP link).
    var volumeButtonsAvailable: Bool {
        VolumeButtonPolicy.isAvailable(tvVolumeEnabled: tvVolumeEnabled, remoteReady: samsungRemoteReady,
                                       upnpReady: volumeLinkReady, upnpControlsOutput: upnpControlsOutput)
    }

    // MARK: - Which output the volume reaches (VolumeOutput.swift)

    /// UPnP may be used for commands and shown as the level: the user chose TV speakers, or a
    /// volume key was seen to move the UPnP level.
    var upnpControlsOutput: Bool {
        VolumeRoutePolicy.upnpControlsOutput(output: samsungAudioOutput, evidence: volumeOutputEvidence)
    }

    /// The slider's route right now.
    var volumeCommandRoute: VolumeCommandRoute {
        VolumeRoutePolicy.route(enabled: tvVolumeEnabled, remoteReady: samsungRemoteReady, upnpReady: volumeLinkReady,
                                output: samsungAudioOutput, evidence: volumeOutputEvidence)
    }

    /// Shown in the Connection sheet.
    var volumeRouteSummary: String {
        VolumeRoutePolicy.summary(route: volumeCommandRoute, output: samsungAudioOutput,
                                  evidence: volumeOutputEvidence, upnpReady: volumeLinkReady)
    }

    /// The route may have changed (setting or evidence): drop the assumed key position and, on the
    /// absolute route, read the real level so the slider settles on it.
    func volumeRouteChanged() {
        volumeOutputProbe.reset()
        volumePendingSteps = 0
        volumeStateReset()
        if volumeCommandRoute == .absolute { volumeLink.refresh() }
    }

    /// A verdict from `VolumeOutputProbe`: remembered for this TV, and the route follows it.
    func applyVolumeEvidence(_ verdict: VolumeOutputEvidence) {
        guard verdict != volumeOutputEvidence else { return }
        let before = volumeCommandRoute
        volumeOutputEvidence = verdict
        VolumeOutputEvidenceStore.save(verdict, host: samsungHost)
        GRLog.note("volume", verdict == .tracksKeys
                   ? "the TV's UPnP level followed its volume keys: absolute volume is in use"
                   : "the TV's UPnP level ignored its volume keys: an external audio device is playing, remote keys only")
        if volumeCommandRoute != before { volumeRouteChanged() }
    }

    /// Forget what was learned about this TV's output (Connection sheet).
    func resetVolumeEvidence() {
        VolumeOutputEvidenceStore.save(.unknown, host: samsungHost)
        volumeOutputEvidence = .unknown
        volumeRouteChanged()
    }

    /// The explicit unavailable state (never a silent fallback to the Android box).
    var soundbarUnavailableMessage: String { "Soundbar unavailable · \(samsungUnavailableMessage)" }

    func reportSoundbarUnavailable() {
        status = soundbarUnavailableMessage
        GRLog.note("volume", "volume command not sent: no Samsung route (Android TV volume is not used)")
    }

    /// A key the TV connection accepted and then failed to deliver: reported, never re-sent over ADB.
    func samsungSendFailed(_ name: String) {
        GRLog.note("samsung", "send failed for \(name); not re-sent over ADB")
        if VolumeKeyPolicy.isVolumeKey(name) { reportSoundbarUnavailable() } else { status = samsungUnavailableMessage }
    }

    // MARK: - Real TV volume (UPnP RenderingControl)

    func configureVolumeLink() {
        volumeLink.isActive = { [weak self] in self?.appActive ?? false }
        volumeLink.onStatus = { [weak self] text in self?.volumeStatus = text }
        volumeLink.onAvailabilityChanged = { [weak self] available in
            guard let self else { return }
            self.volumeLinkReady = available
            self.volumeStateReset()
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
            if let verdict = self.volumeOutputProbe.reading(value, at: Date()) { self.applyVolumeEvidence(verdict) }
            let cal = self.volumeCalibration
            let unusedWhy = self.volumeOutputEvidence == .ignoresKeys
                ? "it does not follow the TV's volume keys" : "not yet seen to follow the TV's volume keys"
            self.volumeStatus = self.upnpControlsOutput
                ? "TV volume: \(value) (range \(cal.lo)–\(cal.hi), read from the TV)"
                : "TV's own level (UPnP): \(value) · not used for volume (\(unusedWhy))"
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
        case .samsungKeys: break   // the soundbar does not report its level over the remote socket
        case .unavailable: break   // v5 §5: no Samsung route; the Android box is never asked
        }
    }

    func publishVolumeReading(_ fraction: Double) {
        volumeReadingSerial &+= 1
        volumeReading = VolumeReadingEvent(fraction: fraction, serial: volumeReadingSerial)
    }

    // MARK: - Slider -> volume mapping

    /// Number of volume-key presses a full slider sweep spans. Through the TV this is the
    /// soundbar's own scale (`tvVolumeMax`). v5 §5: there is no ADB volume scale.
    var volumeLevels: Int { volumeScale.steps }

    /// Continuation §C2: the current target's real range (VolumeScale.swift). Same routing as the
    /// commands: the TV's absolute level when it reports one, then the TV's keys, otherwise
    /// unavailable (v5 §5: never the Android box).
    var volumeScale: VolumeScale {
        switch volumeCommandRoute {
        case .absolute: return .samsungAbsolute(volumeCalibration)
        case .keys: return .samsungKeys(max: tvVolumeMax)
        case .unavailable: return .unavailable
        }
    }

    /// Forget what we assumed about the real volume (range or route changed).
    func volumeStateReset() {
        volumeLevelKnown = false
        volumeLevelsInUse = 0
    }

    /// Maps the 0...1 slider to key presses. The slider is relative (the app cannot read the
    /// soundbar's real level), so the first time it reaches either end the full range is
    /// pressed once: the soundbar clamps at its true limit, after which slider and soundbar
    /// agree exactly at that end and every later move is an exact press count.
    func setVolumeFraction(_ fraction: Double) {
        lastUserVolumeInput = Date()
        volumeSync.userChanged()
        if !volumeDragActive { scheduleVolumeReconcile() }   // VoiceOver increments settle too
        // Absolute (0...100) only when UPnP is known to address the output that is playing
        // (VolumeOutput.swift). The slider's full travel is then exactly that output's range.
        if volumeCommandRoute == .absolute {
            volumeOutputProbe.reset()   // a UPnP set moves the level by itself: not evidence about the keys
            let raw = volumeScale.raw(forFraction: fraction)
            if fraction <= 0 { endpointLearner.commandSent(raw: raw, isMax: false) }
            else if fraction >= 1 { endpointLearner.commandSent(raw: raw, isMax: true) }
            else { endpointLearner.invalidate() }   // a mid-range command can never teach an end
            volumeLink.setVolume(raw)
            return
        }
        let scale = volumeScale
        // v5 §5: no Samsung route means nothing is sent (no ADB fallback) and the user is told.
        guard scale.isAvailable else { reportSoundbarUnavailable(); return }
        let levels = scale.steps
        // The real level this fraction commands (only the very ends reach 0 and the top).
        let target = scale.step(forFraction: fraction)

        if volumeLevelsInUse != levels {
            // Range changed: rescale the assumed position, and stop trusting it.
            if volumeLevelsInUse > 0 {
                volumeAssumedLevel = Int((Double(volumeAssumedLevel) / Double(volumeLevelsInUse) * Double(levels)).rounded())
            } else {
                volumeAssumedLevel = levels / 2   // slider starts at 50 %
            }
            volumeLevelsInUse = levels
            volumeLevelKnown = false
        }

        var delta = target - volumeAssumedLevel
        if !volumeLevelKnown {
            if target >= levels { delta = levels; volumeLevelKnown = true }
            else if target <= 0 { delta = -levels; volumeLevelKnown = true }
        }
        guard delta != 0 else { return }
        volumeAssumedLevel = target
        volumePendingSteps += delta
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
                    // The Samsung link dropped mid-sweep: stop and forget the assumed level.
                    self.volumePendingSteps = 0
                    self.volumeLevelKnown = false
                    break
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            self?.volumeDrainTask = nil
            // Read the TV's own level once the keys have landed: it shows whether that level follows them.
            if self?.volumeLinkReady == true { self?.volumeLink.refresh() }
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

    /// Reconnects ONLY the remote WebSocket (explicit: may ask for approval again). The UPnP
    /// volume link keeps running untouched.
    func reconnectTV() {
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
