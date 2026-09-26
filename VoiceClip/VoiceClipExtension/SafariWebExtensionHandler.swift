import SafariServices
import UIKit

/// Native side of the extension. background.js reaches it with
/// `browser.runtime.sendNativeMessage`. It owns the clipboard (a web page
/// can only write the clipboard during a tap on that page, which a Siri
/// command or a popup tap isn't) and the Siri inbox.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let maxClipLength = 500_000

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        // UIPasteboard is UIKit; touch it on the main thread.
        DispatchQueue.main.async {
            let reply = Self.handle(message)
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private static func handle(_ message: [String: Any]) -> [String: Any] {
        switch message["type"] as? String {
        case "copy":
            guard let text = message["text"] as? String, !text.isEmpty else {
                return ["ok": false, "error": "Nothing to copy."]
            }
            guard text.count <= maxClipLength else {
                return ["ok": false, "error": "That's too much text to copy at once."]
            }
            UIPasteboard.general.string = text
            return ["ok": true]

        case "readClipboard":
            // Reading text another app put on the clipboard may be refused by
            // iOS until "Paste from Other Apps" is set to Allow for VoiceClip.
            guard UIPasteboard.general.hasStrings else {
                return ["ok": false, "error": "The clipboard has no text."]
            }
            guard let text = UIPasteboard.general.string, !text.isEmpty else {
                return ["ok": false, "error": "iOS blocked reading the clipboard. Settings → Apps → VoiceClip → Paste from Other Apps → Allow."]
            }
            return ["ok": true, "text": text]

        case "poll":
            guard let pending = CommandInbox.take() else { return [:] }
            return ["id": pending.id, "command": pending.command]

        case "result":
            guard let id = message["id"] as? String else { return ["ok": false] }
            CommandInbox.postResult(
                id: id,
                ok: message["ok"] as? Bool ?? false,
                message: message["message"] as? String ?? ""
            )
            return ["ok": true]

        default:
            return ["ok": false, "error": "Unknown request."]
        }
    }
}
