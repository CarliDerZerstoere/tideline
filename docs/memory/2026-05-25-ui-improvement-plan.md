---
date: 2026-05-25
status: prioritized plan synthesized from 8 parallel UI/UX agent reviews
author: Claude (owner-requested UI/UX pass with emphasis on common-path use cases + competitive learning)
---

# Tideline UI/UX improvement plan — 2026-05-25

## Synthesis

Eight specialist agents reviewed Tideline's surfaces in parallel:
- ui-designer × 3 — home view, Mein Zyklus, Doctor PDF / HK sheets
- ux-researcher × 3 — logging+calendar, onboarding+settings, daily-driver common path
- competitive-analyst — Flo / Clue / Stardust / Apple Health / Natural Cycles / Euki / Drip
- frontend-developer — design-language consistency

This plan synthesizes all findings, **prioritized by daily-frequency impact on the common-path user** (not edge cases). It honors the owner's explicit framing: "Lay an emphasis on the simple usage cases" and "take what other apps do well and use it also in this app."

Every item has a file:line reference and a rough complexity tag (XS = under 1 hr, S = 1–3 hr, M = half day, L = full day or more).

---

## TIER 1 — Common-path daily friction (ship before TestFlight)

Every user encounters these every session. Highest ROI per LOC.

### 1.1 — Default LogDaySheet flow to `.medium` instead of `.light` 🔴 XS

**File:** `Tideline/Sources/Views/LogDaySheet.swift:77` + `TidelineHomeView.swift:379`

The default `initialFlow: FlowLevel = .light` is statistically wrong: most users open the sheet on the FIRST DAY of bleeding, when `.medium` is the modal observation. The current default forces one extra tap on every first-day log — the single highest-frequency action in the app.

**Change:** Default to `.medium`. Optionally only when `bleedingDays.isEmpty` for the current cycle (i.e. this is plausibly day 1), keep `.medium`; if a bleeding day was already logged today, keep `.light` (more typical for continuation).

### 1.2 — "Heute bereits erfasst" signal on hero/FAB 🔴 S

**Files:** `TidelineHero.swift:246-269` (centerText for `.active`) + `TidelineHomeView.swift:454-458` (FAB icon)

The home screen currently provides no obvious answer to "did I log today?". The user must read the small coral blood-drop under the phase-strip thumb. Clue and Flo both surface this prominently.

**Change:** Flip the "+" tab-bar FAB icon to `checkmark.circle` when today has a bleeding `DayEntry`. Optionally add a one-line "Heute erfasst" subhead in the hero.

### 1.3 — One-tap "Periode heute begonnen" fast path (Clue pattern) 🔴 S

**File:** New affordance on FAB long-press or contextual menu in `TidelineHomeView.swift`

Clue lets the user log today as a period day in a single tap from the home screen — the full LogDaySheet is reserved for "add detail." Tideline currently always opens the sheet.

**Change:** Add a `.contextMenu` (long-press) on the Loggen FAB with two items:
- "Periode heute begonnen" → calls `store.startPeriod(on: .now)` directly, dismisses with a brief haptic + toast.
- "Tag bearbeiten…" → opens the existing LogDaySheet.

First day of period is the single most important data point for the predictor; reducing friction here directly improves prediction accuracy.

### 1.4 — Echo next-period prediction in phase-strip summary 🔴 XS

**File:** `CyclePhaseStrip.swift:19-25` (add `predictionText: String?` param) + `:339-365` (render below `makeNextPhaseSentence()`)

The predicted date range lives only in `TidelineHero.swift:265` at 14pt. Once the user scrolls past the hero, the date is gone. The phase strip — the persistent data anchor that stays visible — never echoes it.

**Change:** Pass `model.predictionIntervalText` down from `TidelineHomeView` into the strip; render as a secondary subhead in the summary block.

### 1.5 — "Heute" jump button in calendar header 🟠 XS

**File:** `CalendarSheet.swift:300` (in `header` var)

After scrolling 6 months back to check "when did my period start in November?", the user has to repeatedly tap the chevron forward to return. Trivial fix.

**Change:** Show "Heute" pill in the calendar header when `displayedMonth != Date.now.startOfMonth`; tap → `displayedMonth = .now`.

### 1.6 — Symptoms & mood above the disclosure fold 🟠 M

**File:** `LogDaySheet.swift:175-249` (the `DisclosureGroup`)

Logging a headache or bad mood for yesterday currently costs ~6 taps (tab → calendar → date → sheet → disclosure → scroll → chip → save). The disclosure label "Weitere Details" with a `plus.circle.fill` icon reads as "add a new section" rather than "expand hidden fields."

