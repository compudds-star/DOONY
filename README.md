# DOONY

**Privacy-first iOS app for two purposes in one:**

1. **Day tracking** — record, via background GPS, whether each calendar day
   (America/New_York) was spent **inside** or **outside** New York State, to
   support NY's statutory-resident **183-day** test.
2. **Florida domicile dossier** — a structured, on-device record of the
   qualitative evidence a NY residency auditor weighs under the "totality of
   circumstances" domicile test.

Everything stays **on-device**. No cloud, no analytics, no third-party SDKs, no
network calls — the only way data leaves the phone is an **export you initiate**
through the iOS share sheet.

> ⚖️ **Not legal advice.** DOONY is a record-keeping aid. It organizes evidence
> and corroborates a day-count; it does **not** substitute for the actual
> filings (Declaration of Domicile, homestead exemption, NY driver's-license
> surrender) and is not proof of domicile. See [`docs/LEGAL_CAVEATS.md`](docs/LEGAL_CAVEATS.md).

---

## Why native Swift (not Expo / React Native)

**Recommendation: native Swift/SwiftUI. Confirmed.** The two hardest
requirements — *reliable background location that survives termination/reboot*
and *on-device encryption at rest* — are exactly where a JS bridge is weakest.

| Requirement | Native Swift | Expo / React Native |
|---|---|---|
| Background location **after app termination & reboot** (SLC + region relaunch) | First-class `CLLocationManager` APIs; OS relaunches the app into the background delegate | Depends on `expo-location`/`expo-task-manager`; JS runtime must be resurrected — historically fragile for *terminated*-state relaunch, and Expo Go can't do always-on background location at all (needs a dev/prod build) |
| On-device encryption | CryptoKit + Keychain + `NSFileProtectionComplete` directly | Needs native modules anyway (`expo-secure-store`, `expo-crypto`); you end up writing/native-bridging the exact code we wrote here |
| Point-in-polygon on bundled GeoJSON | Pure Swift, runs in the background delegate with no bridge | Doable in JS, but the heavy border math would run on the JS thread during background wakeups |
| "No third-party SDKs" constraint | Zero external dependencies (Apple frameworks only) | React Native itself + Expo modules are third-party code in your process |
| Data-protection classes per file | Full control (`.complete`, `.completeUntilFirstUserAuthentication`) | Not exposed granularly |

The moment you need robust background location **and** file-level encryption
**and** zero third-party SDKs, Expo's advantage (cross-platform JS) is spent on
plumbing you'd have to write natively anyway. Since the app is iPhone-only for
two users, native Swift is the right call. **This repo is the native Swift
implementation.**

---

## What's in the box

```
DOONY/
├── DOONY/
│   ├── DOONYApp.swift            App entry; SwiftData container + file protection
│   ├── Info.plist                All location keys + background modes (below)
│   ├── DOONY.entitlements        Data Protection capability
│   ├── Resources/
│   │   └── ny_state_boundary.geojson   Bundled NY boundary (MultiPolygon)
│   ├── Models/                   SwiftData @Model types (samples, days, dossier)
│   ├── Location/                 GeoBoundary (point-in-polygon), LocationManager, DayClassifier
│   ├── Security/                 Keychain key, AES-GCM attachment crypto, EXIF stripper
│   ├── Domicile/                 Readiness + red-flag engine
│   ├── Export/                   CSV + PDF builders (local share only)
│   └── Views/                    SwiftUI — day tracking, dossier, export
├── DOONYTests/                   Point-in-polygon + classification tests
├── project.yml                   XcodeGen spec → DOONY.xcodeproj
├── scripts/                      How to swap in an authoritative NY boundary
└── docs/                         Architecture, security review, legal caveats, setup
```

## How day classification works

- A background fix is tested **on-device** against the bundled NY polygon
  (ray-casting point-in-polygon, supports the state's islands via MultiPolygon +
  holes). No remote geocoding, ever.
