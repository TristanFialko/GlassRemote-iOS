import Foundation
import Network
import Darwin

/// Finds devices on the phone's own Wi-Fi subnet that accept a TCP connection on one port.
/// Used to discover the Android box (ADB, 5555) and the Samsung TV (8002) without typing IPs.
enum NetworkScanner {
    /// The phone's Wi-Fi IPv4 address and netmask, if it is on Wi-Fi.
    nonisolated static func wifiIPv4() -> (address: UInt32, mask: UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name) == "en0",
                  let netmask = entry.pointee.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            return (ip, mask)
        }
        return nil
    }

    nonisolated static func string(from address: UInt32) -> String {
        "\((address >> 24) & 255).\((address >> 16) & 255).\((address >> 8) & 255).\(address & 255)"
    }

    /// Hosts on the local subnet (capped at a /24 around the phone) that open `port`, sorted.
    nonisolated static func scan(port: UInt16, timeout: Double = 0.7) async -> [String] {
        guard let wifi = wifiIPv4(), let nwPort = NWEndpoint.Port(rawValue: port) else { return [] }
        let base = wifi.address & 0xFFFF_FF00   // never scan more than 254 hosts
        let candidates = (1...254).map { base | UInt32($0) }.filter { $0 != wifi.address }

        var found: [String] = []
        await withTaskGroup(of: String?.self) { group in
            var iterator = candidates.makeIterator()
            var running = 0
            func addNext() {
                guard let next = iterator.next() else { return }
                let host = string(from: next)
                running += 1
                group.addTask { await probe(host: host, port: nwPort, timeout: timeout) ? host : nil }
            }
            for _ in 0..<48 { addNext() }              // bounded concurrency
            while running > 0, let result = await group.next() {
                running -= 1
                if let host = result { found.append(host) }
                addNext()
            }
        }
        return found.sorted { lhs, rhs in
            lhs.split(separator: ".").compactMap { Int($0) }.last ?? 0 < rhs.split(separator: ".").compactMap { Int($0) }.last ?? 0
        }
    }

    private nonisolated static func probe(host: String, port: NWEndpoint.Port, timeout: Double) async -> Bool {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let gate = ProbeGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            func finish(_ result: Bool) {
                guard gate.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}

private final class ProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
