# TestFlight Cut Checklist — Tideline v0.9.0 (build 2)

**Audience**: you, doing the first TestFlight upload of Tideline.
**Estimated time**: 2 hours including smoke test.
**Outcome**: v0.9.0 build 2 installable by you + invited internal
testers via TestFlight on real iPhones.

Walk top-to-bottom.

---

## 1. Prerequisites (one-time, before this session)

- [ ] Active Apple Developer Program membership (€99/year)
- [ ] You're enrolled in App Store Connect as Account Holder or Admin
- [ ] An iPhone running iOS 18.0+ for the smoke test
- [ ] Xcode 26.4+ installed with iOS 26.4 platform available
- [ ] The Tideline GitHub repo cloned locally
- [ ] Session 9's `appstoreconnect-checklist.md` already walked
  (ASC app record exists, listing is filled, IAP product configured)
- [ ] Session 9's `docs-public/` published via GitHub Pages

If any are missing, do them first — the rest of this checklist
assumes them.

---

## 2. Code-level pre-flight

### 2.1 Fill `DEVELOPMENT_TEAM`

The audit shows `DEVELOPMENT_TEAM` is empty in `project.yml`. Without
it, `xcodebuild archive` fails immediately.

Get your team ID:
- App Store Connect → Users and Access → "Account Holder" column shows
  your team's name. Hover over → the URL contains the 10-char team ID.
- Or: developer.apple.com → Membership Details → Team ID.

Edit `/Users/nr/Developer/CycleApp/project.yml`:

```yaml
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEVELOPMENT_TEAM: "YOUR10CHARID"  # <-- paste here
    CODE_SIGN_STYLE: Automatic
```

Save. Then:

```sh
cd /Users/nr/Developer/CycleApp
xcodegen generate
```

### 2.2 Verify build settings

```sh
xcodebuild -showBuildSettings -project Tideline.xcodeproj -scheme Tideline | grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION|DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER"
```

Expected:
- `MARKETING_VERSION = 0.9.0`
- `CURRENT_PROJECT_VERSION = 2`
- `DEVELOPMENT_TEAM = YOUR10CHARID` (your value)
- `PRODUCT_BUNDLE_IDENTIFIER = com.carliderzerstoere.tideline`

### 2.3 Full suite green

```sh
xcodebuild test -project Tideline.xcodeproj -scheme Tideline \
  -destination 'platform=iOS Simulator,id=0421D4AD-D49B-47A1-9FC2-2EBC3D90E4F1'
```

Expected: `Test run with 520 tests in 52 suites passed`.

### 2.4 Release-config build

The default Run config is Debug. Archive uses Release — make sure it
compiles too (some Swift 6 strict-concurrency rules surface only in
Release optimisation):

```sh
xcodebuild build -project Tideline.xcodeproj -scheme Tideline \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=0421D4AD-D49B-47A1-9FC2-2EBC3D90E4F1'
```

Expected: `** BUILD SUCCEEDED **`.

---

## 3. Smoke on your iPhone via Xcode → Run

This is the most important step. Don't skip.

### 3.1 Install via Xcode Run

1. Connect your iPhone via cable. Trust the Mac if asked.
2. Xcode → top-bar destination picker → select your iPhone (not a
   simulator).
3. Xcode → Product → Run (⌘R). First install may prompt for the iOS
   developer trust (Settings → General → VPN & Device Management →
   trust the developer profile).
4. App launches on your iPhone.

If Xcode complains:
- **"No code signing identity"** → Xcode → Settings → Accounts → log
  in with your Apple ID → "Download Manual Profiles".
- **"Bundle ID not registered"** → developer.apple.com → Certificates
  → Identifiers → "+" → register `com.carliderzerstoere.tideline` as
  an App ID.
- **"Provisioning profile doesn't match"** → in Xcode signing tab,
  toggle "Automatically manage signing" off and on.

### 3.2 Walk the smoke plan

Open `docs/marketing/smoke-test-plan.md` and walk all 12 scenarios.
**Do not proceed until every scenario passes.**

If any fails:
1. Fix in source.
2. Rebuild via Xcode Run.
3. Repeat the *full* smoke (not just the failed scenario).

---

## 4. Archive

### 4.1 Switch destination to "Any iOS Device"

Xcode top-bar → destination picker → "Any iOS Device (arm64)".
Archives require this — they can't target a specific device.

### 4.2 Archive

Xcode → Product → Archive.

Wait ~3–8 min. Watch the bottom-right status indicator.

If archive fails:
- Read the error carefully — Xcode shows the exact build phase that
  failed.
- Common error: `Sign with a certificate signed by a Code Signing
  Authority` → re-trigger automatic signing.
- Common error: `Failed to resolve dependency` → close Xcode, delete
  `~/Library/Developer/Xcode/DerivedData`, re-open, retry.

### 4.3 Organizer opens automatically

When the archive succeeds, the Organizer window opens with the new
archive selected.

Verify:
- Application Loader version matches `Tideline 0.9.0 (2)`
- Date is today
- Type is "iOS App Archive"

---

## 5. Distribute to App Store Connect

### 5.1 Click Distribute App

In the Organizer with your archive selected, click **Distribute App**.

