# Tideline — Post-v2 Reprioritization

**Date:** 2026-05-26
**Status:** Active. Supersedes Phase 3 predictor-routing scoping from `2026-05-24-roadmap-resync.md`. Decisions D1–D10, R1–R25 from prior roadmaps carry forward unchanged unless explicitly noted here.
**Synthesized from:**
- `docs/research/2026-05-26-v2-empirical-validation.md` (V6 Fehring head-to-head, n=624 predictions)
- `docs/research/2026-05-26-v2-prior-tuning-results.md` (V7 sweep, 7 prior combinations)
- `docs/research/2026-05-26-v2-mcphases-validation.md` (V8/V9-lite/V10 MCPhases + biology test)
- Track 1 (Predictor ROI), Track 2 (Underserved populations), Track 3 (Competitive landscape) research waves

---

## 1. Executive Summary

Six sessions of v2 mixture predictor work produced a correctly-implemented Gibbs sampler that passes all synthetic-truth tests, bit-exact cross-language RNG parity, and 503 green tests. The empirical finding is that **the math is correct and the model does not do what it was designed to do.** V9-lite (MCPhases, n=28 cycle observations) showed that v2's per-cycle component assignment correlates positively with LH peak rather than negatively — the wrong sign. v2 classifies cycle LENGTH, not biological anovulation. This is a known confound: long cycles tend to have higher max LH due to delayed surge from prolonged follicular phase. Combined with the V10 pooled MAE finding (+0.486 days, 95% CI [+0.396, +0.576], statistically significant), the result is clear: **v2 routing has no empirical basis on the data we have.** The Sessions 1–3 sidecar uses (badge, late-mode conditional interval, recovery profiles) pay their way without depending on the biology claim and are not affected by this finding.

What this changes about priorities is substantial. Phase 3 was structured around #83 (v2 mixture) + #124 (conformal calibrator) shipping together as a paired differentiator per D4. That framing assumed v2 routing added value over v1 for identifiable user segments. It does not, on cycle-length data alone. The conformal calibrator, however, is more valuable than ever: V6 also confirmed that v1 over-covers its 80% credible interval by ~8.6pp (covers 87.8% when targeting 80%). Fixing that calibration is achievable in 1–2 dev-days by refreshing `ConformalResiduals.swift` against current NIG priors, unblocking #114 without waiting on the now-deprioritized v2 routing. **D4 ("v2 + conformal ship together") is superseded**: conformal calibration ships standalone on v1.

The top-5 recommendations for the next 6 months, in ROI order: (1) conformal calibration via MCPhases residuals — 1–2 dev-days; (2) variance-aware interval widening on v1 — 1–2 dev-days; (3) doctor-handoff PDF extension as shared infrastructure for PCOS, TTC, and Long COVID — 3–5 dev-days; (4) PCOS phenotype-tagged symptom and lab logbook — 4–6 dev-days; (5) wrist temperature integration via Apple Watch S8+, with 0.20-day MAE improvement per Goodale & Shilaih 2025 (Hum Reprod 40(3):469, n=260, 889 cycles) — 3–5 dev-days. Total: 12–21 dev-days, all within Phase 3–4 scope.

The competitive threat from Natural Cycles NC° Perimenopause (shipped March 2026, DACH runway 12–18 months) is real. The response is not to build perimenopause first — R8 still requires 6–8 DACH user interviews before that design doc is drafted. The response is to ship the structural differentiators that NC° cannot match without rebuilding their architecture: on-device only, German-first, doctor-handoff PDF, no account. Those are Phase 2 and Phase 3 work, already in progress.