**Change (lighter):** Rename the disclosure label to "Symptome & Stimmung (N)" with a live count badge — doubles as discoverability + save confirmation.

**Change (deeper):** Surface a compact symptom/mood/note icon row in the LogDaySheet header at the `.medium` detent. Three icons, tap → inline picker. Remove the disclosure entirely. (Deferred to post-TestFlight if scope is tight.)

### 1.7 — Gate delete button behind `snapshot != nil` 🟠 XS

**File:** `LogDaySheet.swift:252-281`

The destructive "Eintrag löschen" button is always visible — even when opening the sheet on a never-logged day. New users see a prominent red button before they've saved anything.

**Change:** `if snapshot != nil { deleteButton }` — show only in edit mode.

### 1.8 — "Periode beendet" disclosure in strip summary 🟠 XS

**File:** `CyclePhaseStrip.swift:360-365` (conditional sentence)

Tideline derives `mensesEnd` from consecutive bleeding days via the Belsey rule. The user has no idea this is happening. Day 6 with no log shows "Tag 6 — Menstruation" with no hint that the period may have ended.

**Change:** When today is 1–2 days past the last logged bleeding day, append a one-line note: "Kein Eintrag heute? Tideline schließt auf Ende der Blutung." Pure disclosure, no behavior change.

---

## TIER 2 — Competitive parity (learnings from Flo / Clue / Stardust / Apple Health / Natural Cycles)

### 2.1 — Make countdown the dominant typographic element above the fold (Flo) 🔴 M

**File:** `TidelineHero.swift:246-269`

Flo's home screen puts the "N days until period" countdown as the largest, boldest element on screen. Tideline's `predictionIntervalText` is the smallest text in the hero. DACH switchers from Flo are conditioned to this hierarchy; failing it makes Tideline feel like a downgrade.

**Change:** Promote `predictionIntervalText` (or a short countdown computed from it: "8 Tage") to one of the dominant lines. Keep "Tag 14" + phase name, but reshuffle so the answer to "when?" is at least as prominent as the answer to "where am I in the cycle?".

### 2.2 — Graduated-opacity uncertainty on predicted days (Natural Cycles) 🟠 M

