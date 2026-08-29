# App Store submission checklist — DOONY (unlisted)

App Store Connect Apple ID: **6806615033** · Bundle ID: `com.doony.app` ·
Team: `24Q366W5BQ`

Companion files: [`APP_REVIEW_NOTES.md`](APP_REVIEW_NOTES.md) (paste into App
Review Information → Notes) and [`PRIVACY.md`](PRIVACY.md) (the policy that
needs a public URL).

---

## 1. Privacy policy URL

Required for every app, including ones that collect nothing. It must be a
**public** URL that Apple can load without signing in.

The `DOONY` repo is private, so GitHub Pages can't serve it from there on a free
plan. Options, best first:

1. **A small public repo with Pages.** Create e.g. `doony-privacy`, drop
   `PRIVACY.md` in as `index.md`, enable Pages, and you get a stable
   `https://compudds-star.github.io/doony-privacy/`. Free, and the URL never
   changes as long as the repo exists.
2. **A public Gist.** Fastest. Use the Gist's own page URL, not the `raw` one —
   raw URLs carry a revision hash and change on every edit.
3. **A domain you already own**, if there is one.

Whichever you pick, fill in the contact address at the bottom of `PRIVACY.md`
first. That page is public; use an address you're willing to expose rather than
your primary personal one.

Enter the URL in App Store Connect under **App Information → Privacy Policy
URL** (it is set per app, not per build).

## 2. App Privacy questionnaire → "Data Not Collected"

**App Store Connect → your app → App Privacy → Data Collection → Edit.**

Answer the first question — *"Do you or your third-party partners collect any
data from this app?"* — with **No**. That is the whole questionnaire; answering
No ends it. Then **Publish**.

**Why "No" is correct even though the app handles location and documents.**
Apple defines "collect" as transmitting data off the device in a way that makes
it available to you or your partners beyond servicing the immediate request.
Data that is processed and stored **only on the device** is explicitly not
collected. DOONY has no networking code at all — verified: zero networking
symbols in the source, and no networking framework among its imports. So
location, dossier entries, and attachments are all handled but none are
collected.

The user-initiated share-sheet export is also not collection: you are moving
your own data yourself, and the developer never receives it.

⚠️ **This answer becomes false the moment the app gains analytics, crash
reporting, or any cloud sync.** Revisit it if that ever changes.

## 3. Age rating

**App Store Connect → App Information → Age Rating → Edit.**

Every content question is **None** / **No**: no violence, sexual content,
profanity, alcohol/tobacco/drugs, gambling, contests, horror, or mature themes.

Watch the non-obvious ones:

| Question | Answer | Why |
|---|---|---|
| Unrestricted web access | **No** | No `WKWebView` or `SFSafariViewController` anywhere in the app |
| In-app purchases | **No** | None |
| Advertising | **No** | None |
| User-generated content / messaging | **No** | Single-user, no sharing between users |
| Medical or treatment information | **No** | Tax record-keeping, not health |
| Gambling or contests | **No** | — |

Expected result: **4+**.

Note that Apple expanded the rating tiers in 2025 (adding 13+, 16+, 18+), so the
questionnaire may look unfamiliar if you last did this a while ago. The answers
above are unaffected — everything still resolves to 4+.

## 4. Unlisted distribution request

Submit at **developer.apple.com → Support → Request Unlisted App Distribution**.
The app must be complete and ready for review; you do not need to release it
publicly first — and you should not, since a public release is the thing you are
avoiding.

Approval is a manual Apple review of the *request*, separate from the normal App
Review of the build. Expect it to take a few days.

Have ready: the app name, the Apple ID above, your contact details, and a
justification. Draft justification:

> DOONY is a personal record-keeping app built for a single household. Using
> on-device background location, it tracks whether each calendar day was spent
> inside or outside New York State — the day-count evidence a New York State
> tax-residency audit turns on — and organizes the supporting domicile
> documentation alongside it.
>
> The app is specific to one U.S. state's residency test and is shaped around
> one family's circumstances. It has no value to a general App Store audience,
> and we do not want it discoverable through search or browse. Unlisted
> distribution matches its actual audience: a link shared with the two people
> who use it and their accountant.
>
> The app collects no data, makes no network requests, and contains no
> third-party SDKs. All records remain on the device.

Adapt the wording to whatever fields the form actually presents, and change "we"
to "I" if you prefer — see the same note in `APP_REVIEW_NOTES.md`.

## 5. Everything else the submission needs

- **Screenshots** — required even for unlisted. 6.7" iPhone at minimum.
- **Description, keywords, support URL** — keywords matter little when the app
  is not searchable, but the fields are still required.
- **Export compliance** — already handled in the binary:
  `ITSAppUsesNonExemptEncryption` is `false` in `Info.plist`, so no per-build
  prompt.
- **Privacy manifest** — not required. The app uses no required-reason APIs and
  bundles no third-party SDKs. Nothing to add.
- **App Review notes** — paste `APP_REVIEW_NOTES.md`; the Always-location
  justification there is the part most likely to decide the review.

## Order of operations

1. Fill in the contact address in `PRIVACY.md` and publish it somewhere public.
2. Enter that URL, the age rating, and the App Privacy answer in App Store
   Connect.
3. Add screenshots and description; attach the processed build.
4. Paste the App Review notes.
5. Submit the unlisted-distribution request.
6. Submit the build for review.

Steps 5 and 6 are independent reviews and can run concurrently.
