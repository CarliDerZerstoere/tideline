# App Store Connect Handoff Checklist — Tideline v0.9.0

**Audience**: the owner (you), working through App Store Connect in one
sitting. Estimated time: 2–3 hours including screenshot capture.

**Prerequisites**:
- Active Apple Developer Program membership
- Bundle ID `com.carliderzerstoere.tideline` confirmed available (or
  already registered to your team)
- This repo's `docs-public/` published to GitHub Pages and resolving
- Screenshots captured per `screenshot-shotlist.md`
- A Xcode-signed archive of the v0.9.0 build (Session 10 produces this)

Walk top-to-bottom; check items off as you go.

---

## 1. Repo housekeeping (done by Session 9 already)

- [x] `MARKETING_VERSION` bumped to `0.9.0` in `project.yml`
- [x] `CURRENT_PROJECT_VERSION` stays at `1` (Session 10 increments)
- [x] `PrivacyInfo.xcprivacy` in place
- [x] DE + EN .lproj contains InfoPlist + Localizable
- [x] App icon 1024×1024 in `Assets.xcassets/AppIcon.appiconset`

If you re-cloned the repo, run `xcodegen generate` once before the
Session 10 archive.

---

## 2. GitHub Pages publish

If not done yet:

1. Go to the Tideline repo on github.com
2. Settings → Pages
3. Source: **Deploy from a branch**
4. Branch: `main`, folder: `/docs-public`
5. Save
6. Wait 5–10 min. The URL appears at the top of the Pages settings.
7. Test in browser:
   - Landing page resolves: `https://carliderzerstoere.github.io/tideline/`
   - `…/privacy` resolves
   - `…/support` resolves

**If the URL is different from the assumed pattern**, update the three
URL references in `docs/marketing/appstore-listing-de.md` and
`appstore-listing-en.md` before pasting into ASC.

---

## 3. App Store Connect app record

If the record doesn't exist yet:

1. App Store Connect → Apps → "+" → New App
2. Platforms: iOS
3. Name: `Tideline — Dein Zyklus` (you can edit per locale later)
4. Primary Language: **German (Germany)**
5. Bundle ID: pick `com.carliderzerstoere.tideline` from the dropdown
   (it must be registered in your Developer Account → Identifiers first)
6. SKU: `tideline-ios-001`
7. User Access: Full Access
8. Create

The record is now created. You're on the App Information page.

---

## 4. App Information (paste from `appstore-listing-de.md`)

This page has fields per locale. Set DE first, then add EN.

### German (default locale)

Open `docs/marketing/appstore-listing-de.md` in a separate window. Paste:

- **Subtitle** → from the file's Subtitle block
- **Promotional Text** → from the Promotional text block
- **Description** → from the Description block (whole multi-line block)
- **Keywords** → from the Keywords block (one line, comma-separated)
- **Support URL** → from the URLs table
- **Marketing URL** → optional, paste from same table
- **Privacy Policy URL** → from same table

### English (add new localisation)

Click "+" on the localisations row at the top. Pick "English (U.S.)".
Paste the same five fields from `docs/marketing/appstore-listing-en.md`.

### Categories

- **Primary**: Health & Fitness
- **Secondary**: Lifestyle

### Content Rights

- **Does this app contain, show, or access third-party content?** No

### Age Rating

Click "Edit" next to "Age Rating". You're answering a questionnaire.

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Graphic Sexual Content and Nudity | None |
| **Medical/Treatment Information** | **Infrequent/Mild** |
| Gambling | None |
| Contests | None |
| Unrestricted Web Access | No |

**Medical/Treatment** justification: Tideline displays cycle-phase
descriptions and lifestyle summaries (e.g. "Zeit der Erneuerung"). These
are wellness content, not treatment advice — hence "Infrequent/Mild,"
not "Frequent/Intense" and not "None".

Net rating: **12+**.

### License Agreement

Use the standard Apple End User License Agreement (the default). Don't
write a custom EULA.

---

## 5. In-App Purchase

If not created yet:

1. App Store Connect → Apps → Tideline → Features → In-App Purchases →
   "+" → New Subscription? **NO**. Pick **Non-Consumable**.
2. Reference Name: `Tideline Support Contribution`
3. Product ID: `com.carliderzerstoere.tideline.support`
4. Price: select **Tier 5 (€4.99 / $4.99 / £4.99)**
5. Display Name + Description per locale:

| Locale | Display Name | Description |
|---|---|---|
| German (DE) | Tideline unterstützen | Ein einmaliger, freiwilliger Beitrag zur Tideline-Entwicklung. Schaltet keine zusätzlichen Funktionen frei — Tideline funktioniert für alle gleich. |
| English (US) | Support Tideline | A one-time, optional contribution to Tideline development. Unlocks no additional features — Tideline works the same for everyone. |

6. Review Information:
   - Review notes: `This is an optional, non-consumable contribution.
     It does NOT unlock any features. All Tideline features work for
     all users regardless of purchase.`
   - Review screenshot: the SupportSheet capture from
     `screenshot-shotlist.md` shot #7
7. Save

The IAP product status will read "Ready to Submit" once everything's
filled. The actual review happens together with the app build.

---

## 6. Pricing and Availability

- **Price**: Free (the app itself is free; only the optional IAP costs
  anything)
