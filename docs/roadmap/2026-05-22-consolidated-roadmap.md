# Tideline — Consolidated Roadmap

**Date:** 2026-05-22
**Status:** Active roadmap. Supersedes ad-hoc prioritization scattered across tracker tasks.
**Synthesized from:**
- `docs/design/app-ui-architecture.md` (information architecture + per-surface plan)
- `docs/research/2026-05-21-market-research-synthesis.md`
- `docs/research/2026-05-21-mein-zyklus-tab-research.md` (fact-checked, supersedes 3 claims)
- Clue + Flo competitive feature inventories (this session)
- `CLAUDE.md` product pillars + hard rules
- `docs/design/mixture-predictor.md` (v2 predictor design)
- `docs/design/differentiators.md` (positioning)
- Current tracker state (tasks #9 – #119)

---

## 0. Where we are

Pre-alpha. Numeric core, design docs, and a working home view ship. Recent waves:

- **Audit cluster (#99, #113, #114, #117, #118)** — closed: DST audit, conformal-PCOS masking, disappearing-log bug, delete-path bugs.
- **Cluster A (#101, #115, #116)** + **Cluster B (#77, #78)** — closed: widening flag wired, PCOS irregularity declared, late-mode hero with "Keine klare Schätzung."
- **Block A + Block B design-handoff polish (#57, #58)** — closed: hero overlay, Cormorant Garamond wired (falls back until TTF bundled), tighter card shadow, two-line sparkline, phase-strip slider rewrite.
- **#89 CycleEvent display** — closed: event list ships; the user correctly flagged this list-as-primary as wasted space → forms the entry point for Mein Zyklus redesign in Phase 1.
- **#74 EventKind.resumeAfterPause** — model + service layer done; **UI layer (Gap-Detector + Resume-Sheet) is the active open P0.**

What this roadmap re-orders against today's tracker is informed by *new evidence* gathered in the last 36 hours:

1. **Doctor-PDF (#46) is the strongest single competitive gap** — unoccupied in the lead-position App Store screenshot of all 15 cycle apps audited (fact-check 2026-05-22: the audit was screenshot-lead-position, NOT exhaustive per-app feature audit; Flo's cloud-derived Health Report and Clue's CSV export exist but neither is on-device + free). The unoccupied competitive territory is "free, on-device, ready for the Frauenarzt appointment". Promote P2 → **P0**.
2. **Mein Zyklus needs a 3-layer redesign** (Layer 1 recognition / Layer 2 pattern / Layer 3 history) — the event-list-as-primary was correctly identified as wasted space. New P0 task.
3. **Loss-aware 28-day notification suppression** — CLAUDE.md hard rule, no implementation track exists. New P1 task.
4. **Statistik tab — drop for v1.** Reduce to 4-tab layout. Re-introduce as power-user numeric drill-down post-HealthKit (#71) if empirical demand emerges.
5. **Predictor v2 + conformal calibrator ship together** — conformal wrapper is small (~30–60 LOC); shipping it with v2 makes Tideline the first peer-reviewed-or-shipped cycle app with conformal coverage guarantees.

---

## 1. Decisions to lock before any new code

These are blocking the next sprint. Listed by priority of needing an answer.

| # | Question | Recommendation | Why |
|---|---|---|---|
| D1 | Statistik tab — keep, drop, repurpose? | **Drop for v1** (Option A from UI plan) | Mein Zyklus absorbs its job; 4-tab feels less placeholder-heavy; can re-introduce later as the HealthKit-charts surface |
| D2 | Promote #46 Doctor-PDF to P0? | **Yes** | Free + on-device doctor export is unoccupied in the lead-position App Store screenshot of all 15 audited apps; MDR-safe. (Fact-check note 2026-05-22: the "15/15 lack" framing overreaches the actual audit — Flo's cloud Health Report and Clue's CSV export do exist; the genuine gap is "free + on-device". Use this softer framing for App Store copy.) |
| D3 | Pricing — one-time, freemium, or free? | **One-time purchase (lean)** | Preserves on-device-only thesis (no recurring server costs); aligns with differentiator #15; subscription requires accounts → violates Pillar 1 |
| D4 | Ship v2 mixture and conformal wrapper together, or v2 first? | **Together** | Conformal is ~30–60 LOC; bundles the differentiator with the math change |
| D5 | iCloud private DB sync — when? | **v1.1 / v2** | Opt-in, default off; preserves on-device-default; addresses iPhone↔iPad use case |
| D6 | Adolescent (<16) onboarding flow? | **Defer to post-launch** | EU UCPD doesn't require parental gate for wellness apps; revisit if/when DiGA pursued |
| D7 | DiGA (German prescription reimbursement) pathway? | **Defer past v1.0** | Significant cert/clinical-trial cost; pursue only once retention proves the model |

All decisions D1-D7 should be confirmed by the owner before Phase 1 kicks off. The doc captures the current recommendation; nothing here is built without the green-light.

---

## 2. Phase 0 — Wrap pre-alpha (1–2 weeks)

**Goal:** clear the immediate-tail backlog before starting the bigger Phase 1 work.

| Task | Status | Notes |
|---|---|---|
| **#74** Resume-Sheet UI + Gap-Detector | in_progress (model done, UI pending) | Active P0; finishes the event-routing feature |
| **#84** Cleanup dead `showEventSheet` state | pending | Cosmetic, finish during #74 work |
| Bundle Cormorant Garamond TTF (Block C from design handoff) | not tracked | One-line plan; covers A2's font once TTF available |
| Confirm D1–D7 decisions above | meta | Blocks Phase 1 |

Exit criteria: #74 ships, decisions D1–D7 locked, tracker tidy.

---

## 3. Phase 1 — Trust Foundation (4–6 weeks)

**Goal:** ship the surfaces that make Tideline trustworthy enough to use. Privacy, recognition framing, and the doctor-export gap. This is the work that earns the "this is different from Flo / Clue" pitch.

### 3.1 P0 — must ship in Phase 1

| Task | Source | Description |
|---|---|---|
| **#46** Doctor PDF (on-device) | Promoted from P2 per D2 | Generate PDF locally, share via system sheet. Includes cycle log, events, optional symptom journal. Doctor-readable layout. Cryptographic SHA-256 export receipt (differentiator #18). |
| **#71** HealthKit Import + Review Onboarding | already P0 | Import past period/symptom flows; backfill cycles. Review screen confirms before commit. Largest remaining P0. |
| **#76** First-launch onboarding (3 screens) | already P0/P1 | Per UI-plan Part 4.1: privacy disclosure → single-question "letzte Periode" → optional opt-in tracking toggles |
| **NEW-A** Mein Zyklus 3-layer redesign | UI plan Part 3.2 | Layer 1 recognition card + Layer 2 pattern observation + Layer 3 collapsed retrospection. Replaces the current event-list-as-primary surface. |
| **NEW-B** German recognition-copy template library | UI plan Part 5 | Owns Layer 1 phrases. Per-phase + per-day-in-phase + per-event-context templates. Static, no AI. |
| **NEW-C** Loss-aware notification suppression | CLAUDE.md hard rule | 28 days no cycle-prediction notifications after Category C loss events. Settings toggle to manually re-enable. |
| Drop Statistik tab → 4-tab layout | D1 | One commit, low risk. |

### 3.2 P1 — companions

| Task | Description |
|---|---|
| **#75** Ereignis-Tab functional | General event creation UI (Block 3 disruption events) |
| **#79** Calendar range-select for bulk backfill | Big win for re-onboarding |
| **#80** LogDaySheet first-entry contextual hint | Soft onboarding hint |
| **#81** Privacy microcopy in empty hero | Reinforces Pillar 1 visually |
| **NEW-D** Privacy disclosure section in Mehr tab | "Über Tideline" + plain-language privacy card + link to whitepaper PDF |

Exit criteria: trust foundation in place. Mein Zyklus tab earns its slot. Doctor PDF works. HealthKit import works. First-launch flow exists. Phase 1 leaves us with an honest **alpha-quality** app.

---

## 4. Phase 2 — Predictor v2 + Robustness (6–10 weeks)

**Goal:** ship the math we designed and clean the predictor edge cases. The first version that delivers on Pillar 3 ("honest uncertainty") at the level the design docs claim.

### 4.1 Predictor work

| Task | Source | Description |
|---|---|---|
| **#83** v2 Mixture Predictor | `mixture-predictor.md` | Normal ovulatory + shifted log-normal anovulatory, Gibbs sampling. Per-event recovery profiles. Est. 7–12 dev-days. |
| **NEW-E** Conformal-prediction wrapper | predictor-roadmap memory + D4 | ~30–60 LOC. Distribution-free finite-sample coverage. Ships *with* v2. First cycle app to do this. |
| **#95** 21–45 day clinical clamp on cycle lengths | already P1 | Reject impossible logged lengths before they hit the predictor |
| **#96** Category D outlier rejection (documented, unimplemented) | already P1 | Close the documented gap |
| **#97** Age-stratified SD prior (AWHS values) | already P2 | Pre-work for v2 if not bundled |

### 4.2 Reliability + integration

| Task | Description |
|---|---|
| **#91** HealthKit round-trip (write + read) | The import pipe is half-built; close the loop |
| **#90** refresh() race producing mixed-vintage @State | Concurrency correctness |
| **#103** `startPeriod` orphan Cycle rows | Public API guards |
| **#92** CyclePhaseStrip "Bearbeiten" relies on async rescue | Cleanup |
| **#93** phaseNamingClinical_v2 toggle has no settings UI | Add to Mehr |
| **#105** Sparkline behaviour when predictor paused/retired | Edge-case display |
| **#106** CalendarSheet shiftMonth uses stale averageLength | Bug |
| **#110** Timezone display drift after travel | Bug |

### 4.3 Test depth

| Task | Description |
|---|---|
| **#11** Build synthetic cycle generator for tests | Foundation for predictor validation |
| **#10** DSP temperature pipeline | Necessary for v3 (Phase 5) but the scaffolding lands here |

Exit criteria: predictor is calibrated. HealthKit round-trips. Open-tracker P1 reliability bugs resolved. Phase 2 leaves us with **beta-quality** numerics.

---

## 5. Phase 3 — Launch readiness (10–16 weeks)

**Goal:** the work that doesn't show up in the app but determines whether anyone finds and trusts it.

| Workstream | Notes |
|---|---|
| App Store screenshot suite | Per UI-plan Part 6. Screenshot 1 = privacy-as-architecture. Screenshot 2 = retrospective recognition. Screenshot 3 = Doctor PDF. **No competitor occupies any of these in screenshot 1.** |
| Privacy whitepaper PDF | One page; markdown → PDF is fine. Linked from Mehr → Privacy disclosure. |
| App Store copy (DACH-first) | German primary; English secondary. Honest, no marketing-speak. |
| Pricing implementation (per D3 = one-time) | StoreKit 2 single non-consumable IAP. No subscription. |
| TestFlight closed beta | Real DACH users. Iterate on Mein Zyklus copy with empirical feedback. |
| Crash + telemetry sanity check | MetricKit on-device only (opt-in upload). No third-party SDK. |
| Bug-bash sweep + accessibility audit | VoiceOver, Dynamic Type, Reduce Motion |

Exit criteria: shippable v1.0 binary, App Store listing ready, beta user signal positive. 

---

## 6. Phase 4 — Post-launch (3–6 months)

**Goal:** consolidate the launch, ship deferred Phase 1/2 items that didn't make the cut, and start the differentiation work.

| Task | Source |
|---|---|
| **#85** Notification scaffolding for late-period quiet check-in | already P3 |
| **#82** Hide / contextualize placeholder tabs on first launch | already P2 |
| **#109** Duress / Decoy passcode + Quick-Wipe | already P1, deferred to post-launch |
| **#47** DRSP-Modus für PMS/PMDD-Journaling | Differentiator #10 |
| **NEW-F** v2.5 μ-drift random walk inside Gibbs | predictor-roadmap memory (Oliveira 2021; σ_η ≈ 1 day/cycle) |
| **NEW-G** iCloud private DB sync (opt-in) | D5; CloudKit private database, no server |
| **NEW-H** Adolescent first-launch flow | D6 if revisited |

---

## 7. Phase 5 — Differentiation (6–12 months)

**Goal:** the moves that turn "honest cycle tracker" into "the cycle tracker no one else can copy."

| Workstream | Source |
|---|---|
| **v3 wrist-temperature within-cycle updating** | predictor-roadmap memory; HR 2025 evidence MAE 1.70 vs 1.90. ~400–700 LOC + HealthKit deeper integration. Must include "no detectable signal" observation state (38% of cycles per Mu 2021). |
| **Open-source predictor as Swift Package** | differentiator #14 |
| **Cryptographic export receipts** (SHA-256 + timestamp) | differentiator #18; ties into doctor PDF |
| **Apple-Watch-native fertility tracking** (no cloud) | differentiator #17. Differentiates vs Natural Cycles device-dependency. |
| **#86** Partner-sharing via CloudKit CKShare | already future |
| In-app research notes ("How we predict" transparency view) | differentiator #16 |
| DiGA cert pathway exploration | D7 if pursued |

---

## 8. Explicitly out of scope for v1.0

Documenting these prevents drift. Each is in scope for a *later* phase, not v1.

- ❌ AI-generated insight copy. **Templates only.** Phase 1-4. Apple Intelligence summaries optional, never the primary insight source.
- ❌ Streaks, badges, daily-login rewards. **Never.** (Pillar 5.)
- ❌ Cloud sync. **v2.**
- ❌ Generative chatbot ("Ask Flo"-style Q&A). **Phase 5 if at all.**
- ❌ Symptom-checker / diagnostic flow. **Never** (MDR drift).
- ❌ Subscription paywall. **Never** (Pillar 1 — accounts violate on-device).
- ❌ Partner sharing. **Phase 5.**
- ❌ Cross-user federated learning. **Never** (on-device thesis).
- ❌ Conception / contraception efficacy claims. **Never** (MDR Class IIb / Class I trigger).
- ❌ Personalised clinical interpretation. **Never** (Pillar 2).

---

## 9. Open questions still requiring resolution

Carried forward from the UI plan (Part 7), tightened where the roadmap pins them.

1. **Loss-aware-silence trigger semantics.** When does the 28d timer start (event date? log date?), what restarts it (a re-logged loss?), what ends it (manual override only, or also a logged-period?). **Needed before NEW-C ships.**
2. **HealthKit import-conflict resolution.** What happens when HealthKit and Tideline both claim a period start on the same day with different metadata? **Needed during #71 design.**
3. **Doctor PDF content scope.** What's the minimum useful layout for the doctor? Cycle history alone? + symptoms? + events? Recommend: **cycle history + events + optional symptom journal**, with user-side toggles per section. **Needed before #46 ships.**
4. **Mein Zyklus Layer 2 pattern detection.** What patterns are worth surfacing in v1? Recommend three: (a) phase length stability, (b) cycle-length trend, (c) bleeding-days vs average. **Needed before NEW-A ships.**
5. **iCloud sync conflict policy.** Last-write-wins is wrong for cycle data. Need CRDT-like merge for `DayEntry`s (events are easier — log is append-only). **Needed for Phase 4 NEW-G.**

---

## 10. Proposed tracker delta

Once D1–D7 are confirmed, apply these to the task list:

**Promote:**
- #46 (Doctor PDF) — P2 → **P0**

**New P0 tasks:**
- NEW-A: Mein Zyklus 3-layer redesign (Layer 1 / 2 / 3 architecture)
- NEW-B: German recognition-copy template library

**New P1 tasks:**
- NEW-C: Loss-aware 28-day notification suppression
- NEW-D: Privacy disclosure section in Mehr tab
- NEW-E: Conformal-prediction wrapper (ship with #83)

**New post-launch tasks (P2/Future):**
- NEW-F: v2.5 μ-drift random walk
- NEW-G: iCloud private DB sync (opt-in)
- NEW-H: Adolescent first-launch flow

**Re-categorize:**
- Drop the Statistik tab work — close placeholder tracker entry (#82 partial scope changes)
- #89 (event-list UI) — scope already shipped; the "wasted space" critique is addressed by NEW-A, not by redoing #89

---

## 11. What this roadmap deliberately does *not* commit to

- **Exact dates.** Phase ranges are weeks-of-work estimates assuming solo dev focused on Tideline ~50% of the time. Calendar mapping happens when the user has bandwidth visibility.
- **Per-cycle resource allocation.** No sprint planning here; the doc is goal-shaped, not Jira-shaped.
- **Marketing or growth tactics beyond App Store positioning.** Out of doc scope.
- **Internationalisation beyond DE/EN.** v1 is bilingual; further locales follow demand.

---

## Document conventions

This is a write-once dated roadmap. When the priorities shift materially, write a *new* dated roadmap (`docs/roadmap/YYYY-MM-DD-*.md`) and let the index of files communicate evolution — same convention as research notes. Do not edit this file in place once Phase 1 starts; let it become the snapshot of "what we decided on 2026-05-22 with the evidence we had."
