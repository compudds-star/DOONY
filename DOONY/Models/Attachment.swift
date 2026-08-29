import Foundation
import SwiftData

/// Metadata for an encrypted attachment (document/photo) that supports a dossier entry.
///
/// The bytes themselves are NEVER stored in the database. They live as an
/// AES-GCM–encrypted blob on disk (see `AttachmentCrypto`), protected with
/// `NSFileProtectionComplete`. Only this metadata row references it.
@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    /// Filename of the encrypted blob on disk (e.g. "<uuid>.enc").
    var encryptedFilename: String
    /// Original filename shown in the UI.
    var displayName: String
    /// UTI / MIME hint for re-opening (e.g. "public.jpeg", "com.adobe.pdf").
    var typeIdentifier: String
    var createdAt: Date
    /// For image imports: whether the user chose to KEEP EXIF/GPS. Default false = stripped.
    var retainedImageMetadata: Bool
    /// Size of the plaintext in bytes (for display).
    var byteCount: Int

    init(id: UUID = UUID(),
         encryptedFilename: String,
         displayName: String,
         typeIdentifier: String,
         createdAt: Date = .now,
         retainedImageMetadata: Bool = false,
         byteCount: Int = 0) {
        self.id = id
        self.encryptedFilename = encryptedFilename
        self.displayName = displayName
        self.typeIdentifier = typeIdentifier
        self.createdAt = createdAt
        self.retainedImageMetadata = retainedImageMetadata
        self.byteCount = byteCount
    }
}
