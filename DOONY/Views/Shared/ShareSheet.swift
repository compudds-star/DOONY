import SwiftUI
import UIKit

/// Wraps `UIActivityViewController` so exports go ONLY through the OS share
/// sheet (AirDrop, Files, Mail chosen by the user). The app itself makes no
/// network calls — any egress is an explicit user action here.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Writes a string to a temporary file and returns its URL (for CSV sharing).
enum TempFile {
    static func write(_ contents: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        do { try contents.write(to: url, atomically: true, encoding: .utf8); return url }
        catch { return nil }
    }

    static func write(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        do { try data.write(to: url); return url } catch { return nil }
    }
}
