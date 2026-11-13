import Foundation
import Security

// The client identity Remote v2 presents in both TLS connections (pairing on 6467, control on 6466).
//
// The TV binds a pairing to the client certificate's public key: the pairing secret hashes the
// client's RSA modulus and exponent, and later control connections are accepted only from the same
// key. The key is therefore generated once, kept in the Keychain (this device only, never synced or
// backed up), and reused until the user removes the pairing.

enum RemoteV2IdentityError: Error, Equatable {
    case keyGenerationFailed
    case publicKeyExportFailed
    case signingFailed
    case certificateRejected
    case identityUnavailable
    case keychain(OSStatus)
}

/// Minimal DER encoding for the one structure this app writes: a self-signed X.509 v3 certificate.
enum RemoteV2DER {
    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }

    static func set(_ parts: [UInt8]...) -> [UInt8] { tlv(0x31, parts.flatMap { $0 }) }

    /// A non-negative INTEGER from big-endian magnitude bytes (minimal, with a 0x00 sign byte if needed).
    static func integer(unsigned magnitude: [UInt8]) -> [UInt8] {
        var bytes = Array(magnitude.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = [0] }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, bytes)
    }

    /// A BIT STRING with no unused bits.
    static func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + bytes) }

    static let null: [UInt8] = [0x05, 0x00]

    static func objectIdentifier(_ encoded: [UInt8]) -> [UInt8] { tlv(0x06, encoded) }

    static func utf8String(_ text: String) -> [UInt8] { tlv(0x0C, Array(text.utf8)) }

    /// RFC 5280: UTCTime for 1950 through 2049, GeneralizedTime from 2050 on. Always UTC, seconds precision.
    static func time(_ date: Date) -> [UInt8] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let year = c.year ?? 1970
        let rest = two(c.month) + two(c.day) + two(c.hour) + two(c.minute) + two(c.second) + "Z"
        if (1950..<2050).contains(year) {
            return tlv(0x17, Array((two(year % 100) + rest).utf8))
        }
        return tlv(0x18, Array((String(format: "%04d", year) + rest).utf8))
    }
}

/// Builds the self-signed client certificate (pure apart from signing, unit tested).
enum RemoteV2CertificateBuilder {
    /// 1.2.840.113549.1.1.11
    static let sha256WithRSAEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    /// 1.2.840.113549.1.1.1
    static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    /// 2.5.4.3
    static let commonNameOID: [UInt8] = [0x55, 0x04, 0x03]

    /// The subject androidtvremote2 uses for its client certificate. The TV only uses the key.
    static let defaultCommonName = "atvremote"
    /// Long enough that a pairing never expires in practice; the TV does not check validity dates.
    static let lifetime: TimeInterval = 20 * 365 * 86_400

    static func algorithm(_ oid: [UInt8]) -> [UInt8] {
        RemoteV2DER.sequence(RemoteV2DER.objectIdentifier(oid), RemoteV2DER.null)
    }

    static func name(_ commonName: String) -> [UInt8] {
        RemoteV2DER.sequence(RemoteV2DER.set(RemoteV2DER.sequence(
            RemoteV2DER.objectIdentifier(commonNameOID), RemoteV2DER.utf8String(commonName))))
    }

    static func tbsCertificate(publicKeyPKCS1: [UInt8], commonName: String, serial: [UInt8],
                               notBefore: Date, notAfter: Date) -> [UInt8] {
        let subject = name(commonName)
        return RemoteV2DER.sequence(
            RemoteV2DER.tlv(0xA0, RemoteV2DER.integer(unsigned: [2])), // v3
            RemoteV2DER.integer(unsigned: serial),
            algorithm(sha256WithRSAEncryption),
            subject, // issuer: self-signed
            RemoteV2DER.sequence(RemoteV2DER.time(notBefore), RemoteV2DER.time(notAfter)),
            subject,
            RemoteV2DER.sequence(algorithm(rsaEncryption), RemoteV2DER.bitString(publicKeyPKCS1))
        )
    }

    static func certificate(tbs: [UInt8], signature: [UInt8]) -> [UInt8] {
        RemoteV2DER.sequence(tbs, algorithm(sha256WithRSAEncryption), RemoteV2DER.bitString(signature))
    }

