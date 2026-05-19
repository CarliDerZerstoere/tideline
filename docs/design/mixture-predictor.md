# Mixture Predictor — Design Note (Option D)

**Status:** Draft for review
**Date:** 2026-05-19
**Scope:** Architecture, distributional families, inference algorithm, and per-event recovery profiles for Tideline's next-generation cycle predictor.
**Supersedes:** the single Gaussian Normal-Inverse-Gamma model in `Tideline/Sources/Services/CyclePredictor.swift`.
**Evidence base:** `research/2026-05-19-mixture-predictor-verified.md` (verified primary sources only).

---

## Context

The current `CyclePredictor` is a Normal-Inverse-Gamma conjugate model with a single Gaussian likelihood over cycle length. Clinical fact-check identified four structural problems:

1. **Right tail.** Cycle length has a long right tail (Apple WHS 2023, Bull 2019); a Gaussian assigns essentially zero probability to cycles >42 days, which catastrophically misses anovulatory cycles.
2. **PCOS misfit.** PCOS users have cycles spanning 35–90+ days with markedly elevated within-user variance (specific SD ranges in the PCOS literature were not verified in our primary-source extraction pass — earlier "SD 10–30 days" figures from un-fact-checked synthesis should not be cited authoritatively); the current `declareOngoingIrregularity()` patch (β × 2.5) gives SD ~5.8 days, which is narrower than even conservative PCOS estimates and is the wrong distributional family besides.
3. **Postpartum misfit.** Postpartum non-breastfeeding cycle 1 is systematically +8 days vs. baseline with SD ~12 days (Jackson & Glasier 2011); current uniform soft reset assumes baseline immediately.
4. **Mixture structure.** The cycle-length distribution is a mixture of qualitatively distinct components (Harlow & Zeger 1991, Guo et al. 2006). A single-component model conflates ovulatory and anovulatory cycles.

Option D replaces the single-component model with a two-component Bayesian mixture, properly handling all of the above.

---

## Principles inherited from prior design docs

This design must respect:

- **`disrupted-cycles.md`:** Five event categories with explicit reactions; user-declarative events; first-class `CycleEvent` model; no streaks; silence is valid.
- **`late-and-missed-periods.md`:** Never go silent; continue showing prediction with widening intervals through late phases; pregnancy test framing limited to population-statistics framing.
- **`CLAUDE.md`:** On-device only; no medical advice; honest uncertainty over false precision; conjugate closed-form math preferred over MCMC for on-device.

---

## Architecture

### Two-component mixture, in log-space

Cycle length L (in days) is modeled as:

```
L ~ π · Component₁(ovulatory) + (1−π) · Component₂(anovulatory)
```

with components:

- **Component 1 (ovulatory):** L | S=1 ~ Normal(μ₁, σ₁²) restricted to L ≥ 15 days. With μ₁ ≈ 28–30 and σ₁ ≈ 3–5, the truncation at 15 is computationally negligible (probability mass below is essentially zero).
- **Component 2 (anovulatory):** log(L − δ) | S=2 ~ Normal(μ₂, σ₂²) with **shift δ = 14 days fixed**. This is a shifted log-normal in original-day space, supported on (14, ∞), naturally right-skewed. (The shift is set to 14 rather than 15 so that legitimate 15-day spotting-to-bleed intervals don't produce log(0) = −∞ if accidentally routed to component 2. Component 1's effective floor stays at 15.)

The original-scale probability density of component 2 includes the Jacobian of the log transform:
```
p₂(L) = (1 / (L − δ)) · φ(log(L − δ); μ₂, σ₂²)
```
where φ is the normal pdf. **Implementations must include the (L − δ)⁻¹ Jacobian factor** — implementing only `Normal_pdf(log(L − δ); μ₂, σ₂²)` is a subtle bug that biases the mixture comparison.

