import Foundation
import CryptoKit
import SwiftADB

/// Shared plumbing for talking to the TV box: running shell commands, reading raw output,
/// finding bundled helper files, and installing them with size + SHA-1 verification.
/// (Previously this logic was copied into RemoteModel, PersistentHelper and VirtualKeyboard.)
@MainActor
enum TVShell {
    // MARK: Quoting and running

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs `args` as one quoted shell command and returns everything it printed.
    /// (SwiftADB's own helper concatenates arguments without spaces, so the destination is built here.)
    static func run(_ adb: AdbConnection, _ args: [String]) async throws -> String {
        let data = try await runData(adb, destination: "shell:" + args.map(quote).joined(separator: " "))
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs a shell script via `sh -c`.
    static func script(_ adb: AdbConnection, _ script: String) async throws -> String {
        try await run(adb, ["sh", "-c", script])
    }

    /// Opens any ADB destination (`shell:…`, `exec:…`) and reads until the TV closes the stream.
    /// Use `exec:` for binary output; `shell:` can rewrite line endings.
    static func runData(_ adb: AdbConnection, destination: String) async throws -> Data {
        let stream = try await adb.open(destination: destination)
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
        return result
    }

    // MARK: Bundled files

    /// Finds a file shipped inside the app bundle (direct lookup first, then a directory walk).
    static func bundled(_ name: String) -> URL? {
        let bundle = Bundle.main
        if let direct = bundle.url(forResource: name, withExtension: nil),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        for root in [bundle.resourceURL, bundle.bundleURL].compactMap({ $0 }) {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            while let candidate = enumerator.nextObject() as? URL {
                if candidate.lastPathComponent == name { return candidate }
            }
        }
        return nil
    }

    // MARK: CPU architecture

    private static var cachedABI: String?

    /// `ro.product.cpu.abi` of the TV box (cached for the app session; "" if it can't be read).
    static func abi(_ adb: AdbConnection) async -> String {
        if let cachedABI { return cachedABI }
        let out = (try? await run(adb, ["getprop", "ro.product.cpu.abi"])) ?? ""
        let value = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { cachedABI = value }
        return value
    }

    static func forgetABI() { cachedABI = nil }

    /// Bundled helper matching the box: `<name>_arm64` on a 64-bit ARM userland (when shipped),
    /// otherwise the 32-bit ARM build `<name>`.
    static func bundledHelper(_ adb: AdbConnection, _ name: String) async -> URL? {
        let abi = await abi(adb).lowercased()
        if abi.contains("arm64") || abi.contains("aarch64"), let arm64 = bundled(name + "_arm64") {
            return arm64
        }
        return bundled(name)
    }

    /// ELF header check. `machine` 0x28 = 32-bit ARM, 0xB7 = AArch64.
    static func elfMachine(_ data: Data) -> (is64: Bool, machine: Int)? {
        guard data.count >= 20 else { return nil }
        let h = Array(data.prefix(20))
        guard h[0] == 0x7F, h[1] == 0x45, h[2] == 0x4C, h[3] == 0x46, h[5] == 1 else { return nil }
        return (h[4] == 2, Int(h[18]) | (Int(h[19]) << 8))
    }

    // MARK: Install with verification

    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func firstInt(_ text: String) -> Int? {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }.first
    }

    private static func remoteSize(_ adb: AdbConnection, _ path: String) async throws -> Int? {
        let out = try await script(adb, "if [ -f \(quote(path)) ]; then wc -c < \(quote(path)); else echo MISSING; fi")
        return firstInt(out)
    }

    private static func remoteSHA1(_ adb: AdbConnection, _ path: String) async -> String? {
        guard let out = try? await run(adb, ["sha1sum", path]),
              let token = out.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        let candidate = String(token).lowercased()
        return candidate.count == 40 && candidate.allSatisfy({ $0.isHexDigit }) ? candidate : nil
    }

    /// Makes sure `remote` holds exactly `data`. Skips the upload when an identical file is already
    /// there. Uploads to `<remote>.upload` first (a partial file is never executed), waits until the
    /// TV reports the full size, verifies SHA-1 when the box has `sha1sum`, then moves it into place.
    /// Returns true when an upload happened.
    @discardableResult
    static func install(
        _ adb: AdbConnection,
        data: Data,
        remote: String,
        mode: String,
        progress: ((String) -> Void)? = nil
    ) async throws -> Bool {
        let expected = data.count
        let localSHA1 = sha1(data)
        let name = (remote as NSString).lastPathComponent

        if try await remoteSize(adb, remote) == expected, await remoteSHA1(adb, remote) == localSHA1 {
            let out = try await script(adb, "chmod \(mode) \(quote(remote)) && echo GLASSREMOTE_FILE_OK")
            if out.contains("GLASSREMOTE_FILE_OK") { return false }
        }

        let temp = remote + ".upload"
        progress?("\(name) uploading · 0/\(expected) bytes")
        let upload = try await adb.open(destination: "exec:sh -c 'cat > \(temp)'")
        var sent = 0
        while sent < expected {
            let next = min(sent + 1024, expected)
            try await upload.write(data.subdata(in: sent..<next))
            sent = next
            if sent % 4096 == 0 || sent == expected { progress?("\(name) uploading · \(sent)/\(expected) bytes") }
        }
        try await upload.close()

        // close() returns before the TV has necessarily finished writing, so poll the real size.
        var remoteBytes: Int?
        for _ in 0..<50 {
            remoteBytes = try await remoteSize(adb, temp)
            if remoteBytes == expected { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard remoteBytes == expected else {
            throw NSError(domain: "GlassRemote", code: 30, userInfo: [NSLocalizedDescriptionKey:
                "\(name) upload incomplete: local \(expected) bytes, TV has \(remoteBytes.map(String.init) ?? "none")"])
        }
        if let remoteHash = await remoteSHA1(adb, temp), remoteHash != localSHA1 {
            throw NSError(domain: "GlassRemote", code: 32, userInfo: [NSLocalizedDescriptionKey:
                "\(name) checksum mismatch after upload"])
        }
        let done = try await script(adb, "chmod \(mode) \(quote(temp)) && mv -f \(quote(temp)) \(quote(remote)) && echo GLASSREMOTE_FILE_OK")
        guard done.contains("GLASSREMOTE_FILE_OK") else {
            throw NSError(domain: "GlassRemote", code: 31, userInfo: [NSLocalizedDescriptionKey:
                "could not install \(name): \(done.trimmingCharacters(in: .whitespacesAndNewlines))"])
        }
        return true
    }
}
