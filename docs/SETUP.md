# Setup & Build

## Prerequisites
- macOS with **Xcode 15+** (iOS 17 SDK).
- **XcodeGen** (`brew install xcodegen`) to generate the project from `project.yml`.
- An Apple Developer account (free is fine for on-device installs of your own).

## Generate and open
```bash
cd DOONY
xcodegen generate      # produces DOONY.xcodeproj
open DOONY.xcodeproj
```

## Signing
1. In `project.yml`, set `DEVELOPMENT_TEAM` to your Apple **Team ID**
   (or leave blank and set it in Xcode → target → Signing & Capabilities).
2. Ensure **Signing** is set to "Automatically manage signing".
3. The **Data Protection** capability is provided by `DOONY.entitlements`.

## Run on device (required for location)
Background location needs real hardware. Select your iPhone, Run, then:
1. When prompted, choose **Allow While Using**, then upgrade to **Always** from
   the app's Days screen (or Settings → DOONY → Location → **Always**).
2. Optionally enable **Precise Location**.

### Verifying background behavior
- Xcode → Debug → Simulate Location, or drive/walk with the phone.
- The app records fixes via significant-change and geofence exits; you won't see
  a foreground indicator (by design — `showsBackgroundLocationIndicator = false`).
- Force-quit the app and move a significant distance; iOS relaunches it to record
  the day. Reboot and repeat to confirm survival.

## Getting it onto two family phones
There's no account system — each phone is independent. Options:
- **Free / personal:** open the project on your Mac and Run it to each iPhone
  over USB with the same Apple ID (7-day resign cycle on free accounts).
- **Best for family:** enroll in the Apple Developer Program and use **TestFlight**
  to install on both phones (90-day builds, easy re-installs). No data is shared
  between the two installs.

## Replacing the NY boundary (recommended before real use)
See `scripts/fetch_ny_boundary.md`. Drop the new file in at
`DOONY/Resources/ny_state_boundary.geojson` (keep the same name); the loader
handles full-resolution `Polygon`/`MultiPolygon`.

## Run tests
```bash
xcodebuild test -scheme DOONY -destination 'platform=iOS Simulator,name=iPhone 15'
```
