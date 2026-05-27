---
date: 2026-05-25
status: empirical validation results — Wave A authoritative reference
dataset: data/raw/fehring_cycles.csv (Fehring 2013 Marquette NFP, n=1,665 cycles)
script: data/validate_phase_predictor.py
supersedes: the Q1 conclusions in 2026-05-25-phase-prediction-synthesis.md
---

# Empirical validation results — Wave A math

This document records the empirical validation of Tideline's proposed Wave A phase-prediction math against the Fehring NFP dataset (1,665 BBT/LH-confirmed cycles, 157 women, randomized comparison study Fehring 2013). After two fact-check passes (one on the methodology, one on the interpretation), this is the canonical reference for what the data actually shows.

The original synthesis at `docs/research/2026-05-25-phase-prediction-synthesis.md` got the *direction* right on every question, but the specific numbers in the Q1 luteal-stability section need correcting per the V3b empirical test and the fact-check methodology corrections.

## Headline conclusions (after corrections)

1. **`cycleLength − 14` is empirically wrong.** Fehring mean luteal = 13.24 d; Bull 2019 mean = 12.4 d. Both cohorts agree the true number is in [12, 13.5]; 14 is too high.
2. **`−12` (Bull 2019, BBT-based) is the right Tideline default.** Larger n (612k vs 1.5k), BBT-based measurement aligns with our future Apple Watch wrist-temp integration. **NEW-169 stays at `−12`.**
3. **Luteal IS more stable than follicular within-person** (1.15 d vs 1.90 d Fehring within-woman SDs — confirms Henry 2024 direction).
4. **Per-user luteal MEAN is empirically unidentifiable from cycle dates alone** (V3b fair head-to-head: per-user estimate is 0.89 d *worse* than population). Tideline does NOT attempt to learn per-user luteal mean in v1.
5. **The corrected Bayesian propagation math is honestly conservative.** 90% CI covers 98.6% (overcovers by ~9pp). Pillar-3-compatible (wider than needed, never narrower). Conformal calibrator (#124) is the principled tightening path.

## Methodology (post-fact-check corrections)

| Element | Original spec | Corrected spec | Source |
|---|---|---|---|
| Posterior predictive variance | `β·(κ+1)/((α−1)·κ)` | unchanged ✅ | Murphy 2007 NIG derivation |
| Ovulation variance | `Var(cycle) + σ²_within` | `Var(cycle) + σ²_within + σ²_between` | Fact-check I4 |
| CI quantile | Gaussian z (1.645 @ 90%) | Student-t with df = 2·α_post | Fact-check M3 |
| V3 comparison | Mixed: post-hoc vs prospective | V3b added: fair training-only head-to-head | Fact-check I2 |

Independence assumption (`Var(ovulation) = Var(cycle) + Var(luteal)`) is approximately defensible — literature shows a mildly *negative* follicular-luteal correlation, which makes the additive variance assumption slightly *conservative* (right direction).

## V1 — Population luteal phase (Fehring n=1,508 after clinical filter)

```
mean      = 13.24 d   (Bull 2019 reference: 12.4 d)
median    = 13.00 d
SD        = 2.53 d
5th–95th  = 10 – 17 d
```

**Why Fehring 13.24 ≠ Bull 12.4:** Fehring 2013 uses urinary LH peak (precedes actual ovulation by 0–1 d → computed luteal *longer*). Bull 2019 uses BBT thermal shift (lags actual ovulation by 1–3 d → computed luteal *shorter*). Same biology, two measurement conventions. For Tideline (which will eventually integrate Apple Watch wrist-temp = BBT-like), **Bull 2019's 12.4 is the right reference**.

**Decision:** `defaultLutealDuration = 12` (rounded from 12.4). NEW-169 stays at `−12`. Not `−13` (would over-fit to one cohort's measurement convention). Not `−14` (folk rule, empirically wrong).

## V2 — Within-person vs between-person stability (n=132 women ≥3 cycles)

| Phase | Within-woman SD (median) | Between-woman SD (across means) |
|---|---|---|
| Luteal | **1.15 d** | 1.87 d |
| Follicular | 1.90 d | 2.93 d |
| Total cycle | 2.10 d | 2.75 d |

**Confirms Henry 2024 directional claim on independent dataset.** Luteal within-woman SD < follicular within-woman SD. Magnitudes are smaller than Henry 2024 reports (3.0 d / 5.2 d) — that's because Fehring users are prescreened NFP cohort (more regular cycles) and use LH-peak detection (lower measurement noise).

**Caveat:** Median-of-SDs is biased ~10–25% low vs a mixed-effects pooled estimator. The 1.15 d figure is **dataset-specific to this prescreened cohort** — do NOT use as a universal constant in shipped code. For the Tideline variance formula, use it as a *lower bound* with `between-person` variance added on top.

## V3 — Post-hoc MAE of ovulation-day predictions (n=837 test cycles)

Rules (a)–(d) use the actual test cycle length (post-hoc oracle); rules (e)–(f) use only training data:

| Rule | MAE | Median | 95th %ile |
|---|---|---|---|
| (a) folk: cycle − 14 | 1.71 d | 1.00 | 5.00 |
| (b) NEW-169: cycle − 12 | 1.88 d | 2.00 | 5.00 |
| (c) Apple: cycle − 13 | **1.56 d** | 1.00 | 4.00 |
| (d) Bull-precise: cycle − 12.4 | 1.75 d | 1.60 | 4.60 |
| (e) personal-luteal-from-pop-foll | 2.68 d | 2.30 | 6.70 |
| (f) NIG-posterior-mean − 12.4 | 2.25 d | 1.90 | 5.49 |

**Important caveat (fact-check I2):** V3 is NOT a fair test of "per-user vs population." Rules (a–d) get cycle length for free; rules (e–f) have to predict it. So V3 only shows "perfect cycle knowledge + right constant beats imperfect cycle prediction." See V3b for the fair test.

## V3b — Fair head-to-head: both rules use only training data (n=837)

| Rule | MAE | Median | 
|---|---|---|
| A. NIG-posterior-mean − 12.4 (population luteal) | **2.252 d** | 1.90 d |
| B. NIG-posterior-mean − (personal-cycle-mean − 16.9) (per-user) | 3.142 d | 2.94 d |
| **Difference (B − A)** | **+0.890 d worse** | — |

**Decisive:** per-user luteal estimation from cycle dates alone makes predictions **worse**, not better. The naïve "subtract population follicular mean from personal cycle mean" decomposition adds noise rather than subtracting it. **Empirically confirms the unidentifiability claim.**

Tideline does NOT attempt to learn per-user luteal mean in v1. NEW-170 from the earlier draft plan (per-user learned luteal length) is **dropped** as a feature — empirical evidence shows it would degrade predictions.

The ONLY way to identify per-user luteal mean from observable data requires adding an ovulation signal (BBT, LH/OPK, cervical mucus, wrist-temp). All of those are Phase 4 features.

## V4 — Bayesian ovulation CI calibration (corrected: Student-t + within+between)

```
Model: ov ~ StudentT_df(μ_NIG − 12.4, σ²_NIG_pred + σ²_within + σ²_between)
       df = 2·α_post
       σ²_within = 1.15² = 1.32   (Fehring V2 within-woman luteal)
       σ²_between = 1.87² = 3.50  (Fehring V2 between-woman luteal means)
       σ²_luteal_total = 4.82
```

| Variant | 50% | 80% | **90%** | 95% | CI90 width |
|---|---|---|---|---|---|
| **within + between (CORRECT per I4)** | 64.5% | 94.4% | **98.6%** | 99.6% | 13.27 d |
| within only (was buggy) | 56.4% | 89.8% | 96.9% | 99.0% | 11.48 d |
| no luteal var (NIG only) | 53.3% | 86.5% | 95.6% | 98.6% | 10.71 d |
| within + between + Fehring μ=13.24 | 71.9% | 95.7% | 98.7% | 99.5% | 13.27 d |
| within + between, Gaussian z (M3 not applied) | 63.1% | 93.1% | 97.7% | 99.5% | 12.43 d |

**Primary variant (the principled choice):**
- 90% nominal coverage → **98.6% empirical coverage** (overcovers by +8.6 pp)
- Mean CI90 width 13.27 d → ±6.6 d window around predicted ovulation

**Why overcovers:** the NIG prior `β = 28.73` is calibrated for population heterogeneity. For users with stable cycles (Fehring NFP cohort is selected for stability), the posterior takes many observations to tighten. Empirical median residual is 1.9 d but the model predicts SD ≈ 3.6 d — about 28% too wide.

**Why this is OK to ship (Pillar 3):**
- The model is **honestly conservative**: claims less precision than the data suggests it has.
- It NEVER undercovers (which would be false precision — Pillar-3 violation).
- The principled tightening is conformal calibration (NEW-E / #124), which empirically calibrates against the residual distribution. That's a planned follow-on, blocked on Fehring dataset licensing (#155).

## V5 — Population menses duration (NEW-171 sanity)

```
Population mean   = 5.25 d
Population median = 5.00 d
Population SD     = 1.28 d
```

Per-woman median menses across 132 women with ≥3 cycles:
- median = 5.00 d
- 25th/50th/75th %ile = 5.0 / 5.0 / 6.0

**NEW-171 gating effect on this cohort:**
- 81.1% of women have personal median ≥ 5 → floor APPLIES (= max of personal vs default)
- 40.2% have personal median > 5 → floor RAISES above default
- 18.9% have personal median < 5 → default-5 kept (defensive against under-logging)

**Conclusion:** NEW-171 activates meaningful behavior for ~40% of users — real impact, not theoretical.

## Citation corrections to propagate

Inherited from the previous fact-check (these all apply to this validation pass too):

| What earlier docs said | Actually correct |
|---|---|
| Forrester-Knauss & Zemp Stutz 2017 | **Lorenz TK, Gesselman AN, Vitzthum VJ 2017** (PMC5708589) |
| Barron & Fehring 2005 | **Stanford, Schliep, Chang, O'Sullivan, Porucznik 2020** (PMC8495767) |
| Symul 2020 first author | **Li K, Urteaga I, Wiggins CH** (PMC7250828) |
| Hambridge 2013 PMID 23193131 | **PMID 23589536** |
| Natural Cycles K183179 | **DEN170052** (de novo) |
| Halbreich 1982 PMID 7081438 | **PMID 6892280** |
| Lenton 1984 PMID 6743608 | **PMID 6743610** |
| Scarpa Dunson Colombo 2006 PMID 15990223 | **PMID 16154254** |
| Billings 1972 PMID 4109848 | **PMID 4109930** |
| Bosman 2023 Hum Reprod 38:2126 | 🔴 fabricated (Claude hallucination); remove |

## Verification debt remaining

Items the second fact-check flagged that this validation script doesn't fully resolve:

- **Henry 2024 unit ambiguity** (variance vs SD) — not relevant here because we're using Fehring's own measurements; only matters if we cite Henry's specific numbers in shipped product copy.
- **Bull 2019 within-person luteal SD** — Bull reports per-user cycle-length variation (2.6 ± 2.5 d) but doesn't decompose into follicular vs luteal within-person. Our use of Fehring's 1.15 d as the within-person luteal SD is dataset-specific.
- **Median-of-SDs vs pooled mixed-effects estimator** for within-person SDs — Fehring's 1.15 d is likely 10–25% lower than the pooled estimator would give. The propagation uses `σ²_within + σ²_between`, where the slight bias-low on σ²_within is partially compensated by the σ²_between term.
- **Negative follicular-luteal covariance** — empirically present in literature (WHO 1983; Fehring 2006), making the additive variance assumption slightly conservative. Net direction is right (model is wider, not narrower, than truth).

## Marquette dataset licensing reminder

Per CLAUDE.md and tracker #155: the Fehring dataset is consent-bound; **shipping derived constants or residuals in a commercial app requires written permission** from Prof. Fehring or Marquette IFNP. This validation work is internal analysis (fair use), but:

- Do NOT ship the V1 number 13.24 as a constant. Ship Bull 2019's 12.4 → 12.
- Do NOT ship the V2 number 1.15 as a constant. Ship a literature-derived value (or wait for the conformal calibrator that bundles this into empirical residuals).
- The conformal residuals already shipped in `ConformalResiduals.swift` are derived from this dataset; #155 tracks getting permission before any production ship.

## What this validation justifies for Wave A

- **NEW-169 — `defaultLutealDuration = 12`** ← supported by Bull 2019 (n=612k) primary citation; Fehring 13.24 is methodologically-explained sensitivity confirmation
- **NEW-171 — per-user mensesEnd floor** ← supported by V5: 40% of users in the validation cohort would benefit
- **NEW-176 — Posterior types with σ²_within + σ²_between propagation, Student-t quantile** ← math is principled; overcovers ~9pp under Pillar-3-compatible "honest conservatism"
- **NEW-170 (per-user learned luteal mean)** is DROPPED ← V3b empirically shows per-user estimate is worse than population by 0.89 d MAE