**Why log-normal for component 2, not Weibull?**
Guo et al. 2006 (the seminal mixture paper, verified) uses Normal + shifted Weibull. We deliberately diverge to shifted log-normal because:
1. **Conjugate inference.** Log-transform y = log(L − δ) gives `y ~ Normal(μ₂, σ₂²)`, which has standard NIG conjugacy — the same math as our existing `CyclePredictor`. Weibull has no closed-form conjugate update.
2. **Bortot et al. 2010** (*Biostatistics* 11(4):741–755, verified to exist) establishes that non-Weibull Bayesian frameworks for cycle-length sequential prediction are peer-reviewed and viable; the paper uses a hierarchical state-space approach. We could not access full text to verify the exact likelihood family Bortot uses — so we cite this paper as precedent for "you can be peer-reviewed in this domain without using Weibull," not as direct support for log-normal specifically. Our actual justification for log-normal is conjugate-update tractability (point 1) plus the family's natural fit to right-skewed positive-valued data.
3. **On-device cost.** Weibull would require MCMC or variational inference for parameter inference. Log-normal stays within the closed-form NIG regime, ~10–50× faster per update.

The cost: marginally worse fit to the extreme tail compared to Weibull. Acceptable for v1 given the on-device constraints. Documented here as a known trade-off, not a claim of literature endorsement.

### Mixing weight and transition structure

The mixing weight π = P(next cycle is ovulatory) is modeled as a learnable per-user parameter with Beta prior:

- **Baseline user (no condition declared):** π ~ Beta(8, 2) → prior mean 0.80 (80% of cycles ovulatory)
- **PCOS-declared user:** π ~ Beta(3, 5) → prior mean 0.375 (37.5% of cycles ovulatory)
- **Post-disruption recovery (Category C):** π temporarily lowered for first 3 cycles, then graduates back

**Cycle-to-cycle persistence (HMM extension, deferred to v1.5):** The HMM literature on cycle data (Guo et al. 2006, Harlow & Zeger 1991) suggests positive lag-1 autocorrelation — anovulatory cycles cluster — but specific transition probability ranges (e.g., P(anov | prev anov)) were not verified in our primary-source extraction pass. v1 uses an i.i.d. mixture for simplicity; v1.5 adds the hidden Markov transition layer with a 2×2 transition matrix and Dirichlet priors. Concrete transition probability priors will be re-derived from primary sources when v1.5 is scoped.

### Population priors — calibrated to Apple WHS 2023

From `research/2026-05-19-mixture-predictor-verified.md` (full text accessed):

| Parameter | Source | Value |
|---|---|---|
| Population mean (component 1) | AWHS 2023, n=165,668 cycles | μ₁₀ = 28.7 days |
| Within-person SD by age | AWHS 2023, direct quotes | <20: 5.33, 20–34: ~4.5, 35–39: 3.79, 40–44: ~4.2, 45–49: 5.42, 50+: 11.19 |
| Anovulatory threshold | Harlow & Zeger 1991 | L > 43 days defines "nonstandard" |
| Default anovulatory component centre | Derived from Harlow threshold + heavy right tail | μ₂₀ = log(40 − 15) ≈ log(25) ≈ 3.22 |
| Default anovulatory component spread | Estimated to give realistic right-tail mass | σ₂₀ ≈ 0.45 (gives ~95% range 25–75 days post-shift) |
| Mixing weight (no condition) | AWHS proportions: 86% in 24–38, 5% >38, 9% <24 | Beta(8, 2), E[π]=0.80 |
| Mixing weight (PCOS-declared) | Clinical PCOS phenotype mix | Beta(3, 5), E[π]=0.375 |

**Age-stratified σ₁ prior:** rather than a single σ₁₀ value, use:
```
σ₁_prior(age) ∈ {5.33 (<20), 4.5 (20-34), 3.79 (35-39), 4.2 (40-44), 5.42 (45-49)}
```
Encoded via the prior β: β₀(age) = α₀ × σ₁_prior(age)². α₀ = 3 (constant).

### Why these numbers, not the earlier synthesis numbers

Earlier research-analyst outputs hallucinated specific parameter values that looked plausible but couldn't be traced to primary sources. The values above come from `research/2026-05-19-mixture-predictor-verified.md` which uses only:
- 🟢 **Full text accessed:** AWHS 2023 within-person SDs by age
- 🟡 **Abstract-confirmed direct quotes:** Harlow & Zeger threshold (>43 days)
- 🟠 **Architecture inference:** anovulatory component spread (analyst-elicited from tail behavior)

