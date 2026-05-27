# 2026-05-24 — Data Fusion Research

**Date:** 2026-05-24
**Type:** Research note (write-once per project convention).
**Purpose:** Architecture + literature + UX + feature-catalog research on how to combine the multi-modal data Tideline collects (or plans to collect) into new features and predictor improvements. Fourth research wave of the day; intentionally cross-cutting (touches predictor architecture, HK integration, pattern detection, Doctor PDF, and UX framing simultaneously).

**Why this matters strategically:** Tideline's competitive moat is not single-feature richness vs. Flo/Clue — it's that the on-device data combination is fundamentally different (no cloud aggregation, no third-party SDKs, no cross-user federated learning). Data fusion is the layer where Tideline's architecture becomes a product advantage rather than just a privacy promise.

---

## 0. Methodology

Four specialist agents dispatched in parallel:

| Target | Agent | Output |
|---|---|---|
| Peer-reviewed multi-signal cycle prediction literature | scientific-literature-researcher | ~3,500 words, 16 PMC/PubMed sources verified |
| On-device technical feasibility (Swift/SwiftData) | data-scientist | ~4,200 words, Swift code sketches, latency budgets |
| Feature catalog (F1–F10 combination categories) | research-analyst | ~6,000 words (output truncated past F1; preview captured) |
| Value vs. creepiness UX spectrum (DACH-specific) | ux-researcher | ~5,800 words, 10 PMC sources, 15-feature scoring table |

All four prompted with the same hard constraints: on-device only, no cloud, no diagnostic interpretation, no contraceptive/conception efficacy claims, no streaks, AI summaries only never AI prediction, probabilistic predictions with credible intervals, 28-day post-loss notification suppression, lockscreen content redaction.

---

## 1. The literature reality (what's been validated)

### 1.1 The single most important honest finding

**No formal sequential-ablation study exists** showing the marginal MAE lift per added modality (dates → +temp → +HRV → +sleep). This is a genuine literature gap, not a search failure. Every published wearable/multi-signal study either compares one method to calendar baseline OR pools heterogeneous studies in meta-analysis — never the clean sequential comparison that would directly inform "is it worth adding HRV after we have temperature?"

This means Tideline's per-user Bayesian model accumulating modalities over time could itself become an internal ablation source — track per-user predictive accuracy as signals are added, as an internal evaluation metric.

### 1.2 Verified effect sizes (multi-signal prediction)

| Source | Sample | Finding | Verified |
|---|---|---|---|
| Goodale/Shilaih 2025 (Hum Reprod 40(3):469) | n=260, 889 cycles | Wrist-temp MAE **1.65 days** strong-signal cycles, **1.70 days** all cycles; calendar comparison p<0.001 | ✅ |
| PMC11829181 (Oura, JMIR 2025) | n=964, 1,155 ovulatory cycles | Finger-temp ovulation MAE **1.26 days**; 96.4% detection rate, 68% within ±1 day of LH surge | ✅ |
| WHOOP PMC11666598 (npj DM 2024) | n=11,590, 45,811 cycles | RHR min day 5 / max day 26; RMSSD max day 5 / min day 27 — **characterization only, not prediction** | ✅ |
| PMC12886881 systematic review (2026) | 27 studies, 6,244 participants | Pooled wearable fertility accuracy 0.88 (95% CI 0.86–0.90); cannot isolate per-modality contribution | ✅ |
| npj Women's Health 2025 (s44294-025-00078-8) | n=18, 65 cycles | Random forest on temp+EDA+IBI+HR: 87% phase accuracy, AUC 0.96 — **small controlled sample, optimistic** | ✅ |

**Honest effect-size translation:** Adding wrist temperature to the cycle-date predictor improves MAE by an estimated 0.3–0.8 days for cycles with detectable temperature signal. That's **practically invisible** when CI is already ±5 days; meaningful when CI is ±2 days (long-term consistent trackers). Frame accordingly — don't oversell.

### 1.3 The 19.2% / 38% no-signal problem