- Each **America/New_York** calendar day becomes:
  - **NY** — if *any* sample that day is inside NY (NY's "any part of a day" rule),
  - **Out of NY** — only if the day has samples and *all* are outside NY,
  - **Unverified** — if the day has **no** samples (phone off). Never assumed.
- Every raw sample is stored (timestamp, coords, accuracy, result, distance to
  border, source), so a day's status always traces back to its points.
- Samples within ~3 km of the border are flagged `nearBorder`, precise sampling
  is escalated, and the day is marked for your review.

### Battery strategy (event-driven, no foreground loop)
1. **Significant-location-change** baseline — very low power; the OS relaunches
   the app in the background to deliver these even after termination/reboot.
2. **Dynamic geofence** — one circular region centered on your current location
   with radius ≈ distance-to-border; leaving it wakes the app for a fresh check.
3. **Escalation** — high-accuracy sampling turns on only near the border, off again once safely inside/outside.

## Info.plist location keys & background modes

Included in [`DOONY/Info.plist`](DOONY/Info.plist):

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationAlwaysUsageDescription` (legacy)
- `NSLocationTemporaryUsageDescriptionDictionary` → `BorderPrecision`
- `UIBackgroundModes` = `location`
- `ITSAppUsesNonExemptEncryption` = `false` (standard, exempt encryption)

Data protection is enabled via the **Data Protection** capability in
[`DOONY/DOONY.entitlements`](DOONY/DOONY.entitlements)
(`com.apple.developer.default-data-protection` = `NSFileProtectionComplete`).

## Two people, two phones

There is no account system and no shared storage — each install is a fully
independent, self-contained dossier and day-count on that person's own device.
You and your wife each run your own copy; nothing syncs between them.

## Security & privacy at a glance

- **No egress.** No networking code anywhere; the only outbound path is the
  user-tapped share sheet. See the audit in [`docs/SECURITY_PRIVACY_REVIEW.md`](docs/SECURITY_PRIVACY_REVIEW.md).
- **Encrypted at rest.** SwiftData store uses `NSFileProtectionCompleteUntilFirstUserAuthentication` (writable in the background, encrypted at rest); attachment blobs use AES-GCM with a Keychain key **and** `NSFileProtectionComplete`.
- **Keychain** key is `WhenUnlockedThisDeviceOnly` — never backed up, never leaves the device.
- **EXIF/GPS stripped** from imported photos by default (opt-in to keep).
- **Masked in UI**: driver's-license, policy, and account numbers show only the last few characters; full values are encrypted at rest.
- **No PII in logs/crashes.** Coordinates and errors are logged only under `#if DEBUG`; release builds are silent.

## Build & run

```bash
brew install xcodegen        # one-time
cd DOONY
xcodegen generate            # creates DOONY.xcodeproj from project.yml
open DOONY.xcodeproj
```
Set your Apple **Team ID** in `project.yml` (or in Xcode's Signing pane), then
run on a real device (background location needs hardware). Full steps and the
"getting the app onto two family phones" notes are in [`docs/SETUP.md`](docs/SETUP.md).

## Bundled NY boundary — replace for production accuracy

The bundled `ny_state_boundary.geojson` is a **medium-fidelity** public-domain
outline (good enough to demo and to classify interior days). For **audit-grade
border accuracy**, replace it with the authoritative U.S. Census **TIGER/Line**
boundary — see [`scripts/fetch_ny_boundary.md`](scripts/fetch_ny_boundary.md).
The loader already handles a full-resolution `Polygon`/`MultiPolygon` drop-in.

## ⚠️ This was generated in the cloud

This project was generated in a remote container and pushed to GitHub — it could
not create a folder on your physical Desktop. To put it where you asked:

```bash
mkdir -p ~/Desktop/Claude
cd ~/Desktop/Claude
git clone <your DOONY repo URL> DOONY
cd DOONY && git checkout claude/ny-residency-fl-domicile-app-5tm2wl
```