Where a parameter is analyst-elicited rather than literature-extracted, the design doc says so explicitly. This is the honest path.

---

## Inference algorithm

### Choice: Gibbs sampling (not CAVI)

The on-device inference research suggested CAVI (Coordinate Ascent Variational Inference). The mixture architectures research suggested Gibbs sampling. We choose **Gibbs**.

**Rationale:**
- **Doctrine alignment.** Principle 6 of `disrupted-cycles.md` is "honest uncertainty over false precision." CAVI is a known underestimator of posterior variance — exactly the wrong failure mode for us. Gibbs gives exact posteriors (up to sampling error).
- **Latency budget.** 200 Gibbs iterations on K=2 components, N=50 cycles is estimated 15–25ms on iPhone 14 class (this is unverified — needs benchmarking — but well inside the 100ms target). Gibbs cost is dominated by per-sample assignment draws, which are cheap.
- **Code complexity.** Surprisingly, Gibbs is *simpler* to implement correctly than CAVI for this model: forward-backward responsibilities, conjugate NIG updates per component, Beta-Binomial weight update. ~425 LOC estimated. CAVI's ELBO bookkeeping and digamma-function approximations add complexity.
- **Identifiability.** Gibbs handles label switching with a post-iteration ordering constraint (μ₁ < μ₂_in_original_scale); CAVI handles it via initialization but is fragile to local optima.

**Trade-off accepted:** Gibbs has sampling variance; CAVI is deterministic. For our use case (sub-day-resolution predictions for monthly cycles), Gibbs variance is invisible to users.

### Gibbs sampler structure

For each user, given the user's logged cycle lengths L₁, …, Lₙ:

```
Initialize:
  S_t ← assign each cycle to component via soft priors (shorter cycles → S=1)
  μ₁, σ₁², μ₂, σ₂² ← prior values
  π ← prior mean

For iter = 1 to 200:
  // Sample assignments — ALL DENSITY EVALUATIONS IN LOG-SPACE to avoid underflow
  For t = 1 to n:
    log_p₁ = log(π) + log_normal_pdf(L_t; μ₁, σ₁²)
    if L_t > δ:
      // Note the Jacobian term −log(L_t − δ); this is the log of the shifted-LN density
      log_p₂ = log(1 − π) + log_normal_pdf(log(L_t − δ); μ₂, σ₂²) − log(L_t − δ)
    else:
      log_p₂ = −∞    // component 2 has zero density at L ≤ δ
    // Numerically stable softmax
    m = max(log_p₁, log_p₂)
    p₁_norm = exp(log_p₁ − m) / (exp(log_p₁ − m) + exp(log_p₂ − m))
    S_t ~ Bernoulli(p₁_norm)

  // Sample component 1 params (conjugate NIG)
  Let L^(1) = {L_t : S_t=1}
  Update (μ₁, σ₁²) via NIG posterior on L^(1) — exact existing math from CyclePredictor.observe()

  // Sample component 2 params (conjugate NIG on log scale)
  Let y^(2) = {log(L_t − δ) : S_t=2 AND L_t > δ}
  Update (μ₂, σ₂²) via NIG posterior on y^(2) — same math as component 1, but in log-space

  // Sample mixing weight (Beta-Binomial)
  n₁ = |L^(1)|, n₂ = |L^(2)|
  π ~ Beta(α_π + n₁, β_π + n₂)

  // Enforce identifiability constraint EVERY iteration to prevent label switching
  // Compare original-scale means: μ₁ vs the mean of the shifted log-normal
  // which is exp(μ₂ + σ₂²/2) + δ   (Jensen correction — NOT just exp(μ₂) + δ)
  if μ₁ > exp(μ₂ + σ₂²/2) + δ:
      swap (μ₁, σ₁²) and (μ₂_in_log_space, σ₂²_in_log_space)
      // Note: swapping requires transforming component 1's Normal params to log-scale
      // and component 2's log-Normal params to original-scale. Implementation detail.

Collect last 100 samples for posterior; discard first 100 as burn-in.
Diagnostic: track assignment stability (fraction of S_t identical between iterations i and i+1)
across the last 100 samples; if < 0.9 average, sampler has not converged — bump to 400 total iterations.
```