- Goodale 2025 (Apple Watch-like wrist sensor): **19.2% of cycles** had no adequate temperature signal
- Mu 2021 (Ava bracelet): the claimed "38% no detectable signal" rate **could not be verified**. Closest figure: 26% of *anovulatory* cycles showed no signal (PMC8238491). Do not cite the 38% figure — it doesn't appear in any retrieved paper.

Any temperature layer must have an explicit "no signal" state that propagates unchanged rather than corrupting the estimate.

### 1.4 HRV is weaker than marketing suggests

- 2025 Sports Medicine living systematic review (DOI 10.1007/s40279-025-02388-y, 37 lab studies): trend toward higher follicular HRV but "substantially heterogeneous, frequency-domain metrics contradictory"
- Oura PMC9005074 (n=26): HRV model not statistically significant overall (F=1.93, **p=0.13**)
- WHOOP PMC11666598 shows population-level pattern; within-person SNR is too low for individual ovulation detection

**Verdict:** HRV as a standalone or high-weight signal is not ready. Use only as anomaly flag or weak corroborator, not as positive prediction signal.

### 1.5 Apple Watch sleep stages: insufficient SNR for cycle inference

PMC11511193 (3-device PSG comparison): Apple Watch S8 **deep-sleep sensitivity 50.5%**, underestimates deep sleep by 43 min, overestimates light sleep by 45 min. Any cycle-phase effect on sleep architecture is well within the device's measurement error. Using Apple Watch sleep stages as a predictor input adds noise, not signal.

Sleep duration (not stages) is more reliable and can be used safely.

### 1.6 Novel design space: OPK + wrist temp Bayesian fusion

**No peer-reviewed implementation exists** of Bayesian fusion combining urinary OPK (Inito/Mira: LH, E3G, PdG) with wrist temperature and cycle dates, each with its own error model. This is a genuinely novel contribution if Tideline implements it — high differentiation potential.

### 1.7 Symptom × biometric fusion has emerging evidence

PMC13022203 (Aitken et al. 2026, npj DM, n=4,244 ME/CFS + long COVID): morning HRV/HR shifts predict evening symptom severity. AUC 0.73–0.83 from prior-day symptoms alone; adding biometrics raises to 0.82–0.85. **Modest marginal lift**, but the methodological pattern (symptom history dominates; biometrics add ~5 AUC points) is the realistic expectation for Tideline's case.

---

## 2. Recommended technical architecture (modular Bayesian factor graph)

### 2.1 Core principle

NOT a single monolithic state-space model over all modalities. Instead: **modular factor graph with per-modality conjugate sub-models that feed asynchronously into the central mixture predictor.** Each optional modality contributes a likelihood term or parameter-shift; removing a modality removes its contribution; remaining posteriors stay valid.

### 2.2 Layer composition

| Layer | Required? | Update mechanism |
|---|---|---|
| **Core NIG mixture** (cycle lengths, v2) | Always | Existing Gibbs sampler |
| **SkipTrack** (latent c_ij) | Always (Phase 3a) | Additional Gibbs step |
| **Temperature layer** (wrist temp) | Optional, Watch S8+ | Scalar Kalman filter on residuals |
| **HRV/RHR layer** | Optional, AW required | Anomaly flag only, not predictor input |
| **Hormone layer** (LH/E2/PdG manual) | Optional, sparse | Bernoulli likelihood on component assignment |
| **Sleep duration** | Optional | Phase-conditional covariate in pattern detection |

### 2.3 Data infrastructure: DailySummary pre-aggregation

Don't query HK at inference time (50–400ms variable latency, can't bound at 25ms). Instead pre-aggregate nightly via `BGProcessingTask`:

```swift
@Model final class DailySummary {
    var date: Date                    // civilDay-normalized
    var rhrBPM: Double?               // nil if no Watch data
    var hrv_rmssd: Double?            // nil if unavailable
    var wristTempDelta: Double?       // nil if S7 or no sleep data
    var sleepHours: Double?           // nil if phone not charged
    var stepCount: Int?
    var cycleDay: Int?                // computed on write
}
```

