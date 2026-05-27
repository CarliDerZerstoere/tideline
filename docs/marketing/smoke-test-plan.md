# Smoke Test Plan — Tideline v0.9.0 (pre-TestFlight)

**When to run**: after Xcode → Run installs v0.9.0 (build 2) on your
real iPhone, **before** clicking Archive.

**How long**: ~15 minutes if everything passes; longer if you hit a
blocker (which you'd want to know before tester invites go out).

**Setup**:
- Real iPhone (iOS 18.0+), connected via cable
- Xcode → select your iPhone as the run destination
- Xcode → Product → Run (⌘R) — build, install, launch
- Once installed, **disconnect the cable** for the rest of the smoke
  test. Some bugs only surface when the app isn't actively debugged
  (e.g. background-task lifecycle).
- Wipe before starting: long-press Tideline icon → Remove App → Delete
  App. Then re-install via Xcode Run for a clean cold launch.

**How to record failures**: screenshot to a dated folder
`~/Desktop/Tideline-smoke-2026-MM-DD/`. File names: `S{N}-{symptom}.png`
where N is the scenario number below. Add a one-line note in a
`notes.txt` in the same folder.

**Pass criterion**: every scenario passes. Any failure → fix in
source → repeat the entire smoke (not just the failed scenario).

---

## S1 — Cold launch, no Apple Account prompt (LOAD-BEARING)

This is the Session 7 lazy-init regression guard. If this fails, the
generous-free promise is broken.

**Steps**:
1. Force-quit Tideline (swipe up app switcher → flick away).
2. Wait 10 seconds.
3. Tap Tideline icon. Watch carefully.

**Pass**:
- App opens to onboarding (first install) or home (subsequent)
- **NO** system "Sign in to your Apple Account" dialog appears
- Time-to-first-content < 2 seconds

**Fail signals**: any Apple-Account dialog. Any "Sign in to App Store"
modal. Any spinner > 3s on first content.

---

## S2 — Onboarding flow (first install only)

**Steps**:
1. From the wipe state, launch the app.
2. Walk through onboarding: privacy screen → seed-day question → HK
   permission question → finish.
3. For seed-day: pick "An einem bestimmten Tag" → today.
4. For HK: tap "Erlauben". When the system permission sheet appears,
   tap "Erlauben" / "Alle einschalten".
5. Tap "Fertig" or whatever the last button says.

**Pass**:
- Each screen renders without text truncation
- Both DE strings show (verify the privacy bullet "Deine Zyklusdaten
  bleiben auf diesem Gerät" appears)
- After finish, you land on Mein Zyklus tab with the seed day visible

**Fail signals**: blank screen, infinite spinner, app crash, untranslated
"???" strings, English text where DE is expected.

---

## S3 — Mein Zyklus phase strip + today-tick

**Steps**:
1. Tap Mein Zyklus tab.
2. Observe the phase strip (the gradient bar with 29 dots).
3. Drag the thumb horizontally to a different day.
4. Release.
5. Drag the thumb back to today.

**Pass** (verifying #161):
- When dragging away from today, a thin vertical tick appears at
  today's position
- The tick disappears when the thumb sits on today
- The "Heute" mini-label (under the bar) toggles correctly
- No flicker, no z-order issue (tick should NOT overlap the thumb
  awkwardly)

**Fail signals**: tick stays visible when thumb is on today (would
duplicate the thumb center line). Tick never appears.

---

## S4 — Calendar navigation + range-select colour

**Steps**:
1. Tap Kalender tab.
2. Swipe between months.
3. Tap "Mehrere Tage" pill.
4. Tap day 5 in the current month → tap day 9.
5. Observe the fill colour.

**Pass** (verifying #160):
- Range fill is **teal** (#3E8890), not coral
- Range stroke is teal
- Menses days (coral) remain visibly distinct
- "Anwenden" button activates

**Fail signals**: range fills coral (regression to pre-#160). Range
days overlap menses days indistinguishably.

---

## S5 — Logging a day

**Steps**:
1. From the calendar, tap today.
2. LogDaySheet opens.
3. Pick a flow level (e.g. "Mittel").
4. Tap Save / Speichern.
5. Verify home reflects the change.

**Pass**:
- Sheet opens within 1 second
- Save persists (close + reopen → flow level is preserved)
- Home view shows the logged day (BloodDrop or similar marker)

**Fail signals**: sheet doesn't dismiss on save; reopening shows stale
state; crash on save.

---

## S6 — HealthKit roundtrip (read + write)

**Steps**:
1. Have at least one period day logged.
2. Mehr → "Daten in Apple Health speichern" → confirm.
3. Open the iOS Health app → Zyklusverfolgung → check if today's logged
   flow appears.
4. In the Health app, manually add a period day for *yesterday*.
5. Back to Tideline → Mehr → "Aus Apple Health importieren" → confirm.
6. Yesterday should now show as logged in Tideline.

**Pass**: both directions sync within 5 seconds of confirmation.

**Fail signals**: data missing in either direction; duplicate entries
created; HK permission missing for a type.

---

## S7 — Doctor PDF

**Steps**:
1. Mehr → "Bericht für meinen Frauenarzt-Termin" → confirm generation.
2. Wait for the in-app PDF preview to render.
3. Tap the share icon → confirm the share sheet opens.
4. Tap "Kopieren" or "Notizen" to test (not necessary to actually share).
5. Dismiss.

**Pass**: PDF preview renders cycle data (no blank pages); share sheet
works; date range is current.

**Fail signals**: blank PDF; crash during render; share sheet missing.

---

## S8 — App Lock

**Steps**:
1. Mehr → App-Sperre → Enable with Face ID (or Touch ID, or Passcode).
2. Force-quit Tideline.
3. Re-open Tideline.
4. Confirm biometric / passcode prompt appears.
5. Authenticate.

**Pass**: lock activates within 1 second of relaunch; correct biometric
icon shown; unlock returns you to where you left off.

**Fail signals**: app bypasses the lock; lock persists even after
correct auth; wrong biometric icon (e.g. Touch ID on a Face ID device).

---

## S9 — Notifications (if enabled)

**Steps**:
1. Mehr → Benachrichtigungen → enable master toggle.
2. When iOS prompts for notification permission, allow.
3. Enable a per-category toggle (e.g. late-period check-in).
4. *Optional*: change your phone clock forward to simulate the
   notification trigger time. Skip this if you don't want to mess with
   the clock.

**Pass**: permission dialog appears; toggle persists across app close;
no crashes when toggling.

**Fail signals**: toggle reverts on relaunch; crash when system permission
denied; notification fires immediately (should be scheduled, not instant).

---

## S10 — StoreKit (lazy init regression guard)

**Steps**:
1. Force-quit Tideline.
2. Cold launch.
3. Use the app normally for ~2 minutes — Mein Zyklus, Kalender, log a
   day, etc. **Do NOT** open the support sheet.
4. After 2 min: Mehr → "Tideline unterstützen". Watch carefully.

**Pass** (verifying Session 7 lazy init):
- During the first 2 minutes of normal use: **NO** Apple-Account prompt
- Only when you open the Unterstützen sheet does the SupportSheet
  appear with a price (or "Unterstützen" if product fetch failed)
- If you tap the Unterstützen button, only THEN is an Apple-Account
  prompt acceptable (Apple requires it for the purchase itself)

**Fail signals**: any Apple-Account dialog before step 4. Support sheet
fails to load at all.

---

## S11 — Timezone refresh (#110 regression guard)

**Steps**:
1. Note today's date as shown in Tideline (top of Mein Zyklus).
2. iOS Settings → General → Date & Time → toggle off "Set Automatically".
3. Change Time Zone to something far away (e.g. Pacific/Auckland).
4. Return to Tideline (don't relaunch — bring it back from background).
5. Observe the date shown.

**Pass**: the date in Tideline updates within 1–2 seconds of returning
to the app — reflects the new timezone's "today".

**Fail signals**: date stays on the old timezone's today until you
force-quit and relaunch.

**Cleanup**: re-enable "Set Automatically" so you don't accidentally
ship with a wrong timezone.

---

## S12 — Dynamic Type AX5 (#132 partial regression check)

**Steps**:
1. iOS Settings → Accessibility → Display & Text Size → Larger Text →
   enable "Larger Accessibility Sizes" → drag slider all the way right
   (AX5).
2. Return to Tideline.
3. Walk: Mein Zyklus → Kalender → Mehr → Tideline unterstützen.
4. Note any text that's truncated, overlapping, or cut off mid-word.

**Pass**: the 5 surfaces touched by #132 (CyclePhaseStrip phase labels,
summary text, MoreSettingsSheet rows, support row, support sheet) all
scale up readably. Some legacy fixed-size text elsewhere may still
truncate — that's documented as v1.1 (≈195 sites untouched in #132).

**Fail signals**: critical action buttons cut off; phase strip
unreadable; settings rows un-tappable.

**Cleanup**: drop Larger Text back to default.

---

## After the smoke

- **All 12 pass**: proceed to `testflight-checklist.md` step 3 (Archive).
- **Anything fails**: fix in source, rebuild via Xcode Run, repeat the
  full smoke. Yes — the *full* smoke. Don't trust that an unrelated fix
  didn't break something else.

Document any pass-with-caveats observations in a fresh post-launch tracker
entry so they're captured but don't block the cut.