**Why per-iteration ordering instead of Stephens (2000) post-hoc relabeling:** Stephens's algorithm
is the gold standard for offline analyses where you process all samples after the chain finishes,
but it requires solving an assignment problem and is more code. For K=2 with strong priors that
separately ground each component, the per-iteration constraint catches label switches early and
is both simpler and sufficient. We do not claim to implement Stephens's algorithm.

Total cost per cycle-log update: dominated by ~10,000 log-likelihood evaluations
(200 iterations × ~50 cycles × K=2 components × O(1) pdf evaluations each) plus the
mixing-weight and NIG updates. Estimated **15–25ms on iPhone 14-class hardware**;
must be benchmarked on real device before being treated as fact. Well within the 100ms target.

### Predictive distribution

For predicting the next cycle length, given collected posterior samples:

```
For each sample (μ₁, σ₁², μ₂, σ₂², π) in posterior:
  L_pred ~ {with prob π: Normal(μ₁, σ₁²); with prob 1-π: LogNormal(μ₂, σ₂², shift=15)}

Aggregate L_pred samples → empirical CDF
Report median, 80% CI, 90% CI from empirical CDF
```

This propagates posterior uncertainty correctly into the predictive distribution — including the uncertainty about which component the next cycle will come from.

### Conditional prediction (late period handling)

When a cycle has reached day D without bleeding starting:

```
P(L = D + k | L > D) = ∫ [F(D+k) − F(D)] / [1 − F(D)] over posterior
```

Computed by Monte Carlo over the posterior samples. Wide as D grows; correctly captures both the user's own posterior uncertainty and the right tail of the anovulatory component. Same UX contract as in `late-and-missed-periods.md`.

---

## Per-event recovery profiles

Replaces the uniform `softReset()`. Each Category C event gets its own recovery prior. Values from `research/2026-05-19-mixture-predictor-verified.md`.

### Profile structure

For each event type, store:
- **μ₁ offset:** days added to pre-event μ₁ for cycle 1 (typically 0 to +8)
- **σ₁ for cycle 1:** widened SD reflecting cycle-1 unpredictability
- **σ₁ for cycle 2:** narrower than cycle 1
- **σ₁ for cycle 3+:** approaching baseline
- **π for cycle 1:** lowered mixing weight (more anovulatory)
- **Cycles to baseline:** when to graduate back to standard prior

### The recovery profile table

> ⚠ **Most numerical values in this table are analyst-elicited starting points**, not directly literature-derived. Only the entries with bold-marked sources are anchored to primary-source numerical values; the rest are best-effort starting points calibrated to make the overall recovery trajectories qualitatively match the cited evidence. **Subject to refinement after real-data validation in production.** The point of this table is to give the implementation concrete numbers to ship with; it is not a literature review.

