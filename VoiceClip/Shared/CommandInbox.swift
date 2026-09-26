import Foundation

/// Hand-off between the Siri intent (app process) and the Safari extension
/// (extension process) through the shared App Group.
///
/// Siri posts a command; the page the user is looking at polls, takes it
/// (exactly once), runs it, and posts a result the intent speaks back.
/// Commands expire quickly so a stale one never fires on a page opened later.
/// Only the command text and a short status message are stored — never the
/// copied text itself.
enum CommandInbox {
    static let appGroup = "group.com.compudds.voiceclip"

    private static let pendingKey = "pendingCommand"
    private static let resultKey = "lastResult"
    private static let commandTTL: TimeInterval = 20
    private static let resultTTL: TimeInterval = 30
    static let maxCommandLength = 500

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    struct Result {
        let ok: Bool
        let message: String
    }

    /// Stores `command` for the extension and returns its id.
    @discardableResult
    static func post(_ command: String) -> String {
        let id = UUID().uuidString
        let trimmed = String(command.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCommandLength))
        defaults?.set(["id": id, "command": trimmed, "at": Date().timeIntervalSince1970], forKey: pendingKey)
        defaults?.removeObject(forKey: resultKey)
        return id
    }

    /// Removes and returns the pending command, if one is fresh.
    static func take() -> (id: String, command: String)? {
        guard let d = defaults, let entry = d.dictionary(forKey: pendingKey) else { return nil }
        d.removeObject(forKey: pendingKey)
        guard
            let id = entry["id"] as? String,
            let command = entry["command"] as? String,
            let at = entry["at"] as? TimeInterval,
            Date().timeIntervalSince1970 - at <= commandTTL
        else { return nil }
        return (id, command)
    }

    static func postResult(id: String, ok: Bool, message: String) {
        defaults?.set(
            ["id": id, "ok": ok, "message": String(message.prefix(300)), "at": Date().timeIntervalSince1970],
            forKey: resultKey
        )
    }

    /// Removes and returns the result for `id`, if the extension has posted it.
    static func takeResult(id: String) -> Result? {
        guard
            let d = defaults,
            let entry = d.dictionary(forKey: resultKey),
            entry["id"] as? String == id
        else { return nil }
        d.removeObject(forKey: resultKey)
        guard let at = entry["at"] as? TimeInterval, Date().timeIntervalSince1970 - at <= resultTTL else { return nil }
        return Result(ok: entry["ok"] as? Bool ?? false, message: entry["message"] as? String ?? "")
    }

    /// Drops an unclaimed command so it can't fire after Siri has given up.
    static func cancel(id: String) {
        guard let d = defaults, let entry = d.dictionary(forKey: pendingKey), entry["id"] as? String == id else { return }
        d.removeObject(forKey: pendingKey)
    }
}
