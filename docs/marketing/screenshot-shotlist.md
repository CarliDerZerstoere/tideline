# Screenshot Shotlist — Tideline App Store Submission

**Goal**: 7 screenshots × 2 device sizes × 2 locales = 28 PNGs total.

Apple Store Connect accepts 3–10 screenshots per device size per
locale. We submit 7. More than 10 is rejected.

---

## Device sizes required (iOS 18 SDK rules)

| Apple display class | Simulator to use | Resolution | Mandatory? |
|---|---|---|---|
| 6.7" iPhone Pro Max | iPhone 16 Pro Max (or 15 Pro Max) | 1320 × 2868 | **Yes** |
| 6.1" iPhone | iPhone 16 (or 15) | 1206 × 2622 | **Yes** |
| 6.5" iPhone (legacy XS Max) | — | 1284 × 2778 | No — covered by 6.7 |
| 5.5" iPhone (legacy 8 Plus) | — | 1242 × 2208 | **Skip** — no longer required under iOS 18 SDK |

Apple auto-scales the 6.7" screenshots down to fill the 6.5" requirement.
Submitting only the two mandatory sizes is sufficient.

---

## Demo data to seed before capture

To make every screenshot show a coherent, typical user state — not the
dev's chaotic test data — wipe the simulator and seed this exact data
before capturing.

**Reset**: `iOS Simulator → Device → Erase All Content and Settings`
(or `xcrun simctl erase all` from terminal).

**Onboarding**: pick "An einem bestimmten Tag" → 5 days ago. Allow
HealthKit when prompted. Accept the default age band (25–34).

**Seed cycles via Loggen tab**:
- Cycle N-2: started day −58, period days −58 to −54 (5 days, medium flow)
- Cycle N-1: started day −29, period days −29 to −25 (5 days, medium flow)
- Current: started day −5, period days −5 to −1 (5 days, medium flow)
- Today (day 6 of current cycle): no entry yet

This yields:
- Cycle length sample: [29, 29] days → predictor stable at ~29
- mensesEnd: day 5 (matches default)
- "Today" lands in follicular phase
- Next predicted period: ~day 24, with ±2 day interval
- CyclePatternBadge: "Stabil" or similar (after 2 cycles in [25,32])

**Add for shot 4 (Mein Zyklus pattern detail)**: add light symptoms on
days −12 and −13 of current cycle ("PMS-Stimmung" + "Krämpfe") to
populate the Layer 2 pattern card.

**For shot 5 (Calendar range-select demo)**: enter selecting mode on
day +1 to +5 to display the new teal range fill from #160.

---

## Screen-by-screen capture instructions

### 1. Mein Zyklus tab — hero shot (Layer 1)

**What it shows**: the most-used surface, with the new today-tick from
#161, recognition copy, and CyclePatternBadge.

**Setup**:
- Open Tideline at the post-seed state.
- Tap Mein-Zyklus tab.
- Scroll to top.

**Caption suggestion**: "Dein Zyklus auf einen Blick"

**File names**:
- `Tideline-de-iPhone-6.7-01.png`
- `Tideline-de-iPhone-6.1-01.png`
- `Tideline-en-iPhone-6.7-01.png`
- `Tideline-en-iPhone-6.1-01.png`

### 2. Calendar — graduated prediction days + range select

