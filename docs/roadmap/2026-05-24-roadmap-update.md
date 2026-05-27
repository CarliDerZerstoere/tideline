# Tideline — Roadmap Update

**Date:** 2026-05-24
**Status:** Active roadmap. Supersedes `2026-05-22-consolidated-roadmap.md` for phase ordering and current-state status. Architectural decisions D1–D7 and out-of-scope list from 2026-05-22 carry forward unchanged unless explicitly noted.

**Why a new roadmap two days later** — the prior plan put Phase 2 = "Predictor v2 + Robustness". After clearing most of Phase 1 plus the v1-predictor cleanup cluster (#95, #96, #103, #90, #97), we decided to flip the next two phases: **TestFlight-readiness first, v2 mixture predictor second**. Real DACH user feedback informs v2's scope better than the design doc alone, and the v1 predictor is in the cleanest shape it has ever been.

---

## 0. What shipped since 2026-05-22

Roughly two days of focused work, ordered as completed:

**Phase 1 P0/P1 work** (from prior roadmap):
- ✅ **#74** Resume-Sheet UI + Gap-Detector (the Phase 0 in-progress item)
- ✅ **#46** Doctor PDF (on-device, with SHA-256 receipt per differentiator #18)
- ✅ **#71** HealthKit Import + Review onboarding
- ✅ **#91** HealthKit write-back (round-trip closed)
- ✅ **#75** LogEventSheet (disruption events UI)
- ✅ **#76** First-launch onboarding
- ✅ **NEW-A (#120)** Mein Zyklus 3-layer redesign
- ✅ **NEW-B (#121)** German recognition-copy template library
- ✅ **#80** LogDaySheet first-entry hint
- ✅ **#81** Privacy microcopy in empty hero
- ✅ **NEW-D (#123)** Privacy disclosure section in Mehr tab

**Predictor cleanup cluster** (the work that made me confident v1 is honest enough to ship to beta):
- ✅ **#95** 21–45 day clinical clamp on `observe(cycleLength:)`
- ✅ **#96** Category D single-anomaly outlier rejection (was documented-but-unimplemented; now `skipNextObservation` flag end-to-end)
- ✅ **#103** `startPeriod` no longer creates orphan Cycle rows
- ✅ **#90** `refresh()` race producing mixed-vintage `@State` — closed via `homeSnapshot` atomic accessor
- ✅ **#97** Age-stratified within-person SD prior (AWHS bands; pre-work for v2)
- ✅ **#79** Calendar range-select for bulk backfill

**Infrastructure**:
- ✅ **#85** Notification scaffolding (`NotificationService` + `NotificationGate` + Settings section, opt-in default off, lockscreen-privacy enforced at the chokepoint)

**Explicitly deferred** (decision made this session):
- ❌ **#109** Duress / Decoy passcode + Quick-Wipe — deferred, possibly indefinitely. DACH threat model doesn't justify the implementation complexity; existing App-Lock (#87) handles the 95% case; a badly-implemented duress mode is actively dangerous (false confidence).

**Test count**: 343 → 355. All green.

---

## 1. Where we are now

The prior Phase 1 ("Trust Foundation") is **substantially complete**. What remains of it:
- Cleanup batch: #82, #92, #93, #105, #106 — five 0.5-day paper-cuts.
- NEW-C (#122) Loss-aware notification suppression — newly unblocked by #85 shipping.

The prior Phase 2 ("Predictor v2 + Robustness") is **not started** and we have decided to defer it behind a TestFlight-readiness sprint. The case is documented in `plans/testflight-readiness-sprint.md`:

1. Real users redirect more than spec docs do.
2. TestFlight gates (StoreKit, EN strings, VoiceOver) don't get smaller by waiting.
3. v1 NIG is honest about its limits — even PCOS users get the widened-β path via #77.
4. Beta feedback shapes v2's actual scope.
5. Pillar 4 ("silence is valid, but never the only response") needs notifications — #85 unblocked the foundation, #122 is the doctrinal completion.

---

## 2. New phase ordering

| Old (2026-05-22) | New (2026-05-24) |
|---|---|
| Phase 1: Trust Foundation | ✅ done (substantially) |
| Phase 2: Predictor v2 + Robustness | → **Phase 3** |
| Phase 3: Launch readiness | → merged into new **Phase 2** |
| Phase 4: Post-launch | unchanged (Phase 4) |
| Phase 5: Differentiation | unchanged (Phase 5) |

The phase boundaries are now **TestFlight-cut as Phase 2 exit criterion**.

---

## 3. Phase 2 — TestFlight readiness (active, ~12–13 working days)

Detailed plan in `plans/testflight-readiness-sprint.md`. Summary:

### 3.1 Phase A — Functional gaps + cleanup (~4–5 days)
| Item | Status | Notes |
|---|---|---|
| #123 Privacy disclosure section in Mehr tab | ✅ shipped | Foundational pre-alpha promise + EU MDR small-print |
| #85 Notification scaffolding | ✅ shipped | `NotificationService` + `NotificationGate` + opt-in toggle |
| #122 Loss-aware 28-day suppression | pending | Extend `NotificationGate.shouldDeliver(...)` with the 28-day window check; needs CycleEvent lookup |
| #82 Hide placeholder tabs on first launch | pending | 0.5d |
| #92 CyclePhaseStrip Bearbeiten async-rescue race | pending | 0.5d |
| #93 phaseNamingClinical_v2 toggle UI | pending | 0.5d (toggle exists; needs Settings UI) |
| #105 Sparkline behaviour when predictor paused/retired | pending | 0.5d |
| #106 CalendarSheet shiftMonth stale averageLength | pending | 0.5d |

### 3.2 Phase B — Commerce + bilingual (~5 days)
| Item | Notes |
|---|---|
| StoreKit one-time purchase | Per D3 — single non-consumable IAP. Currently zero StoreKit code. ~2d |
| EN string-table extraction | Currently every UI string is inline German. Extract to `Localizable.strings` (de.lproj + en.lproj). ~2d |
| Currency / number / date locale audit | DACH expects DE-format dates + 24h. Audit `.formatted(...)` call sites. ~1d |

### 3.3 Phase C — Accessibility + App Store (~3 days)
| Item | Notes |
|---|---|
| VoiceOver audit | Every screen. Priorities: hero, phase strip, calendar, log sheet. ~1d |
| Dynamic Type XXXL audit | Hero + CyclePhaseStrip are the truncation risk surface. ~0.5d |
| WCAG AA contrast audit | Mein Zyklus already got the contrast fix in #120 review; sweep the rest. ~0.5d |
| App Store assets | 5 DACH-localized screenshots + copy + keywords. ~1d |

**Phase 2 exit criterion**: TestFlight binary uploaded.

---

## 4. Phase 3 — Predictor v2 + Robustness (post-TestFlight, ~3–4 weeks)

Same scope as the prior roadmap's Phase 2, with **#97 already done** (age-stratified prior shipped as v2 pre-work).

### 4.1 Predictor work
| Task | Source | Description |
|---|---|---|
| **#83** v2 Mixture Predictor | `mixture-predictor.md` | Normal ovulatory + shifted log-normal anovulatory, Gibbs sampling. Per-event recovery profiles. Est. 7–12 dev-days. |
| **NEW-E (#124)** Conformal-prediction wrapper | predictor-roadmap memory + D4 | ~30–60 LOC. Distribution-free finite-sample coverage. Ships *with* v2. First cycle app to do this. |
| Per-event recovery profiles | mixture-predictor doc | Replace uniform `softReset()` with per-event lookup (postpartum vs. EC vs. miscarriage all different). |

### 4.2 Reliability + integration leftovers
| Task | Status |
|---|---|
| **#110** Timezone display drift after travel | P2 pending |
| **#11** Synthetic cycle generator for tests | P1 pending — foundation for v2 validation |
| **#10** DSP temperature pipeline | P1 pending — needed for v3 (Phase 5) but the scaffolding can land here |

### 4.3 Beta-feedback-driven work
TBD based on real DACH user feedback from TestFlight. The whole point of doing TestFlight first.

**Phase 3 exit criterion**: predictor is calibrated against real DACH beta data. Open-tracker P1 reliability bugs resolved. **Beta-quality numerics.**

---

## 5. Phase 4 — Post-launch (3–6 months)

Same as prior roadmap. Items:
- **#47** DRSP-Modus für PMS/PMDD-Journaling (differentiator #10)
- **NEW-F (#125)** v2.5 μ-drift random walk inside Gibbs
- **NEW-G (#126)** iCloud private DB sync (opt-in, default off)
- **NEW-H (#127)** Adolescent first-launch flow (D6 if revisited)
- AI summary layer (Foundation Models + static template fallback) — currently zero code; not pre-alpha-blocking
- Hormone tracking (OPK manual entry, blood lab E2/P4/LH/FSH/AMH context) — design doc pending
- Wrist temp / RHR / HRV / sleep HealthKit reads

---

## 6. Phase 5 — Differentiation (6–12 months)

Same as prior roadmap:
- **v3 wrist-temperature within-cycle updating** — HR 2025 evidence MAE 1.70 vs 1.90. ~400–700 LOC + HealthKit deeper integration. Must include "no detectable signal" observation state (38% of cycles per Mu 2021).
- **Open-source predictor as Swift Package** — differentiator #14
- **Cryptographic export receipts** — differentiator #18; partially in via Doctor PDF SHA-256
- **Apple-Watch-native fertility tracking** — differentiator #17
- **#86** Partner-sharing via CloudKit CKShare — already future
- **In-app research notes** ("How we predict" transparency view) — differentiator #16
- DiGA cert pathway exploration — D7 if pursued

---

## 7. Decisions carried forward unchanged from 2026-05-22

D1–D7 from the prior roadmap all stand:
- **D1**: Statistik tab dropped — confirmed by Mein Zyklus shipping.
- **D2**: Doctor PDF promoted to P0 — confirmed and shipped.
- **D3**: One-time purchase pricing — Phase 2B implementation pending.
- **D4**: v2 + conformal ship together — Phase 3 commitment.
- **D5**: iCloud sync v1.1 / v2 — Phase 4 commitment.
- **D6**: Adolescent flow deferred — Phase 4 (#127).
- **D7**: DiGA past v1.0 — Phase 5 if pursued.

---

## 8. New decisions made since 2026-05-22

| # | Question | Decision | Reasoning |
|---|---|---|---|
| **D8** | TestFlight readiness or v2 mixture next? | **TestFlight readiness first** | Real DACH user feedback informs v2's scope better than the design doc alone; v1 is in the cleanest shape it has ever been. |
| **D9** | Build Duress/Decoy passcode (#109)? | **No, defer indefinitely** | DACH threat model doesn't justify the complexity; App-Lock (#87) handles 95% of the "give me your phone" case; a badly-implemented duress mode is actively dangerous (false confidence). |
| **D10** | Add age question to onboarding for #97? | **Yes, as optional question with "Lieber nicht angeben" default** | AWHS-stratified prior fixes the Pillar-3 violation for adolescent + perimenopausal users; coarse 6-bucket bands are more privacy-conservative than reading DOB from HealthKit. |

---

## 9. Status of open questions from 2026-05-22

The five open questions from the prior roadmap, with current status:

1. **Loss-aware-silence trigger semantics.** Still open. Needs an answer **before #122 ships** (Phase A item). Recommended: timer starts at event date (logged or backdated equivalently); restarted by a re-logged loss; ended only by manual user override OR by a new logged period start.

2. **HealthKit import-conflict resolution.** Resolved during #71 implementation: existing Tideline entry wins on same-day conflict; the import sheet exposes the count of skipped-existing.

3. **Doctor PDF content scope.** Resolved during #46 implementation: cycle history + events + optional symptom journal with per-section toggles.

4. **Mein Zyklus Layer 2 pattern detection.** Resolved during #120 implementation: phase length stability + cycle-length trend + bleeding-days vs average.

5. **iCloud sync conflict policy.** Still open. Phase 4 (NEW-G / #126) blocker.

---

## 10. Explicitly out of scope for v1.0 (unchanged from 2026-05-22)

Carried forward verbatim:
- ❌ AI-generated insight copy. Templates only.
- ❌ Streaks, badges, daily-login rewards. Never.
- ❌ Cloud sync. v2 (Phase 4).
- ❌ Generative chatbot. Phase 5 if at all.
- ❌ Symptom-checker / diagnostic flow. Never.
- ❌ Subscription paywall. Never.
- ❌ Partner sharing. Phase 5.
- ❌ Cross-user federated learning. Never.
- ❌ Conception / contraception efficacy claims. Never (MDR Class IIb / Class I trigger).
- ❌ Personalised clinical interpretation. Never (Pillar 2).
- ❌ Duress passcode + decoy mode (D9, **new this update**). Reconsidered; not justified.

---

## 11. Tracker delta since 2026-05-22

Compared to the prior roadmap's "proposed tracker delta", the actual state today:

**Promoted + shipped:**
- #46 Doctor PDF: P0 ✅
- NEW-A #120 Mein Zyklus 3-layer redesign: P0 ✅
- NEW-B #121 German recognition-copy templates: P0 ✅
- NEW-D #123 Privacy disclosure: P1 ✅
- NEW-C #122 Loss-aware suppression: pending (Phase 2A)
- NEW-E #124 Conformal wrapper: pending (Phase 3, ships with #83)
- NEW-F #125 / NEW-G #126 / NEW-H #127: pending (Phase 4)

**Re-categorized:**
- #109 Duress passcode: P1 → **deferred** (D9)
- #97 Age-stratified prior: P2 → ✅ shipped (was scheduled for Phase 2/3, completed early)
- #85 Notification scaffolding: P3 → ✅ shipped early (Phase 2A entry)

---

## 12. What this update deliberately does *not* commit to

Same as 2026-05-22:
- **Exact dates.** Phase ranges are weeks-of-work estimates assuming solo dev ~50% focused.
- **Per-cycle resource allocation.** No sprint planning here.
- **Marketing or growth tactics beyond App Store positioning.** Out of doc scope.
- **Internationalisation beyond DE/EN.** v1 is bilingual; further locales follow demand.

---

## 13. Quick orientation for future-me

When you read this in three weeks:
- **If still in Phase 2** (TestFlight sprint): the next item is the cleanup batch (#82, #92, #93, #105, #106) plus #122. After that, StoreKit + localization (Phase 2B).
- **If TestFlight is uploaded**: you're in Phase 3. Start with `mixture-predictor.md` and #83 + #124 paired.
- **If beta feedback has landed**: re-prioritize Phase 3 items against what users actually complained about. The point of TestFlight-first was to gather this signal.

The list of decisions to revisit on this re-read:
- **D9** (Duress passcode deferral) — if DACH beta users in DV contexts request it, reconsider.
- **D10** (Age band onboarding question) — if onboarding-completion data shows the step drops off significantly, consider making it skip-by-default-with-skip-button less prominent.
- **D8** (TestFlight before v2) — once beta feedback exists, validate that the decision paid off.

---

## Document conventions

Same write-once dated convention. When priorities shift materially again, write a new `docs/roadmap/YYYY-MM-DD-*.md`. Both 2026-05-22 and 2026-05-24 are now snapshots; this one is current, the prior is historical.
