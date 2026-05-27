# μ-drift Random Walk Inside the Gibbs Sampler (v2.5 design)

**Status**: design doc, implementation deferred to post-launch per
canonical roadmap memory `[[project-tideline-predictor-roadmap]]`.
Task #125 (NEW-F).

**Date**: 2026-05-26 (design only; deferring code per roadmap).

## Problem this solves

The current v1 NIG predictor and v2 mixture sampler assume the user's
**mean cycle length μ is fixed over time** within a session. That's
fine for short windows but inaccurate over the timescales Tideline
actually serves:

- **Perimenopause** (gradual cycle-length increase from late 30s
  through mid-40s): user's μ literally shifts upward by 2–4 days over
  3–5 years. Without drift, old data anchors the posterior to a μ that
  no longer applies.
- **Postpartum recovery** (cycle length gradually shortens from ~40d
  postpartum-1 toward the user's baseline): μ shifts downward as
  cycles stabilise.
- **Adolescent stabilisation** (gynecologic-age 0–5 years): μ slowly
  decreases from initially-irregular high values toward adult-stable
  ~28.7. Linked to task #138 (NEW-L) gynecologic-age-stratified prior.
- **Lifestyle changes** affecting baseline (significant weight change,
  chronic illness, post-OCP recovery): same shift mechanism.

Today's predictor treats these as "events" requiring explicit recovery
profiles (Category B/C). That works for sharp transitions; it doesn't
handle smooth drift.

## Proposed approach (post-launch v2.5)

Add a **random-walk prior on μ** between observations, parameterised
by a single drift scale `τ_μ`:

```
μ_{t+1} | μ_t ~ Normal(μ_t, τ_μ²)
```

This makes μ a time-varying state rather than a fixed parameter.

### Implementation sketch (v2 mixture path; analogous for v1)

In the Gibbs sampler at `Tideline/Sources/Services/MixturePredictor.swift`:

1. **Augment state**: instead of one μ₁ per chain, track a sequence
   `μ_{1,t}` indexed by cycle position t.
2. **Forward-backward sweep**: in the Gibbs iteration, after sampling
   the component assignment z_t for each cycle:
   - Forward filter: `μ_{1,t}` given `μ_{1,t−1}` and cycle length L_t
     in assigned component
   - Backward smoother: refine `μ_{1,t}` using future observations
     (Kalman smoothing within the Gaussian sub-model)
3. **Predict next**: the predictive μ for "next cycle" reads
   `μ_{1,T}` (the latest filtered state), not the average over
   history.
4. **Hyperparameter**: `τ_μ` = 0.15 days/cycle as a starting point.
   Order-of-magnitude estimate: for ≥1-day shift over 10 cycles,
   τ_μ needs to be at least sqrt(1/10) ≈ 0.32 d/cycle. Too small =
   no drift; too large = noise-driven over-fitting. Start tight,
   relax if Fehring shows underfit.

### Why a Kalman-style approach inside Gibbs

The forward-backward sweep is a closed-form Gaussian update because
the random-walk prior + Gaussian likelihood is the textbook linear
state-space model. No additional MCMC required — just one
matrix-vector pass per Gibbs iteration. Adds ~5–10% to sampler
latency at current input sizes.

Reference: Durbin & Koopman 2012, *Time Series Analysis by State Space
Methods* (2nd ed.), Ch. 4 — closed-form filter + smoother for the
local-level model. (Real reference, textbook, no PMID.)

## v1 NIG path

For the v1 NIG predictor, the analogous extension is easier: weight
observations by an exponential decay `λ ∈ (0, 1]` with effective
sample size `n_eff = (1 − λⁿ) / (1 − λ)`. As n grows, `n_eff →
1/(1−λ)`, so old observations stop accumulating κ. This implements
"forgetting" without needing the full Kalman machinery.

A `λ = 0.95` choice gives `n_eff_∞ = 20`. Tideline's NIG converges to
mostly-data within ~10 cycles; with λ = 0.95 it'd cap at ~20 cycles'
effective weight, matching realistic drift timescales.

## Why deferred to post-launch (v2.5)

Per roadmap memory `[[project-tideline-predictor-roadmap]]`:
*"v2 conformal + v2.5 μ-drift + v3 wrist-temp (10–18%, not 20–30%);
skip stress/sleep covariates"*.

Specific reasons to defer:

1. **v2 mixture is sidecar-only** (per V10 findings). μ-drift's primary
   benefit is in the mixture's primary predictor role, which doesn't
   ship in v0.9.0.
2. **Real-world drift signals come from TestFlight cohorts** — without
   user data showing actual drift patterns, we'd be tuning τ_μ on
   Fehring's regular-population residuals (where drift is small) and
   missing perimenopausal cohorts (where drift matters most).
3. **Adolescent gynecologic-age work (#138, blocked on #127) needs to
   land first** — its prior structure may inform how μ-drift parameters
   change with age band.
4. **Conformal calibration (#163) just shipped** — stacking another
   math change on top before observing v0.9.0 behavior would entangle
   debugging.

## When this gets implemented (sequencing)

Natural sequence post-TestFlight:
1. v0.9.0 ships, internal tester feedback for 2-4 weeks
2. If feedback includes "predictions are off after multi-month
   absence" or "perimenopausal patterns aren't captured" — μ-drift
   moves from v1.1 to v1.0.1 (urgent)
3. Otherwise, μ-drift lands as v1.1 feature work alongside
   wrist-temperature pipeline (#10) and v3 expansion

## Files to modify when implementation begins

| File | Change |
|---|---|
| `Tideline/Sources/Services/MixturePredictor.swift` | Add μ-drift random walk inside the Gibbs sweep. New `tauMu` parameter on init |
| `Tideline/Sources/Services/CyclePredictor.swift` | Add exponential-decay weighting on observations. New `lambda` parameter |
| `Tideline/Sources/Services/PredictorService.swift` | Wire drift parameters from age-band defaults |
| `Tideline/Sources/Models/AgeBand.swift` | Add per-band drift hyperparameters (τ_μ + λ) |
| `Tideline/Tests/MixturePredictorTests.swift` | Synthetic-drift recovery test |
| `data/extract_conformal_residuals.py` | Re-extract once drift is enabled |

Estimated effort: 5–7 dev-days for full implementation + validation.

## Open questions for the implementation session

1. **Should λ in v1 be age-band-dependent?** Older users (perimenopause)
   have faster real drift → maybe λ = 0.92 for perimenopausal band,
   λ = 0.95 for reproductive.
2. **How is drift initialised on a fresh user?** Probably: until n≥5
   cycles, behave like fixed-μ predictor (no drift); enable drift
   once enough data accumulates.
3. **Should the conformal residuals be re-extracted with drift
   enabled?** Yes — drift changes the residual distribution. New task
   would parallel #163.
4. **UX**: should the user see "your predicted cycle length is
   shifting" surfacing on Mein Zyklus? Probably not — drift is meant
   to be invisible adjustment, not a separate feature.

## Out of scope for this design doc

- Coding the implementation (deferred to post-launch session)
- Empirical validation of τ_μ values (needs real-cohort data, not
  Fehring's regular-population)
- Coupling drift to wrist-temperature signal (separate task #10)
