import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Removes metadata (notably GPS/EXIF) from imported images before they are
/// encrypted and stored, unless the user explicitly opts to keep it.
///
/// Rationale: a domicile photo (e.g. a scanned FL registration) should not
/// silently carry the coordinates of where it was taken. This is a privacy
/// safeguard, on by default.
enum ExifStripper {

    /// Returns image data with all metadata removed. If re-encoding fails for any
    /// reason, returns nil (caller can decide to keep the original or reject it).
    static func stripped(imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let uti = CGImageSourceGetType(source) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            return nil
        }

        // Overwrite metadata dictionaries with empty/removed values.
        let removeProperties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: kCFNull as Any,
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyIPTCDictionary: kCFNull as Any,
            kCGImagePropertyTIFFDictionary: kCFNull as Any,
            kCGImageMetadataShouldExcludeGPS: kCFBooleanTrue as Any,
            kCGImageDestinationMetadata: kCFNull as Any
        ]

        CGImageDestinationAddImageFromSource(destination, source, 0, removeProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// True if the data appears to be an image type we can strip.
    static func isImage(typeIdentifier: String) -> Bool {
        guard let type = UTType(typeIdentifier) else { return false }
        return type.conforms(to: .image)
    }
}
