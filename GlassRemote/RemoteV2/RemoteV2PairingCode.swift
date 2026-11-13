import CryptoKit
import Foundation

/// The pairing secret (pure, unit tested). Algorithm from androidtvremote2 pairing.py (v0.3.3):
///
///     secret = SHA-256(client modulus, client exponent, server modulus, server exponent, code[1...2])
///
/// Each RSA number is its minimal big-endian bytes (no sign byte, no leading zeros). The TV shows
/// six hex digits: the first byte is a check byte that must equal secret[0], the last two bytes are a
/// nonce. A mismatched check byte means a typo, or that the TV's key is not the key in this TLS
/// session, so the secret is never sent in that case.
enum RemoteV2PairingCode {
    /// Parses six hexadecimal characters (case-insensitive, surrounding spaces ignored).
    static func parse(_ text: String) -> [UInt8]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(trimmed.utf8)
        guard chars.count == 6 else { return nil }
        var out: [UInt8] = []
        for index in stride(from: 0, to: 6, by: 2) {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else { return nil }
            out.append(high << 4 | low)
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }

    /// Strips leading zero bytes, matching Python's `n.to_bytes((n.bit_length() + 7) // 8, "big")`.
    static func minimal(_ bytes: [UInt8]) -> [UInt8] {
        Array(bytes.drop(while: { $0 == 0 }))
    }

    static func secret(code: [UInt8], client: RemoteV2RSAPublicKey, server: RemoteV2RSAPublicKey) throws -> [UInt8] {
        guard code.count == 3 else { throw RemoteV2PairingFailure.malformedCode }
        var hash = SHA256()
        for part in [client.modulus, client.exponent, server.modulus, server.exponent] {
            hash.update(data: minimal(part))
        }
        hash.update(data: Array(code[1...2]))
        let digest = Array(hash.finalize())
        guard digest[0] == code[0] else { throw RemoteV2PairingFailure.codeMismatch }
        return digest
    }
}

/// An RSA public key's modulus and exponent as minimal big-endian bytes.
struct RemoteV2RSAPublicKey: Equatable {
    var modulus: [UInt8]
    var exponent: [UInt8]

    init(modulus: [UInt8], exponent: [UInt8]) {
        self.modulus = modulus
        self.exponent = exponent
    }

    /// Parses a PKCS#1 RSAPublicKey (`SEQUENCE { INTEGER n, INTEGER e }`), which is what
    /// `SecKeyCopyExternalRepresentation` returns for an RSA public key.
    init(pkcs1 der: [UInt8]) throws {
        var reader = RemoteV2DERReader(der)
        var sequence = try reader.read(tag: 0x30)
        let modulus = try sequence.read(tag: 0x02)
        let exponent = try sequence.read(tag: 0x02)
        guard sequence.isAtEnd, reader.isAtEnd else { throw RemoteV2DERReader.Failure.malformed }
        self.init(modulus: RemoteV2PairingCode.minimal(modulus.remaining),
                  exponent: RemoteV2PairingCode.minimal(exponent.remaining))
    }
}

extension RemoteV2RSAPublicKey {
    /// SHA-256 (lowercase hex) over the length-prefixed minimal modulus and exponent. Identifies the
    /// TV's key for pinning; a public value, safe to store.
    var fingerprint: String {
        var hash = SHA256()
        for part in [RemoteV2PairingCode.minimal(modulus), RemoteV2PairingCode.minimal(exponent)] {
            let n = UInt32(part.count)
            hash.update(data: [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
            hash.update(data: part)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Just enough DER to read PKCS#1 keys (definite lengths only).
struct RemoteV2DERReader {
    enum Failure: Error { case malformed }

    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { index == bytes.count }
    var remaining: [UInt8] { Array(bytes[index...]) }

    /// Reads one element with the given tag and returns a reader over its contents.
    mutating func read(tag: UInt8) throws -> RemoteV2DERReader {
        guard index < bytes.count, bytes[index] == tag else { throw Failure.malformed }
        index += 1
        guard index < bytes.count else { throw Failure.malformed }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count >= 1, count <= 4, bytes.count - index >= count else { throw Failure.malformed }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(bytes[index])
                index += 1
            }
        }
        guard length <= bytes.count - index else { throw Failure.malformed }
        let contents = Array(bytes[index..<index + length])
        index += length
        return RemoteV2DERReader(contents)
    }
}