Phase 2 (TestFlight readiness) is not affected by this reprioritization. Ship Phase 2C as soon as the cleanup batch (#82, #92, #93, #105, #106), #122 (loss-aware suppression), and Phase 2B (StoreKit + i18n + a11y) are complete. Do not wait for Phase 3 predictor work.

---

## 2. Top-5 Features for Next 6 Months

ROI-ranked by impact-per-dev-day. Effort estimates assume solo developer familiar with codebase.

### Rank 1: Conformal Calibration via MCPhases Residuals

**Rationale:** V6 confirmed v1 over-covers its 80% CI by ~8.6pp (covers 87.8%). The conformal calibrator in `ConformalResiduals.swift` uses residuals derived before the #97 age-stratified prior update — those residuals are stale. Refreshing them against current NIG priors is the single highest-ROI predictor action available. This is unblocked by using MCPhases-derived or AWHS-synthetic residuals rather than Fehring residuals, sidestepping the #155 licensing blocker. Check whether the Fehring licensing restriction applies specifically to derived residuals in a commercial binary — it may not block MCPhases-derived residuals at all.

**Effort:** 1–2 dev-days.

**Evidence anchor:** V6 over-coverage 87.8% at 80% target; V10 pooled MAE difference [+0.396, +0.576] CI, statistically significant. Conformal calibration was designed as #114/#124 — this reprioritizes it to standalone Phase 3 entry.

**Expected outcome:** v1 credible intervals calibrated to within ~1–2pp of stated coverage. Directly demonstrable: "our 80% interval contains your period start 80% of the time" is a defensible and honest statement. This is the "honest uncertainty over false precision" pillar in action and is explicitly demonstrable in Doctor PDF and App Store copy. No competitor ships this.

---

### Rank 2: Variance-Aware Interval Widening on v1

**Rationale:** The sole genuine UX benefit v2 routing was meant to provide — wider intervals for users with high within-person cycle variance — is deliverable without the Gibbs sampler. When a user's NIG posterior has high β/α (elevated estimated within-person SD), apply a multiplier to the predictive interval width. Approximately 50 LOC. This serves `.occasionallyAnovulatory` and `.oftenAnovulatory` badge users honestly without inflicting the 28% MAE penalty that v2 baseline routing would impose on the 96% regular-user majority.

**Effort:** 1–2 dev-days.

**Evidence anchor:** V9-lite conclusion: "the remaining argument ('wider intervals are honest for irregular users') is real but achievable via simpler means." V7 confirmed β-tightening is the mechanistically dominant factor, confirming the interval width is driven by the variance parameter, not the mixture mechanism.

**Expected outcome:** Irregular users see interval widths that honestly reflect their logged cycle variance. Regular users are unaffected. The UX promise of v2 routing is delivered at ~10% of the code complexity.

---

### Rank 3: Doctor-Handoff PDF as Shared Infrastructure for PCOS, TTC, and Long COVID

**Rationale:** Track 2 identified PCOS, TTC, and Long COVID as three ready-to-design segments with no pre-work blocking implementation. All three converge on the doctor-handoff use case. The Doctor PDF (#46) is already shipped and confirmed as the sharpest competitive differentiator in the App Store screenshot competitive audit. Extending it with segment-specific section templates is a 3–5 dev-day investment that simultaneously serves three segments. Build once, configure per segment.

**Effort:** 3–5 dev-days for section templates + layout logic. Segment-specific data collection (PCOS lab logbook, OPK entry) is separate subsequent work.

**Evidence anchor:** Maybin 2025 (Nat Comms, PMC12441152, n=12,187) is the peer-reviewed anchor for Long COVID section content: increased menstrual volume (RR 1.93), extended duration (PR 2.26), intermenstrual bleeding (RR 1.59), PEM cluster in late secretory/menstrual phase. PCOS section displays user-logged labs + cycle-length distribution. TTC historical fertile window display is past-tense and does not constitute a conception-facilitation claim under EU MDR wellness classification.

**Expected outcome:** Tideline becomes the first DACH on-device app with structured multi-segment clinical handoff export. Flo offers cloud-derived Health Report, not on-device. Clue offers CSV, not clinician-readable. Neither is free.

**MDR check:** Display of user-entered values = safe. Population reference ranges as context = safe. "Your FSH is elevated, consider..." = forbidden. Section headers must be descriptive, not interpretive.

---

### Rank 4: PCOS Phenotype-Tagged Symptom and Lab Logbook

**Rationale:** PCOS is the largest underserved segment in Track 2 with zero pre-work blocking implementation. `declareOngoingIrregularity` already handles Category E predictor behavior (β × 2.5, range-only display). The new work is the data collection surface: PCOS-relevant symptom tags in the day logger, a lab logbook for LH/FSH/AMH/SHBG with cycle-day annotation, and cycle-length distribution display replacing false-precision point prediction. No other DACH on-device app offers cycle-day-anchored lab logging with a doctor-handoff export.

**Effort:** 4–6 dev-days (symptom tags + lab logbook SwiftData model + distribution display + Doctor PDF section). Predictor-side behavior is already implemented.

**Evidence anchor:** Track 2 synthesis. The design does not diagnose PCOS, compute fertility windows, or predict ovulation for PCOS users. It displays what the user logged.

**Expected outcome:** PCOS users get a cycle app that acknowledges their cycles are not 28 days, lets them track clinical markers their doctor asks about, and generates a PDF they can actually bring to an appointment. No competitor in DACH does this.

---

### Rank 5: Wrist Temperature Integration (Apple Watch S8+)

**Rationale:** V9-lite identified that v2's failure was the absence of biological signal — cycle-length data alone cannot distinguish ovulatory from anovulatory cycles. Wrist temperature is the direct biological signal that fills this gap and would eventually enable a biologically-grounded v2 routing redesign (Path C per the V10 document). The DSP pipeline (#10) is already in Phase 3 infrastructure scope. Goodale & Shilaih 2025 documents a verified 0.20-day MAE improvement on next menses prediction.

**Effort:** 3–5 dev-days for HealthKit reads + Kalman pipeline + predictor integration. DSP scaffold (#10) lands here.

**Evidence anchor:** Goodale & Shilaih 2025, Hum Reprod 40(3):469 (n=260, 889 cycles) — 0.20-day MAE improvement. Zero gain for atypical cycles per subgroup analysis. This is the 10–18% MAE improvement path for v3 per the project memory note.

**Expected outcome:** Apple Watch users get measurably better next-menses predictions. More importantly, Tideline gains the per-cycle biological ground truth that makes v2 routing re-evaluation possible.

**Constraint:** Zero gain for atypical cycles (Goodale subgroup) means segment-appropriate copy is required. Do not tell PCOS users their predictions improved from wrist temperature.

---

## 3. Updated NEW-* Priorities Table

### Items That RISE

| Item | Prior state | New state | Reason |
|---|---|---|---|
| **#114 conformal calibration refresh** | Phase 3, paired with v2 routing (D4) | **Phase 3 entry, standalone** | V6 confirmed 8.6pp over-coverage on v1; fix is highest-value predictor work; D4 superseded |
| **#141 NEW-W intra-day stamps schema** | Phase 4 | **Phase 4 early (enabler)** | Enables PCOS symptom logbook (Rank 4) + per-symptom pattern engine |
| **#47 DRSP-Modus** | Phase 4 | **Phase 4 early** | Long COVID + PCOS users need structured symptom logging; DRSP is the infrastructure |
| **#142 NEW-Q hormone/lab log** | Phase 4 | **Phase 4 early** | PCOS lab logbook + TTC OPK both require this foundation |
| **#145 NEW-T Long COVID clustering** | Phase 4 | **Phase 4 early** | Maybin 2025 PMC12441152 is peer-reviewed; symptom pattern well-documented; MDR-safe as display |
| **#10 DSP temperature pipeline** | Phase 3 infrastructure | **Phase 3 active** | Wrist-temp integration (Rank 5) is blocked until this ships |
| **#139 NEW-M SkipTrack** | Phase 3 | **Phase 3 — important** | More important now that v2 routing is paused and v1 posterior accuracy is primary lever |

### Items That FALL

| Item | Prior state | New state | Reason |
|---|---|---|---|
| **#83 v2 Gibbs routing / Session 5–7** | Phase 3 primary | **Sidecar-only; routing paused indefinitely** | V9-lite biology test refutes routing premise on cycle-length data |
| **#216 selective routing** | Phase 3 Session 7 | **Paused indefinitely** | Path B (sidecar-only) chosen |
| **#125 NEW-F v2.5 μ-drift** | Phase 4 | **Deprioritized** | Adds complexity to predictor whose routing is paused |
| **#138 NEW-L adolescent prior** | Phase 3 | **Phase 2C polish** | Mostly done via #97; small remaining work can ship in 2C |
| **#140 NEW-O postpartum Gompertz** | Phase 3 | **Phase 4** | Depends on DACH cohort data (genuine literature gap); milestone-text v1 per R18 is Phase 3 |
| **#134 NEW-P perimenopause mode** | Phase 4 | **Phase 4, with user research prerequisite** | R8 stands: 6–8 DACH interviews required; NC° threat increases urgency but does not bypass |

### Items That Become OBSOLETE

| Item | Status | Reason |
|---|---|---|
| **v2 routing to main prediction path** | Obsolete | V9-lite biology; V6/V8/V10 consistent across three datasets |
| **#124 NEW-E as mixture conformal wrapper** | Scope-changed to v1 conformal | D4 superseded |
| **D4 "v2 + conformal ship together"** | Superseded by R28 | Conformal ships standalone on v1 |
| **V7 "tighter-pi" tuning as routing pre-work** | Obsolete as implementation target | Stays informative if Path C eventually pursued |
| **Blanket v2 routing in any form** | Obsolete | V6 + V8 + V10 all consistent |

---

## 4. Decision Rule: Ship vs. Polish vs. New Feature

The owner's position is "best possible, don't ship yet." That is the right instinct for predictor routing — which is now correctly paused. Applied globally to TestFlight timing, it is the wrong call.

**Ship Phase 2C as soon as it is complete.** v1 NIG, post-#97 age-stratified prior, with widened-β Category E for irregular users, is honest in the sense that matters: it is conservative, not misleading. V6 confirmed it over-covers its stated intervals — a conservative failure mode, not a precision-inflating one. A cycle app that says "your period will probably arrive in this range, and the range might be somewhat wider than necessary" is better for real users than a cycle app that does not exist yet.

**The threshold for "polish before ship" applies to features that would be actively harmful if shipped under-built.** Loss-aware suppression (#122) meets this bar — CLAUDE.md hard rule, ships before TestFlight. The predictor over-coverage (8.6pp) does not meet this bar for a TestFlight binary. It gets fixed in v1.1 (Phase 3 Rank 1).

**The threshold for "new feature before ship" is: does this feature prevent installation or cause immediate uninstall?** Privacy onboarding (#137) and Doctor PDF (#46) meet this bar — conversion and retention hooks. PCOS lab logbook does not meet this bar for v1.0.

Apply this test to pending items:

| Item | Blocks TestFlight? | Timing |
|---|---|---|
| #122 Loss-aware suppression | Yes (CLAUDE.md) | Before TestFlight |
| #82, #92, #93, #105, #106 cleanup | Yes (functional bugs) | Before TestFlight |
| #128 StoreKit | Yes (Phase 2B gate) | Before TestFlight |
| #114 Conformal calibration refresh | No | Phase 3 / v1.1 |
| Variance-aware interval widening | No | Phase 3 |
| Doctor PDF segment extensions | No | Phase 4 |
| PCOS lab logbook | No | Phase 4 |
| Wrist temperature | No | Phase 3–4 |

**Concrete rule:** When continued building provides less information per dev-day than real users would provide, stop building and ship. You are at that point. 10–20 DACH TestFlight users answering "what confused you?" will produce higher-quality product decisions than the next design iteration on Phase 4 features.

**Exception:** A known defect that actively misleads users about their health or violates a hard rule blocks shipping. Loss-aware suppression (#122) is the only current item in that category. Everything else is improvement, not repair.

---

## 5. Risk Register

### Risk 1: Natural Cycles NC° Perimenopause Extends to DACH

**Status:** Active threat. NC° Perimenopause + NC° Band wearable + Garmin integration shipped March 2026. German UX estimated 12–18 months out, medium-high probability.

**Impact:** Tideline's NEW-P perimenopause positioning is no longer "first in market" globally. Can still be "first in DACH with German-native, on-device, doctor-handoff perimenopause tracking" — only if Tideline ships before NC° lands.

**Mitigation:** (a) Ship Phase 2 (TestFlight) before NC° DACH launch. (b) Have Doctor PDF, PCOS features, and on-device structural story established before NC° arrives. (c) Do not position perimenopause as Tideline's v1 headline. (d) Accelerate the 6–8 DACH perimenopause user interviews required per R8; schedule during Phase 3. NC° cannot offer German-first, on-device, no-account architecture — that's the durable differentiator.

### Risk 2: "AI vs. No-AI" Market Narrative Misclassifies Tideline

**Status:** Latent. Flo's "Ask Flo" cloud AI pivot via Databricks is live; press will frame as AI-powered vs. traditional.

**Impact:** Positioning risk. Tideline's on-device AI (Foundation Models iOS 26) is architecturally superior for privacy but may be perceived as "no AI" by users who conflate AI with cloud AI.

**Mitigation:** App Store copy and onboarding must explicitly distinguish "on-device AI that never sends your data anywhere" from "cloud AI that requires your data to function." Flo's confirmed non-writing to HealthKit (R15) and their $56M/$59.5M preliminary privacy settlement are concrete inferiorities to cite when relevant.

### Risk 3: Fehring Dataset Licensing Blocks Conformal Binary Ship

**Status:** Active blocker for Fehring-derived residuals. #155 unresolved.

**Mitigation:** Derive conformal residuals from MCPhases or AWHS-synthetic instead of Fehring. Calibration quality somewhat lower but implementation unblocked. Pursue Fehring permission in parallel. Document residual dataset provenance.

### Risk 4: 540-LOC Gibbs Sampler Accumulates Maintenance Burden

**Status:** Accepted risk with mitigations. v2 sidecar uses (badge + late-mode + recovery profiles) are the only runtime footprint now that routing is paused.

**Mitigation:** Do not delete the sampler. Sidecar uses are well-tested and serve clear UX purposes independent of biology claim. Documented in `mixture-predictor.md` empirical reality check callout. If wrist temperature or OPK provides per-cycle biological ground truth, Path C reopens.

### Risk 5: Solo Developer Bandwidth — Phase 4 Features Before User Validation

**Status:** High probability if not explicitly guarded.

**Mitigation:** Enforce phase gate discipline. Phase 2C ships before Phase 3 predictor work. Phase 3 ships (or at minimum: conformal + variance widening complete + wrist-temp scaffold landed) before Phase 4 segment features begin. Beta users may reveal PCOS is 2% of TestFlight cohort and TTC is 40% — let that data drive Phase 4 prioritization.

---

## 6. What Stays Paused or Wontfix Indefinitely

### Paused Indefinitely

**v2 selective routing (#216)** — Routing resumes only under: (a) wrist-temperature per-cycle ovulation confirmation enables Path C; (b) OPK manual entry (NEW-Q, Phase 4) provides LH ground-truth cycles; (c) PCOS-representative labeled dataset with >45-day cycles and LH/PDG ground truth.

**#124 NEW-E as mixture conformal wrapper** — Re-scoped: conformal wraps v1 predictive, not the mixture routing path. D4 superseded per R28.

**NEW-F (#125) v2.5 μ-drift random walk** — Re-evaluate when wrist temperature provides biological ground truth.

**Cycle-length-only predictor ceiling work** — V10 bootstrap CI establishes the empirical ceiling. Further Gibbs tuning approaches a ceiling that biological-signal data can move, but cycle-length recombination cannot.

### Wontfix Until Prerequisites Met

**NEW-P perimenopause mode design doc (#134)** — R8 stands: 6–8 DACH user interviews required before drafting.

**NEW-Y T-suppression mode (#150)** — R5 stands: co-design with 6–10 trans men and NB users on T before any string is written.

**NEW-O postpartum Gompertz curve (#140)** — R18 stands: blocked on DACH cohort data; milestone-text v1 ships in Phase 3.

**v2 routing on PCOS claim** — Fehring [21, 45] day filter structurally under-represents PCOS-like tail. No PCOS routing benefit can ship without adequate-n dataset with >45-day cycles and LH/PDG ground truth.

### Wontfix Permanently

**Blanket v2 routing with baseline priors** — V6 confirms 28% MAE inflation and 61% interval widening for 96% of users.

**HRV, sleep stages, RHR as primary predictor inputs** — Oura PMC9005074 (HRV p=0.13 null), Apple Watch deep-sleep sensitivity 50.5% (PMC11511193). Signal-to-noise too low at individual-cycle resolution.

**#109 Duress passcode** — D9 stands: DACH threat model does not justify implementation complexity.

---

## Decisions Added by This Document

| # | Decision | Replaces |
|---|---|---|
| **D4 (superseded by R28)** | ~~"v2 + conformal ship together"~~ → conformal calibration (#114) ships standalone on v1 in Phase 3; v2 routing paused indefinitely | D4 from 2026-05-22 consolidated roadmap |
| **R26** | v2 sidecar uses (badge + late-mode + recovery profiles) remain in production. Do not delete the Gibbs sampler. | — |
| **R27** | Doctor-handoff PDF extension for PCOS + TTC + Long COVID builds on #46 infrastructure. One renderer, configurable per segment. Phase 4. | — |
| **R28** | Phase 3 predictor work priority order: (1) conformal calibration refresh; (2) variance-aware interval widening on v1; (3) wrist-temp pipeline (#10). v2 routing is not Phase 3 work. | Supersedes "v2 + conformal paired" framing from 2026-05-24 roadmap docs |
| **R29** | TestFlight ships before Phase 3 predictor work. Phase 2C exit criterion unchanged. | Reinforces D8 |
| **R30** | "v2's components are length classes, not biological states" is the permanent framing in `mixture-predictor.md`. | Documents V9-lite finding as authoritative |

---

*Document conventions: write-once dated. Supersedes Phase 3 scoping for items marked above. D1–D10, R1–R25 carry forward unless noted here. Read in chronological order: 2026-05-22-consolidated-roadmap.md → 2026-05-24-roadmap-update.md → 2026-05-24-research-findings-integration.md → 2026-05-24-roadmap-resync.md → 2026-05-25-phase-prediction-implementation-plan.md → this file.*
