# Tideline — App UI Architecture and Information Hierarchy

**Status:** Living design doc. Supersedes ad-hoc UI decisions scattered across other design docs.
**Author of current version:** 2026-05-21
**Grounded in:** `docs/research/2026-05-21-market-research-synthesis.md`, `docs/research/2026-05-21-mein-zyklus-tab-research.md` (fact-checked), `CLAUDE.md` product pillars, `tideline-visual-language.md` (visual identity).

This document defines what each surface of the app exists to do, what content belongs where, and what does *not* belong on each surface. It is the answer to "why does this screen exist" for every screen in the app.

---

## Part 1 — Design principles (binding)

These are the rules that override taste arguments. They come from CLAUDE.md pillars + post-fact-check research findings.

### P1. Honest uncertainty over false precision
Every prediction must show its uncertainty range. A single date is never the right answer — even when the user wants one. The strongest review-complaint pattern across all 15 apps in our App Store analysis was *"the predicted date was wrong and the app acted certain."* (Source: today's competitive screenshot analysis + Frontiers 2023 design critique.)

### P2. Recognition framing over diagnostic framing
Insight copy says *"Wenn du dich in den letzten Tagen müder gefühlt hast — das ist typisch in der späten Lutealphase"* (recognition + validation). Not *"Du bist in der Lutealphase, erwarte niedrige Energie"* (instruction). The former generates the "now I understand why" emotional payload that drives viral content (Pfender 2025); the latter reads as horoscope text and is the most-abandoned surface across mainstream apps.

### P3. Privacy is structural, not decorative
For DACH users (load-bearing for our market positioning), privacy is a trust prerequisite, not a feature. 15% vs. 43% trust gap between tech companies and research institutions (Rietz 2025, n=1,004 representative German sample). The app must make its privacy architecture visible — App Store screenshot 1 or 2; in-app reminders that data stays on-device; doctor PDF export framed as "your data, your choice, your device."

### P4. Forward-looking content is the price of entry; retrospective recognition is the differentiator
~62-85% of cycle-app users open the app for prediction (Lee et al. 2024, n=431 app users). A cycle app that doesn't lead with prediction loses to Flo/Clue immediately. But every competitor occupies prediction; the unoccupied territory is *retrospective recognition* — closing the loop on the symptoms the user already felt. This is where the Mein Zyklus tab earns its slot.

### P5. No engagement manipulation
No streaks, no badges, no daily-login rewards, no anxiety-triggering notifications. These are CLAUDE.md hard rules backed by published ethics research (PMC 2021 gamification ethics paper documenting surveillance anxiety + feelings of defeat) and review-volume data (DACH App Store reviews consistently cite "nervige Benachrichtigungen" as a top complaint).

### P6. Minimum viable logging
Every additional input field is an abandonment risk. Symptom apps offering 17-200+ options exhibit a consistent pattern: heavy week-1 logging, collapse to "period start + pain only" by week 4, then attrition. The logging surface should ask for the minimum that produces useful pattern detection. Power users opt in to more via disclosures, never as defaults.

### P7. No medical-device drift
Wellness-category app. No diagnostic claims. No personalised clinical interpretation. *"Many people consult a doctor at this point"* is fine. *"You should see a doctor"* is not. This is regulatory, not aesthetic.

---

## Part 2 — Information architecture

### Tab bar (4 slots, post-D1)

```
| Mein Zyklus | Kalender | + Loggen | Mehr |
```

Statistik tab dropped on 2026-05-22 per roadmap decision D1 — the Mein Zyklus 3-layer redesign (NEW-A) absorbs its retrospective job. The 5th slot can be re-introduced post-launch as the HealthKit-derived charts surface (Option C from §3.5 below) if empirical demand emerges after #71 ships.

### The home view (no tab; landed-on by default)

The user lands here on cold launch and on app return. It is **not** a tab — it is the root view that hosts the tab bar at the bottom. Its job is **forward-looking + at-a-glance**, the highest-frequency surface in the app.

---

## Part 3 — Per-surface specification

### 3.1 Home view (root, forward-looking)

**Purpose:** Answer "where am I in my cycle right now, and what's coming?" in 2 seconds.

**Primary content (existing, shipped):**
- Atmospheric hero with phase-colored sky + tide animation. Phase name + day count + interval text.
- Phase strip card showing current phase + approaching-period mist when not late.
- Tide sparkline of past cycle lengths.
- Late milestone card when in late mode (post-#73).

**Content additions / changes:**
- *(no significant changes needed — this surface already implements P1, P4 correctly)*

**What NOT to put here:**
- Insight cards beyond the interval text — those belong on Mein Zyklus.
- Long symptom logs — that's Loggen's job.
- Pattern observations across cycles — that's Mein Zyklus.
- Doctor PDF CTA — that's Mein Zyklus.

**States to handle (all shipped):**
- `empty` — never logged
- `active` — within expected window
- `late` — past expected, with milestone card
- `paused` — Category B event active
- `retired` — Category A event active

---

### 3.2 Tab: Mein Zyklus (the "Now I understand why" surface)

**Purpose:** Close the loop on the symptoms and rhythms the user already lived through. Generate the "this makes sense now" moment that converts curious users into long-term users.

**Currently:** event list (just shipped in #89). The user correctly identified this as wasted space — it's data the user typed back at them, not insight.

**Replace with three layers:**

#### Layer 1 — Today's recognition (always visible, first card)

Single sentence + soft visual frame. Recognition-framed, never diagnostic.

Example copy patterns:
- *"Wenn du dich heute fitter gefühlt hast — du bist in der Ovulationsphase, das ist typisch."*
- *"Bemerkst du gerade vermehrte Reizbarkeit oder Müdigkeit? Du bist in der späten Lutealphase. Bei vielen klingt das mit dem Periodenstart ab."*
- *"Tag 3 deiner Periode. Bei den meisten Menschen ist die Energie heute noch niedrig — das pendelt sich in den nächsten Tagen ein."*

**Rules:**
- Pulls from a German-language template library, not AI-generated in v1.
- Refreshes when phase changes or the user logs a new symptom. Not on every refresh.
- Includes one *user-data-specific* element where possible (their last cycle's pattern, their typical phase length). Generic phase text alone fails the credibility check.
- Never says "you should." Always says "this is typical" or "many people experience."

#### Layer 2 — One pattern observation (refreshes on meaningful trigger)

Single sentence + small inline chart (sparkline or trend arrow). Anchored in the data-storytelling evidence (annotated chart + sentence outperforms either alone, arxiv 2402.12634 — 0.889 vs 0.667 comprehension).

Example copy + chart pairs:
- *"Deine Lutealphase war zuletzt konstant bei 13 Tagen."* + 6-cycle dot trend
- *"Deine Zyklen wurden in den letzten 3 Monaten leicht länger."* + 6-cycle line
- *"Diesen Zyklus hattest du 4 Bluttage — entspricht deinem Durchschnitt."* + small dot
- *"Du loggst seit 8 Wochen Migräne — der erste Cluster zeigt sich Tag -3 bis -1 vor der Periode."* + heatmap

**Rules:**
- Only show when there is actually a pattern to show. If there isn't, show nothing or a single low-volume "Noch zu wenig Daten" line.
- Refreshes when a new cycle closes or a new pattern emerges. Stale insights = trust loss.
- The chart is the evidence; the sentence is the headline. Both, not either.

#### Layer 3 — Collapsed retrospection (tap-to-expand)

The phase-band timeline + cycle history. Serves the 54.5% of users who value record-keeping (Lee et al. 2024) without dominating the tab for the 62.3% who came for forward-looking content.

Format:
```
─── Verlauf (letzte 6 Zyklen) ───────────────
[chevron] Mai      ▓▓▓▓░░░○░░░░░░░░░░░░░  31 T
[chevron] Apr      ▓▓▓▓▓░░○░░░░░░░░░░░░  29 T
[chevron] Mär      ▓▓▓░░░░○░░░░░░░░░░░  28 T
[chevron] Feb      ▓▓▓▓░░░○░░░░░░░░░░░  30 T
```

Tap a row → that cycle's detail: bleeding days, logged symptoms, events that fell in that cycle.

#### CTAs at the bottom of the tab

1. **"Für meinen Frauenarzt-Termin"** — opens task #46 (Doctor-PDF export). The market research established this as unoccupied territory across all 15 competitor apps; the App Store competitive pass confirmed zero apps lead with it. **Promote task #46 from P2 to P0 in tracker.**

2. **"Ereignisse anzeigen (N)"** — opens the event list (current #89 implementation, moved from primary to secondary). Includes future add-event flow from #75 once it lands.

**What NOT to put on Mein Zyklus:**
- Phase explainer content read once and never returned to ("In the luteal phase your progesterone rises…") — research shows this is the most-abandoned surface across competitors. Move to onboarding or a "Was passiert gerade?" tap-to-expand on Layer 1.
- Generic wellness tips ("drink more water") — universally cited as the most-useless surface.
- AI-generated text in v1 — templates only. Layer AI later if templates feel robotic.
- Streaks, badges, gamification (P5).
- Predictions with false precision (P1; predictions live on the home view with intervals).

**States:**
- `cold` — no logged cycles → friendly empty state pointing to Loggen tab
- `active` — three-layer view as designed
- `paused` — Layer 1 says *"Deine Vorhersage ist pausiert. Hier siehst du wieder Statistiken, sobald dein Zyklus zurückkehrt."* Layer 3 retrospection still shown.
- `retired` — Layer 1 acknowledges retirement; Layer 3 retrospection still shown.

---

### 3.3 Tab: Kalender (month-grid retrospection)

**Purpose:** Look up or edit a specific day. Browse month at a glance.

**Currently shipped, works well.** No major changes needed.

**Minor improvements queued in tracker:**
- #79 Calendar range-select for bulk backfill
- #106 shiftMonth uses stale averageLength
- #110 Timezone display drift after travel

**What NOT to put here:**
- Insights, summary statistics, doctor PDF CTA — those are Mein Zyklus.
- Phase explainer cards — onboarding.

---

### 3.4 Center tab: + Loggen (logging FAB)

**Purpose:** Fastest possible path to "I had bleeding today" or "I logged a symptom."

**Currently shipped.** Recent fixes (#118 delete bugs, notes field theming, focus-to-detent) brought this to a good state.

**Key principles for future changes:**
- P6 binding — every new optional field is an abandonment risk. New symptom types must opt-in via disclosure, never default.
- The "Weitere Details" disclosure pattern is correct. Don't move logging fields above the disclosure unless they reach the >80% engagement threshold.
- Auto-scroll to focused fields (just shipped) — keep this pattern for any future text input.

**Open: task #80 LogDaySheet first-entry contextual hint** — provide a friendly hint on the user's very first log (eg. *"Du loggst gerade deine erste Periode. Tideline lernt deinen Rhythmus in den nächsten Zyklen kennen — die ersten Schätzungen werden grob sein."*).

---

### 3.5 Tab: Statistik — **RESOLVED 2026-05-22 (D1: Option A — dropped for v1)**

Originally an open architectural decision; resolved by roadmap §D1 in favour of Option A. Statistik tab dropped; tab bar is now 4 slots (Mein Zyklus / Kalender / Loggen / Mehr). The reasoning + the deferred options B and C below are preserved for future revisit.

**Problem:** Mein Zyklus tab (redesigned per Layer 1/2/3 above) absorbs most of what "Statistik" would have been. With both tabs present, we'd have two competing retrospective surfaces.

**Three options:**

**A. Drop the Statistik tab entirely** (4-tab layout: Mein Zyklus / Kalender / Loggen / Mehr). Cleanest. Tab bar feels less placeholder-heavy. Matches the smallness of the user data we have for any single user — heavy stats aren't useful at 6 cycles.

**B. Repurpose Statistik as the power-user numerical view.** Mein Zyklus = qualitative recognition + insight (mass audience). Statistik = numerical drill-down (raw cycle lengths, BBT charts from HealthKit, hormone test imports if/when integrated, mean/SD per phase). Hidden behind a Settings toggle ("Erweiterte Statistik aktivieren") so it doesn't appear for users who don't want it. Honest about who it's for.

**C. Keep Statistik as the placeholder for HealthKit-derived charts** (HRV + RHR + wrist temperature trends across phases — task #71-adjacent). Job: "what your wearables noticed about your cycle." This earns the slot IF and only IF HealthKit integration ships first.

**Recommendation: A for now, defer B/C until there's empirical evidence one is needed.** A 4-tab bar is materially cleaner and signals product confidence. The 5th tab can be reintroduced if a clear use case emerges (most likely C, after #71).

This decision should be made before any code touches the Mein Zyklus tab redesign.

---

### 3.6 Tab: Mehr (settings + privacy + about)

**Purpose:** Configuration + privacy controls + "about" surfaces.

**Currently shipped:**
- App-lock toggle (task #87)
- PCOS / "Meine Zyklen sind unregelmäßig" toggle (task #77)

**Additions justified by research:**

1. **Privacy disclosure section** — small card stating, in plain German: *"Deine Daten verlassen dein Gerät nie. Keine Cloud, kein Account, keine Tracker."* Plus a link to a one-page technical whitepaper PDF (markdown is enough for v1). Backed by Rietz 2025 evidence that DACH users explicitly seek this signal.

2. **Data export section** (separate from the Mein Zyklus doctor PDF):
   - Export full data as JSON / CSV (task implicit, not yet tracked)
   - Erase all data (with confirmation)

3. **"Über Tideline" section** — short, honest *Why we built this*. Surfaces the "made in Europe, GDPR by architecture, no advertising business model" positioning. **DACH-relevant per the research.**

4. **(Future) Settings for irregular-cycle declaration variations** — perimenopause toggle, hypothalamic amenorrhea toggle, etc. Currently the irregularity toggle is single binary.

**What NOT to put here:**
- Engagement preferences for streaks/badges (we don't have any).
- Notification toggles for features that don't exist yet — show as they ship.

---

## Part 4 — Cross-cutting flows

### 4.1 First-launch onboarding (task #76 pending)

The single most consequential surface. Per the UX retention research, users who fail to get a meaningful first impression are the highest lapsing risk.

**Recommended flow (3 screens):**

1. **Privacy disclosure** — large type. *"Deine Zyklusdaten bleiben auf deinem iPhone. Keine Cloud, keine Tracker, kein Account."* + a small "Mehr dazu" link.
2. **Single question modal** — *"Wann hat deine letzte Periode begonnen?"* with three answers: a date picker, *"Vor kurzem"* (skip, log forward only), *"Weiß ich nicht genau"* (skip with explicit "we'll learn as you go").
3. **Optional: "Was möchtest du tracken?"** — list with toggles, off by default: *Periode + Tage*, *Stimmung*, *Symptome*, *Notizen*. Allow opt-in or skip entirely. Defaults to just Periode + Tage.

**No** account creation. **No** "premium upsell." **No** Apple Intelligence-required content. **No** social syncing.

This is task #76. Should ship before the Mein Zyklus tab redesign because the onboarding's data-quality determines what Mein Zyklus has to work with.

### 4.2 Late mode (currently shipped via tasks #72/#73)

Cross-references: `late-and-missed-periods.md`, `late-mode-implementation.md`.

Flow already implemented. The only architectural addition this UI plan suggests: the late milestone card might link to the Mein Zyklus tab for additional context (*"Mehr über diese Phase anzeigen"*), but not in a way that feels like a hard sell.

### 4.3 Paused mode (Category B events)

When the predictor pauses (breastfeeding, HBC, HA):
- Home view: hero shows *"Pausiert — Stillzeit"* or similar. No phase strip. No predictions.
- Mein Zyklus: Layer 1 acknowledges pause; Layer 3 retrospection still shown.
- Calendar: still shows historical cycle data; future days show no phase coloring.

### 4.4 Recovery / resume (task #74 in progress)

When a paused user logs bleeding again, surface a one-time Resume sheet (per task #74 design). Sheet copy: *"Willkommen zurück. Es sieht so aus, als wäre dein Zyklus wieder da. Möchtest du die Vorhersage neu starten?"* Two options: *"Ja, neu lernen"* (fires `.resumeAfterPause` event) / *"Später"* (dismissed flag persisted via @AppStorage).

### 4.5 Loss-aware silence (4-week post-loss notification suppression)

CLAUDE.md hard rule: *"Never send a notification about cycle predictions within 4 weeks of a logged loss."* When a Category C `.miscarriageEarly/.miscarriageLate/.medicalAbortion/.surgicalAbortion` event is logged:
- All cycle-prediction notifications suppressed for 28 days.
- Home view shows softer copy. Late milestone cards suppressed.
- The Resume sheet from task #74 does NOT auto-surface — user must manually re-enable.

Not currently implemented as a system; needs a future task tracked. **Recommend adding to roadmap as P1.**

---

## Part 5 — Microcopy direction (German recognition framing)

A vocabulary library for designers + writers. Templates only; no AI generation in v1.

### Recognition headlines (Layer 1)
- *"Wenn du heute…"* / *"Wenn du in den letzten Tagen…"*
- *"Bemerkst du gerade…"*
- *"Bei vielen klingt das…"*
- *"Du bist in der [X]-Phase — das ist typisch."*

### Pattern observations (Layer 2)
- *"In den letzten 3 Zyklen war [X]…"*
- *"Dein Durchschnitt liegt bei [X] Tagen."*
- *"Diesen Zyklus war [X] etwas länger / kürzer als sonst."*
- *"Wir sehen ein Muster bei [Symptom]: …"*

### Late-mode milestone copy
*(Already shipped, see late-mode-implementation.md. Lifted verbatim from EU-MDR-reviewed doc — DO NOT paraphrase.)*

### Privacy disclosure
- *"Deine Daten verlassen dein Gerät nie."*
- *"Keine Cloud, keine Tracker, kein Account."*
- *"Privatsphäre ist hier kein Feature, sondern die Architektur."*

### Never
- *"Du solltest…"* (instruction)
- *"Wahrscheinlich hast du PCOS / Endometriose / [Diagnose]"* (diagnostic)
- *"Streak: 14 Tage geloggt"* (engagement manipulation)
- *"Premium freischalten"* (no paywall)

---

## Part 6 — App Store screenshot strategy

The competitive screenshot analysis told us: **every single competitor leads with prediction/countdown in screenshot 1.** This is unoccupied territory:

1. **Screenshot 1 — Privacy-as-architecture.** Tide visualization with overlay text *"Deine Daten verlassen dein Gerät nie."* Concrete, not legal-disclaimer. **No competitor occupies this in screenshot 1 except Clue (badge only, not architectural claim).**

2. **Screenshot 2 — Retrospective recognition.** Mein Zyklus tab with a Layer 1 recognition headline visible + Layer 2 pattern observation visible. *"Verstehe deinen Zyklus statt ihn nur zu zählen."*

3. **Screenshot 3 — Doctor PDF.** *"Mit einem Tipp für deinen Frauenarzt-Termin."* The 15-app analysis confirmed zero competitors put this in their screenshots.

4. **Screenshots 4-6** — phase strip + calendar + ambient hero. Standard product surfaces.

This screenshot ordering is the strongest single decision for App Store discovery in DACH per the competitive research.

---

## Part 7 — Open architectural questions to resolve before building

1. **Statistik tab — keep, drop, or repurpose?** (Part 3.5.) Recommendation: drop for v1.
2. **Loss-aware silence implementation** — when does the 28-day suppression timer start, restart, end? Should there be a settings toggle ("I want to be reminded again")? Currently no implementation track.
3. **iCloud sync (private CloudKit)** — CLAUDE.md flagged as open question. Research from 2026-05-21 supports this for the iPhone↔iPad use case while preserving on-device thesis. Recommendation: add to roadmap as v2 feature, opt-in default off.
4. **HealthKit integration sequencing (task #71)** — does it need to ship before the Statistik tab can be repurposed (Part 3.5 option C)?
5. **Adolescent first-launch (research-recommended segment)** — when the user is under 16, should the onboarding ask a parental-consent question? Currently no logic exists.

---

## Part 8 — Implementation priorities derived from this UI plan

Cross-referenced against the tracker:

**Promote to P0:**
- **#46 Doctor-Export: on-device PDF generation** — research-validated as the single most differentiating MDR-safe feature.

**Active P0s still in flight:**
- #74 Resume-after-pause (in progress)
- #71 HealthKit Import (pending — informs Statistik decision)

**New P1 tasks this UI plan implies (not yet tracked):**
- Mein Zyklus tab redesign (Layer 1 / 2 / 3 — replaces task #89's event-list-as-primary)
- Privacy-as-architecture App Store screenshot copy (when we ship to App Store)
- Loss-aware silence: 28-day notification suppression after Category C events
- Template library for Layer 1 recognition copy (German)
- Statistik tab decision (drop or repurpose)

---

## Document scope

This is the *what goes where and why* document. It does not specify:
- Exact pixel layouts (those live in mockups, future Figma if needed)
- Color systems (live in `tideline-visual-language.md`)
- Numeric algorithms (live in `mixture-predictor.md`, `disrupted-cycles.md`)
- Per-event copy (lives per-feature, e.g. `late-mode-implementation.md`)
- Animation specifics (live in code comments where relevant)

Decisions captured here should be cited from feature design docs, not re-litigated.
