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
    @Published var host = UserDefaults.standard.string(forKey: "tvHost") ?? "192.168.1.70"
    @Published var port = UserDefaults.standard.integer(forKey: "tvPort") == 0 ? "5555" : String(UserDefaults.standard.integer(forKey: "tvPort"))
    @Published var status = "Not connected"
    @Published var connected = false
    @Published var installed = Set<String>()
    @Published var showConnection = false
    @Published var isTrackpad = true

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

    private var adb: AdbConnection?
    private var mouseStream: AdbStream?
    private var mouseReady = false
    private var reportQueue = TaskQueue()

    func connect() {
        Task {
            status = "Connecting…"
            UserDefaults.standard.set(host, forKey: "tvHost")
            UserDefaults.standard.set(Int(port) ?? 5555, forKey: "tvPort")

            do {
                let identity = try ADBIdentity.loadOrCreate()

                var builder = AdbConnection.Builder()
                builder.setHost(host.trimmingCharacters(in: .whitespacesAndNewlines))
                builder.setPort(UInt16(port) ?? 5555)
                builder.setKeyPair(identity)
                builder.setDeviceName("Glass Remote iPhone")

                let connection = try builder.build()
                let ok = try await connection.connect(timeout: 35, throwOnUnauthorised: false)

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
                        userInfo: [NSLocalizedDescriptionKey: "ADB connected, but the shell test returned unexpected output: \(test)"]
                    )
                }

                status = "Connected · ADB shell working"
                await refreshApps()
                await startMouse()

            } catch {
                connected = false
                status = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        Task {
            await stopMouse()
            await adb?.close()
            adb = nil
            connected = false
            installed.removeAll()
            status = "Disconnected"
        }
    }

    func refreshApps() async {
        guard let adb else { return }

        do {
            let output = try await runShell(adb, ["pm", "list", "packages"])

            installed = Set(
                output.components(separatedBy: .newlines).compactMap { line in
                    line.hasPrefix("package:")
                    ? String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    : nil
                }
            )

            status = "Connected · \(installed.count) third-party apps found"

        } catch {
            status = "ADB connected · app scan failed: \(error.localizedDescription)"
        }
    }

    func launch(_ app: TVApp) {
        Task {
            guard let adb else {
                status = "Cannot launch · not connected"
                return
            }

            do {
                let output = try await runShell(adb, ["monkey", "-p", app.package, "1"])
                status = "Launch command sent · \(app.name)"

                if output.localizedCaseInsensitiveContains("no activities found") {
                    status = "Launch failed · no activity found for \(app.name)"
                }

            } catch {
                status = "Launch failed: \(error.localizedDescription)"
            }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

func key(_ key: String) {
    let codes: [String: String] = [
        "UP": "19",
        "DOWN": "20",
        "LEFT": "21",
        "RIGHT": "22",
        "OK": "23",
        "BACK": "4",
        "HOME": "3",
        "MENU": "82",
        "VOLUME_DOWN": "25",
        "MUTE": "164",
        "VOLUME_UP": "24"
    ]

    guard let code = codes[key] else {
        status = "Unknown button: \(key)"
        return
    }

    Task {
        guard let adb else {
            status = "Button failed · not connected"
            return
        }

        do {
            let output = try await runShell(
                adb,
                ["sh", "-c", "input keyevent \(code); echo GLASSREMOTE_KEYEVENT_DONE"]
            )

            if output.contains("GLASSREMOTE_KEYEVENT_DONE") {
                status = "TV shell completed \(key) · keycode \(code)"
            } else {
                status = "Key command returned unexpected output: \(output.isEmpty ? "(empty)" : output)"
            }
        } catch {
            status = "Button \(key) failed: \(error.localizedDescription)"
        }
    }

    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
}

    func sendText(_ text: String) {
        let safe = text
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "'", with: "\\'")

        Task {
            guard let adb else {
                status = "Text entry failed · not connected"
                return
            }

            do {
                _ = try await runShell(adb, ["input", "text", safe])
                status = "Text command sent"
            } catch {
                status = "Text entry failed: \(error.localizedDescription)"
            }
        }
    }

    // Executes a one-shot ADB shell command and collects its output.
    // ADB may close the stream normally once the command has finished.
    private func runShell(_ connection: AdbConnection, _ args: [String]) async throws -> String {
        let stream = try await connection.open(service: .shell, args: args)
        var result = Data()

        while !(await stream.getIsClosed()) {
            do {
                let chunk = try await stream.read()
                if chunk.isEmpty {
                    break
                }
                result.append(chunk)
            } catch {
                // A closed stream after command completion is end-of-output,
                // not a command failure. Keep genuine errors on open streams.
                if await stream.getIsClosed() {
                    break
                }
                throw error
            }
        }

        return String(data: result, encoding: .utf8) ?? ""
    }

    private func startMouse() async {
        guard let adb else { return }

        let helperURL =
            Bundle.main.url(forResource: "glass_uhid_bridge", withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent("glass_uhid_bridge")

        guard let helperURL,
              FileManager.default.fileExists(atPath: helperURL.path) else {
            mouseReady = false
            status = "ADB working · mouse helper missing from app bundle"
            return
        }

        do {
            let data = try Data(contentsOf: helperURL)

            let upload = try await adb.open(
                destination: "exec:sh -c 'cat > /data/local/tmp/glass_uhid_bridge && chmod 700 /data/local/tmp/glass_uhid_bridge'"
            )

            try await upload.write(data)
            try await upload.close()

            let stream = try await adb.open(service: .shell, args: [])
            try await stream.write(Data("/data/local/tmp/glass_uhid_bridge\n".utf8))

            mouseStream = stream
            mouseReady = true
            status = "ADB working · trackpad helper started"

        } catch {
            mouseReady = false
            status = "ADB working · mouse startup failed: \(error.localizedDescription)"
        }
    }

    func mouse(
        buttons: Int = 0,
        dx: Int = 0,
        dy: Int = 0,
        wheel: Int = 0,
        hscroll: Int = 0
    ) {
        guard mouseReady, let mouseStream else { return }

        let line = "M \(buttons) \(max(-127, min(127, dx))) \(max(-127, min(127, dy))) \(max(-127, min(127, wheel))) \(max(-127, min(127, hscroll)))\n"

        reportQueue.enqueue {
            try? await mouseStream.write(Data(line.utf8))
        }
    }

    private func stopMouse() async {
        mouseReady = false

        if let mouseStream {
            try? await mouseStream.close()
        }

        mouseStream = nil
    }
}

/// Serializes HID reports so rapid movement never reorders button transitions.
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