**Critical:** Use `BGProcessingTask` (30s budget, can run nightly), **NOT** `BGAppRefreshTask` (30s budget, throttled to once per several hours, not guaranteed to run). Declare in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`. Foreground inference reads whatever's in `DailySummary`; background task refreshes it. Stale data > blocked UI.

### 2.4 Latency budgets (estimates, not measured)

| Operation | Target | Ceiling |
|---|---|---|
| Gibbs sampler 200 iter, N=50, K=2 | 15–25ms | 50ms |
| Gibbs + SkipTrack c_ij step | 20–35ms | 60ms |
| SwiftData fetch 365 DailySummary rows | 2–8ms | 15ms |
| HK query 90-day RHR (auth granted) | 50–400ms | 1s |
| Kalman filter wrist temp update | <1ms | 2ms |
| Mahalanobis anomaly check (K=3) | <1ms | 2ms |
| Full inference + conformal wrap | 20–40ms | 80ms |
| Background HK biometric import | 200–800ms | 2s |

**Critical foreground path** (blocks user): SwiftData fetch + Gibbs + conformal wrap = 15–50ms median. Under 100ms target. **HK query NEVER on critical path.**

**Verification debt:** None of these are measured on Tideline code. Must instrument with `PerfSignpost` (already in repo at `Sources/Diagnostics/PerfSignpost.swift`) and benchmark on release build on real hardware before treating as hard targets.

### 2.5 Numerical stability gotchas

- Log-sum-exp pattern for Gibbs categorical sampling (already specified in `mixture-predictor.md`)
- Shifted log-normal: explicit `guard L > delta` before `log(L - delta)` — don't rely on float propagation
- Joseph-form covariance update in Kalman: `P' = (I-KH)P(I-KH)' + KRK'` for positive-definiteness
- Ledoit-Wolf shrinkage for Mahalanobis covariance with sparse multi-modal data (avoids singular Σ at low N)

### 2.6 RNG pattern (for reproducible tests)

```swift
mutating func runGibbs(iterations: Int = 200, rng: inout some RandomNumberGenerator) { ... }
```

Production: `SystemRandomNumberGenerator`. Tests: seeded XorShift64 (4 lines, sufficient). Swift 6 Sendable-safe since RNG consumed by value.

---

## 3. Graceful degradation spec

### 3.1 FusionContext detection

```swift
struct FusionContext: Sendable {
    let hasBiometrics: Bool           // DailySummary rows for ≥7 of last 14 days
    let hasTemperature: Bool          // wristTempDelta non-nil ≥50% of recent nights
    let hasHormoneReadings: Bool      // any HormoneReading this cycle
    let cycleCount: Int               // drives mixture vs single-component graduation
    let biometricCompleteness: Double // 0–1 fraction of days with non-nil biometrics
}
```

### 3.2 FusionPrediction output

```swift
struct FusionPrediction: Sendable {
    let estimate: Date
    let interval: ClosedRange<Date>
    let activeSignals: Set<Signal>    // .cycleLength, .temperature, .hrv, .hormone
    let confidenceGrade: ConfidenceGrade  // .population, .personal, .multiModal
}
```

UI reads `activeSignals` to show "based on your cycle history + sleep" provenance.

### 3.3 Weighting by per-modality sample size

Hormone likelihood weighted `min(n_hormone / 10.0, 1.0)` — full weight at 10+ readings, 10% at 1 reading. Prevents single aberrant LH from dominating component assignment.

### 3.4 Base case = default case

A user with cycle dates + flow + zero biometrics gets the full v2 mixture predictor. Biometric layers are strictly additive. **Architectural constraint:** `MixturePredictor` has no required biometric fields; `FusionContext` is optional enhancement, not required input.

---

## 4. UX value-creepiness spectrum (DACH-critical)

### 4.1 The DACH framing problem

**Only 15% of Germans willing to share health data with technology companies** (PMC11836014, n=1004 stratified random CATI, December 2023, representative). 66% actively refuse. 79% require complete anonymization.

