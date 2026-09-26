import SwiftUI

@main
struct VoiceClipApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

/// The container app only exists to ship the Safari extension and the Siri
/// shortcut, so its one screen is setup instructions.
struct SetupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("1 · Turn on the Safari extension") {
                    Step(n: 1, text: "Open Settings → Apps → Safari → Extensions → VoiceClip.")
                    Step(n: 2, text: "Turn it on, and set All Websites to Allow.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("2 · Talk to it") {
                    Label {
                        Text("**Siri:** “Hey Siri, VoiceClip command.” When Siri asks, say “copy from FaceTime to location”.")
                    } icon: { Image(systemName: "waveform") }
                    Label {
                        Text("**In Safari:** tap aA → VoiceClip, then tap 🎙 (or the keyboard's dictation key) and speak.")
                    } icon: { Image(systemName: "safari") }
                    Label {
                        Text("**Action Button / Back Tap:** assign the “Clipboard Command” shortcut for one-press voice.")
                    } icon: { Image(systemName: "hand.tap") }
                }

                Section("Things you can say") {
                    ForEach(Self.examples, id: \.self) { Text($0).font(.body.monospaced()) }
                }

                Section("Paste from other apps") {
                    Text("To paste text you copied outside Safari, set Settings → Apps → VoiceClip → Paste from Other Apps → Allow.")
                        .font(.footnote)
                }

                Section("Privacy") {
                    Text("VoiceClip reads page text only when you give it a command, keeps nothing it copies, and makes no network requests.")
                        .font(.footnote)
                }
            }
            .navigationTitle("VoiceClip")
        }
    }

    static let examples = [
        "copy from FaceTime to location",
        "copy the paragraph about pricing",
        "copy the sentence containing deadline",
        "copy from Dear to the end",
        "cut from please to thanks",
        "select everything",
        "copy selection",
        "paste into email",
    ]
}

private struct Step: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n).").bold().foregroundStyle(.orange)
            Text(text)
        }
    }
}
