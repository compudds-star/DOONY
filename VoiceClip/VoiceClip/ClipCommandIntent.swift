import AppIntents

/// "Hey Siri, VoiceClip command" → Siri asks "What should I copy, cut, or
/// paste?" → "copy from FaceTime to location". The command is handed to the
/// Safari page on screen through the App Group inbox; the page runs it and
/// the result is spoken back.
struct ClipCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Clipboard Command in Safari"
    static let description = IntentDescription(
        "Copy, cut, select, or paste text on the Safari page you're looking at, e.g. “copy from FaceTime to location”."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Command",
        requestValueDialog: IntentDialog("What should I copy, cut, or paste?")
    )
    var command: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = CommandInbox.post(command)

        // The page polls every 1.5 s; give it a few rounds.
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(200))
            if let result = CommandInbox.takeResult(id: id) {
                return .result(dialog: "\(result.message)")
            }
        }
        CommandInbox.cancel(id: id)
        return .result(dialog: "Safari didn't pick that up. Make sure VoiceClip is allowed on this website, then try again.")
    }
}

struct VoiceClipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClipCommandIntent(),
            phrases: [
                "\(.applicationName) command",
                "Clip with \(.applicationName)",
                "Run \(.applicationName)",
            ],
            shortTitle: "Clipboard Command",
            systemImageName: "doc.on.clipboard"
        )
    }
}