| Event | μ₁ offset | σ₁ cycle 1 | σ₁ cycle 2 | π cycle 1 | Cycles to baseline | Evidence anchor |
|---|---|---|---|---|---|---|
| Medical abortion | +2 | 7 days | 5 days | 0.75 | 2–3 | analyst-elicited; **Schreiber 2011** anchors ovulation timing (20.6±5.1d) only |
| Surgical abortion | +3 | 8 days | 5 days | 0.75 | 2–3 | analyst-elicited; Asherman flag based on **HRU 2024**: 17% IUA (95% CI 11–25%) |
| Miscarriage <10wk | +2 | 6 days | 5 days | 0.75 | 2–3 | analyst-elicited by analogy to medical abortion |
| Miscarriage 10–20wk | +6 | 11 days | 8 days | 0.55 | 3–4 | analyst-elicited; sparse primary literature |
| Live birth, non-BF | +8 | 12 days | 8 days | 0.45 | 4–5 | analyst-elicited; **Jackson & Glasier 2011** anchors first-ovulation range (45–94d) and ovulatory fraction range (20–71%) |
| Live birth, BF (post-resume) | +8 | 12 days | 8 days | 0.40 | 4–5 | analyst-elicited; post-LAM physiology approximated as same as non-BF |
| Stop OCP | +2 | **11 days** | 7 days | 0.65 | **5–9** | **σ₁ from Nassaralla 2011 (cycle 1: 31.5±11.1, n=70, full text)**; **cycle-9 from Gnoth 2002 (n=175, disturbance through cycle 9)** |
| Stop LNG-IUD | +1 | 6 days | 5 days | 0.80 | 1–3 | analyst-elicited (local-action mechanism implies fast recovery) |
| Stop Nexplanon | +3 | 9 days | 6 days | 0.70 | 2–4 | analyst-elicited from Organon clinical data on serum clearance |
| Stop Depo-Provera | +8 | 16 days | 12 days | 0.30 | **6–10** | analyst-elicited σ; **DMPA-IM label: median ovulation 183 days (~6 mo), median conception 10 months, 55% amenorrhea at 12 months** |
| Prolonged illness | +4 | 10 days | 7 days | 0.65 | 2–4 | analyst-elicited; **Meczekalski 2014** anchors FHA spectrum framing |
| EC (follicular phase) | Reject current cycle | — | — | — | 1 | **PMID 18402847 (Hum Reprod 2008)**: follicular-phase EC shortens cycle by 10.9±1d; next cycle unaffected |
| EC (peri/luteal phase) | Observe normally | — | — | — | 0 | **Same source**: no effect on current cycle |

**Reading guide:** "μ₁ offset" is added to the user's pre-event μ₁ for cycle 1's prior location. σ₁ for cycle 1 sets the prior β via β = α × σ₁² (with α = 3). π cycle 1 is the lowered mixing weight for that cycle. Graduation to baseline = restore standard prior over component 1 parameters; component 2 and π priors remain widened slightly longer.

**Bolded numbers** are directly traceable to primary-source extractions in `research/2026-05-19-mixture-predictor-verified.md`. Non-bolded values are analyst-elicited starting points.

### Asherman syndrome flag

For surgical abortion and late miscarriage with D&C: if post-event cycles 4+ remain anomalous (i.e., posterior π stays low or σ₁ stays high), **do not force convergence**. Keep the widened β and lowered π. Reason: ~17% (95% CI 11–25%) of first-trimester D&C cases develop intrauterine adhesions per HRU 2024 meta-analysis. The user may be in that group.

### "No pre-event history" fallback

The biggest operational edge case: a user who started OCP as a teenager, never tracked a natural cycle, then stops OCP.

```
fallback μ₁ = age-stratified value from AWHS 2023:
  age <20    → 27 days
  age 20-34  → 28.7 days (population mean)
  age 35-39  → 29 days
  age 40-44  → 30 days
  age ≥45    → 30 days (with elevated σ)

fallback σ₁_prior = AWHS within-person SD for that age group
fallback μ₂, σ₂, π = standard mixture priors
```

Apply the post-OCP recovery profile on top of this fallback. By cycle 6–9, the user's own data dominates and the fallback origin becomes irrelevant.

---

## Cold-start and graduation

For users with very little data, the full mixture is unidentifiable. Strategy:

- **N < 6 cycles:** Use single-component Gaussian (current `CyclePredictor` behavior). Mixture would overfit to noise.
- **N = 6–11 cycles:** Use single component but evaluate ELBO/log-marginal-likelihood of 2-component fit. If 2-component clearly preferred, graduate.
- **N ≥ 12 cycles:** Full 2-component mixture is default.

Graduation criterion (BIC approximation): switch to 2-component when:
```
log p(data | 2-comp model) > log p(data | 1-comp model) + 2 · log(N)
```

Derivation: the BIC penalty is `k · log(N) / 2` where k is the number of extra parameters. For
2-component vs. 1-component, the extra free parameters are (μ₂, σ₂², π) — i.e., k = 3, giving
a penalty of `1.5 · log(N)`. We use a slightly stricter threshold (`2 · log(N)`) to prefer the
simpler model in the borderline regime where Gibbs would be noisy anyway. Latent assignments are
not counted as free parameters under standard BIC.

