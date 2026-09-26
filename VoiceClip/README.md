# VoiceClip

A Safari extension for iPhone/iPad that copies, cuts, selects, and pastes page
text by voice:

> “Hey Siri, VoiceClip command.” → *“What should I copy, cut, or paste?”* →
> “**copy from FaceTime to location**”

VoiceClip finds “FaceTime” on the page you're looking at, selects through the
next “location”, flashes the selection, puts the text on the clipboard, and
Siri answers “Copied 14 words.”

Everything lives in `VoiceClip/`; generate the Xcode project from `VoiceClip/project.yml`.

## Ways to speak a command

| Path | How | Notes |
|---|---|---|
| **Siri** | “Hey Siri, VoiceClip command”, then say the command | Hands-free. Siri asks for the command as a second step, because App Shortcut phrases can't contain free-form text. |
| **Action Button / Back Tap** | Assign the **Clipboard Command** shortcut | One press, then speak. |
| **Extension popup** | Safari → aA (or the puzzle icon) → VoiceClip → 🎙 | Uses the Web Speech API when Safari allows it in the popup; otherwise tap the field and use the keyboard's dictation key. |

## What you can say

| Command | Does |
|---|---|
| `copy from FaceTime to location` | From the first word through the next occurrence of the second |
| `copy from Dear to the end` | …to the end of that paragraph (`…end of the sentence`, `…end of the page` also work) |
| `copy the paragraph about pricing` | The whole paragraph containing the phrase (`containing`, `with`, `mentioning`, … all work) |
| `copy the sentence containing deadline` | Just that sentence |
| `copy invoice number` | Just the phrase |
| `copy selection` / `copy` | Whatever is already selected |
| `select everything` | Whole page, or the whole focused text field |
| `cut from please to thanks` | Copy, then delete — only in editable text (text fields, compose windows); on normal page text it copies and says so |
| `paste` / `paste into email` | Into the focused field, or the field whose label/placeholder matches |

`select` / `highlight` do the same matching without touching the clipboard.

**Matching is speech-tolerant.** Both the page and the command are reduced to
lowercase letters and digits, so “face time” matches *FaceTime*, “e mail”
matches *e-mail*, “and” matches *&*, and accents are ignored. When a phrase
occurs more than once, the one on screen wins. When “to” is ambiguous
(“copy from how to cook to dessert”), every split is tried against the page.
If you're typing in a text field, that field is searched before the page.

## How it fits together

```
Siri ─▶ ClipCommandIntent ─▶ CommandInbox (App Group) ◀─ poll ─ content.js (visible tab)
                    ▲                                                   │
                    └──────────── result ("Copied 14 words") ◀──────────┘
Popup ─▶ background.js ─▶ content.js ─▶ background.js ─▶ SafariWebExtensionHandler ─▶ UIPasteboard
```

- `VoiceClipExtension/Resources/parser.js` — command grammar (pure, unit-tested).
- `…/textmatch.js` — speech-tolerant matching that maps back to exact offsets.
- `…/content.js` — walks visible text nodes, builds DOM ranges, selects, cuts, pastes, shows a toast.
- `…/background.js` — relay; only accepts messages from its own content script/popup.
- `VoiceClipExtension/SafariWebExtensionHandler.swift` — clipboard read/write and the Siri inbox.
- `VoiceClip/ClipCommandIntent.swift` — the Siri / Shortcuts action.
- `Shared/CommandInbox.swift` — App Group hand-off, used by both processes.

**Why the clipboard is written natively:** `navigator.clipboard` only works
during a tap *on that page*. A Siri command or a tap in the popup isn't one,
so the page hands the text to the extension's native handler, which sets
`UIPasteboard.general`.

**Siri pickup:** the extension can't be woken by Siri directly, so the visible
tab polls the App Group inbox every 1.5 s (only while it's visible, one
native call each). Each command is handed out once and expires after 20 s,
so it runs in exactly one tab and never fires late. You can turn this off in
the popup (“Listen for Siri commands…”) if you only use the popup.

## Build

```bash
brew install xcodegen
cd VoiceClip
xcodegen generate
open VoiceClip.xcodeproj
```

1. Signing uses team `24Q366W5BQ`. Bundle IDs are
   `com.compudds.voiceclip` and `com.compudds.voiceclip.extension`; change both
   plus the App Group (`group.com.compudds.voiceclip` in both `.entitlements`
   files **and** `Shared/CommandInbox.swift`) if you want a different prefix.
2. Enable the **App Groups** capability for both App IDs in the developer
   portal (automatic signing usually does this for you).
3. Run the **VoiceClip** scheme on your iPhone.
4. Settings → Apps → Safari → Extensions → VoiceClip → on, **All Websites → Allow**.
5. Say “Hey Siri, VoiceClip command.” The first time, Siri may ask to allow
   VoiceClip — allow it.
6. To paste text copied in other apps: Settings → Apps → VoiceClip → Paste from
   Other Apps → **Allow**.

Regenerate icons after editing the drawing: `python3 scripts/generate_icons.py`.

## Tests

```bash
cd VoiceClip
node --test tests/*.test.mjs                  # grammar + matching (13 tests)
NODE_PATH=$(npm root -g) node tests/e2e.mjs   # real content script in headless Chromium, browser API stubbed
```

The e2e run covers range/paragraph/sentence/end selection, ambiguous “to”,
cut in a textarea vs. read-only page text, paste into a named field, password
fields, and the Siri inbox round-trip. It runs in Chromium, not Safari — do a
device pass for the Safari-specific bits below.

## Known limits

- **Web Speech in the popup** depends on the iOS version; the keyboard
  dictation key always works as a fallback.
- **Cut** only deletes editable text. Page text on a normal website can't be
  removed, so VoiceClip copies it and tells you.
- **Iframes** (some embedded editors, e.g. Google Docs' canvas) aren't
  searched; the extension runs in the top-level page only.
- **Numbers**: say them the way the page writes them; “twenty five” won't match “25”.
- **Siri latency**: up to ~1.5 s for the page to pick up the command.

## Privacy & security

- No network requests; no analytics.
- Page text is read only when you give a command, and only visible text.
  Password fields are never read.
- Copied text goes straight to the system clipboard; nothing you copy is stored.
  The App Group holds only the pending command string (≤ 500 chars, 20 s TTL)
  and a one-line status message.
- Web pages can't talk to the extension (no `externally_connectable`), and
  `background.js` only forwards the fixed message types, checking which come
  from a tab and which from the popup.
- The toast and flash overlay live in a closed shadow root and use
  `textContent` only, so page text can't inject markup.
