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
                        userInfo: [NSLocalizedDescriptionKey: "ADB connected, but shell test returned: \(test)"]
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
            status = "Connected · \(installed.count) apps found"
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
                let output = try await runShell(
                    adb,
                    ["sh", "-c", "monkey -p \(app.package) 1 2>&1; rc=$?; echo GLASSREMOTE_LAUNCH_EXIT:$rc"]
                )
                if output.localizedCaseInsensitiveContains("no activities found") ||
                   output.localizedCaseInsensitiveContains("monkey aborted") {
                    status = "Launch failed · \(app.name) is not launchable on this TV"
                } else if output.contains("GLASSREMOTE_LAUNCH_EXIT:0") {
                    status = "Android accepted launch request · \(app.name)"
                } else {
                    status = "Launch result · \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            } catch {
                status = "Launch failed: \(error.localizedDescription)"
            }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
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

        Task {
            guard let adb else {
                status = "Button failed · not connected"
                return
            }

            do {
                let output = try await runShell(
                    adb,
                    ["sh", "-c", "input keyevent \(code); rc=$?; echo GLASSREMOTE_KEYEVENT_EXIT:$rc"]
                )
                if output.contains("GLASSREMOTE_KEYEVENT_EXIT:0") {
                    status = "Android accepted \(key) · keycode \(code)"
                } else if let result = output.components(separatedBy: "GLASSREMOTE_KEYEVENT_EXIT:").last {
                    status = "Android rejected \(key) · exit \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
                } else {
                    status = "Key result · \(output.isEmpty ? "no shell response" : output)"
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

    private func runShell(_ connection: AdbConnection, _ args: [String]) async throws -> String {
        let stream = try await connection.open(service: .shell, args: args)
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
                throw NSError(domain: "GlassRemote", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: "Bundled mouse helper is empty"])
            }

            status = "Mouse helper found · uploading \(data.count) bytes"

            let upload = try await adb.open(
                destination: "exec:sh -c 'cat > /data/local/tmp/glass_uhid_bridge && chmod 700 /data/local/tmp/glass_uhid_bridge'"
            )
            try await upload.write(data)
            try await upload.close()

            let verification = try await runShell(
                adb,
                ["sh", "-c", "test -s /data/local/tmp/glass_uhid_bridge && chmod 700 /data/local/tmp/glass_uhid_bridge && echo GLASSREMOTE_UPLOAD_OK"]
            )
            guard verification.contains("GLASSREMOTE_UPLOAD_OK") else {
                throw NSError(domain: "GlassRemote", code: 11,
                              userInfo: [NSLocalizedDescriptionKey: "TV did not confirm helper upload: \(verification)"])
            }

            let stream = try await adb.open(service: .shell, args: [])
            try await stream.write(Data("exec /data/local/tmp/glass_uhid_bridge\n".utf8))

            // The helper prints READY only after successfully opening and creating /dev/uhid.
            let startup = try await stream.read()
            let startupText = String(data: startup, encoding: .utf8) ?? ""

            guard startupText.contains("READY") else {
                try? await stream.close()
                throw NSError(
                    domain: "GlassRemote",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: startupText.isEmpty
                        ? "Mouse helper exited without a READY response"
                        : "Mouse helper did not start: \(startupText)"]
                )
            }

            mouseStream = stream
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
        guard mouseReady, let mouseStream else { return }

        let line = "M \(buttons) \(max(-127, min(127, dx))) \(max(-127, min(127, dy))) \(max(-127, min(127, wheel))) \(max(-127, min(127, hscroll)))\n"

        reportQueue.enqueue {
            do {
                try await mouseStream.write(Data(line.utf8))
            } catch {
                await MainActor.run {
                    self.mouseReady = false
                    self.status = "Mouse input stream failed: \(error.localizedDescription)"
                }
            }
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
