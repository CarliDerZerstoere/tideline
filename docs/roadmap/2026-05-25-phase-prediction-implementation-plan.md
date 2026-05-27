---
date: 2026-05-25
status: implementation plan (revised post empirical validation)
research: docs/research/2026-05-25-phase-prediction-synthesis.md
validation: docs/research/2026-05-25-empirical-validation-results.md ← AUTHORITATIVE
decision authority: solo dev, approved for Wave A execution
---

# Phase-prediction implementation plan

This plan operationalises the Q1/Q2/Q3 research synthesis into concrete tracker items.

> **Post-validation revision (2026-05-25 evening):** Two fact-check passes and an empirical run against the Fehring NFP dataset (1,508 cycles, 157 women) led to concrete corrections. The authoritative spec lives in the next section; the original draft below is preserved for audit trail but **superseded** wherever it conflicts with the post-validation spec.

---

## ⭐ AUTHORITATIVE Wave A SPEC (post empirical validation)

After running `data/validate_phase_predictor.py` and a fact-check on both methodology and interpretation, Wave A reduces to **three items**:

| Item | Decision | Confidence |
|---|---|---|
| **NEW-169** — `defaultLutealDuration = 12` (Int rounded from Bull 2019's 12.4) | SHIP | 92% |
| **NEW-170** — Per-user learned luteal length | **DROP** — V3b empirically shows per-user estimate is 0.89 d *worse* than population (MAE 3.14 vs 2.25). Naïve "subtract pop follicular" decomposition adds noise. Unidentifiable from cycle dates alone. | n/a |
| **NEW-171** — Per-user mensesEnd floor | SHIP | 95% |
| **NEW-176** — `PhaseBoundariesPosterior` + `GaussianPosterior` types | SHIP types only (no UI changes). Variance = σ²_NIG + σ²_within + σ²_between. Student-t quantile for CI, df = 2·α_post. Documented as honestly conservative (90% CI covers 98.6% empirically — Pillar-3-compatible overcoverage; conformal calibrator #124 is the tightening path). | 85% |

**Total Wave A effort: ~3 dev-days.** Reasoning per item below.

### NEW-169 — authoritative spec

- Add `defaultLutealDuration: Int = 12` constant in `PhaseBoundaries`.
- Replace literal `14` in `PhaseBoundaries.from(cycleLength:mensesEnd:)` and `PhaseBoundaries.populationDefault` with the new constant.
- Cite Bull 2019 PMC6710244 + Fehring 2013 13.24 sensitivity confirmation in doc-comment.
- **NOT `−13`.** Bull 2019 BBT-method (n=612k) is the right reference; Fehring's 13.24 reflects LH-peak measurement convention (precedes ovulation 0–1 d; computed luteal *longer*). Tideline's future Apple Watch wrist-temp aligns with BBT, so Bull is the methodologically correct anchor.

### NEW-171 — authoritative spec (unchanged from original draft)

- Add `personalMedianMenses: Int?` parameter to `PhaseBoundaries.mensesEnd(...)`.
- Floor = `max(personalMedianMenses ?? defaultMenses, defaultMenses)` — ratchet up never down.
- New `CycleStore.personalMedianMenses(limit: 6)` method: derive per-cycle bleeding-day count via #156 Belsey rebuild; median of last 6; require ≥3 cycles AND median ≥ defaultMenses (defensive against under-logging).
- Thread through `HomeSnapshot`, `MyCycleSnapshot`, `CalendarSheet.computeMensesEndByCycle`.
- V5 confirms 40% of users benefit.

### NEW-176 — authoritative spec (NEW item, replaces NEW-170)

- Add `GaussianPosterior` struct: `mean: Double`, `variance: Double`, `sd: Double` computed.
- Add `PhaseBoundariesPosterior` struct:
  - `mensesEnd: Int` (observed via #156 + NEW-171 — crisp)
  - `ovulationDay: GaussianPosterior` — mean = `μ_NIG − defaultLutealDuration`, variance = `predictiveVar_NIG + σ²_within + σ²_between`
  - `cycleLength: GaussianPosterior` (from NIG predictor)
  - `df: Double` = `2·α_post` for Student-t CI computation
  - `isWidenedRecovery: Bool`, `isOngoingIrregularity: Bool` (inherited from predictor mode)
  - `.crisp: PhaseBoundaries` computed property — rounds posterior means to Int for legacy callers
  - `credibleInterval(_ confidence: Double) -> ClosedRange<Double>` — Student-t with df
- Constants `σ²_within = 1.32` (Berglund Scherwitzl ±1.25 literature anchor; not from Fehring directly per licensing) and `σ²_between = 3.50` for the propagation.
- **No UI changes.** Existing callers continue using the crisp `.from(cycleLength:mensesEnd:)`. New types are dead code today; later tracker items consume them for graduated-opacity rendering.
- Tests pin `.crisp` equivalence to legacy `.from()` output (regression safety).

### Wontfix from V3b empirical evidence

- **Per-user learned luteal mean from cycle dates alone** (was NEW-170). V3b: MAE +0.89 d *worse* than population. Empirically unidentifiable. Revisit only when adding ovulation signals (Phase 4 wrist-temp / OPK / mucus).

### Follow-on tracker items (not Wave A; queued separately)

- **#124 (NEW-E) Conformal calibration** — the principled tightening path for NEW-176's 9pp overcoverage. Blocked on Fehring licensing (#155).
- **Step 3 of NEW-176** — calendar consumes `PhaseBoundariesPosterior` for graduated-opacity ovulation band (closes #164 fully).
- **Step 4 of NEW-176** — hero text consumes posterior for "Eisprung etwa um [date] (~±N Tage)" line.
- **NEW-172** (recovery wider-β) — was contingent on NEW-170; since NEW-170 is dropped, this becomes purely about cycle-length recovery widening, which is already partially in place. Re-evaluate post-Wave A.
- **NEW-173 / NEW-174 / NEW-175** — Phase 4, unchanged by validation.

---

## Original draft (preserved for audit; superseded by spec above)

> Below this point is the pre-validation draft. **Where it conflicts with the authoritative spec above, the spec above wins.** Kept for context on how the plan evolved.

## Summary

| Item | Question | Priority | Effort | Dependency | Phase |
|---|---|---|---|---|---|
| **NEW-169 — Population luteal default = 12.4 d** | Q1 | P1 | <½ dev-day | None | Phase 2C polish |
| **NEW-170 — Per-user learned luteal length** | Q1 | P1 | 1–2 dev-days | NEW-169 | Phase 2C / 3 |
| **NEW-171 — Per-user mensesEnd floor (personal median)** | Q1 follow-on | P2 | 1 dev-day | #156 (shipped) | Phase 2C polish |
| **NEW-172 — Recovery-population wider-β luteal** | Q1 follow-on | P2 | 1 dev-day | NEW-170 | Phase 3 |
| **NEW-173 — Per-symptom pattern engine (recognition copy)** | Q2 | P2 | 3–5 dev-days | #148 intra-day stamps; #154 Layer 2 v1.1 | Phase 4 |
| **NEW-174 — Cervical mucus logging (Billings-aligned)** | Q3 | P3 | 5–8 dev-days | #148 schema; new EventKind subtype or DayEntry field | Phase 4 |
| **NEW-175 — Bayesian fusion of date + mucus posterior** | Q3 | P3 | 5–8 dev-days | NEW-170; NEW-174; #83 mixture; #155 conformal | Phase 4–5 |
| **Wontfix items** | various | — | — | — | Documented below |

Total Phase 2C/3 effort estimate: **~3–4 dev-days** (NEW-169 + NEW-170 + NEW-171).
Total Phase 4 estimate (if all approved): **~13–21 dev-days**.

---

## NEW-169 — Population luteal default = 12.4 d (replace fixed 14)

**Goal:** Replace the hardcoded `cycleLength − 14` with `cycleLength − 12` (rounded from 12.4) until per-user learning is built. One-day correction toward population truth.

**Evidence:** Bull et al. 2019, PMC6710244 — population mean 12.4 d (SD 2.4) across 612k cycles. Apple Health already uses −13. We move to −12.

**Code surface:**
- `Tideline/Sources/Models/CyclePhase.swift:104-110` — `PhaseBoundaries.from(cycleLength:mensesEnd:)`
  ```swift
  ovulation: max(mensesEnd + 2, cycleLength - 12),  // was: - 14
  ```
- Plus the doc-comment `defaultCycleLength` constant comment update (~line 80).
- Plus `populationDefault` constant update (~line 97) if any caller relies on the `cycleLength − 14` numerical result.

**Tests to add:**
- `PhaseBoundariesTests` — pin `from(cycleLength: 28, mensesEnd: 5).ovulation == 16` (was 14; now reflects 28 − 12).
- Check no existing test asserts the old `-14` value; if any do, update with comment referencing this change.

**Risks:**
- Existing tests pin the `−14` value. Sweep before implementation.
- Population mean is 12.4, not 12. The 0.4 d rounding is acceptable given `Int` ovulation day; could float-promote later. Document the rounding choice.

**Effort:** <½ dev-day code + tests + reviewer pass.

**Dependencies:** None.

---

## NEW-170 — Per-user learned luteal length

**Goal:** When N ≥ 3 cycles observed, replace the population default with the user's own median luteal length. Phase boundaries `from()` accepts an optional `personalLutealLength: Int?`.

**Evidence:**
- Berglund Scherwitzl 2015 PMID 25592280: within-user luteal stability ±1.25 d → learning is meaningful.
- Henry 2024 PMC11532606: within-person SD ≈ 1.7 d (after unit resolution), p<0.001 less than follicular.
- Natural Cycles DEN170052 already ships this; competitive parity.
- No published date-only luteal inference exists → Tideline novelty.

**Architecture decision:** Since Tideline has cycle dates but NO temperature data (Apple Watch is Phase 4), we cannot directly observe luteal length per cycle. Instead, learn it indirectly:

Option A (recommended): **Personal luteal = personal_cycle_median − personal_follicular_estimate**, where follicular estimate falls back to population mean (Bull 2019: 16.9 d). This is mathematically equivalent to assuming user's follicular length is population-typical and her cycle-length variance comes from her own pattern.

Option B (rejected for v1): Latent-variable Bayesian decomposition of cycle length into per-user follicular + luteal components. Bortot 2010 (PMID 20400622) is the closest published precedent but does not target luteal. Implementation cost ~3× higher, validation impossible without temp data.

Option A is the right v1 because:
- It's correct in expectation (subtracting one stable population mean from a learned personal mean preserves the per-user signal).
- The error bound vs Option B is small (luteal varies less than follicular within-person).
- The lack of LH/temp ground truth means we couldn't validate Option B better than Option A anyway.

**Code surface:**
- New `CyclePredictor.personalLutealEstimate` computed property (`mu − 16.9`, clamped to 8…18).
- New `CycleStore.snapshot` field: `personalLutealLength: Int?` (nil when N<3).
- `PhaseBoundaries.from(cycleLength:mensesEnd:personalLuteal:)` overload.
- All callers of `PhaseBoundaries.from` in views (`CalendarSheet`, `CyclePhaseStrip`, `MyCycleSheet`, `HomeSnapshot`, `DoctorPDFRenderer`) updated to thread the personal value.

**Tests:**
- Personal luteal returns nil at N<3 → fallback to NEW-169 default.
- Personal luteal at N=6 cycles of 28d → estimate ≈ 11.1 d.
- Personal luteal at N=6 cycles of 30d → estimate ≈ 13.1 d.
- Clamp at boundaries: cycle-mean 22 → estimate 8 (not 5); cycle-mean 38 → estimate 18 (not 21).
- Doctor PDF rendering uses personal luteal when available.

**Risks:**
- The "subtract population follicular mean" simplification can be challenged. Document explicitly as a design choice with this fact-checked rationale.
- Users with anovulation get a meaningless luteal estimate. Gate via `isOngoingIrregularity` and `isWidenedRecovery` flags — for those users, fall back to population default.
- Recently post-pill users (per Gnoth 2002): 6-9 cycle recovery. Gate via existing `.recoverable` event memory — keep population default until N ≥ 6 cycles post-event.

**Effort:** 1.5–2 dev-days code + tests + reviewer pass + code-reviewer per standing directive.

**Dependencies:** NEW-169 (the new fallback default).

---

## NEW-171 — Per-user mensesEnd floor (personal median)

**Goal:** Replace `defaultMenses = 5` lower bound in `PhaseBoundaries.mensesEnd` with the user's own median menses duration when N ≥ 3 cycles available.

**Evidence:** Direct user observation in earlier conversation: if Anna typically has 7-day periods, the current day-6 "fallback to follicular" feels wrong. Personal history is its own evidence — no external research needed.

**Code surface:**
- `PhaseBoundaries.mensesEnd(...)` signature: add `personalMedianMenses: Int?` parameter, default nil.
- When non-nil and ≥ 3, use as the lower bound instead of `defaultMenses`.
- `CycleStore` derives per-cycle menses duration from the rebuild's Belsey episode logic (uses #156 fix) and computes median of last 6 cycles.
- `HomeSnapshot` and `MyCycleSnapshot` include the value.

**Tests:**
- N<3: returns existing default-5 behavior (regression-pin existing tests).
- N=6 cycles all 7 days bleeding: personal floor = 7; day 7 still painted menses.
- N=6 cycles mixed [5, 7, 6, 8, 7, 6]: median = 6.5 → 7 (rounded up); floor = 7.
- Edge: one extreme outlier (3-day cycle in a 7-day pattern) doesn't move the median much.

**Risks:**
- Tightly coupled to #156's Belsey fix. If that breaks, this becomes inconsistent. Tests must cover the interaction.
- Personal median might be heavily influenced by short cycles where the user just didn't log all days. Defensive: require ≥ 3 cycles with bleeding-day count ≥ defaultMenses (i.e. trust the high-floor evidence, not the low-floor).

**Effort:** 1 dev-day.

**Dependencies:** #156 (shipped this session).

---

## NEW-172 — Recovery-population wider-β luteal

**Goal:** For users flagged as anovulatory, post-pill <6 cycles, or postpartum <6 cycles, widen the credible interval around the predicted ovulation day instead of using the (potentially wrong) personal luteal estimate.

**Evidence:**
- Gnoth 2002 PMID 12396560: post-pill recovery 6-9 cycles to luteal stability.
- Schliep 2014 PMC4037737: 8.9% LPD prevalence; only 3.4% recurrent → most short luteals are transient.
- ASRM 2015 (PMID 25681857): "LPD as an independent entity has not been proven" — implication: do NOT diagnose; just acknowledge uncertainty.
- Steiner 2021 PMID 33772306: high AMH (>8) extends luteal 1.8 d — flag as wider-uncertainty population.

**Code surface:**
- New `PredictorMode.recoveryWindow` flag with explicit reason. Already exists via `isWidenedRecovery` — extend to expose number of cycles remaining in recovery window.
- `personalLutealEstimate` returns nil when in recovery window.
- Default falls through to NEW-169 population default.

**Tests:**
- `.recoverable` event → next 6 observe() calls return personalLuteal = nil → fallback used.
- After 6 post-event cycles → personalLuteal computed normally.

**Effort:** 1 dev-day (mostly state-tracking; math is reused).

**Dependencies:** NEW-170.

---

## NEW-173 — Per-symptom pattern engine (recognition copy)

**Goal:** Surface "based on your last N cycles, you may experience X tomorrow/this week" copy for the specific symptom domains where literature supports repeatability.

**Evidence:**
- Verhagen 2022 PMC9535967: menstrual migraine 70% test-retest consistency → eligible.
- Dysmenorrhea ~54% consistency (longitudinal cohort, PMID not extracted) → eligible with caveats.
- Lorenz/Gesselman/Vitzthum 2017 PMC5708589: mood symptoms 1-6% cycle-level variance → NOT eligible for population prediction; per-user may still work but evidence weaker.
- Symul/Li/Urteaga 2020 PMC7250828: engagement-artifact warning → frame as "of the days you logged, X% had Y" not "you have Y X% of the time."

**Code surface:**
- New `PatternEngine` service that consumes `SymptomStamp` records (depends on #148 intra-day stamps schema migration).
- For each (symptom, cycle-day-bin) pair, count occurrences over last 6 cycles.
- If occurrence rate ≥ 50% AND N ≥ 3 cycles, surface a recognition card.
- Hard-coded eligibility list (whitelist of symptoms with literature support); start with migraine, headache, cramps, breast tenderness in late luteal. Mood explicitly NOT in the eligible list initially.

**MDR-safe copy templates:**
- "In **4 von 6 Zyklen** hattest du am Tag 1-2 deiner Periode Krämpfe." (descriptive baseline)
- "Basierend auf deinen letzten 6 Zyklen können diese Symptome **bald wieder auftreten**." (forward, hedged)
- Never: "Du hast PMDD", "Das ist menstruelle Migräne", "Deine Symptome sind hormonell bedingt" (diagnostic — forbidden).

**Tests:**
- N=2 → no forward copy, only historical display.
- N=3, 2/3 cycles had cramps on day 1 → "in 2 of 3 cycles" descriptive shown.
- N=6, 5/6 cycles had migraine on day 14 → "may happen again" forward copy shown.
- Mood (not eligible) never gets forward copy regardless of N.

**Risks:**
- The eligibility whitelist is policy. Document carefully.
- Cross-cycle averaging is sensitive to user engagement (per Li 2020). The "of the days you logged" framing must be tested with non-engineers for clarity.

**Effort:** 3–5 dev-days.

**Dependencies:** #148 intra-day stamps (Phase 4); #154 Layer 2 v1.1.

---

## NEW-174 — Cervical mucus logging (Billings-aligned schema)

**Goal:** Allow users to log cervical mucus quality on the day of intercourse / each day. Use Billings classification (none / sticky / creamy / watery / lubricative-peak).

**Evidence:**
- Fehring 2002 PMID 12413617: peak day ±2 d of LH in 91% of cycles.
- Stanford 2020 PMC8495767: woman-picked peak ±2 d in 84%; kappa 0.71.
- Scarpa-Dunson 2006 PMID 16154254: conception probability 0.003 (none) to 0.29 (peak) — strong signal.
- Billings is the established mucus-only methodology; Sensiplan requires temp.

**Schema:**
- New `CervicalMucusObservation` SwiftData model with date + Billings-coded enum + optional confidence flag.
- Or extend `DayEntry` with optional `mucus: BillingsCategory?` field (Option A in line with #148 schema migration policy).

**UI:**
- Per-day logger in the Day Sheet, opt-in via Settings (default off — most users won't want it).
- Calendar surfaces a peak-day marker (small drop or symbol).
- Doctor PDF gets a new section.

**Tests:**
- Schema migration for existing users.
- Peak-day detection rule: peak = last lubricative day before drying (3 dry days = peak day finalised).
- Doctor PDF inclusion.

**Risks:**
- Logging burden. Default off, opt-in via Settings.
- Schema migration. Follow Option A pattern from #148.
- Privacy: cervical mucus data is intimate. Already covered by Pillar 1 on-device-only, but emphasize in any new UI.

**Effort:** 5–8 dev-days (schema + UI + tests + reviewer).

**Dependencies:** #148 intra-day stamps schema decisions (Option A pattern).

---

## NEW-175 — Bayesian fusion of date + mucus posterior

**Goal:** A per-user posterior on ovulation day that updates day-by-day as mucus observations arrive within the current cycle.

**Evidence:**
- Scarpa-Dunson-Giacchi 2007 PMID 17601602: published calendar+mucus Bayesian decision rule. n=191, 2,536 cycles.
- The "personalized prior seeded from longitudinal history + within-cycle update via mucus likelihoods" architecture is **not published**. Tideline would be the first.

**Architecture sketch:**
1. Cold-start prior on ovulation day: `Normal(personalLuteal + currentCycleLength, σ_personal)` where personalLuteal from NEW-170.
2. For each mucus observation, multiply prior by likelihood `P(observed_mucus | ovulation_day)` from Scarpa-Dunson empirical table.
3. Renormalise. Update phase boundaries.
4. Conformal wrapper applied at the end (NEW-E / #124) to give honest uncertainty.

**Tests:**
- Cold start: posterior matches NEW-170's estimate ± 0 (no mucus data).
- 3 days of "no mucus" observations narrow the posterior.
- 1 "peak" observation collapses the posterior dramatically (most-informative signal).
- Posterior is consistent with NIG predictor's marginals.

**Risks:**
- Adds complexity to the core math. Document the Bayesian update carefully.
- Validation: without temperature/LH ground truth, we can only validate against the user's next-period prediction. Indirect.
- May require the conformal calibrator wrapper (#124, blocked on #155 Fehring licensing).

**Effort:** 5–8 dev-days.

**Dependencies:** NEW-170 (personal luteal), NEW-174 (mucus logging), #83 mixture predictor (better prior), #124/#155 conformal calibration.

---

## Wontfix items (explicit rationale)

These items came up in research but should NOT be built. Documenting so they don't get re-proposed.

| Item | Why wontfix |
|---|---|
| Mood as cycle-phase predictor | Lorenz 2017: cycle phase explains only 1.1-5.7% of mood variance in healthy women. Day-to-day individual variability dominates. We display mood patterns descriptively but do NOT predict mood from cycle phase. |
| Mittelschmerz as standalone ovulation-timing input | 20-25% prevalence even in affected women; absent in 75% of cycles. Captured via general symptom logging (#148), not promoted to predictor input. |
| Breast tenderness as ovulation indicator | PMC12068584: peaks in late luteal (post-ovulatory). Useless for forward ovulation timing. Captured descriptively. |
| Libido as ovulation indicator | Effect size d=0.26-0.74 at fertile-window level but no day-resolution timing. Captured descriptively. |
| Population-prior symptom forecasts ("many users feel X on day 26") | Lorenz 2017: variance at cycle level too small to support population-level mood claims. Per-user only. |
| Apple Watch sleep stages for cycle inference | PMC11511193: 50.5% deep-sleep sensitivity — measurement error > signal. Documented in 2026-05-24 data-fusion wave. |
| HRV alone for ovulation detection | Oura PMC9005074: p=0.13 null result. Documented in 2026-05-24 wave. |
| Cycle-Archaeology marketing to Flo users | Flo does not write to HealthKit. Migration target = Apple Health / Clue / possibly Stardust only. Confirmed in 2026-05-24 implementation-depth wave. |

---

## Implementation sequencing recommendation

**Wave A — Cheap, high-impact, no dependencies (Phase 2C polish, ~3 dev-days total):**
1. NEW-169 (population default 12.4)
2. NEW-171 (personal mensesEnd floor)

**Wave B — Per-user learning, requires Wave A (Phase 2C / 3, ~2 dev-days):**
3. NEW-170 (personal luteal length)
4. NEW-172 (recovery-population wider-β luteal)

**Wave C — Pattern surfacing (Phase 4, ~3-5 dev-days):**
5. NEW-173 (per-symptom pattern engine)

**Wave D — Sympto-only ovulation fusion (Phase 4-5, ~10-16 dev-days):**
6. NEW-174 (mucus logging)
7. NEW-175 (Bayesian fusion)

Total Phase 2C / 3 commitment: ~5 dev-days. This is the immediate-value cluster.

Total Phase 4 commitment if all approved: ~13-21 dev-days. This is the differentiation cluster.

---

## Approval gate

This is a proposal. None of the NEW-169 through NEW-175 items should land in the tracker until:

1. The user (solo dev) reviews the synthesis doc and confirms the decision matrix.
2. Each ship item gets a defined acceptance test.
3. Standing project rules (no streaks, no diagnostic claims, on-device only, code-reviewer pass after every change) are checked against each item's implementation plan.

Suggested next step: review this plan, mark items as **approved / deferred / reject** in a follow-up doc, then I can convert approved items to tracker entries.
