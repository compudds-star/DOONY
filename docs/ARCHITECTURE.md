# Architecture

## Stack
- **SwiftUI** (iOS 17+) for UI.
- **SwiftData** for persistence (`@Model` types, `ModelContainer`).
- **CoreLocation** for background location, geofencing, significant-change.
- **CryptoKit + Security (Keychain)** for attachment encryption.
- **ImageIO** for EXIF stripping. **PDFKit/UIKit** for PDF export.
- **Zero third-party dependencies.** Apple frameworks only.

## Data model (SwiftData)

Location:
- `LocationSample` — one raw fix (timestamp, lat/lon, accuracy, result, distance
  to border, source, `dayKey`). The audit trail.
- `DayClassification` — one row per America/New_York day (`dayKey` unique),
  derived from its samples; supports manual override + note.

Dossier (each with `notes`, date fields, and encrypted `attachments`):
- `Advisor`, `Vehicle`, `DriverLicense`, `VoterRegistration`, `RealProperty`,
  `FinancialTie`, `NearAndDearItem`, `Membership`, `EmploymentBusiness`,
  `MailingAddressRecord`, `ResidenceNight`.
- `Attachment` — metadata only; bytes live as an encrypted blob on disk.

## Modules

```
Location/
  GeoBoundary.swift    Loads bundled GeoJSON; ray-cast point-in-polygon
                       (MultiPolygon + holes); approx distance-to-border.
  DayClassifier.swift  America/New_York day keys; "any part of a day" rule.
  LocationManager.swift @MainActor CLLocationManagerDelegate. SLC baseline +
                       dynamic geofence + near-border escalation. Persists
                       samples and recomputes the day on each fix.

Security/
  KeychainKeyStore.swift  Generates/loads the AES key (WhenUnlockedThisDeviceOnly).
  AttachmentCrypto.swift  AES-GCM seal/open to NSFileProtectionComplete blobs.
  ExifStripper.swift      ImageIO re-encode dropping EXIF/GPS/IPTC/TIFF.
  AttachmentStore.swift   Import → (strip) → encrypt → Attachment; decrypt; delete.

Domicile/
  DomicileReadiness.swift Per-category completeness + red-flag ties to NY.

Export/
  CSVExporter.swift  Days, raw samples, yearly summary CSVs.
  PDFExporter.swift  Combined audit report (UIGraphicsPDFRenderer).

Views/
  RootTabView            Days · Domicile · Export
  DayTracking/           YearSummary, CalendarHeatmap, DayDetail
  Dossier/               DomicileReadiness + one list/form per record type
  Shared/                ShareSheet, AttachmentsSection, Masking, SecureNumberField
```

## Background flow

```
OS event (significant change / region exit / reboot relaunch)
        │
        ▼
LocationManager.process(fix)
        ├─ GeoBoundary.contains + distanceToBorderMeters   (on-device)
        ├─ classify sample: insideNY / outsideNY / nearBorder
        ├─ persist LocationSample  (dayKey = America/New_York)
        ├─ recomputeDay(dayKey)    → DayClassification
        ├─ updateDynamicGeofence(radius ≈ dist-to-border)
        └─ adjustEscalation(precise sampling on/off)
```

No timers, no foreground polling. All wakeups are OS-delivered, which is what
lets the app survive termination and reboot within the location background mode.

## Persistence & protection

- Store in Application Support, `cloudKitDatabase: .none`.
- Store files set to `NSFileProtectionCompleteUntilFirstUserAuthentication`
  (background-writable, encrypted at rest).
- Attachments: AES-GCM + `NSFileProtectionComplete`, directory excluded from backup.

## Testing

`DOONYTests/GeoBoundaryTests.swift` covers the audit-critical logic:
known NY cities classify inside, out-of-state cities classify outside, and the
"any part of a day" rule (unverified / NY-if-any-inside / nonNY-only-if-all-out /
near-border-counts-as-NY).
