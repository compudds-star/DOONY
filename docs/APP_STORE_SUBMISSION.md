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

**This is served from this repo via GitHub Pages:**

> ## https://compudds-star.github.io/DOONY/

`docs/index.html` is the page; `docs/.nojekyll` tells Pages to serve it as-is
rather than running it through Jekyll. `docs/PRIVACY.md` is the same text in
Markdown, kept alongside it as the reviewable source.

To (re-)enable Pages after a fresh clone or if it gets switched off:
**Settings → Pages → Source: Deploy from a branch → `main` / `/docs`**, or

```bash
gh api -X POST repos/compudds-star/DOONY/pages \
  -f 'source[branch]=main' -f 'source[path]=/docs'
```

Pages serves from `main`, so a change to the policy is only live once it is
merged there — editing it on a feature branch changes nothing publicly.

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

The form is at:

> ## https://developer.apple.com/contact/request/unlisted-app/

It is behind Apple ID sign-in — the link redirects to Apple's login before it
shows you anything, so sign in to your developer account first. Background
reading: https://developer.apple.com/support/unlisted-app-distribution/

⚠️ **Order matters. Submit the build to App Review BEFORE submitting this
request.** Apple declines unlisted requests for apps that have not been
submitted to App Review, or that are in a beta/prerelease state. The app must
either already be on the App Store or be submitted and awaiting review. You do
*not* need to release it publicly — being in review is enough, which is the
point, since a public release is the thing you are avoiding.

Apple also asks that you **say so in the Review Notes** of the submission itself.
`APP_REVIEW_NOTES.md` already carries a "WHY UNLISTED DISTRIBUTION" section, so
pasting it satisfies this.

Approval is a manual Apple review of the *request*, separate from App Review of
the build. Expect a few days.

Apple recommends apps distributed this way include some mechanism preventing
unauthorized use, in case the link spreads. For a two-person app holding only
on-device data that is arguably moot, but it is worth knowing they suggest it.

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

1. Publish the privacy policy (Pages, from `main` — see step 1).
2. Enter that URL, the age rating, and the App Privacy answer in App Store
   Connect.
3. Add screenshots and description; attach the processed build.
4. Paste the App Review notes, including the unlisted-distribution section.
5. **Submit the build for review.**
6. **Then** submit the unlisted-distribution request.

The order of 5 and 6 is not interchangeable: a request filed before the build is
in review gets declined.