---

## Inputs from existing design docs

This design must respect commitments made in earlier docs:

### From `disrupted-cycles.md`
- Five event categories (A–E) with explicit reactions
- `CycleEvent` SwiftData model with `EventKind` enum (13 cases)
- No streaks
- 4-week notification embargo after Category C events
- PredictorMode (active / paused / retired)

The mixture predictor slots into the existing `PredictorService` actor:

```swift
extension PredictorService {
    // Replace single-component update with mixture Gibbs update
    func observe(cycleLength: Double, asOf: Date) async {
        switch mode {
        case .active(var predictor):
            predictor.observe(cycleLength)   // now runs Gibbs mixture sampler
            self.mode = .active(predictor)
        case .paused, .retired:
            break
        }
    }

    // Per-event recovery profile applied at event log time
    func apply(event: CycleEvent) async {
        switch event.kind {
        case .abortion: applyRecoveryProfile(.medicalAbortion)
        case .miscarriage: applyRecoveryProfile(.miscarriageEarly)  // or late based on note
        case .birthNotBreastfeeding: applyRecoveryProfile(.livebirth_nonBF)
        case .stoppedHormonalContraception: applyRecoveryProfile(.stopOCP)  // or Depo, IUD, etc.
        // ... etc
        }
    }
}
```

### From `late-and-missed-periods.md`
- Conditional CDF for late-period prediction: already present in `CyclePredictor.swift`; trivially extends to the mixture predictive (Monte Carlo over posterior samples).
- "No clear estimate" UI state triggers when 90% CI width > 14 days.
- Pregnancy test framing rules unchanged.

---

## Implementation breakdown

Estimated LOC and ordering for the implementation work (a separate work block, after this design is approved):

### Phase 1: Log-normal NIG baseline (1–2 days)
- Apply log-transform to anovulatory observations
- Reuse existing NIG conjugate update on transformed data
- Captures the right-tail improvement without mixture machinery
- ~80 LOC modifications to `CyclePredictor.swift`
- Tests: synthetic right-tailed sequences

### Phase 2: 2-component Gibbs sampler (3–5 days)
- `MixturePredictor` struct (parallel to `CyclePredictor`, not replacing it)
- Gibbs loop: assignments → component 1 NIG → component 2 NIG (log-space) → π Beta
- Identifiability post-processing
- Posterior predictive sampling
- ~250 LOC new code
- Tests: synthetic 2-component data with known truth; ELBO monotonicity; cold-start behavior

### Phase 3: Per-event recovery profiles (1–2 days)
- `RecoveryProfile` enum mapping event kind → prior parameter set
- Integration with `PredictorService.apply(event:)`
- Asherman flag logic
- ~100 LOC
- Tests: each Category C event produces expected first-cycle predictions

### Phase 4: Graduation + cold-start (1 day)
- `PredictorVariant` enum: `.singleComponent(CyclePredictor)` | `.mixture(MixturePredictor)`
- Graduation logic at N=6, 12 cycles
- Fallback to age-stratified population priors when no pre-event history
- ~75 LOC
- Tests: graduation triggers correctly; no oscillation between variants

### Phase 5: Validation (1–2 days)
- Posterior predictive checks on synthetic + Bull 2019 FigShare data (if accessible)
- Calibration testing (80% CI should contain 80% of held-out cycles)
- Latency benchmarks on real iPhone hardware

**Total estimate:** 7–12 developer-days. Larger than the current single-component model but manageable for one person.

---

## CAVI vs. Gibbs — the choice explained

The on-device inference research strongly recommended **CAVI** (Coordinate Ascent Variational Inference). The mixture architectures research strongly recommended **Gibbs sampling**. Both are real, both are defensible. They differ on three axes:

### Axis 1: Posterior calibration

- **CAVI** finds the variational distribution `q*` that minimizes KL(q || posterior) over a factorized family. Known consequence: variance is *underestimated* (mean-field VI is over-confident). The Stan and PyMC documentation, Bishop's textbook, and Blei et al. 2017 JASA all explicitly state this.
- **Gibbs** samples from the actual posterior. Variance is correct (up to MCMC noise).

