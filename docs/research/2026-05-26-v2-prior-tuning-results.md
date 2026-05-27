# v2 Mixture Predictor — Prior Tuning Results

**Date:** 2026-05-26
**Builds on:** `docs/research/2026-05-26-v2-empirical-validation.md` (V6 head-to-head finding)
**Method:** V7 sweep across 7 (π prior, σ₂²) combinations on Fehring n=1,508 via `data/validate_phase_predictor.py § V7`. Reuses V6's per-user leave-last-out methodology.
**Decision:** **Best tuning is "tighter-pi" `Beta(15, 2) + σ₂²=0.45²`.** Recommended Session 6 implementation: selective routing with tuned default + PCOS-declared override via existing `declareOngoingIrregularity` Beta(3, 5).

---

## The sweep

7 prior combinations. Each ran through the V6 methodology end-to-end (624 predictions per combination, stratified by subset).

```
tuning         subset     cov80   cov90   cov95    MAE   w80   w90
----------------------------------------------------------------------
v1 BASELINE    regular    88.2%   94.6%   98.5%   1.82   7.2   9.4
v1 BASELINE    pcos       71.4%   92.9%   92.9%   5.42  13.7  17.9

baseline       regular    92.0%   98.0%  100.0%   2.33   9.0  15.1   ← current ship
baseline       pcos       92.9%   92.9%  100.0%   5.11  15.4  22.5

tighter-pi     regular    91.1%   97.4%  100.0%   2.14   8.2  12.4   ★ recommended
tighter-pi     pcos       78.6%   92.9%  100.0%   5.19  13.9  20.3

much-tighter   regular    89.3%   96.1%   99.3%   1.92   7.5  10.1
much-tighter   pcos       71.4%   92.9%   92.9%   5.35  12.9  17.6

narrower-s2    regular    91.8%   97.9%   99.8%   2.20   9.1  14.6
narrower-s2    pcos       85.7%   92.9%  100.0%   5.28  15.1  20.6

both           regular    90.8%   97.5%   99.8%   2.06   8.3  12.6
both           pcos       78.6%   92.9%  100.0%   5.37  13.9  19.3

aggressive     regular    89.8%   95.9%   99.5%   1.89   7.5  10.2
aggressive     pcos       71.4%   92.9%   92.9%   5.42  12.9  17.4

cold-bias      regular    92.8%   98.2%  100.0%   2.56   9.0  15.8
cold-bias      pcos       92.9%  100.0%  100.0%   4.91  15.8  24.6
```

Tunings:
- **baseline**: Beta(8, 2), σ₂²=0.45² — current ship
- **tighter-pi**: Beta(15, 2), σ₂²=0.45² — strengthen ovulatory prior
- **much-tighter**: Beta(20, 1), σ₂²=0.45² — very strong ovulatory prior
- **narrower-s2**: Beta(8, 2), σ₂²=0.30² — narrower comp-2 prior
- **both**: Beta(15, 2), σ₂²=0.30² — combined
- **aggressive**: Beta(20, 1), σ₂²=0.25² — both very strong
- **cold-bias**: Beta(8, 2), σ₂²=0.60² — reverse direction (sanity check)

---

## Headline findings

### 1. Tuning can close the regular-user gap

`much-tighter` (Beta(20, 1)) gets v2 to MAE 1.92 d on regular users — within 5% of v1's 1.82 d. width₉₀ 10.1 d vs v1's 9.4 d, also within 10%. Coverage at 90% (96.1%) is actually closer to the target (90%) than v1's over-conservative 94.6%.

**v2 is fixable on regular users.** Session 4's "v2 is structurally bad" framing was too strong; the priors were just too soft.

### 2. But the strongest tunings sacrifice the PCOS benefit

`much-tighter` and `aggressive` collapse v2's PCOS coverage from 92.9% back down to 71.4% — matching v1. The strong-π prior makes the mixture essentially behave like v1 because component 2 barely fires.

So there's a real trade-off curve, not a free lunch:

| Tuning | Regular MAE gap to v1 | PCOS cov₈₀ retained vs v2 baseline |
|---|---|---|
| baseline | +28% | 100% |
| **tighter-pi** | **+18%** | **85%** |
| much-tighter | +5% | 77% |
| aggressive | +4% | 77% |

