# App Review Notes — DOONY

Paste everything below the line into App Store Connect → your build → **App
Review Information → Notes**. Plain text on purpose: that field does not render
Markdown, and it caps at **4000 characters** — check the count after any edit
(`awk 'f{print} /^---$/{f=1}' docs/APP_REVIEW_NOTES.md | wc -c`).

Reusable across submissions.

> **Two things not to reintroduce.** (1) An early draft, written for unlisted
> distribution, called the app a single-household tool with "no value to a
> general audience" — that argues the reviewer's case for a Guideline 4.2
> rejection on a public listing. (2) Length: the notes were rewritten to fit
> the 4000-character cap. Add a paragraph only by cutting one.

---

WHAT THIS APP IS

DOONY is a record-keeping tool for New York State's statutory-residence rule:
New York taxes you as a resident if you keep a home in the state and are
physically present there more than 183 days in a year, counting any part of a
day as a full day. Anyone keeping a New York home while claiming domicile
elsewhere — often people who relocated to Florida — has to document that count
if audited. DOONY maintains it automatically from on-device location and
organizes the domicile evidence an auditor weighs alongside it. The audience is anyone in that position and the accountants who
advise them. One-time purchase: no subscriptions, IAP, or ads.

ACCOUNTS

None — no sign-in, no server, no account system, so no demo credentials
needed.

BACKGROUND MODES (Guideline 2.5.4)

"location" is no longer declared in UIBackgroundModes — removed in build 1.0 (5)
in response to the 1.0 (4) review. DOONY does not need persistent real-time
location: background day-counting runs on the significant-change location
service, one dynamic geofence, and a daily BGAppRefresh task, the APIs
recommended for exactly this case. The only mode declared is "fetch", required
by BGAppRefreshTaskRequest. High-accuracy sampling engages only within 2 km of
the border and is foreground-only. There are no timers and no polling.

WHY "ALWAYS" LOCATION IS REQUESTED (Guideline 5.1.1)

The core feature is a per-day determination of whether the user was inside or
outside New York. As audit evidence it is only useful if complete: a count with
a gap on every day the user did not open the app is worthless, so "When In Use"
cannot support it. Background access records a fix on days the app is never
opened, catches a crossing with the phone in a pocket, and keeps recording after
termination or reboot — significant-location-change and region monitoring are
the only APIs that relaunch a terminated app.

The request itself is left to iOS. In build 1.0 (5) the button preceding the
system prompt reads "Continue", and the text above it explains only what the
feature does with location; it does not tell the user which option to choose.
The wording flagged in the 1.0 (4) review is gone. Declining is harmless: days
stay Unverified and the screen offers a Settings link, not a repeat prompt.

HOW TO TEST — a reviewer outside New York will see every day classified "Out of
NY"; that is correct behavior and demonstrates the feature.

1. Launch. The Days tab's first row explains the feature; "Continue" hands off
   to the iOS prompt. Declining leaves the app fully usable — every step below
   works without location.
2. For the in-NY path without traveling: tap any day in the Days tab and set
   Manual override to In NY; counts update immediately. Xcode's Debug >
   Simulate Location with a New York coordinate gives the same result through
   the real classification path.
3. The Domicile tab is a manually-entered checklist of domicile evidence.
4. The Export tab builds CSV/PDF and hands them to the share sheet — the only
   path by which data leaves the device, and only on user action.

PRIVACY

Zero network requests: no networking code, no analytics, no third-party SDKs,
no advertising identifiers — the basis for the "Data Not Collected"
declaration. Location data never leaves the device. Records are kept in an
on-device store with NSFileProtectionComplete; attachments are further
encrypted with AES-GCM under a Keychain key. All cryptography is Apple-provided
and used only for local data at rest, so ITSAppUsesNonExemptEncryption is
false.

NOT LEGAL OR TAX ADVICE

The app states, in-product and in its documentation, that it is a record-keeping
aid — not legal or tax advice, and not proof of residency or domicile. It files
nothing, connects to no tax authority, offers no professional services, and
processes no payments.
