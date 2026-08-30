# App Store submission checklist — DOONY

**Distribution: public, paid, one-time purchase.** Family members get it free
via promo code or Family Sharing. Unlisted distribution was considered and
dropped — it required the same support URL, screenshots, description, privacy
policy and age rating as a public listing, so it bought nothing but
non-discoverability while adding a second Apple review that could be declined.

App Store Connect Apple ID: **6806615033** · Bundle ID: `com.doony.app` ·
Team: `24Q366W5BQ`

Companion file: [`APP_REVIEW_NOTES.md`](APP_REVIEW_NOTES.md) — paste into App
Review Information → Notes.

---

## 1. The two required URLs

Both are served from this repo by GitHub Pages (`main` branch, `/docs` folder):

| Field | URL |
|---|---|
| Privacy Policy URL | https://compudds-star.github.io/DOONY/ |
| Support URL | https://compudds-star.github.io/DOONY/support.html |

Sources are `docs/index.html` and `docs/support.html`; `docs/.nojekyll` makes
Pages serve them as-is. `docs/PRIVACY.md` is the policy text in Markdown.

To (re-)enable Pages: **Settings → Pages → Deploy from a branch → `main` /
`/docs`**, or

```bash
gh api -X POST repos/compudds-star/DOONY/pages \
  -f 'source[branch]=main' -f 'source[path]=/docs'
```

Pages serves from `main` — edits on a feature branch change nothing publicly
until merged.

Both go in App Store Connect under **App Information** (set per app, not per
build).

## 2. Paid app setup — start this first, it gates everything

A paid app cannot be sold until **Agreements, Tax, and Banking** is complete.
This is the longest-lead item here: bank verification and tax forms can take
days, and the app cannot go on sale without them, however ready the binary is.

**App Store Connect → Business** (or Agreements, Tax, and Banking):

1. **Sign the Paid Applications Agreement.** The free agreement you already have
   does not cover paid apps.
2. **Add a bank account** for payouts.
3. **Complete the tax forms** — a W-9 for a US developer.

Then **Pricing and Availability**:

- Set the price. Apple's price points are not exactly $5.00 — pick the tier
  nearest to it (typically $4.99).
- Consider limiting availability to the **United States** storefront. The app is
  specific to New York State law; selling it in 175 countries invites confused
  buyers and bad reviews for no gain.
- **Enable Family Sharing** if you want family members to get it from your own
  purchase rather than via codes.

Also worth doing: enroll in the **App Store Small Business Program**. It drops
Apple's commission from 30% to 15% for developers under $1M/year. Free, and
takes a few minutes.

## 3. Getting it to family for free

Two options; the second is less hassle if everyone is in one Family group.

**Promo codes** — App Store Connect → your app → Promo Codes. **100 per
version.** Each code is single-use and **must be redeemed within 4 weeks** of
being generated. That deadline is only on redemption: once redeemed the app is a
normal purchase, permanent, and updates forever. This is what finally solves the
TestFlight 90-day expiry problem that started this whole exercise.

One quirk: someone who installs via promo code cannot rate or review the app.

**Family Sharing** — enable it in Pricing and Availability, buy the app once
yourself, and up to five family members get it free with no codes and no expiry.
Simplest option if it fits.

## 4. App Privacy questionnaire → "Data Not Collected"

**App Store Connect → App Privacy → Data Collection → Edit.**

Answer *"Do you or your third-party partners collect any data from this app?"*
with **No**. That ends the questionnaire. Then **Publish**.

**Why "No" is correct even though the app handles location and documents.**
Apple defines "collect" as transmitting data off the device in a way that makes
it available to you or your partners beyond servicing the immediate request.
Data processed and stored **only on the device** is explicitly not collected.
DOONY has no networking code at all — verified: zero networking symbols in the
source, and no networking framework among its imports.

The user-initiated share-sheet export is also not collection: the user moves
their own data, and the developer never receives it.

⚠️ **This answer becomes false the moment the app gains analytics, crash
reporting, or any cloud sync.**

## 5. Age rating → 4+

**App Information → Age Rating → Edit.** Every content question is **None** /
**No**. Watch the non-obvious ones:

| Question | Answer | Why |
|---|---|---|
| Unrestricted web access | **No** | No `WKWebView` or `SFSafariViewController` in the app |
| In-app purchases | **No** | One-time purchase only |
| Advertising | **No** | None |
| User-generated content / messaging | **No** | Single-user, no sharing between users |
| Medical or treatment information | **No** | Tax record-keeping, not health |

Apple expanded the rating tiers in 2025 (adding 13+, 16+, 18+), so the
questionnaire may look unfamiliar. The answers above still resolve to **4+**.

## 6. Everything else

- **Screenshots** — 6.9" iPhone, 1320 × 2868, between 1 and 10. No iPad set is
  needed because the app ships iPhone-only. Capture from the iPhone 17 Pro Max
  simulator with `xcrun simctl io booted screenshot`, which writes at exactly
  that size. Use seeded demo data, never your own records — real screenshots
  would publish your actual day count and addresses to a public listing.
- **Description and keywords** — now they matter, since the app is
  discoverable. Write for someone searching "New York residency days" or
  "183 day rule", not for someone who already knows what DOONY is.
- **Export compliance** — already handled:
  `ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`, so no per-build
  prompt.
- **Privacy manifest** — not required. No required-reason APIs, no third-party
  SDKs.

## 7. The two review risks

- **Guideline 5.1.1 — background location.** The single most likely cause of a
  round trip. The justification in `APP_REVIEW_NOTES.md` is written for exactly
  this. Do not submit without pasting it.
- **Guideline 4.2 — minimum functionality.** Lower than it would have been for
  an obviously personal app, because DOONY is substantial and addresses a real
  market. Keep the framing on the general audience: people who keep a home in
  New York while claiming domicile elsewhere. Never describe it as built for
  your family — that invites the rejection.

## Order of operations

1. **Start Agreements, Tax, and Banking now.** It gates everything and is the
   slowest step.
2. Merge to `main` and enable Pages; confirm both URLs load.
3. Enter the URLs, age rating, and App Privacy answer in App Store Connect.
4. Set price, availability, and Family Sharing.
5. Capture screenshots from seeded demo data; write the description.
6. Attach the processed build and paste the App Review notes.
7. Submit for review.
8. On approval, generate promo codes (they expire 4 weeks after generation, so
   do this when you are ready to hand them out, not before).
