import Foundation
import Security
import SwiftADB

/// Keeps one stable ADB RSA identity in Keychain so the TV does not need to
/// authorize a freshly generated host key every time Glass Remote launches.
enum ADBIdentity {
    private static let service = "com.glassremote.ios.adb"
    private static let account = "host-rsa-private"

    static func loadOrCreate() throws -> KeyPair {
        if let privateData = readKey(),
           let privateKey = makeKey(data: privateData, isPrivate: true),
           let publicKey = SecKeyCopyPublicKey(privateKey) {
            return KeyPair(privateKey: privateKey, publicKey: publicKey)
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw (error?.takeRetainedValue() as Error?) ?? NSError(domain: "GlassRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create ADB identity"])
        }
        saveKey(privateData)
        return KeyPair(privateKey: privateKey, publicKey: publicKey)
    }

    private static func makeKey(data: Data, isPrivate: Bool) -> SecKey? {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        return SecKeyCreateWithData(data as CFData, attrs as CFDictionary, nil)
    }

    private static func readKey() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func saveKey(_ data: Data) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