**Why this matters for Tideline:** the disrupted-cycles design doc lists "honest uncertainty over false precision" as Principle 6. CAVI's known failure mode is exactly false precision. We can't be in the business of saying "your period will likely arrive ±2 days" when the truth is ±4 days. Gibbs is the doctrinally aligned choice.

### Axis 2: Latency

- **CAVI** is deterministic, closed-form, fast. Estimated 0.3–0.5ms per update.
- **Gibbs** runs 200 iterations × N observations × K components. Estimated 15–25ms per update.

Both are well under the 100ms target. **Gibbs is ~50× slower but still imperceptible to users.** No latency-driven reason to pick CAVI.

### Axis 3: Implementation complexity

- **CAVI:** ~700 LOC estimated, plus digamma function approximation, ELBO bookkeeping, careful initialization to avoid local optima.
- **Gibbs:** ~425 LOC estimated. Per-iteration logic is each sub-step's standard conjugate update — math we already have for component 1, mirrored for component 2.

**Gibbs is simpler in this specific case** because we already have the NIG conjugate update infrastructure. CAVI's ELBO machinery is new code we'd have to write and debug.

### Conclusion: Gibbs

For Tideline specifically:
- ✅ Calibrated posteriors (doctrine alignment)
- ✅ Latency budget easily met
- ✅ Less new code than CAVI
- ✅ Reuses existing NIG conjugate updates
- ⚠️ MCMC sampling noise visible in tests (deterministic for given seed; acceptable trade-off)

This is the recommendation. CAVI is fine in worlds where deterministic speed is paramount or where exact calibration doesn't matter — neither applies to us.

---

## What implementation would look like

After this design is approved, the work block to actually build this would look like:

### Files to create
- `Tideline/Sources/Services/MixturePredictor.swift` — the Gibbs sampler + mixture posterior representation (~250 LOC)
- `Tideline/Sources/Services/RecoveryProfile.swift` — per-event prior parameter sets (~100 LOC)
- `Tideline/Sources/Services/PredictorVariant.swift` — variant enum + graduation logic (~75 LOC)
- `Tideline/Tests/MixturePredictorTests.swift` — synthetic data tests (~200 LOC)
- `Tideline/Tests/RecoveryProfileTests.swift` — per-event recovery tests (~100 LOC)

### Files to modify
- `Tideline/Sources/Services/CyclePredictor.swift` — add log-transform option for Phase 1 (~30 LOC)
- `Tideline/Sources/Services/PredictorService.swift` — route through `PredictorVariant`; per-event recovery dispatch (~50 LOC)
- Tests in `CyclePredictorTests.swift` — extend with log-normal cases (~50 LOC)

### Files to leave alone
- `CycleEvent.swift` — unchanged; event taxonomy already correct
- `Cycle.swift`, `DayEntry.swift` — unchanged
- All UI files — unchanged at this layer (UI consumes `PredictorService` API which stays the same)

### Sequencing
Implement in the 5-phase order documented above. Each phase is independently testable; later phases can be deferred without leaving the codebase in a broken state.

### What I would *not* do
- Try to do MCMC convergence diagnostics on-device — beyond scope; trust the burn-in and a fixed iteration count
- Implement the HMM transition layer in v1 — defer to v1.5 once we have real user data showing whether autocorrelation matters
- Multi-component mixtures (K=3+) — overkill; the literature consistently shows K=2 is enough
- Cross-validation on-device — too expensive; rely on offline synthetic-data validation

### Risk register
- **Gibbs convergence:** monitored via assignment-stability metric; if iteration 100 differs from iteration 200, sampler may not have converged. Mitigated by 200 iterations + identifiability constraint.
- **Cold-start instability:** if user has 6–11 cycles and the graduation criterion oscillates, force one decision and stick with it for 3 cycles. Add as a unit test.
- **Per-event prior mis-specification:** if the recovery profiles produce visibly wrong predictions for real users, we have no easy way to detect this without telemetry. Mitigation: comprehensive synthetic tests covering edge cases; document the profiles as v1 starting points subject to revision based on user feedback.