For comparison: 57% would share with health insurances, 43% with public research. **Tech companies are starkly below every other category.** This is the majority German position, not a privacy-aware niche.

**Implication:** Any Tideline feature that *looks* like the app is analyzing data — even when computation is fully on-device — risks triggering the "technology company as adversary" mental model. This is presentation, not architecture.

### 4.2 The earned-insight principle

The distinction is whether the app appears to be analyzing **you** or reflecting **you back to yourself.** (Helen Nissenbaum's contextual integrity framework, applied to mHealth in JCMC 2025.)

Two copy patterns making the difference:
- ✅ "Your headaches have clustered premenstrually in **4 of your last 5 cycles**" (user as subject, denominator visible, observation not interpretation)
- ❌ "We noticed you tend to get headaches before your period" (institutional voice, no denominator, implies surveillance)

### 4.3 Copy direction principles (system-wide)

1. **First-person possessive on every data noun.** "Your headaches" not "headaches we observed."
2. **Sample-size denominator always visible.** "In 4 of your last 5 cycles" not "often."
3. **"Based on" provenance over "we computed."** "Based on your headache logs and cycle phase logs over the last 5 cycles."
4. **Past observation over forward prediction for fusion outputs.** "Have clustered" > "will likely."
5. **"Wir haben gemerkt" is forbidden; "du hast gemerkt" is preferred.** German institutional voice = highest creepiness.
6. **Uncertainty is part of the message, not a disclaimer.** "...though this wasn't consistent in every cycle" added inline, not as footnote.

### 4.4 Proactive vs. on-demand policy

**Fusion-layer insights default to on-demand (in Mein Zyklus tab). Push notifications for fusion outputs require explicit per-category opt-in and are forbidden in specific contexts.**

| Tier | Default | Triggered when |
|---|---|---|
| Tier 1 — same-cycle / same-session fusion | On, on-demand | User opens Mein Zyklus tab |
| Tier 2 — HK biometric × symptom/phase | Off, opt-in at HK permission grant | User confirms during HK first-use |
| Tier 3 — Cross-domain (sleep + mood + cycle + hormone) | Off, explicit per-feature | User explicitly enables in Settings |

Push prohibited in 28-day post-loss window (existing rule extends). Push prohibited where preview text could be cycle-phase-adjacent on lockscreen.

### 4.5 Segment differences

| Segment | Fusion tolerance | Notes |
|---|---|---|
| Privacy-first early adopters | **Highest** — value sophisticated fusion as architecture proof IF provenance visible | Don't hide computation from them — that's the risk |
| PMDD users | High depth tolerance for Doctor PDF; in-app moderate | Diagnostic-adjacent evidence for clinician is primary use case |
| Trans/NB on T | Minimum interpretation; show raw data | Inferring gender-normative patterns from atypical data is harm |
| Postpartum | **Lowest during pause mode** | Reduced cognitive capacity + vulnerability; fusion surfaces re-emerge gradually |
| General users | Prediction-first, patterns secondary | Fusion outputs on home view = highest creepiness for this segment |

### 4.6 Doctor PDF as release valve

Fusion combinations that feel invasive in-app are often **legitimate as Doctor PDF sections** that the user explicitly generated. The contextual integrity shift: user-initiated, clinician-directed. Doctor PDF is also a regulatory hedge — frames "data you generated for your clinician" rather than "app analysis of your health."

Specific combinations that belong in Doctor PDF before (or instead of) in-app:
- Cup volume vs. population norms (menorrhagia-adjacent)
- DRSP scores vs. PMDD diagnostic thresholds
- HRV/RHR across cycles (anxiety-inducing without clinical context in-app)
- Hormone log vs. reference ranges (already NEW-Q Doctor-PDF-primary)

### 4.7 15-feature value-creepiness scoring

Default presentation: on-demand in-app. Push adds 1–2 creepiness points.

| # | Feature | Value | Creep | Decision |
|---|---|---|---|---|
| 1 | "Your cycle is 4 days late — your average is 28d" | 5 | 1 | Ship |
| 2 | "Headaches clustered premenstrually in 4 of 5 cycles" | 5 | 1 | Ship (exemplar of earned insight) |
| 3 | "You usually log poorer sleep before your period" | 4 | 2 | Ship, Tier 2 opt-in |
| 4 | "Cup fill estimates: heavier-than-typical bleed" | 4 | 3 | Ship as "vs your earlier cycles" (not vs population); move population comparison to Doctor PDF |
| 5 | "Your HRV pattern across last 3 cycles shows luteal dip" | 3 | 2 | Ship on-demand, Tier 2 opt-in |
| 6 | "Your mood clusters on days following poor sleep" | 3 | 3 | Ship on-demand only; push = creepy |
| 7 | "Your HRV pattern matches an anovulatory cycle" | 2 | 4 | Reframe — "matches" is quasi-diagnostic; use "looked different from your prior cycles" |
| 8 | "We noticed you skipped logging — should we ignore?" | 4 | 3 | Reframe to "You have 3 unlogged days — mark them?" (user as subject) |
| 9 | "Your last cycle was different — was it work stress?" | 1 | 5 | **Never** — assumes external context |
| 10 | "Sex log + ovulation suggests use protection today" | 0 | 5 | **Never** — MDR trigger, hard rule |
| 11 | "Sleep+steps+HRV suggest you're getting sick" | 1 | 5 | **Never** — predictive medical claim |
| 12 | "You've been logging more anxious — suggest meditation?" | 1 | 5 | **Never** — feels like commercial cross-sell |
| 13 | "Phone usage + cycle → likely in PMS today" | 0 | 5 | **Never** — uses data user didn't log |
| 14 | Same as #2 but as Doctor PDF section | 5 | 1 | Ship (user-initiated context) |
| 15 | "Your RHR was lower — consistent with what you logged for energy" | 3 | 2 | Ship — validation function ("consistent with what you logged") |

---

## 5. Feature catalog (F1–F10 combination categories)

Research-analyst output was truncated past F1; only F1-A captured in preview. Full catalog regenerable via SendMessage to agent `a4cf7cdf0fc7d9890`. Summary structure from agent prompt + verified F1-A:

### F1 — Cycle × biometric fusion (predictor improvements)
- **F1-A Wrist-Temperature Posterior Update** (verified from agent preview): credible interval narrows after temp-confirmed ovulation; retrospective "temperature-confirmed" badge on phase strip. Cites Hum Reprod 2025 + PMC11294004 cosinor. **Ship Phase 4b.**
- Cycle dates + HRV trend → anovulatory cycle flagging (low evidence per §1.4)
- Hormone log + cycle dates → personalized fertile-window display (MDR borderline)

### F2 — Symptom × phase × biometric (insight features)
- Symptoms + sleep + cycle phase → "headaches cluster premenstrually AND on poor-sleep nights"
- DRSP + sleep + cycle phase → PMDD diary with sleep context (Doctor PDF primary)

### F3 — Event × subsequent data (recovery + impact)
- Logged vaccine + subsequent cycle → "your last vaccine was followed by +3d cycle" (post-hoc only)
- Started/stopped HC + 3-month response → personal response summary

### F4 — Multi-source validation (data quality, non-scolding)
- Logged flow vs. HK menstrual record consistency
- Cup volume vs. categorical flow level cross-check
- Logged ovulation date vs. wrist-temp-implied date

### F5 — Personalized baselines (replace population thresholds)
- "Your typical cycle" instead of population "28 days"
- "Your typical luteal phase" instead of "14 days"
- "Your typical RHR pre-period"

### F6 — Doctor PDF combined exports
- One-page health summary (cycle + symptoms + relevant HK trends)
- Migraine + cycle + sleep export for Neurologe
- Postpartum recovery + feeding status + biometric for Frauenarzt

### F7 — Cross-cycle aggregations
- "Last 6 cycles ranked by symptom burden"
- "Your cycle types this year" (anovulatory / normal / disruption-affected clusters)

### F8 — Predictor improvements (not user-facing)
- Per-event recovery profile personalization (hierarchical Bayesian)
- SkipTrack + multi-modal (skip likelihood informed by sleep continuity?)
- Conformal calibration personalization (drift from population residuals → user-specific)

### F9 — Behavioral patterns (lifestyle insight)
- Phase-corrected exercise × sleep correlation
- Cycle-phase-aware cravings logs cluster late-luteal

### F10 — App-level UX improvements
- Adaptive logging suggestions (when user typically logs)
- Phase-contextual symptom prompts (luteal → PMS items)
- Smart default for next-period entry (pre-fills predicted date)

---

## 6. Recommended priority list (synthesis)

Ranking: **evidence strength × on-device feasibility × user value × MDR safety**.

| Rank | Feature | Phase | Effort | Verified evidence | Tier |
|---|---|---|---|---|---|
| 1 | **Wrist-temp Kalman layer** (F1-A) | 4b | 2–3d | Goodale 2025 Hum Reprod | Tier 2 |
| 2 | **Phase-corrected within-person cardiovascular baselines** (F5) | 4a | 1d | WHOOP PMC11666598 | Tier 1 |
| 3 | **Quantitative OPK Bayesian hormone fusion** (F1) | 4f | 2–3d | Mira PMC11356644 + Inito PMC10247788; novel fusion = differentiator | Tier 2 |
| 4 | **Symptom-to-symptom historical pattern display** (F2) | 4d | 2d | Aitken 2026 PMC13022203 (indirect) | Tier 1 |
| 5 | **Anovulatory-pattern flagging via cosinor** (F1) | 4c | 1–2d | PMC11294004 | Tier 2 (requires Watch) |
| 6 | **Per-event recovery profile personalization** (F8) | 4e | 1–2d | Hierarchical Bayesian (Murphy 2012) | (predictor-internal, not user-facing) |

**Deferred to Phase 5 / explicitly punted:**
- CGM × cycle display (effect size 1.7 pp time-in-range — practically invisible for healthy users)
- HRV-based ovulation detection (p=0.13 in Oura study, too noisy)
- Apple Watch sleep stages for cycle inference (50.5% deep-sleep sensitivity — measurement error exceeds signal)
- Joint state-space model over all modalities (dimensional explosion, over-engineered for sparse data)
- Per-user neural networks (data too sparse, training infeasible on-device)
- Federated learning (Pillar 1 violation)
- Seasonality patterns (R4 decision: 0.16-day effect smaller than logging resolution)

---

## 7. Build order (Phase 4 → Phase 5)

Respects existing Phase 3 plan (v2 mixture + SkipTrack + conformal); layers fusion on top without rework.

| Phase | Item | Effort | Dependency |
|---|---|---|---|
| 3 | Mixture predictor + SkipTrack + conformal | (existing) | Foundation |
| **4a** | DailySummary pre-aggregation + HKBiometricImporter + BGProcessingTask | 3–4d | Existing HealthKitService |
| **4b** | Wrist-temp Kalman + LutealPhaseTracker | 2–3d | 4a |
| **4c** | Mahalanobis anomaly detection + Ledoit-Wolf shrinkage | 1–2d | 4a |
| **4d** | Multi-modal pattern extensions (B3, B4, conditional logistic) | 2–3d | Phase 3 mixture + 4a |
| **4e** | Per-event recovery profile personalization | 1–2d | Phase 3 mixture |
| **4f** | Hormone likelihood integration (LH surge as soft evidence) | 2–3d | Phase 3 Gibbs + 4a |
| **5** | State-space μ drift (random walk on μ₁, σ_η=1.04d/cycle per Oliveira 2021 PMC8379295) | 1–2d | Phase 3 stable in production |

Total Phase 4 fusion work: ~12–17 dev-days, sequenced.

---

## 8. Decisions added (R21–R26)

| # | Question | Resolution | Source |
|---|---|---|---|
| **R21** | Architecture for multi-modal fusion? | **Modular Bayesian factor graph** with per-modality conjugate sub-models; NOT monolithic state-space | §2.1 |
| **R22** | HK data access pattern? | **Pre-aggregated DailySummary table via BGProcessingTask**; HK query never on critical path | §2.3 |
| **R23** | HRV as predictor input? | **No** — anomaly flag only (p=0.13 in Oura study; too noisy individually) | §1.4 |
| **R24** | Apple Watch sleep stages as predictor input? | **No** — 50.5% deep-sleep sensitivity exceeds signal | §1.5 |
| **R25** | Fusion notification policy? | **On-demand default; Tier 2 HK opt-in; Tier 3 explicit per-feature**; push prohibited in post-loss window | §4.4 |
| **R26** | Bonferroni vs hierarchical for multi-modal pattern detection? | **Bonferroni at 99.6% CI for v1**; hierarchical pooling deferred to future design pass | §7 of data-scientist output |

---

## 9. Verification debt + open questions

### Verified ✅
- Goodale/Shilaih 2025 (Hum Reprod 40(3):469) — MAE figures
- PMC11294004 cosinor method
- PMC11666598 WHOOP cardiovascular amplitude
- PMC12886881 wearable fertility meta-analysis
- PMC11829181 Oura finger-temp ovulation
- PMC10247788 Inito CV values
- PMC11356644 Mira vs serum comparison
- PMC10421863 CGM × cycle biphasic pattern (n=49)
- PMC11511193 Apple Watch sleep stage validation
- PMC11836014 German 15% tech-company-sharing willingness (n=1004 representative)
- PMC10468710 perceived control coefficient -0.758 reduces anxiety
- PMC13022203 Aitken HRV→symptom AUC

### Not verified / could not find
- "Mu 2021 38% no-detectable-signal rate" — **not in any retrieved paper**; closest is 19.2% (Goodale 2025) or 26% (PMC8238491 anovulatory cycles only). **Do not cite 38%.**
- Formal sequential ablation study (dates → +temp → +HRV → +sleep with MAE at each step) — **does not exist in literature**
- Bayesian fusion of OPK + wrist temperature — **no peer-reviewed implementation**, genuine novel contribution

### Implementation verification debt
- Gibbs sampler 15–25ms latency: **unverified** on Tideline code. Instrument with `PerfSignpost` on release build, real hardware.
- BGProcessingTask reliability: not measured in Tideline context yet
- SwiftData fetch latency for 365 DailySummary rows: estimated 2–8ms, not measured

### Design decisions for owner
- Confirm R21–R26
- Per-event recovery profile personalization: schema = `RecoveryObservation` SwiftData model + `RecoveryProfilePosterior` struct. OK to commit to?
- Multi-modal pattern Bonferroni vs hierarchical: hierarchical is cleaner but adds complexity — defer to v2?
- Tier 3 opt-in UX: settings-buried toggle vs onboarding question vs on-first-use prompt — needs UX decision

---

## 10. Future design docs unlocked

- `docs/design/data-fusion-architecture.md` — citation target §2, can be drafted now
- `docs/design/fusion-features-catalog.md` — citation target §5 + §6 (regenerate full F2–F10 detail from agent if needed)
- `docs/design/fusion-ux-principles.md` — citation target §4 (copy direction, opt-in tiers, segment differences)

The architecture doc is the highest priority — it gates Phase 4a (DailySummary infrastructure) and that's the prerequisite for everything downstream.

---

## Document conventions

Per project convention: research notes are write-once. The verification status in §9 supersedes any prior 🤷 fusion-related citations. This note is the citation target for the three future design docs in §10.

The research-analyst feature catalog full output (truncated past F1) is saved at `/Users/nr/.claude/projects/-Users-nr-Developer-CycleApp/46db944b-dc55-43ae-8ba9-2eccf99d8647/tool-results/toolu_01HrrzSJKK7QEUQaWHUqJ8zT.json`. If F2–F10 detail is needed for design-doc drafting, retrieve from there or SendMessage agent `a4cf7cdf0fc7d9890` for clean regeneration.