**Promoted (2026-05-25)**: also tracked as **tracker #164** after the owner caught
the hero ↔ calendar inconsistency in v1.0 (hero "Beginnt etwa zwischen 11.–20.
Juni" vs calendar red rings June 16–20). Option A — rewording the hero —
shipped same-day as a stopgap; Option B (this item) is the principled fix.
After Option B lands, revert the hero wording to a simpler form because the
calendar will carry the uncertainty visually.

**File:** `CyclePhaseStrip.swift` predicted-window rendering + `CalendarSheet.swift` phase rings

Natural Cycles encodes confidence via gradient: darker = more certain, lighter = less certain. This directly implements Tideline's Pillar 3 ("honest uncertainty over false precision") in a way users read without a tooltip.

**Change:** In the predicted-window display (both phase strip and calendar), render the most-likely period days in the deepest coral; fade outward toward the credible-interval edges. As history accumulates and the posterior narrows, the gradient sharpens — users see the model learning.

### 2.3 — Wide-interval empty state, not a blank one (Apple Health / Clue) 🟠 S

**Files:** `TidelineHomeView.swift:237-253` (sparkline gate) + `OnboardingFlow.swift` lastPeriod step

After the single onboarding question, the population prior (μ=28.7) can immediately publish a (wide) prediction. The empty state should be "useful with low confidence," not "come back when you have data."

**Change:** Make the hero + phase strip render from population prior immediately post-onboarding. Replace the empty sparkline card with onboarding copy: "Dein Zyklusverlauf erscheint hier nach dem ersten abgeschlossenen Zyklus."

### 2.4 — Deferred iCloud sync opt-in, not at onboarding (Flo pattern adapted) 🟢 S

**File:** Future `docs/design/onboarding.md` + `OnboardingFlow.swift`

DACH users have the highest sensitivity to permission requests at first open (PMC11836014: 66% refusal rate). Show value first, ask for sync second. Tideline has no accounts so the analog is iCloud private DB sync — currently planned post-launch (#126); confirm default OFF + show prompt only after first complete cycle.

### 2.5 — Daily contextual sentence ("Daily Decode", Stardust) 🟢 L

**Files:** New `Services/DailyInsightGenerator.swift` + `TidelineHomeView.swift` (insert below sparkline) + `docs/design/ai-summaries.md` (new)

Tideline currently has no mechanism for the app to say anything beyond phase labels and predictions. A single on-device-generated sentence per day, derived from phase + logged data ("Du hast in dieser Lutealphase bisher keine Symptome geloggt — das entspricht deinem Muster aus den letzten 3 Zyklen"), creates daily value without a server. MDR-safe if it describes observed data, never predicts symptoms — the existing CLAUDE.md AI guardrails govern this.

**Note:** This is Phase 2A/B scope, not Phase 1. But it's the lowest-cost, highest-differentiation content layer available before a content team is hired.

### 2.6 — Clinical-naming toggle promoted in settings (Clue) 🟢 XS

**File:** `MoreSettingsSheet.swift` section ordering + `PhaseNamingSettingsSection.swift`

Clue's German-language rating is higher than Flo's, and clinical naming is a documented trust signal for DACH users coming from medical contexts. Currently `phaseNamingClinical_v2` defaults to true and the toggle is buried mid-list.

**Change:** Promote PhaseNamingSettingsSection higher in the More tab (per separate Onboarding+Settings review item 4.4). Consider whether the user-facing label should be tide-default (poetic for new users) with clinical opt-in (the audit research is mixed; document the choice).

### 2.7 — watchOS companion (Apple Health) 🟢 L

**File:** New `Tideline-Watch/` target + `docs/design/watchos-companion.md` (new)

Wrist logging captures the "I just noticed flow" moment before it's forgotten — the single highest-value reduction in daily friction for Watch-wearing users. Out of v1 scope, but should be the first Phase 2 feature given that HK is already Tier 1.

---

## TIER 3 — Design-language consolidation (one-time cleanup, prevents future drift)

The frontend-developer agent found:
- **20 distinct font sizes** in use (4-way collision at body level); 9 inline serif-italic calls bypass the existing `tidelineSerifHeadline` helper.
- **55 raw color literals** for 4 effective semantic colors (coral × 14, coral-shadow × 8, coral-dark × 7, dark-surface × 5).
- **Primary-button gradient+shadow recipe duplicated in 7 files.**
- **9 distinct corner radii** where 4 tokens would suffice.
- **30 shadow calls** with drifting opacity/radius across 3 effective tokens.

### 3.1 — `TidelineColors.swift` 🔴 S
Define `coral`, `coralDark`, `coralShadow`, `darkSurface`, `cream`. Migrate all 55 literals. The lone outlier blue (`OnboardingFlow.swift:354`) and mauve (`LogEventSheet.swift:192`) surface as decisions to make.

### 3.2 — `TidelinePrimaryButton` ButtonStyle 🔴 S
ButtonStyle conformance eliminates 7 duplicate gradient+shadow recipes. Makes the AppLockView capsule-vs-gradient inconsistency a visible decision point.

### 3.3 — Migrate 9 stragglers to `tidelineSerifHeadline` 🟠 XS
Zero design decisions; the helper already exists. Sites: `AppLockView:25`, `PrivacyOverlay:21`, `CalendarSheet:115/317/587`, `LogDaySheet:326/473`, `AgeBandSettingsSection:101`, `RangeFlowPickerSheet:30`.

### 3.4 — Corner-radius tokens 🟠 XS
Collapse 9 values to 4 named constants: `.card` = 14, `.chip` = 10, `.sheet` = 20, `.small` = 8. The `7`, `18`, `22`, `24` outliers are likely bugs.

### 3.5 — Display number font token 🟢 XS
`size: 56, weight: .light` appears 6× across 5 files (the large data readout). Name it `tidelineDisplayNumber`.

---

## TIER 4 — Surface-specific polish (highest impact within each surface)

### 4.1 — Home view (ui-designer findings)
- **Sun/moon position element missing** (`TidelineHero.swift`) — the design doc's core positional metaphor (cycle-day = sun x-position) was never built. M
- **Phase strip labels not proportionally aligned** to the gradient bands beneath (`CyclePhaseStrip.swift:79-93`) — actively misleading. S
- **Mist vertical position wrong** (`TidelineHero.swift:344`) — change `y: 0.45` → `0.60` so it sits at the sea horizon, not mid-sky. XS
- **Hero typeface clash** (`TidelineHero.swift:265`) — prediction line drops from serif to system; use the helper. XS
- **Cap `WaveLayer` frame rate** (`WaveLayer.swift:28`) — `minimumInterval: 1/30` for ProMotion. XS

### 4.2 — Logging + calendar (ux-researcher findings)
- **FlowLevelPicker selected state too subtle** (`FlowLevelPicker.swift:27-38`) — bump opacity + add 2pt border. XS
- **Range-select undiscoverable on empty calendar** (`CalendarSheet.swift:119`) — add inline empty-state hint card. S
- **No intermediate hint after first range tap** (`CalendarSheet.swift:226`) — "Zweites Datum wählen…". XS
- **MoodPicker labels at 9pt** (`MoodPicker.swift:34`) — raise to 11pt (Apple HIG minimum). XS
- **"Stimmung" label collision** (`SymptomGrid.swift:27`) — rename `.moodSwings.label` to "Stimmungsschwankungen". XS
- **Future-date copy implies blocked** (`LogDaySheet.swift:157`) — add "Der Eintrag wird trotzdem gespeichert." XS

### 4.3 — Mein Zyklus (ui-designer findings)
- **Add the delta number to trend sentence** (`PatternObservationGenerator.swift:106`) — the `delta: Int` is computed at :102 but never interpolated. One-line fix; directly improves the value of the only dynamic insight in the app. XS
- **Remove feature-explainer from `.mensesMid` template** (`RecognitionTemplates.swift:125`) — breaks the recognition frame. XS
- **Add `EditButton` to EventListSheet toolbar** (`EventListSheet.swift:78`) — swipe-to-delete is currently undiscoverable. XS
- **Reframe empty states as invitations** (`MyCycleSheet.swift:160`, `:47`) — Layer 3 currently invisible on first open. S
- **Group Layer 2 card as combined a11y element** (`MyCycleSheet.swift:145`) — VoiceOver currently steps through label + sentence + sparkline separately. XS
- **Fix "wegen manueller Pause" genitive** (`MyCycleSheet.swift:285`) — "wegen einer manuellen Pause". XS
- **Per-category leading icon for events** (`EventListSheet.swift:92`) — all events render identically; emotionally significant events (miscarriage) get same weight as mechanical (travel). S

### 4.4 — Onboarding + settings (ux-researcher findings)
- **Reorder onboarding** (`OnboardingFlow.swift:38-44`) — privacy → ageBand → lastPeriod → tracking → healthKit. Age-band currently breaks momentum; reorder so it contextualizes the lastPeriod question. S
- **Move HK offer OUT of onboarding** (`OnboardingFlow.swift:444-477`) — currently disrupts the privacy story's closing beat. Surface as a post-onboarding nudge card on the home screen if no period date provided. M
- **Reword Privacy DisclosureGroup** (`OnboardingFlow.swift:134-147`) — currently signals "fine print." Promote bullets that reinforce control (Deinstallieren), collapse only the iCloud-backup nuance. S
- **AgeBand icon mismatch** (`OnboardingFlow.swift:352`) — `person.badge.clock` reads as "attendance tracking." Use `figure.stand` or omit. XS
- **Reorder MoreSettingsSheet by frequency** (`MoreSettingsSheet.swift:18-32`) — Data → Notifications → PhaseNaming → CycleIrregularity → AgeBand → AppLock → Privacy. Currently set-and-forget items sit above frequently-used ones. XS
- **Rename "Zyklus-Besonderheiten"** (`CycleIrregularitySection.swift:33`) — single toggle under "Besonderheiten" reads as anticlimactic. Either rename to "Zyklusvariabilität" or fold into AgeBand section. XS
- **AgeBandPickerSheet "Übernehmen" disabled state** (`AgeBandSettingsSection.swift:166`) — looks broken when nothing changed. Make it a no-op dismiss instead. XS
- **PhaseNaming title shouldn't mutate** (`PhaseNamingSettingsSection.swift:39-43`) — use static "Phasennamen" + dynamic subtitle. XS

### 4.5 — HK sheets + Doctor PDF (ui-designer findings)
- **Loading vs importing spinners indistinguishable** (`HealthKitImportSheet.swift:105-114`/`:228-236`, `HealthKitExportSheet.swift:106-114`/`:245-253`) — use determinate progress for commit, or differently-tinted spinner. M
- **Conflict resolution at decisive moment** (`HealthKitImportSheet.swift:188-194`) — toggle controls entire cycle, can't choose "import non-conflicting days." Per-row sub-label explaining the skip. S
- **No retry path on permission error** (`HealthKitImportSheet.swift:273-308`, `HealthKitExportSheet.swift:291-328`) — add secondary "Erneut versuchen" button mirroring `DoctorPDFSheet:216`. XS
- **Doctor PDF SHA-256 plain language** (`DoctorPDFSheet.swift:108-112` + `:154-174`) — German gynecologist user doesn't know SHA-256. Replace with "Echtheitsstempel" + tooltip "Dieser Code beweist, dass der Bericht seit der Erstellung nicht verändert wurde." XS
- **PDF preview scale** (`DoctorPDFSheet.swift:290-298`) — change `let scale: CGFloat = 1.0` to `UIScreen.main.scale` (or `UITraitCollection.current.displayScale`) — blurry on 3x devices. XS
- **Export review state icons** (`HealthKitExportSheet.swift:153-175`) — three states (synced/empty/normal) all render as same serif heading. Add leading `checkmark.circle` / `info.circle` for state scan. XS

---

## TIER 5 — Differentiator preservation (DO NOT remove)

The competitive review explicitly flagged things Tideline does that competitors don't — these are the principal differentiators:

- **Probabilistic mist as visual design.** No competitor encodes prediction confidence into the visual metaphor itself. Flo/Clue show false-precision single dates. Tideline's widening/narrowing mist is architecturally unique. Don't trade it for familiarity.
- **No streaks, no shame mechanics.** CLAUDE.md Pillar 5; market research confirmed as unmet need. Don't import Flo's "logging streak" or "X days since last log" patterns.
- **Silence after disruption.** No competitor handles post-loss prediction silence deliberately. Don't borrow any pattern that creates a path around it.
- **On-device + no-account as architecture, not just a claim.** Don't borrow Flo's "save your progress" sync nudges or any cloud-adjacent UX patterns.

---

## Suggested execution order

**Wave A — pre-TestFlight blockers from TIER 1 + cheap TIER 4 polish:**
1.1 (default flow), 1.4 (echo prediction), 1.5 (Heute jump), 1.7 (delete gate), 1.8 (period-ended hint), 4.1 mist fix, 4.1 typeface, 4.1 WaveLayer fps cap, 4.2 future-date copy, 4.3 trend delta, 4.3 EditButton, 4.4 AgeBand icon, 4.4 settings reorder, 4.5 SHA-256 wording, 4.5 PDF preview scale.
Effort: ~5 hours total. Visible improvements to every common-path session.

**Wave B — TIER 1 medium fixes + Wave A loose ends:**
1.2 (Heute erfasst signal), 1.3 (one-tap fast path), 1.6 (symptoms above fold light version), 4.2 (range-select discoverability), 4.4 (onboarding reorder + privacy reword), 4.5 (HK sheets retry + state icons).
Effort: ~1 day.

**Wave C — TIER 3 design-language consolidation:**
3.1 (Colors), 3.2 (PrimaryButton style), 3.3 (typography migration), 3.4 (radius tokens), 3.5 (display token).
Effort: ~1 day. One-time cleanup; future-change tax reduction.

**Wave D — TIER 2 competitive parity (post-TestFlight):**
2.1 (countdown hierarchy), 2.2 (graduated opacity), 2.3 (wide-interval empty state).
2.4 / 2.5 / 2.7 are explicit roadmap items already (iCloud sync = #126; AI summaries = future; watchOS = Phase 2).

**Wave E — sun/moon element + bigger redesigns:**
4.1 sun/moon position. Effort: M-L depending on scope. The biggest single gap between design intent and shipped state.

---

## What this plan does NOT cover

- **Visual mockups / Figma alternatives.** The plan describes WHAT to change, not how to redesign from scratch.
- **Accessibility deep-dives.** TIER 4 includes the spot-fixes the agents flagged; broader WCAG work is tracked separately (#131 + the live FIXMEs in `LuminanceTests.swift`).
- **Internationalization beyond DE/EN.** Tracker item #134 covers DACH App Store assets; broader localization (French, Spanish, Italian for EU expansion) is future.
- **Performance benchmarks.** The home view perf work (#65, AmbientTideBackground tuning) is shipped; this review didn't re-test.
- **Watch / widget / Live Activity / Lock Screen widget** — TIER 2.7 calls out watchOS as Phase 2; widget and Live Activity work is post-watchOS.

---

## Cross-references

- Source agent reports: 8 background-task outputs in `/private/tmp/claude-501/-Users-nr/292763d6-4ded-4e58-a24b-6a1441907847/tasks/` (transient, not persisted in repo).
- Design intent: `docs/design/tideline-visual-language.md`.
- Product pillars: `CLAUDE.md`.
- Audit context this builds on: `docs/memory/2026-05-24-done-audit.md`.