    /// A positive, non-zero 128-bit serial.
    static func randomSerial() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = Array(UUID().uuidString.utf8.prefix(16))
        }
        bytes[0] = (bytes[0] & 0x7F) | 0x01
        return bytes
    }

    static func publicKeyPKCS1(of privateKey: SecKey) throws -> [UInt8] {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw RemoteV2IdentityError.publicKeyExportFailed }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw RemoteV2IdentityError.publicKeyExportFailed
        }
        return Array(data)
    }

    static func selfSigned(privateKey: SecKey, commonName: String = defaultCommonName, now: Date = Date(),
                           serial: [UInt8]? = nil) throws -> [UInt8] {
        let notBefore = now.addingTimeInterval(-86_400)
        let tbs = tbsCertificate(publicKeyPKCS1: try publicKeyPKCS1(of: privateKey), commonName: commonName,
                                 serial: serial ?? randomSerial(), notBefore: notBefore,
                                 notAfter: notBefore.addingTimeInterval(lifetime))
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                    Data(tbs) as CFData, &error) as Data? else {
            throw RemoteV2IdentityError.signingFailed
        }
        return certificate(tbs: tbs, signature: Array(signature))
    }
}

/// The identity a TLS connection presents, plus the public key numbers the pairing secret needs.
struct RemoteV2ClientIdentity {
    let identity: SecIdentity
    let certificateDER: [UInt8]
    let publicKey: RemoteV2RSAPublicKey

    init(identity: SecIdentity, certificate: SecCertificate) throws {
        guard let key = SecCertificateCopyKey(certificate) else { throw RemoteV2IdentityError.publicKeyExportFailed }
        var error: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw RemoteV2IdentityError.publicKeyExportFailed
        }
        self.identity = identity
        certificateDER = Array(SecCertificateCopyData(certificate) as Data)
        publicKey = try RemoteV2RSAPublicKey(pkcs1: Array(pkcs1))
    }
}

/// Seam for the connection layer and tests: where the client identity comes from.
protocol RemoteV2IdentityProviding: AnyObject {
    /// Returns the stored identity, creating one on first use.
    func loadOrCreate() throws -> RemoteV2ClientIdentity
    /// Deletes the identity (used by "Forget pairing"). The next pairing creates a new key.
    func reset() throws
}

/// Keychain-backed identity: RSA 2048, AfterFirstUnlockThisDeviceOnly, not synchronizable.
final class RemoteV2KeychainIdentityStore: RemoteV2IdentityProviding {
    static let shared = RemoteV2KeychainIdentityStore()

    let keyTag: Data
    let certificateLabel: String
    private let lock = NSLock()

    init(keyTag: String = "com.glassremote.remotev2.client-key",
         certificateLabel: String = "GlassRemote Remote v2 client") {
        self.keyTag = Data(keyTag.utf8)
        self.certificateLabel = certificateLabel
    }

    func loadOrCreate() throws -> RemoteV2ClientIdentity {
        lock.lock()
        defer { lock.unlock() }
        if let existing = try load() { return existing }
        // A half-written identity (key without certificate or the reverse) is replaced as a whole.
        try deleteItems()
        return try create()
    }

    func reset() throws {
        lock.lock()
        defer { lock.unlock() }
        try deleteItems()
    }

    private func load() throws -> RemoteV2ClientIdentity? {
        var certificateRef: CFTypeRef?
        let certificateQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
        ]
        let status = SecItemCopyMatching(certificateQuery as CFDictionary, &certificateRef)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let found = certificateRef,
              CFGetTypeID(found) == SecCertificateGetTypeID() else { throw RemoteV2IdentityError.keychain(status) }
        let certificate = found as! SecCertificate
        let der = SecCertificateCopyData(certificate) as Data

        var identitiesRef: CFTypeRef?
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identitiesRef)
        if identityStatus == errSecItemNotFound { return nil }
        guard identityStatus == errSecSuccess, let identities = identitiesRef as? [SecIdentity] else {
            throw RemoteV2IdentityError.keychain(identityStatus)
        }
        for identity in identities {
            var candidate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &candidate) == errSecSuccess,
                  let candidateCertificate = candidate,
                  SecCertificateCopyData(candidateCertificate) as Data == der else { continue }
            return try RemoteV2ClientIdentity(identity: identity, certificate: candidateCertificate)
        }
        return nil
    }

    private func create() throws -> RemoteV2ClientIdentity {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
            ] as [String: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw RemoteV2IdentityError.keyGenerationFailed
        }
        let der = try RemoteV2CertificateBuilder.selfSigned(privateKey: privateKey)
        guard let certificate = SecCertificateCreateWithData(nil, Data(der) as CFData) else {
            throw RemoteV2IdentityError.certificateRejected
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certificateLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw RemoteV2IdentityError.keychain(status) }
        guard let identity = try load() else { throw RemoteV2IdentityError.identityUnavailable }
        return identity
    }

    private func deleteItems() throws {
        let queries: [[String: Any]] = [
            [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag],
            [kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: certificateLabel],
        ]
        for query in queries {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw RemoteV2IdentityError.keychain(status)
            }
        }
    }
}
