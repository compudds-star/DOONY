#!/usr/bin/env bash
# Capture App Store screenshots from seeded demo data.
#
# Builds Debug for the iPhone 17 Pro Max simulator (6.9" — the only iPhone size
# App Store Connect requires; Apple scales it down for smaller devices), launches
# the app with the demo-data seeder, and captures one PNG per tab at exactly
# 1320 x 2868. No resizing or editing needed: upload the files as they come out.
#
#   ./scripts/capture_screenshots.sh [output-dir]
#
# The seeder is DEBUG-only and gated behind -DOONYSeedDemoData, so none of this
# reaches a Release build. Screenshots use invented data on purpose — real ones
# would publish an actual residency day-count and home addresses to a public
# App Store listing.
set -euo pipefail

DEVICE="${DEVICE:-iPhone 17 Pro Max}"
OUT="${1:-screenshots}"
DD="$(mktemp -d)/dd"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$OUT"
cd "$ROOT"

echo "==> Building Debug for $DEVICE"
xcodebuild -project DOONY.xcodeproj -scheme DOONY -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DD" build >/dev/null

APP="$DD/Build/Products/Debug-iphonesimulator/DOONY.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

echo "==> Booting $DEVICE"
SIM="$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for v in d.values() for x in v if x['name']=='$DEVICE'))")"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null

xcrun simctl uninstall "$SIM" com.doony.app 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl privacy "$SIM" grant location-always com.doony.app 2>/dev/null || true

names=(01-days 02-domicile 03-export)
for tab in 0 1 2; do
  name="${names[$tab]}"
  echo "==> Capturing $name"
  xcrun simctl terminate "$SIM" com.doony.app >/dev/null 2>&1 || true
  xcrun simctl launch "$SIM" com.doony.app -DOONYSeedDemoData -DOONYScreenshotTab "$tab" >/dev/null
  python3 -c "import time; time.sleep(4)"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1
done

echo
echo "Wrote to $OUT:"
for f in "$OUT"/*.png; do
  printf '  %-28s %s\n' "$(basename "$f")" \
    "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done
echo
echo "For the calendar heatmap and day-detail screens, tap through from the Days"
echo "tab in the running simulator and press Cmd+S. Those sit behind navigation"
echo "the launch arguments do not reach."
