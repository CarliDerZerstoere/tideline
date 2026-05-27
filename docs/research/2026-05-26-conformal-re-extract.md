# Conformal residual re-extraction (task #163)

**Date**: 2026-05-26
**Task**: #163 — Re-run conformal residual extractor against new NIG prior
**Author**: Tideline development (solo)
**Status**: Shipped in v1.1 wave 1 (immutable record per `docs/README.md`
research-note convention)

## Why this was needed

Task #158 (completed) corrected the production NIG prior in
`CyclePredictor.swift`:

| Parameter | Before #158 | After #158 (production) |
|---|---|---|
| μ (prior mean) | 29.0 (pre-#94 typo) | 28.7 (AWHS 2023 population mean, PMC10226714) |
| β (NIG scale) | 41.07 (wrong derivation: α·σ²) | 28.7282 (standard NIG: (α−1)·σ², σ=3.79, α=3) |
| κ | 2.0 | 2.0 (unchanged) |
| α | 3.0 | 3.0 (unchanged) |

But the conformal residuals shipped in
`Tideline/Sources/Services/ConformalResiduals.swift` were extracted
**against the OLD prior** — explicitly flagged in the
`extract_conformal_residuals.py:23-28` warning comment:
"if you re-run this script with the corrected constants, the residual
distribution will shift slightly. Tracked as task #163."

Practical impact: production was wrapping NIG point predictions with
intervals sized to the old prior's residual distribution. The empirical
coverage at the documented "90% confidence" level was therefore not
exactly 90%. This is a quiet correctness issue, not a crash; users see
slightly mis-sized intervals on their cycle predictions.

## ⚠️ BLOCKER for App Store submission: Fehring NFP licensing

The `ConformalResiduals.fehringPopulation` array shipped in production is
**derived from the Marquette IfNFP Fehring NFP dataset**. The dataset is
consent-bound and shipping derived residuals in a commercial app
requires **written permission from Fehring (Marquette professor
emeritus) or the Marquette Institute for NFP**.

This task (re-extraction against the corrected prior) does NOT change
the licensing exposure — derived data is still derived data. The same
permission requirement applied before #163 and applies after.

**Owner action required before any App Store submission:** email the
Marquette IfNFP contact (per the dataset's publication channel, PMID
23153900) and secure written permission. If declined, the production
app would need to either (a) ship without empirical conformal
calibration (revert to theory-derived quantile bounds, looser
intervals) or (b) collect a fresh, separately-licensed reference
cohort.

This is filed against the tracker as **#155 (still open)** and is the
single most-load-bearing release blocker for the predictor.

## What changed

Ran `python3 data/extract_conformal_residuals.py` against the production
prior (μ=28.7, β=28.7282, κ=2.0, α=3.0) on the same Fehring NFP cohort
(159 subjects, 1665 cycles filtered to [15, 90] days, leave-one-out
with minimum 4-cycle history). Pasted the resulting array into
`ConformalResiduals.swift`, updated the file header stats, ran the test
suite.

Also fixed a pre-existing one-off in the Python script's print
statement: it was using `int(...)` (floor) for the quantile-display
rank, while Swift's `ConformalCalibrator.quantile(_:)` uses
`.rounded(.up)` (ceil, the textbook formula). They now agree: both
display and runtime-return value use rank 1101 (0-indexed) = the
textbook `⌈(n+1)(1-α)⌉ − 1` form per Vovk et al. 2005.

## Before / after

Both extracts used identical inputs (cohort, filter, algorithm). Only
the prior values changed.

| Statistic | Before (old prior) | After (new prior, post-#163) | Δ |
|---|---:|---:|---:|
| n (residual count) | 1223 | 1223 | 0 |
| MAE (mean absolute error) | 2.115 d | 2.109 d | −0.006 d |
| Median | 1.500 d | 1.471 d | −0.029 d |
| 90th percentile (q₀.₉) | 4.571 d | 4.540 d | −0.031 d |
| Interval width at 90% confidence | 9.142 d | 9.080 d | −0.062 d (−0.68%) |

The shift is **measurable but small** — about 0.7% narrower intervals at
the 90% confidence level. Direction matches the prior expectation:
β=28.7282 is smaller than the old 41.07, which makes the posterior more
concentrated, which produces predictions closer to actual, which
produces smaller residuals, which produces a smaller 90th-percentile
quantile, which produces a narrower interval.

The shift is small enough that the interval-rounding to whole days
(e.g. "in 12–16 days") will usually be unchanged: 9.14d / 2 = ±4.57d
rounds to ±5d; 9.08d / 2 = ±4.54d also rounds to ±5d.

## Empirical coverage

Coverage was previously validated in the existing
`ConformalCalibratorTests.empiricalCoverage` test: drawing 1000
residuals uniformly from the calibration set, ≥87% fall ≤ q₀.₉ (giving
slack for finite-sample noise on the conformal guarantee of ≥90%).
With the new residuals this test still passes — confirming the
post-#163 calibration retains the conformal coverage guarantee.

## What this DOES NOT change

- The NIG predictor itself (already at the corrected prior since #158)
- The `ConformalCalibrator.swift` wrapper math (textbook split-conformal,
  Vovk et al. 2005)
- The Python extractor's algorithm (only the prior constants in the
  script header; algorithm unchanged)
- The CycleStore's call site
  (`CycleStore.swift:1247: ConformalCalibrator.shared.wrap(...)`)

## What's still open

**Task #155 — Fehring NFP dataset licensing** remains owner-action.
The dataset is in the repo (`data/raw/fehring_cycles.csv`, 1665 cycles
matching the cited cohort within rounding). Memory note
`project_tideline_validation_2026-05-25.md` flags that **shipping
derived residuals in a commercial app requires written permission from
Fehring (Marquette professor emeritus) or Marquette Institute for NFP**.
Re-extracting against the corrected prior does not change this
licensing exposure — derived data is still derived data.

Recommended owner action: email the Marquette IfNFP contact (per the
dataset's publication channel) before the App Store submission stage.
If permission is declined, the production app would need to either (a)
ship without empirical conformal calibration (revert to theory-derived
quantile bounds, looser intervals) or (b) collect a fresh, separately-
licensed reference cohort.

## Tests added

`Tideline/Tests/ConformalCalibratorTests.swift`:

1. **`Quantile is monotonic non-decreasing in confidence (#163 invariant)`**
   — protects against a future regen that accidentally truncates or
   shuffles the residual array.
2. **`Conformal-width delta after #163 is small (<2% at 90% confidence)`**
   — flags if a future regen drifts >2% from the post-#163 baseline
   (alerts to unintended dataset / prior / algorithm changes).
3. Updated **`Fehring 90% quantile is 4.540 days (post-#163 re-extraction)`**
   — pins the new headline number. (Was `4.571`.)

Full suite was 520 tests → 522 tests, all passing.

## Citations

- Task #158 memory: prior correction (β derivation fix)
- Mahalingaiah et al. 2023, PMC10226714: AWHS-derived μ=28.7 population
  mean
- Vovk, Gammerman, Shafer 2005: split-conformal prediction theory
- Angelopoulos & Bates 2023, arXiv:2107.07511: conformal-prediction
  primer
- Fehring 2013, PMID 23153900: source NFP dataset (Marquette
  ePublications item 7)