### 5.2 Distribution method

Pick **App Store Connect** → Next.

### 5.3 Destination

Pick **Upload** (not "Export"). Next.

### 5.4 Distribution options

- **Include bitcode**: irrelevant for iOS 18 (bitcode is deprecated);
  Xcode will skip this.
- **Upload your app's symbols**: leave **enabled**. Helps with crash
  report symbolication in ASC.
- **Manage Version and Build Number**: leave **off**. We manage these
  manually via `project.yml`.

Click Next.

### 5.5 Signing

Pick **Automatically manage signing**. Next.

Xcode generates a distribution provisioning profile + signs the archive.
~30 seconds.

### 5.6 Review

You'll see a summary:
- Bundle ID: `com.carliderzerstoere.tideline`
- Version: 0.9.0 (2)
- Distribution: App Store Connect
- Signing: Automatic with your Distribution certificate

Click **Upload**. Wait 2–5 min for the upload itself.

### 5.7 Confirmation

Xcode shows a success dialog with the link "View in App Store Connect."
Click it. Browser opens to ASC.

---

## 6. Wait for processing

ASC → Apps → Tideline → TestFlight tab.

Your build will appear under iOS Builds with status:
1. **Processing** (~15–60 min) — Apple is running automated checks
2. **Ready to Test** — green, ready for tester install

If after 1 hour it's still Processing: refresh the ASC page. If after
24 hours: contact Apple Developer Support — rare but happens.

**If status is "Missing Compliance"**:
- Click the build → click the warning.
- "Does your app use encryption?" → Yes.
- "Does it qualify for an exemption?" → Yes (per Session 9's answer).
- Save. Status flips to Ready to Test within minutes.

---

## 7. Add internal testers

### 7.1 Make sure they're ASC users

Each internal tester needs an Apple ID that's been invited to your
ASC team:
- ASC → Users and Access → "+" → enter Apple ID email → role: Developer
  (or Marketing, or any non-admin) → Save.
- The invitee receives an email, accepts, becomes an ASC user.

You can have up to 100 ASC users on the team. Internal testers must
already be ASC users.

### 7.2 Create / use an internal testing group

ASC → Apps → Tideline → TestFlight → Internal Testing → "+ Group" if
none exists. Default name "First Internal Beta" is fine.

### 7.3 Add testers to the group

In the group → Testers tab → "+ Testers" → pick from the ASC user list.

### 7.4 Assign the build

In the group → Builds tab → "+ Build" → pick `0.9.0 (2)`.

This sends a TestFlight invitation email to every tester in the group.

---

## 8. Tester install (each tester, including you)

Each tester:
1. Installs the **TestFlight** app from the App Store (one-time, if
   not already installed).
2. Opens the email invitation → taps "Accept Invitation". This deep-links
   into TestFlight.
3. In TestFlight, taps "Install" next to Tideline.
4. The Tideline TestFlight build appears on the home screen with an
   orange dot (indicating beta).

### 8.1 First post-TestFlight install on YOUR phone

Before sending the group invitation to others, **install on your own
phone via TestFlight** (not just Xcode Run — that's a different signing
identity). Confirm S1 of the smoke plan (cold launch, no Apple-Account
prompt) passes on the TestFlight build, not just the Xcode-Run build.

This is the version testers will actually install.

If anything regresses between Xcode-Run and TestFlight-install: re-build,
re-archive, re-upload, repeat. Don't ship a regression.

---

## 9. Tell testers what to do

After invitation, each tester sees a "What to Test" note. The content
lives in `docs/marketing/testflight-test-notes.md` — copy that into
ASC → TestFlight → Build → Test Information → What to Test.

For the personal outreach (email / Signal / WhatsApp message you send
*before* the formal invite), use `docs/marketing/tester-invite-template.md`.

---

## 10. First 48 hours

Follow `docs/marketing/post-launch-watch.md`. The short version: check
ASC Crashes tab and your email twice a day; reply within 24h to any
feedback; hotfix-trigger criteria are explicit.

---

## Common failure modes + fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Archive grayed out in Organizer | Destination is a simulator | Switch to "Any iOS Device" |
| "No identity found" | No distribution certificate | Xcode → Settings → Accounts → "Manage Certificates" → "+" → Apple Distribution |
| Upload stuck at 0% | Slow Apple ingestion | Wait 5 min. If still stuck, cancel + retry in 30 min |
| Build "Invalid Binary" email | Apple rejected during processing | Open the email; the rejection reason is explicit. Common: missing Privacy nutrition label (Session 9 fixes this) |
| TestFlight shows old version | Build not yet processed | Wait. Sometimes ASC's UI lags processing by ~10 min |
| Tester gets "This app is not available" | Tester not in any group | Verify in ASC → Testers tab |
| Tester install fails with "cannot connect" | iOS < 18.0 on tester device | Tester must upgrade iOS, or skip them for v0.9.0 |

---

## Done

After step 8.1 passes, the cut is live. Anyone in the internal group
can install. Anyone outside it cannot.

Next: stay on top of feedback per `post-launch-watch.md`. Adding
external testers is a separate flow (triggers Apple's Beta App
Review) and is deferred to v0.9.1 or later per D1.
