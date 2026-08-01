import Foundation
import CryptoKit
import Security

/// Owns the single symmetric key used to encrypt attachment blobs.
///
/// The key is generated once, on first launch, and stored in the Keychain with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
///   - never leaves the device,
///   - never included in iCloud/iTunes backups,
///   - only readable while the device is unlocked.
///
/// The SwiftData store itself is separately protected with
/// `NSFileProtectionComplete` (see `DOONYApp`); this key adds a second,
/// app-scoped layer over binary attachments.
enum KeychainKeyStore {
    private static let service = "com.doony.attachmentKey"
    private static let account = "primary"

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    /// Returns the existing key, or generates and stores a new one.
    static func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try storeKey(key)
        return key
    }

    private static func loadKey() throws -> SymmetricKey? {
        var query: [String: Any] = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        var query: [String: Any] = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
