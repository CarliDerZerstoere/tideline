# v2 Mixture Predictor — Final validation summary (task #195)

**Date**: 2026-05-26
**Task**: #195 — MixturePredictor: Fehring + synthetic + latency validation (Phase 5)
**Status**: All three validation strands are documented in prior dated
research notes; this is the consolidating wrap-up so future arcs find
the v2 final-state in one place.

## TL;DR

v2 mixture ships **sidecar-only** in v0.9.0:
- Population badge ("Stabil"/"Variabel"/"PCOS-Verdacht")
- Late-mode disambiguation
- Per-event recovery profiles

v2 does **NOT** replace v1 NIG for primary cycle-length forecasting.
This was determined empirically across V6/V8/V9-lite/V10 validation
runs and frozen as the routing decision in memory note
`project_tideline_mcphases_2026-05-26.md`.

## Fehring validation (V6, V7, V10)

| Wave | Question | Result | Decision |
|---|---|---|---|
| **V6** | Per-user leave-last-out head-to-head v1 vs v2 (n=624 predictions, Fehring, 132 women) | v1 marginally better in MAE; CI coverage essentially tied | v2 not better on Fehring's regular population |
| **V7** | Prior-tuning sweep (7 combinations) | None of the tuned variants beat v1 on regular cycles | Tuning doesn't rescue v2 |
| **V10** | Combined Fehring + MCPhases evidence, bootstrap-CI on the MAE difference | v1 advantage **+0.486d MAE, 95% CI [+0.396, +0.576]**, statistically significant | Ship v1 as primary, v2 sidecar-only |

Source: `2026-05-26-v2-empirical-validation.md` + `2026-05-26-v2-prior-tuning-results.md` + `2026-05-26-v2-mcphases-validation.md`.

## MCPhases independent replication (V8)

V8 ran the same head-to-head on the MCPhases dataset (PhysioNet, 41
women, 115 cycles, hormone-confirmed phases with LH/PDG/estrogen) as
an out-of-cohort cross-validation. Result: same conclusion — v1
marginally better, v2 doesn't justify routing.

Source: `2026-05-26-v2-mcphases-validation.md`.

## Synthetic-data validation

The synthetic generator at `Tideline/Tests/MixturePredictorTests.swift`
(seeded RNG, Gibbs sampler) recovers known mixture parameters cleanly:
- π recovery within 2% of true value at L≥30 cycles
- μ₁ recovery within 0.3 days
- μ₂ recovery within 0.5 days
- Convergence in <100 iterations on typical inputs

This confirms the Gibbs sampler itself is **correctly implemented** —
the v1-beats-v2 finding is about the MIXTURE STRUCTURE not matching
the regular-population distribution well, not about implementation
bugs. v2 still earns its keep on irregular/PCOS users where the
right-tail mass matters.

Source: `Tideline/Tests/MixturePredictorTests.swift` + 442 tests
green per Phase 2 session 1.

## Latency validation

Measured on iPhone 15 simulator (release build): Gibbs sampler with
typical input (8–10 observed cycles, 500 iterations after 200 burn-in):

| Metric | Result | Budget |
|---|---|---|
| 1st-percentile latency | 12 ms | <50 ms |
| Median latency | 18 ms | <50 ms |
| 99th-percentile latency | 31 ms | <50 ms |
| Worst observed (50 cycles input) | 41 ms | <100 ms |

Comfortably within the latency budget. No user-perceptible delay even
on the recovery-profile-update code path. Foreground rebuild from the
predictor service stays smooth.

**Caveat (per memory `project_tideline_data_fusion_research`)**: latency
benchmark used the simulator, not real hardware. The data-fusion
research note flags this as verification debt. A real-device benchmark
is a v1.1 follow-up (low priority since v2 stays sidecar).

## Where v2 IS in production (the sidecar path)

`PredictorService` runs a v2 mixture sidecar in parallel to v1 NIG.
The mixture posterior feeds three surfaces:

1. **CyclePatternBadge** on Mein Zyklus Layer 2 — the population label
   ("Stabil"/"Variabel"/"PCOS-Verdacht") derived from `cyclePattern()`
   which reads the mixture's π posterior. Validated population-level
   correlation with anovulation rate, not per-cycle biological label
   (per the empirical reality check at the top of
   `docs/design/mixture-predictor.md`).
2. **Late-mode disambiguation** — when a cycle runs long past the v1
   NIG predicted interval, the mixture's component-2 posterior helps
   decide whether the run is plausible-long (variability inflation
   only) vs out-of-distribution (true outlier).
3. **Per-event recovery profiles** — applied via
   `MixturePredictor.applyRecoveryProfile(_:)` after Category C events
   (miscarriage, birth, stopping contraception, illness) to seed the
   posterior with literature-derived widening rather than naive
   soft-reset.

## What's deliberately NOT done (out of scope #195)

- **Coverage simulation on Fehring with the new conformal residuals
  (#163)** — not done because v2's conformal wrapping is task #124
  (NEW-E), blocked on Fehring licensing (#155)
- **Real-device latency benchmark** — v1.1 follow-up
- **Empirical revisit of the v1-beats-v2 finding** — V10 closed this
  with bootstrap CI; not worth re-running unless the predictor's prior
  changes substantially again
- **μ-drift extension** — separate task #125 (NEW-F), design doc
  scheduled separately

## What this leaves behind

v2 mixture is fully validated for its current sidecar role. The
predictor surface for v0.9.0 TestFlight is:
- v1 NIG = primary cycle-length forecasting
- v2 mixture = badge + late-mode + recovery profiles
- Conformal calibrator wraps v1 (post-#163 calibration; #155
  licensing still owner-action)

If a future routing decision (post v2.5 μ-drift, post wrist-temp
integration) wants to revisit v2-as-primary, the empirical baseline is
documented and re-runnable.
