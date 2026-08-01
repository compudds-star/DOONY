# Security & Privacy Review

Scope: the DOONY iOS app in this repository. Reviewed against the project's
hard constraints (all data on-device, no egress, encrypted at rest, no PII in
logs/crashes, sensitive identifiers masked).

## 1. No data egress ✅

- **No networking APIs are used anywhere in the codebase.** There is no
  `URLSession`, `URLRequest`, socket, `WKWebView` loading remote content, or
  third-party SDK. You can verify:
  ```bash
  grep -rEn "URLSession|URLRequest|dataTask|http://|https://|Network\\.|CFStream|Socket" DOONY/
  ```
  The only `https://` strings are in Markdown docs, not app code.
- **Point-in-polygon is fully local.** The NY boundary is bundled as GeoJSON and
  evaluated on-device (`GeoBoundary.swift`). No remote geocoding.
- **The only outbound path is the system share sheet** (`ShareSheet.swift`),
  triggered exclusively by a user tap in `ExportView`. The user chooses the
  destination (Files, AirDrop, Mail). Nothing is transmitted automatically.
- **No analytics / telemetry / crash-reporting SDK** is linked. Apple's default
  crash reporting is OS-level and contains no app-collected PII (see §4).

**Recommended defense-in-depth:** ship with **no** networking entitlement and,
if desired, an App Transport Security posture that blocks all loads. Because no
code makes requests, this is belt-and-suspenders.

## 2. Encrypted storage ✅

| Data | At-rest protection | Notes |
|---|---|---|
| SwiftData store (`DOONY.store`, `-wal`, `-shm`) | `NSFileProtectionCompleteUntilFirstUserAuthentication` | Encrypted at rest; readable only after first unlock post-boot. Chosen over `.complete` **on purpose** so background location events can be written while the device is locked. |
| Attachment blobs (photos/docs) | **AES-GCM** (CryptoKit) with a 256-bit key, **plus** `NSFileProtectionComplete` | Double-wrapped: even a file-system compromise yields ciphertext. Only decrypted in the foreground when viewed/exported. |
| Attachment key | **Keychain**, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Never in iCloud/iTunes backups; never leaves the device; only available while unlocked. |
| Encrypted-attachments directory | Excluded from backup (`isExcludedFromBackup`) | Prevents ciphertext from leaking into unencrypted backups. |

**Why the store isn't `.complete`:** a location-tracking app must write in the
background while the phone is locked. `NSFileProtectionComplete` would make the
DB unreadable exactly then, dropping samples. `CompleteUntilFirstUserAuthentication`
is Apple's recommended class for background-writable stores and still encrypts at
rest. This is a deliberate, documented trade-off.

## 3. Sensitive identifiers masked in UI ✅

- Driver's-license number, insurance policy #, and financial account references
  render through `Masking.mask(...)` — only the last ~4 characters show
  (`•••• 1234`) unless the user taps the reveal (eye) control.
- Raw values are stored in the encrypted SwiftData store, never in plaintext
  logs or exports-by-default.

## 4. No PII in logs or crash reports ✅

- The only location logging is guarded by `#if DEBUG` in
  `LocationManager.locationManager(_:didFailWithError:)` and prints just a
  localized error string (no coordinates). Release builds compile this out.
- No `print`/`os_log` of coordinates, names, DL/account numbers anywhere.
- Because no crash-reporting SDK is linked and the app never hands PII to
  `NSLog`/`os_log`, Apple's OS crash logs contain only stack/system data, not
  app-collected personal data.

**Recommendation:** keep it this way. If you ever add logging, route it through a
single helper that is a no-op in release and never accepts coordinates or
identifiers.

## 5. Photo metadata (EXIF/GPS) ✅

- `ExifStripper` re-encodes imported images with the EXIF/GPS/IPTC/TIFF
  dictionaries removed **by default**. The user must explicitly toggle "keep
  metadata" per import; when they do, the attachment is flagged
  (`retainedImageMetadata`) and the UI notes it.
- If stripping fails, the app does **not** silently keep metadata invisibly — it
  stores the original but flags it so the state is visible.

## 6. Residual risks & recommendations

1. **Boundary fidelity.** The bundled GeoJSON is medium-resolution. A day whose
   only fixes are within a few km of the border can be misclassified. Mitigations
   already present: `nearBorder` flagging, precise-sampling escalation, per-day
   manual override, and stored raw samples. **Replace the polygon with TIGER/Line
   for audit use** (`scripts/fetch_ny_boundary.md`).
2. **Device passcode is the root of trust.** File protection and the Keychain
   accessibility class assume a device passcode is set. Encourage a strong
   passcode + Face/Touch ID; consider adding an in-app biometric gate (LocalAuthentication)
   before the dossier is viewable.
3. **Share-sheet destinations are out of our control.** Once the user exports to
   Mail/Files/AirDrop, protection is whatever that destination provides. The
   export screen states this.
4. **Jailbreak / physical compromise** is out of scope; AES-GCM + Keychain raise
   the bar but cannot defend a rooted device with the passcode known.
5. **Backups.** The SwiftData store follows normal backup rules (encrypted-backup
   recommended). Attachment ciphertext and the Keychain key are excluded from
   backup, so restored backups won't carry decryptable attachments to another
   device — by design.

## 7. Verification checklist

```bash
# No networking / third-party SDK
grep -rEn "URLSession|dataTask|Alamofire|Firebase|Amplitude|Sentry" DOONY/ ; echo "expect: no app-code matches"

# No coordinate logging outside DEBUG
grep -rn "print(" DOONY/            # expect: only the one #if DEBUG line

# File protection + keychain classes present
grep -rn "FileProtectionType\|kSecAttrAccessibleWhenUnlockedThisDeviceOnly\|AES.GCM" DOONY/
```