**What it shows**: the calendar with the new teal range-select colour
(#160) plus the graduated-opacity prediction band (#164).

**Setup**:
- Tap Kalender tab.
- Tap "Mehrere Tage" pill.
- Tap day +5 of current cycle as first anchor, day +9 as second.
- Wait for visual to settle.

**Caption**: "Ehrliche Unsicherheit — keine Scheinpräzision"

**File names**:
- `Tideline-de-iPhone-6.7-02.png` …
- … (4 total per shot)

### 3. Doctor PDF preview

**What it shows**: the highly-differentiated "Bericht für deinen
Frauenarzt-Termin" feature.

**Setup**:
- Tap Mehr tab → "Bericht für meinen Frauenarzt-Termin" row.
- Wait for the in-app PDF preview to render.

**Caption**: "PDF für deinen Frauenarzt-Termin — auf dem Gerät erstellt"

### 4. Mehr tab — privacy disclosure

**What it shows**: the load-bearing differentiator vs Flo/Clue: the
"Deine Zyklusdaten bleiben auf diesem Gerät" pillar.

**Setup**:
- Tap Mehr tab.
- Scroll down to the "Privatsphäre" section.

**Caption**: "Deine Daten bleiben, wo sie hingehören"

### 5. Onboarding privacy screen

**What it shows**: the first-time privacy framing — what the user sees
on day one.

**Setup**:
- `Erase All Content and Settings` again, then re-open Tideline.
- Walk through onboarding to the "Privatsphäre" screen.
- Screenshot before tapping continue.

**Caption**: "Ohne Konto. Ohne Cloud. Ohne Werbung."

### 6. Empty hero state

**What it shows**: the honest "tracke deinen ersten Tag" framing — what
the user sees on a fresh install with no data yet.

**Setup**:
- After erase, complete onboarding but **skip the seed-day question**
  (pick "Ich starte heute frisch" or whatever skips initial seeding).
- Land on home tab with no cycles.
- Screenshot the empty hero state.

**Caption**: "Beginne, wann es dir passt — keine Streaks, kein Druck"

### 7. Tideline unterstützen sheet

**What it shows**: the generous-free framing, distinguishing from the
paywall-dominated category.

**Setup**:
- Re-seed data per the standard seed.
- Tap Mehr → "Tideline unterstützen" row.
- Wait for SupportSheet to load (loadProduct() runs).
- Screenshot.

**Caption**: "Alles kostenlos. Unterstützen ist optional."

---

## Localised captions

For each screenshot, App Store Connect accepts an optional caption per
locale. Captions are NOT overlaid on the image automatically — Apple
just shows them under the screenshot. Keep them short (~60 chars).

| # | DE Caption | EN Caption |
|---|---|---|
| 1 | Dein Zyklus auf einen Blick | Your cycle at a glance |
| 2 | Ehrliche Unsicherheit — keine Scheinpräzision | Honest uncertainty — no false precision |
| 3 | PDF für deinen Frauenarzt-Termin — auf dem Gerät erstellt | Doctor-visit PDF — generated on your device |
| 4 | Deine Daten bleiben, wo sie hingehören | Your data stays where it belongs |
| 5 | Ohne Konto. Ohne Cloud. Ohne Werbung. | No account. No cloud. No ads. |
| 6 | Beginne, wann es dir passt — keine Streaks, kein Druck | Start when you're ready — no streaks, no pressure |
| 7 | Alles kostenlos. Unterstützen ist optional. | Everything free. Supporting is optional. |

---

## How to capture in the simulator

1. Set the simulator to the target device (iPhone 16 Pro Max for the
   6.7" set, iPhone 16 for the 6.1" set).
2. Set the simulator language: `Settings → General → Language & Region →
   iPhone Language → Deutsch` (or English).
3. Set the appearance to Light Mode for the first pass; capture Dark Mode
   variants later if you want a second 7-shot set per locale.
4. Open Tideline, seed the data, navigate to the screen.
5. Capture: `⌘S` (Save Screen) — Simulator menu `File → Save Screen`.
   File lands on Desktop with default filename. Rename per the convention
   above.
6. Verify dimensions match the Apple-required resolution exactly (no
   scaling allowed). The simulator's screenshot dimensions match the
   device's screen resolution at the current scale — confirm in Finder
   → Get Info.

---

## Naming convention

`Tideline-{locale}-iPhone-{display}-{shot#}.png`

- `locale`: `de` or `en`
- `display`: `6.7` or `6.1`
- `shot#`: `01` through `07`

Examples:
- `Tideline-de-iPhone-6.7-01.png` — DE, large device, shot 1 (hero)
- `Tideline-en-iPhone-6.1-04.png` — EN, smaller device, shot 4 (privacy)

When uploading to App Store Connect, the order in which you upload
becomes the display order — upload `01` first, `07` last.

---

## What to NOT screenshot

- Anything with real personal cycle data
- Any screen showing the iOS Settings app, Privacy permissions dialog,
  or Apple Account sign-in prompts
- Status bar indicators that reveal account info (cellular operator
  name, etc.) — set the simulator to a generic state via
  `xcrun simctl status_bar` if needed
- Bug screens / error states (Apple may interpret as the app being
  unstable)
