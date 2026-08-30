# App Review Notes — DOONY

Paste everything below the line into App Store Connect → your build → **App
Review Information → Notes**. It is plain text on purpose: that field does not
render Markdown.

Reusable across submissions.

> **History:** an earlier draft of this file was written for unlisted
> distribution and described the app as built for a single household with "no
> value to a general audience." That framing is fine for an unlisted request and
> actively harmful for a public listing — it argues the reviewer's case for a
> Guideline 4.2 rejection. It has been rewritten for public paid distribution.
> Do not reintroduce it.

---

WHAT THIS APP IS

DOONY is a record-keeping tool for New York State's statutory-residence rule.
New York taxes a person as a resident if they keep a home in the state and are
physically present there for more than 183 days in a year, counting any part of
a day as a full day. Anyone who keeps a home in New York while claiming domicile
elsewhere — a large and well-defined group, particularly people who have
relocated to Florida — has to be able to document that day count if audited.

DOONY maintains the count automatically from on-device location, and organizes
the qualitative domicile evidence an auditor weighs alongside it. The audience
is anyone in that situation and the accountants who advise them.

It is a one-time paid purchase. No subscriptions, no in-app purchases, no ads.

ACCOUNTS

None. No sign-in, no server, no account system. Launch the app and it works,
so no demo credentials are needed.

WHY THE APP REQUESTS "ALWAYS" LOCATION (Guideline 5.1.1)

The core feature is a per-calendar-day determination of whether the user was
inside or outside New York State. That record is only useful as audit evidence
if it is complete, and a day-count with gaps on every day the user happened not
to open the app is worthless for its purpose. "When In Use" therefore cannot
support the feature. Background access is needed to:

- record a fix on days the user never opens the app, and detect a border
  crossing while the phone is in a pocket; and
- keep recording after the app is terminated or the phone reboots.
  Significant-location-change and region monitoring are the only APIs that
  relaunch a terminated app, which is why both are used.

On battery, the app is deliberately conservative. The baseline is
significant-location-change only. After each fix it registers one dynamic
geofence whose radius is the distance to the NY border, so iOS wakes the app
only once the user has moved materially toward the line. High-accuracy GPS is
engaged only within 2 km of the border and switched off once the position is
unambiguous. There are no timers and no polling; a stationary user generates a
handful of fixes per day. Location data stays on the device.

HOW TO TEST

A reviewer outside New York will see every day classified as "Out of NY". That
is correct behavior and demonstrates the feature working.

1. Launch and grant location access. The Days tab shows today classified, with
   a calendar heat map for the year.
2. To exercise the in-NY path without traveling, tap any day in the Days tab
   and use Manual override to set it to In NY; the summary counts update
   immediately. Xcode's Debug > Simulate Location with a New York coordinate
   produces the same result through the real classification path.
3. The Domicile tab is a manually-entered checklist of domicile evidence.
4. The Export tab builds CSV/PDF files and hands them to the system share
   sheet. That is the only path by which data leaves the device, and only on
   user action.

PRIVACY

The app makes zero network requests. There is no networking code, no analytics,
no third-party SDKs, and no advertising identifiers, which is the basis for the
"Data Not Collected" App Privacy declaration. Records and documents are kept in
an on-device store protected with NSFileProtectionComplete; attachments are
further encrypted with AES-GCM under a Keychain-held key. All cryptography is
Apple-provided and used solely for local data at rest, so
ITSAppUsesNonExemptEncryption is false.

NOT LEGAL OR TAX ADVICE

The app states, in-product and in its documentation, that it is a
record-keeping aid, not legal or tax advice, and not proof of residency or
domicile. It files nothing, connects to no tax authority, offers no
professional services, and processes no payments.
