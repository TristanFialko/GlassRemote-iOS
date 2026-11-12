import Foundation

// UX-004: installed-app discovery and launching. The rules (parsing, merge, commands, outcomes)
// are pure and live in AppCatalog.swift; this file only runs them against the box.

extension RemoteModel {
    /// What the Apps folder shows: the nine curated apps (always, with their artwork), discovered
    /// TV apps that are not curated, then the Android TV Settings tile.
    var launcherApps: [TVApp] {
        AppCatalog.launcherApps(curated: apps, discovered: launchableApps)
    }

    /// Lists installed packages and launchable TV activities in one shell call. A failed scan never
    /// hides a curated tile; those still launch through the `monkey -p` fallback.
    func refreshApps() async {
        guard let adb else { return }

        do {
            let output = try await runShell(adb, ["sh", "-c", AppCatalog.discoveryCommand])
            let scan = AppCatalog.parseScan(output)
            guard !scan.packages.isEmpty else {
                launchableApps = []
                status = "ADB connected · app scan failed: no packages listed"
                return
            }
            installed = scan.packages
            launchableApps = AppCatalog.resolve(leanback: scan.leanback, launcher: scan.launcher)
            status = "Connected · \(installed.count) apps found"
            GRLog.note("apps", "\(launchableApps.count) launchable apps (\(scan.leanback.count) leanback activities)")
        } catch {
            // Components from an earlier scan may belong to a different box.
            launchableApps = []
            status = "ADB connected · app scan failed: \(error.localizedDescription)"
        }
    }

    func launch(_ app: TVApp) {
        // The tile's PressStyle already gave haptic feedback.
        Task { await launchApp(app) }
    }

    /// Starts `app` with `am start -n <component>` when discovery resolved one, the Settings intent for
    /// the Settings tile, else `monkey -p <package>`. Returns true only when Android accepted the start.
    @discardableResult
    func launchApp(_ app: TVApp) async -> Bool {
        guard let adb else {
            status = "Cannot launch · not connected"
            return false
        }
        let component = AppCatalog.component(for: app.package, in: launchableApps)
        guard let method = AppCatalog.launchMethod(for: app, component: component) else {
            status = "Launch failed · \(app.name): invalid package name"
            return false
        }

        do {
            let output = try await runShell(adb, ["sh", "-c", AppCatalog.launchCommand(method)])
            switch AppCatalog.launchOutcome(output, method: method) {
            case .accepted:
                status = "Android accepted launch request · \(app.name)"
                return true
            case .failed(let detail):
                status = "Launch failed · \(app.name): \(detail)"
            }
        } catch {
            status = "Launch failed: \(error.localizedDescription)"
        }
        return false
    }

    /// Force-stops and relaunches one selected app without rebooting the TV box.
    func restartApp(_ app: TVApp) {
        Task {
            guard let connection = adb, connected else {
                status = "Cannot restart \(app.name) · not connected"
                return
            }
            status = "Restarting \(app.name)…"
            if let stop = AppCatalog.forceStopCommand(for: app) {
                do {
                    _ = try await runShell(connection, ["sh", "-c", stop])
                } catch {
                    status = "Restart failed · \(app.name): \(error.localizedDescription)"
                    Haptics.medium()
                    return
                }
            }
            if await launchApp(app) {
                status = "\(app.name) restarted"
                GRLog.note("apps", "user restarted \(app.package)")
            }
            Haptics.medium()
        }
    }
}
