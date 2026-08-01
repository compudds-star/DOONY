# Legal Caveats — read this

**DOONY is a record-keeping aid, not legal advice, and not proof of domicile or
residency.** It was built to *organize* evidence and *corroborate* a day-count.
Nothing in it substitutes for professional tax/legal counsel or for the actual
legal filings.

## The two separate NY tests this app touches

1. **Statutory residence (the 183-day test).** You can be taxed as a NY resident
   if you (a) maintain a **permanent place of abode** in NY and (b) spend **more
   than 183 days** of the tax year in NY. NY counts **any part of a day**
   physically present in NY as a full NY day (with narrow exceptions, e.g. solely
   in transit, certain medical stays). DOONY's day-count targets this test.

2. **Domicile (totality of circumstances).** Domicile is your one true, permanent
   home — changed only by clear intent plus action. Auditors weigh many factors:
   home, business/employment ties, time spent, location of "near-and-dear"
   items, and family. DOONY's dossier organizes this qualitative evidence.

These are **independent**. You can lose the statutory-residence test even if your
domicile is clearly Florida — which is exactly why the day-count matters.

## What DOONY does **not** do

- It does **not** file, and is not a substitute for:
  - a **Declaration of Domicile** (recorded in the FL county),
  - a **homestead exemption** filing,
  - surrendering your **NY driver's license** and registering in FL,
  - **voter registration** in FL,
  - updating address on **passport, tax returns (IRS Form 8822), insurance, and
    estate documents**.
- It does **not** determine your legal residency or domicile. The classifications
  and "readiness" indicators are informational heuristics, not legal conclusions.

## GPS is corroborating evidence, not the whole case

Auditors triangulate day-presence from multiple independent trails:
**E-ZPass, credit-card and bank transaction locations, cell-phone records,
flight/travel itineraries, and swipe/badge data.** DOONY's GPS log is *one*
corroborating source. Keep and reconcile the others. Where GPS is missing
(phone off), the day is marked **unverified** — DOONY never guesses, and you
should back-fill from the other trails and the app's nightly-residence log.

## Accuracy limitations

- The bundled boundary polygon is medium-resolution; near-border days can be
  ambiguous. Use the `nearBorder` flags, manual day overrides, and replace the
  polygon with the authoritative TIGER/Line boundary for audit use.
- GPS itself has error (meters to tens of meters); the stored accuracy value and
  raw points let you and your advisor judge each ambiguous day.

## Bottom line

Use DOONY to **stay organized and honest**: track days conservatively, keep the
dossier current, and hand the export to your **CPA and attorney**, who make the
actual legal calls and complete the real filings.
