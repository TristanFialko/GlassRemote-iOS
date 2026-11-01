import Foundation
import SwiftUI
import UIKit

// New features layered on the existing connection, mouse and keyboard code.
// Nothing here changes the UHID protocol, the ADB identity or any Android package state.

enum PowerAction: Identifiable {
    case standby, restartLauncher, restartBox
    var id: Self { self }

    var title: String {
        switch self {
        case .standby: return "Put TV box in standby?"
        case .restartLauncher: return "Restart Glass Launcher?"
        case .restartBox: return "Restart TV box?"
        }
    }

    var message: String {
        switch self {
        case .standby: return "The box goes to sleep. Glass Remote may lose its connection until the box is awake again."
        case .restartLauncher: return "Only the launcher restarts. Glass Utility Hub is not touched."
        case .restartBox: return "Glass Remote will disconnect and reconnect automatically. This can take about a minute."
        }
    }

    var confirmLabel: String {
        switch self {
        case .standby: return "Standby"
        case .restartLauncher: return "Restart Launcher"
        case .restartBox: return "Restart"
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
                try? await Task.sleep(nanoseconds: 3_000_000_000)
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
        media = MediaParser.parse(output) ?? .idle
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
        sendPersistentCommand("input keyevent \(code)")
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: - Volume routing

    /// Volume and mute go to the Samsung TV when that connection is ready, otherwise
    /// through the existing ADB path.
    func volume(_ name: String, haptic: Bool = true) {
        if tvVolumeEnabled, tv.send(name) {
            if haptic { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            scheduleVolumeReadback()
            return
        }
        key(name)
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
        volumeLink.onVolume = { [weak self] value in
            guard let self else { return }
            self.volumeStatus = "TV volume: \(value) / 100 (read from the TV)"
            self.tvVolumeFraction = Double(min(max(value, 0), 100)) / 100.0
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
    var volumeSliderAcceptsExternal: Bool {
        Date().timeIntervalSince(lastUserVolumeInput) > 1.2
    }

    // MARK: - Slider -> volume mapping

    /// Number of volume-key presses a full slider sweep spans. Through the TV this is the
    /// soundbar's own scale (`tvVolumeMax`); over ADB it stays at the original 20 steps.
    var volumeLevels: Int { volumeLinkReady ? 100 : ((tvVolumeEnabled && tvVolumeReady) ? tvVolumeMax : 20) }

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
        // Preferred: the TV reports its real level, so set it absolutely (0...100). The slider's
        // full travel is then exactly the TV's full range and nothing is assumed.
        if tvVolumeEnabled, volumeLinkReady {
            volumeLink.setVolume(Int((min(max(fraction, 0), 1) * 100).rounded()))
            return
        }
        let levels = volumeLevels
        let clamped = min(max(fraction, 0), 1)
        let target = Int((clamped * Double(levels)).rounded())

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
                // Feel each step for small moves; stay quiet during long sweeps.
                self.volume(up ? "VOLUME_UP" : "VOLUME_DOWN", haptic: abs(self.volumePendingSteps) < 3)
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
            if !tvVolumeReady, !tv.isAttempting { tv.connect(host: samsungHost) }
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

                if !wanted || self.tv.isReady {
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

    func reconnectTV() {
        tv.stop(report: false)
        applyTVSettings()
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

    // MARK: - Quick Actions

    func runQuickAction(named name: String) {
        guard let action = QuickActionStore.shared.find(named: name) else {
            status = "No Quick Action named “\(name)”"
            return
        }
        runQuickAction(action)
    }

    func runQuickAction(_ action: QuickAction) {
        guard connected else { status = "Quick Action failed · not connected"; return }
        quickActionTask?.cancel()
        runningQuickActionID = action.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        quickActionTask = Task { [weak self] in
            guard let self else { return }
            for step in action.steps {
                if Task.isCancelled { break }
                switch step.kind {
                case .launch:
                    if let app = self.apps.first(where: { $0.package == step.package }) {
                        await self.launchApp(app)
                    }
                case .key:
                    if QuickActionStore.allowedKeys.contains(step.key) { self.key(step.key) }
                case .delay:
                    let seconds = max(0, min(30, step.seconds))
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                case .volume:
                    guard step.key == "VOLUME_UP" || step.key == "VOLUME_DOWN" else { break }
                    for _ in 0..<max(0, min(20, step.count)) {
                        if Task.isCancelled { break }
                        self.volume(step.key)
                        try? await Task.sleep(nanoseconds: 180_000_000)
                    }
                }
                // Small gap so Android can settle between steps.
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            if self.runningQuickActionID == action.id { self.runningQuickActionID = nil }
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
