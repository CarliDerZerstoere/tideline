# v2 Mixture Predictor — Empirical Validation against Fehring n=1,508

**Date:** 2026-05-26
**Scope:** Session 4 / #195 partial — empirical comparison of v1 (single-component NIG) vs v2 (2-component Bayesian mixture) on the Fehring NFP dataset.
**Method:** Per-user leave-last-out calibration. Python ports of both predictors in `data/validate_phase_predictor.py` § V6.
**Decision:** **Do NOT ship Session 5 full routing.** v2 stays sidecar-only for badge + late-mode + recovery profiles.

---

## Headline numbers

Per-user leave-last-out, 624 predictions per model across 103 women (cycles ≥7 per woman after Fehring's clinical filter [21, 45] d).

### Overall

| Model | 80% coverage | 90% coverage | 95% coverage | MAE | width₈₀ | width₉₀ |
|---|---|---|---|---|---|---|
| v1 (NIG) | 87.8% | 94.6% | 98.4% | **1.90 d** | **7.4 d** | **9.6 d** |
| v2 (mixture) | 92.0% | 97.9% | 100.0% | 2.39 d | 9.1 d | 15.3 d |

v1 is **over-conservative** (over-covers target 80%); v2 is **even more over-conservative**. v2's interval width at 90% is 1.6× wider than v1's. v2's MAE is 26% worse.

### PCOS-like subset (any cycle ≥ 43 d in history) — n=4 women, 14 predictions per model

| Model | 80% coverage | 90% coverage | 95% coverage | MAE | width₈₀ | width₉₀ |
|---|---|---|---|---|---|---|
| v1 | 71.4% | 92.9% | 92.9% | 5.42 d | 13.7 d | 17.9 d |
| v2 | 92.9% | 92.9% | 100.0% | 5.11 d | 15.4 d | 22.5 d |

Directionally v2 helps at 80% (closer to target 80%); MAE marginally better (5.11 vs 5.42). **Sample too small (14 predictions) to draw confident conclusions.**

### Regular subset (all cycles <43 d) — n=99 women, 590 predictions per model

| Model | 80% coverage | 90% coverage | 95% coverage | MAE | width₈₀ | width₉₀ |
|---|---|---|---|---|---|---|
| v1 | 88.2% | 94.6% | 98.5% | **1.82 d** | **7.2 d** | **9.4 d** |
| v2 | 92.0% | 98.0% | 100.0% | 2.33 d | 9.0 d | 15.1 d |

v2 systematically **worse** for the 96% of Fehring women in this subset.

---

## Decision rule from the plan

From the Session 4 plan:

> Based on validation results, Session 5 splits into branches:
> - **Branch A** (v2 materially better-calibrated): proceed with full routing
> - **Branch B** (v2 marginal): defer full routing
> - **Branch C** (v2 worse for some subset): refine the graduation logic

**The data lands on Branch C**, mixed with Branch B:

- v2 is **worse** for regular users (96% of Fehring): wider intervals, worse MAE, more over-conservative coverage.
- v2 is **directionally better** for PCOS-like users at 80% confidence, but the Fehring PCOS subset (n=4) is too small to confirm.
- Both models are over-conservative — neither hits the 80% target.

**Conclusion:** Session 5 should not blanket-route v2 across all non-late-mode predictions. Doing so would make 96% of users see worse predictions to help (possibly) 4%.

---

## Why v2 underperforms for regular users on this dataset

Three mechanical reasons, all are tunable:

1. **Beta(8, 2) prior on π is too soft.** For users with all cycles ~28d, the prior keeps posterior π near 0.8, leaving ~20% predictive mass on the anovulatory component 2. That widens the predictive interval and pulls the point estimate toward the Jensen-corrected log-normal mean (~42d × 0.2 = 8d of pull) — explaining the MAE inflation.

2. **Component 2 prior σ₂² is wide.** σ₂=0.45 in log space gives original-scale support roughly 25–75 d. Component 2 mass within that range can't be ruled out by data on the [21, 45] interval (Fehring's clinical filter). The mixture can never *prove* a user is purely ovulatory; it can only push π high.