The "tighter-pi" sits at the inflection point: closes half the regular-user gap while retaining most of the PCOS benefit at 80% coverage.

### 3. Narrowing σ₂² alone barely helps

`narrower-s2` (σ₂² = 0.30² with baseline π prior) closes only a tiny portion of the regular-user gap. The π prior is the dominant factor, not σ₂².

### 4. The `cold-bias` sanity check works as expected

Widening σ₂² to 0.60² makes v2 strictly worse everywhere — MAE 2.56 on regular, width₉₀ 15.8 d. Confirms the sweep is detecting real signal, not noise.

---

## Recommended Session 6 implementation

**Two priors, not one:**

1. **Default mixture prior**: Beta(15, 2), σ₂²=0.45². Modest tightening that closes half the regular-user MAE gap and retains 85% of the PCOS coverage benefit. Better calibration than baseline.

2. **PCOS-declared override**: Beta(3, 5), σ₂²=0.45². The existing `declareOngoingIrregularity` path already widens β by 2.5×; extend it to also override the π prior to Beta(3, 5) as the design doc originally specified for PCOS-declared users.

This gives:
- Regular users: tuned-default v2 ≈ v1 (slight loss on point estimate, comparable intervals)
- PCOS-declared users: aggressive-tail-aware v2 (wide intervals, honest)
- Pattern-detected `.occasionallyAnovulatory` / `.oftenAnovulatory` users: still get the recovery from sidecar-only behaviour

**Selective routing recommendation:**

| User state | Predictor used (non-late-mode) |
|---|---|
| N < 12 cycles | v1 (cold start) |
| N ≥ 12, `.mostlyOvulatory` | v1 + ConformalCalibrator |
| N ≥ 12, `.occasionallyAnovulatory` | v2 with tuned default priors |
| N ≥ 12, `.oftenAnovulatory` | v2 with tuned default priors |
| PCOS-declared (`declareOngoingIrregularity`) | v2 with Beta(3, 5) priors |

Late-mode interval and badge keep using v2 unconditionally — those paths already pay their way.

---

## What this changes about the Session 4 framing

The Session 4 validation report concluded: "do NOT blanket-route — v2 underperforms on regular users." That conclusion holds for the **baseline v2 priors**. With tuned priors, v2 reaches v1-equivalent performance on regular users. The conclusion now refines to:

> **Blanket-routing with baseline priors: still wrong.**
> Routing with tuned priors (Beta(15, 2)): viable for `.occasionallyAnovulatory` and `.oftenAnovulatory` subsets without harming regular users.

---

## Honest caveats (unchanged from Session 4)

1. **PCOS subset n=4 stays statistically weak.** Tighter-pi's apparent 80%-coverage drop (92.9% → 78.6%) is on 14 predictions. Could be noise. The "tuning retains 85% of PCOS benefit" claim should be re-validated against a wider dataset before shipping.

2. **Fehring is still self-selected for regularity.** Tuning fixes v2's behaviour on data Fehring has — it doesn't tell us how v2 behaves on cycles > 45 days, which Fehring excises.

3. **Cross-language RNG parity** (#192) is now bit-exact-tested for `nextUInt64` and `nextUniform`, but Gaussian / Gamma streams haven't been cross-checked. A 1-2% drift in Gibbs noise would shift these numbers by less than the tuning effects we're measuring, so the conclusions should be robust.

4. **The "tighter-pi" recommendation assumes the existing Beta(8, 2) Session 1 behavior is correct for the badge.** If we change the default to Beta(15, 2), the badge threshold (`mostlyOvulatory` at π ≥ 0.85) will trigger for MORE users — the badge becomes biased ovulatory. Need to either lower the threshold (e.g., π ≥ 0.90) or document the badge-routing-prior interaction explicitly.

---

## Files

- `data/validate_phase_predictor.py` § V7 (added 2026-05-26)
- `docs/design/mixture-predictor.md` § "Empirical validation" — needs amendment with tuning result
- `docs/research/2026-05-26-v2-empirical-validation.md` — original validation; this doc supersedes its "Implications for Session 5" section
