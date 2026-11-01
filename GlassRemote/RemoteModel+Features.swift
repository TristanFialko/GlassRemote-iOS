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
    func volume(_ name: String) {
        if tvVolumeEnabled, tv.send(name) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }
        key(name)
    }

    func applyTVSettings() {
        if tvVolumeEnabled, !samsungHost.trimmingCharacters(in: .whitespaces).isEmpty {
            if !tvVolumeReady { tv.connect(host: samsungHost) }
        } else {
            tv.stop(report: false)
            samsungStatus = tvVolumeEnabled ? "Samsung TV: enter the TV's IP address" : "Samsung TV: off"
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