3. **Fehring's filtering selects against PCOS.** Cycles outside [21, 45] are excluded by the NFP-study clinical filter that the validation script applies before V6. Real-world PCOS users routinely log cycles >45 days; the dataset under-represents the exact population v2 was designed for.

---

## Implications for Session 5

### Don't do

- ❌ Blanket-route all non-late-mode predictions through v2 for N≥12 users. The Fehring evidence says this would harm 96% of typical users.

### Do consider

- ✅ **Selective routing**: switch to v2 only when (a) user has self-declared PCOS via `declareOngoingIrregularity`, or (b) the pattern indicator shows `.occasionallyAnovulatory` / `.oftenAnovulatory`. For `.mostlyOvulatory` users, stay with v1. This protects the 96% from v2's over-conservatism while still serving irregular users.

- ✅ **Tune v2's priors** before routing. Specifically: tighten Beta-prior on π (e.g. Beta(15, 2) → E[π]=0.88), or shrink σ₂² (e.g. 0.30 instead of 0.45). Re-run V6 after each tuning to verify it doesn't break the PCOS path. Tunings can be band-aware: PCOS-declared users keep Beta(3, 5).

- ✅ **Validate against a wider dataset before shipping**. The Fehring filter excludes the PCOS-like tail v2 cares about most. Options: (a) keep Fehring with a relaxed cycle filter, (b) supplement with the AWHS 2023 published distributions, (c) hand-construct synthetic PCOS validation set with known truth.

- ✅ **Keep current v2 sidecar uses**. Sessions 1 (badge), 2 (late-mode interval), 3 (recovery profiles) all already pay their way: they activate when the math actually applies. The damage was specifically in the proposed Session 5 blanket-routing.

### Punt

- 🟡 ConformalCalibrator extension (#124) is still the right unblocker for v2 routing in the long term, but the priors need re-tuning first.

---

## Validation script

`data/validate_phase_predictor.py` § V6 (added 2026-05-26). Run via `data/raw/.venv/bin/python data/validate_phase_predictor.py`.

Python port of `Tideline/Sources/Services/MixturePredictor.swift` lives in the same file: `class MixtureRNG`, `class MixturePredictor`. Same priors, same Gibbs algorithm, same H-Z hard threshold. xorshift64 RNG matches Swift bit-for-bit (verified by parity test #192 in Swift; not yet cross-language verified — open follow-up).

V6 output is deterministic (seed=42). Reproducible.

---

## Honest caveats

1. **Per-user leave-last-out underrepresents short-history users.** Excluded 54 women with <7 cycles. The cold-start regime (N<12) is exactly when graduation hasn't happened anyway, so this matches production.

2. **PCOS subset (4 women, 14 predictions) is statistically weak.** Directional findings only.

3. **Fehring NFP cohort is self-selected for regularity.** Population effect size for v2 is likely understated; we don't know by how much.

4. **Both predictors are over-conservative.** That's a finding worth noting independently — neither is properly calibrated. v1's 95% CI covers 98.4% (3-4pp over target); v2's covers 100%. The conformal calibration wrapper (#114) was supposed to fix v1's over-conservatism; we should re-run the conformal residual extractor against the current NIG prior (#163) and see if v1 + conformal hits the target.

5. **Validation script's Python port could diverge from Swift's behaviour.** Cross-language RNG parity isn't tested. A spot-check on synthetic data with known truth would close the gap; tracked as #192 follow-up.

---

## Next steps

1. **Session 5 = NOT blanket routing.** Session 5 candidate becomes: tune v2 priors via V6 iteration + implement selective routing (`mostlyOvulatory` → v1, others → v2).

2. **Re-run conformal residual extractor (#163).** Existing residuals in `Tideline/Sources/Services/ConformalResiduals.swift` use old NIG prior; refresh against current.

3. **Cleanup follow-ups from Sessions 1–3 (#190 NaN→Optional, #191 stability test, #192 RNG parity) still happen this session.** Independent of the routing decision.

4. **Update `docs/design/mixture-predictor.md`** with the empirical findings + revised Session 5 plan.

5. **Long-term**: investigate datasets with adequate PCOS representation for Phase 5 final validation before any shipping decision.