- **Pre-Orders**: No
- **Availability**: All countries and regions

  Rationale for worldwide availability: there's no reason to restrict.
  DE/EN listings reach the DACH primary market plus the broader
  German- and English-speaking world. Privacy-first apps benefit from
  global discovery. App content has no regulatory constraints beyond
  EU MDR (Article 2(1) wellness exemption — applies globally).

---

## 7. App Privacy (the "nutrition label")

App Store Connect → Apps → Tideline → App Privacy → "Get Started"

### Data Collection

**Do you or your third-party partners collect data from this app?**

**Answer: No.**

This is the cleanest possible nutrition label: every detail panel will
show "Data Not Collected." It directly matches `PrivacyInfo.xcprivacy`.

Apple will ask you to confirm. Submit.

### App Tracking Transparency

Tideline's `NSPrivacyTracking = false` in the privacy manifest plus
"No data collected" here means **App Tracking Transparency does NOT
apply**. There's no IDFA prompt to design, no opt-out flow needed.

---

## 8. Encryption Export Compliance

App Store Connect → Apps → Tideline → App Information → Encryption

| Question | Answer |
|---|---|
| Does your app use encryption? | Yes |
| Does your app qualify for any of the exemptions provided in Category 5, Part 2 of the U.S. Export Administration Regulations? | **Yes** |

Tideline uses only standard iOS cryptography (App Lock keychain, HTTPS
for StoreKit, TLS for HealthKit roundtrips). This qualifies for the
exemption under 5D002 / TSU.

Save the answer; you won't be asked again on subsequent versions unless
the encryption use changes.

---

## 9. App Review Information

When you submit the build for review (Session 10), Apple's reviewers
need context.

### Contact Information

- First name: your given name
- Last name: your family name
- Phone: a reachable number
- Email: niki.riedl@gmail.com

### Sign-in Required

- **Yes/No**: No (no account system)

### Demo Account

Skip — not applicable.

### Notes (paste this block verbatim)

```
Hello App Review Team,

Tideline is a wellness/lifestyle cycle tracker for iOS. Key points for review:

1. **Wellness/lifestyle, not medical**: Tideline does NOT claim
   contraceptive efficacy and does NOT claim conception efficacy. All
   user-facing copy avoids diagnostic language. The app is positioned
   under EU MDR Article 2(1) wellness exemption (Regulation 2017/745).

2. **No data collection**: NSPrivacyTracking is false. The privacy
   manifest declares zero collected data types. The app has no
   server-side component; all user data lives on-device in SwiftData.

3. **In-App Purchase is optional and unlocks nothing**: The
   "Tideline unterstützen" / "Support Tideline" non-consumable
   (com.carliderzerstoere.tideline.support, €4.99) is purely a
   developer-support payment. No feature is gated. All app features
   work for all users regardless of purchase. This is documented in
   the description copy ("Generously free").

4. **HealthKit usage**: Read + write of menstrual flow samples only.
   No other HealthKit data types accessed. User-controlled at any
   time via iOS Settings.

5. **First-launch behavior**: The app does NOT prompt for an Apple
   Account on launch. StoreKit is lazily initialised only when the
   user actively navigates to "Mehr" → "Tideline unterstützen". This
   is a deliberate design choice for the generous-free model.

If you have any questions, the support URL is on the listing.

Vielen Dank für die Prüfung.
```

---

## 10. Build upload (Session 10)

Session 10 covers the actual archive + upload. Quick preview:

1. Xcode → bump `CURRENT_PROJECT_VERSION` to `2` in `project.yml`
2. `xcodegen generate`
3. Xcode → Product → Archive
4. Organizer → Distribute App → App Store Connect → Upload
5. Wait for processing (15–60 min)
6. The build appears under App Store Connect → Apps → Tideline →
   TestFlight tab
7. Add it to the next-version's "Build" slot in the App Store tab

After upload, Session 10 also handles:
- TestFlight beta tester invites
- Internal testing group setup
- First smoke pass

---

## 11. Submission for Review (post-TestFlight, when ready)

Not Session 10; comes later after TestFlight feedback.

When ready:
1. App Store Connect → Apps → Tideline → App Store tab
2. Select version 0.9.0 (or whichever the public 1.0 will be)
3. Confirm all sections green (Description, Screenshots, Build,
   Pricing, App Privacy, Review Information)
4. Click "Submit for Review"
5. Wait 24–72 hours

If rejected, Apple sends a reason. Common Tideline-specific risk:
"Health app makes claims that require validation." Mitigation: every
piece of marketing copy avoids contraceptive/conception/diagnostic
framing. If a rejection cites copy, the fix is in
`appstore-listing-{de,en}.md` and is editable without resubmitting the
build.

---

## 12. After approval

- Add the App Store URL to the GitHub repo README
- Tweet / blog launch (out of scope here)
- Watch the first 48 hours of crash reports + email feedback
- Reply to any 1-star reviews within 24h (Apple weighs response rate)

---

## Reference files

- `appstore-listing-de.md` — German copy to paste
- `appstore-listing-en.md` — English copy to paste
- `screenshot-shotlist.md` — what to capture, how
- `/docs-public/privacy.md` + `/docs-public/support.md` — content of
  the hosted pages
- `/Tideline/Resources/PrivacyInfo.xcprivacy` — source of truth for
  the nutrition label answers