---

## Open questions

1. **HMM extension to v1.5:** when do we add the hidden Markov transition layer? Suggest after we have ≥3 months of real user data, can detect autocorrelation, and have a benchmark to compare against.

2. **PCOS subtyping:** the design treats all PCOS-declared users with the same Beta(3,5) mixing weight. Phenotype-specific priors (A/B/D distinct from C) would improve fit but require more onboarding questions. Deferred to v2.

3. **Perimenopause:** AWHS 2023 shows within-person SD of 11.19 days for age 50+ — much wider than reproductive-age. A separate "perimenopause-declared" event might warrant its own prior set distinct from generic Category E. Open for now.

4. **Calibration validation without a labeled dataset:** we have no ground truth other than the user's own future cycles. Post-hoc calibration measurement would require collecting prediction vs. actual data — which requires telemetry. The privacy-first architecture means we can't easily measure model calibration in production. Open question: do we run a one-time opt-in calibration study with a small cohort, or trust synthetic-data validation only?

5. **Bortot 2010 parameter values:** we couldn't access the full text. The shift δ = 15 is consistent with the literature consensus but isn't verified against Bortot's specific value. Acquiring the PDF would let us calibrate more precisely.

---

## References (only verified from `research/2026-05-19-mixture-predictor-verified.md`)

🟢 = full text accessed; 🟡 = abstract direct quote; 🟠 = architecture verified from abstract + downstream citing.

- 🟢 Mahalingaiah S et al. (2023). *npj Digital Medicine*. PMC10226714. — population priors, age-stratified within-person SD.
- 🟢 Nassaralla CL et al. (2011). *J Womens Health* 20(2):169–177. PMC7643763. — post-OCP cycle 1: 31.5 ± 11.1 days.
- 🟢 Depo-Provera prescribing information (DailyMed). — 183d median ovulation IM, 10mo median conception.
- 🟢 HRU 2024 IUA meta-analysis. — Asherman 17% (95% CI 11–25%) first-trimester D&C.
- 🟡 Schreiber CA et al. (2011). *Contraception* 84(3):230–233. PMID 21843685. — medical abortion, 20.6 ± 5.1 days first ovulation.
- 🟡 Jackson E, Glasier A (2011). *Obstet Gynecol* 117(3):657–662. PMID 21343770. — postpartum first ovulation 45–94 days; 20–71% of first menses anovulatory.
- 🟡 Gnoth C et al. (2002). *Gynecol Endocrinol* 16(4):307–317. PMID 12396560. — post-OCP cycle disturbance through cycle 9; 10.24% strict anovulatory cycle 1.
- 🟠 Guo Y et al. (2006). *Biostatistics* 7(1):100–114. PMID 16020617. — Normal + shifted Weibull two-component mixture; nonstandard >43 days.
- 🟠 Harlow SD, Zeger SL (1991). *J Clin Epidemiol* 44(10):1015–1025. PMID 1940994. — original two-component framework; nonstandard threshold >43 days.
- 🟠 Bortot P et al. (2010). *Biostatistics* 11(4):741–755. PMID 20400622. — Bayesian hierarchical state-space alternative.

Inference algorithm references (verified by fact-check, real):
- Bishop, C.M. (2006). *Pattern Recognition and Machine Learning* (PRML), Chapters 9–10. Standard Gaussian-mixture conjugate inference.
- Murphy, K.P. (2012). *Machine Learning: A Probabilistic Perspective*, Chapters 11, 21, 25. Conjugate updates, MCMC, mixtures.
- Stephens, M. (2000). "Dealing with label switching in mixture models." *JRSSB* 62(4):795–809. Reference for the post-hoc relabeling alternative (not used by this design — we use the simpler per-iteration ordering constraint).
- LNG emergency contraception bleeding pattern, PMID 18402847 (Hum Reprod 2008). Used for the EC recovery-profile rows.

---

## Status

**Awaiting review.** Once approved, this becomes the source of truth for the mixture-model implementation work. Any deviation in implementation requires updating this doc first.
