import Foundation
import CryptoKit

/// Encrypts and decrypts attachment blobs with AES-GCM, storing ciphertext in a
/// dedicated Application Support subdirectory that is excluded from backup and
/// marked `NSFileProtectionComplete` (unreadable while the device is locked).
struct AttachmentCrypto {
    private let key: SymmetricKey
    private let directory: URL

    init() throws {
        self.key = try KeychainKeyStore.loadOrCreateKey()
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let dir = base.appendingPathComponent("EncryptedAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        // Keep encrypted blobs out of iCloud/iTunes backups.
        var mutableDir = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableDir.setResourceValues(values)
        self.directory = dir
    }

    /// Encrypts `plaintext` and writes it to `<uuid>.enc`. Returns the filename.
    @discardableResult
    func write(plaintext: Data, filename: String) throws -> URL {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = directory.appendingPathComponent(filename)
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Reads and decrypts the blob for `filename`.
    func read(filename: String) throws -> Data {
        let url = directory.appendingPathComponent(filename)
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    /// Permanently removes the encrypted blob.
    func delete(filename: String) {
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }
}
