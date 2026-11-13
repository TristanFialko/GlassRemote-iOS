import Security
import XCTest
@testable import GlassRemote

/// Remote v2 client identity: DER building blocks and the self-signed certificate Security accepts.
final class RemoteV2IdentityTests: XCTestCase {
    func testDERLengthAndIntegerEncoding() {
        XCTAssertEqual(RemoteV2DER.length(0x7F), [0x7F])
        XCTAssertEqual(RemoteV2DER.length(0x80), [0x81, 0x80])
        XCTAssertEqual(RemoteV2DER.length(0x0100), [0x82, 0x01, 0x00])
        XCTAssertEqual(RemoteV2DER.integer(unsigned: [0x00, 0x00, 0x05]), [0x02, 0x01, 0x05])
        XCTAssertEqual(RemoteV2DER.integer(unsigned: [0x80]), [0x02, 0x02, 0x00, 0x80])
        XCTAssertEqual(RemoteV2DER.integer(unsigned: []), [0x02, 0x01, 0x00])
        XCTAssertEqual(RemoteV2DER.bitString([0xAA]), [0x03, 0x02, 0x00, 0xAA])
    }

    /// Fixtures computed independently (Python datetime, UTC).
    func testCertificateTimesSwitchToGeneralizedTimeIn2050() {
        XCTAssertEqual(RemoteV2DER.time(Date(timeIntervalSince1970: 1_794_564_000)),
                       [0x17, 0x0D] + Array("261113100000Z".utf8))
        XCTAssertEqual(RemoteV2DER.time(Date(timeIntervalSince1970: 2_524_607_999)),
                       [0x17, 0x0D] + Array("491231235959Z".utf8))
        XCTAssertEqual(RemoteV2DER.time(Date(timeIntervalSince1970: 2_524_608_000)),
                       [0x18, 0x0F] + Array("20500101000000Z".utf8))
    }

    private func ephemeralKey() throws -> SecKey {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        return try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    }

    func testSelfSignedCertificateParsesAndCarriesTheSameKey() throws {
        let key = try ephemeralKey()
        let der = try RemoteV2CertificateBuilder.selfSigned(privateKey: key, now: Date(timeIntervalSince1970: 1_794_564_000),
                                                            serial: [0x01, 0x02, 0x03])
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, Data(der) as CFData))
        XCTAssertEqual(SecCertificateCopySubjectSummary(certificate) as String?, "atvremote")

        let certificateKey = try XCTUnwrap(SecCertificateCopyKey(certificate))
        var error: Unmanaged<CFError>?
        let fromCertificate = try XCTUnwrap(SecKeyCopyExternalRepresentation(certificateKey, &error) as Data?)
        XCTAssertEqual(Array(fromCertificate), try RemoteV2CertificateBuilder.publicKeyPKCS1(of: key))

        let numbers = try RemoteV2RSAPublicKey(pkcs1: Array(fromCertificate))
        XCTAssertEqual(numbers.modulus.count, 256, "RSA 2048 modulus, minimal bytes")
        XCTAssertEqual(numbers.exponent, [0x01, 0x00, 0x01])
    }

    func testCertificateSignatureVerifiesWithItsOwnKey() throws {
        let key = try ephemeralKey()
        let start = Date(timeIntervalSince1970: 1_794_564_000)
        let tbs = RemoteV2CertificateBuilder.tbsCertificate(
            publicKeyPKCS1: try RemoteV2CertificateBuilder.publicKeyPKCS1(of: key), commonName: "atvremote",
            serial: [0x7F], notBefore: start, notAfter: start.addingTimeInterval(RemoteV2CertificateBuilder.lifetime))
        var error: Unmanaged<CFError>?
        let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                                            Data(tbs) as CFData, &error) as Data?)
        let der = RemoteV2CertificateBuilder.certificate(tbs: tbs, signature: Array(signature))
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, Data(der) as CFData))
        let publicKey = try XCTUnwrap(SecCertificateCopyKey(certificate))
        XCTAssertTrue(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                            Data(tbs) as CFData, signature as CFData, &error))
    }

    func testSerialsArePositiveAndDistinct() {
        let a = RemoteV2CertificateBuilder.randomSerial()
        let b = RemoteV2CertificateBuilder.randomSerial()
        XCTAssertEqual(a.count, 16)
        XCTAssertEqual(a[0] & 0x80, 0)
        XCTAssertNotEqual(a[0], 0)
        XCTAssertNotEqual(a, b)
    }
}
