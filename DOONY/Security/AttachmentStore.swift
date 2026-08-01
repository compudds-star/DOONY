import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Coordinates importing, encrypting, decrypting, and deleting attachments.
/// A single shared instance is used by the views.
@MainActor
final class AttachmentStore: ObservableObject {
    static let shared = try? AttachmentStore()

    private let crypto: AttachmentCrypto

    init() throws {
        self.crypto = try AttachmentCrypto()
    }

    /// Import raw bytes as a new encrypted attachment.
    ///
    /// - Parameter keepImageMetadata: if false (default) and the data is an image,
    ///   EXIF/GPS metadata is stripped before encryption.
    /// - Returns: an `Attachment` metadata object (caller inserts it into the model).
    func importAttachment(data rawData: Data,
                          displayName: String,
                          typeIdentifier: String,
                          keepImageMetadata: Bool = false) throws -> Attachment {
        var data = rawData
        var retained = keepImageMetadata

        if ExifStripper.isImage(typeIdentifier: typeIdentifier), !keepImageMetadata {
            if let stripped = ExifStripper.stripped(imageData: rawData) {
                data = stripped
                retained = false
            } else {
                // If we cannot strip, do NOT silently keep metadata; store as-is but
                // flag it so the UI can warn the user.
                retained = true
            }
        }

        let filename = UUID().uuidString + ".enc"
        try crypto.write(plaintext: data, filename: filename)

        return Attachment(
            encryptedFilename: filename,
            displayName: displayName,
            typeIdentifier: typeIdentifier,
            retainedImageMetadata: retained,
            byteCount: data.count
        )
    }

    /// Decrypt an attachment's bytes for viewing/export.
    func decrypt(_ attachment: Attachment) throws -> Data {
        try crypto.read(filename: attachment.encryptedFilename)
    }

    /// Delete both the metadata and the on-disk encrypted blob.
    func delete(_ attachment: Attachment, context: ModelContext) {
        crypto.delete(filename: attachment.encryptedFilename)
        context.delete(attachment)
    }
}
