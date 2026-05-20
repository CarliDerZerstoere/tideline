# Verified Research: Improvement Techniques Beyond v2 Mixture Predictor

**Date:** 2026-05-20
**Status:** Write-once, dated immutable. Supersedes any contradictory claims in prior notes.
**Methodology:** Research output produced by research-analyst, then fact-checked by fact-checker against primary sources. Only verified or partially-verified claims are recorded here. Unverifiable / paywalled claims are explicitly flagged as such.

---

## Scope

After validating the v1 Bayesian NIG single-Gaussian predictor against Fehring (MAE 2.12 days) and mcPHASES (MAE 2.71 days), four candidate improvement techniques were researched:

1. Within-cycle BBT / wrist-temperature updating
2. State-space drift on μ (time-varying mean)
3. Conformal prediction calibration wrapper
4. Covariates (BMI, stress, sleep, exercise)

---

## 1. Wrist-temperature within-cycle updating

### Verified primary-source findings

- **Fukaya et al. 2017** ([PMC5575519](https://pmc.ncbi.nlm.nih.gov/articles/PMC5575519/)): State-space model on **oral BBT** (not wrist), n=20 subjects. Median MAE reduction **0.361 days** vs. calendar baseline (range 0.056–1.368). Improvement accumulates as daily temperature data is added across the cycle. **Note:** earlier reports of "46% reduction" appear to conflate the relative improvement vs. specific baselines.
- **Mu et al. 2021** ([PMC8238491](https://pmc.ncbi.nlm.nih.gov/articles/PMC8238491/)): Wrist-skin-temperature (WST, Ava bracelet) vs. oral BBT, n=57 women, 193 cycles. WST sensitivity 0.62 (95% CI 0.55–0.70) vs. BBT sensitivity 0.23 (0.17–0.30). WST temperature rise 0.50°C vs. BBT 0.20°C. **37.6% of wrist cycles produced no detectable signal at all** (64/170).
- **Shilaih et al. 2018** ([PMC6265623](https://pmc.ncbi.nlm.nih.gov/articles/PMC6265623/)): Ava bracelet, 82% of cycles (357/437) showed a detectable 3-day sustained WST shift; 86% of those occurred on or after ovulation day.
- **Maijala et al. 2019** ([PMC6883568](https://pmc.ncbi.nlm.nih.gov/articles/PMC6883568/)): Oura ring (finger, not wrist), 81.4% sensitivity for menstruation start day within ±3 days. Luteal-vs-follicular skin Δ = 0.30°C (SD 0.12) vs. oral BBT 0.23°C (SD 0.09), p=0.003.
- **Human Reproduction 2025** wrist-temperature paper ([Oxford Academic 40(3):469](https://academic.oup.com/humrep/article/40/3/469/7989515)): n=216 participants, 889 cycles. **MAE for next-menses-start prediction = 1.70 days (95% CI 1.57–1.84)** vs. calendar baseline 1.90 days — **~10–11% improvement**. Apple Watch wrist-temperature algorithms are an active comparator.

### Apple Watch HealthKit

`HKQuantityTypeIdentifierAppleSleepingWristTemperatureRelativeToBaseline` (iOS 16+, watchOS 9+, Series 8 and later). Value is **baseline-subtracted by Apple's algorithm** — we cannot recompute the baseline. Approximately 2 cycles of nightly sleep-mode wear required before estimates appear. Hum Reprod 2025 is the first peer-reviewed independent validation; results in line with above (10–18% practical ceiling).

### Calibrated expectation for Tideline

**10–18% MAE reduction** for users wearing Apple Watch nightly with Sleep Focus enabled. **~0% for irregular wearers.** Roughly 38% of cycles are expected to produce no usable signal, so the model must include an explicit "no detectable shift" observation state.

### Status

**v3 work block.** Requires HealthKit reads + DSP signal-quality gate + observation-model addition to the v2 predictor (not a replacement). Earlier internal estimates of 20–30% MAE gain were anchored to oral-BBT literature and do not apply to wrist sensors.

---

## 2. State-space drift on μ

### Verified primary-source findings

- **Bortot, Masarotto & Scarpa 2010** (PMID 20400622, Biostatistics): three-component decomposition (random-walk trend + ARMA + linear covariates). **Paywalled** — internal three-component structure confirmed in abstract; specific parameterization not extractable.
- **Oliveira et al. 2021** ([PMC8379295](https://pmc.ncbi.nlm.nih.gov/articles/PMC8379295/)) implements the same general structure on a public cycle dataset. Fully verified numerical parameters:
  - σ_η = **1.04 days per cycle** (95% CI 0.997–1.088) — process noise on μ
  - σ_w = **4.78 days** (4.57–5.00) — overdispersed-component within-cycle SD
  - **RMSE = 1.64 days; concordance = 0.74; 56% BIC reduction** vs. simpler alternatives
  - Prior on σ_η⁻² is Gamma(0.13, 0.13)
- **Huang/Harlow 2013** ([PMC3979630](https://pmc.ncbi.nlm.nih.gov/articles/PMC3979630/), not "Harlow 2012"): hierarchical changepoint model for perimenopause. Variance changepoint at **42.84 years** (95% CI 42.49–43.17), **3.39 years before mean changepoint** (3.07–3.74). Variance increases **81% per year** post-changepoint. (For Tideline: implies that a μ-only random-walk drift is *insufficient* for perimenopausal users — variance needs to change too. Keep `PredictorMode` architecture for this.)

### Status

**v2.5 addition** (high priority, ~20–50 LOC inside the Gibbs sampler).
Add per-cycle Gaussian random-walk update: μ_j | μ_{j-1}, σ_η. Use Oliveira's prior Gamma(0.13, 0.13) on σ_η⁻² directly. **Do not** rely on random-walk drift to handle perimenopause — the variance explosion needs separate handling (existing `PredictorMode.declareOngoingIrregularity` is the right place).

---

## 3. Conformal prediction wrapper

### Verified findings

- **Core guarantee** (Vovk, Gammerman & Shafer 2005; Angelopoulos & Bates 2023 [arXiv:2107.07511](https://arxiv.org/abs/2107.07511)):

  > If (X₁, Y₁), …, (Xₙ, Yₙ), (X_test, Y_test) are exchangeable, then the conformal prediction set C(X_test) constructed from the ⌈(n+1)(1−α)⌉/n empirical quantile of nonconformity scores satisfies **1−α ≤ P(Y_test ∈ C(X_test)) ≤ 1−α + 1/(n+1)**.

  Distribution-free. Finite-sample. No assumption of model correctness.

- **Exchangeability for cycle data:**
  - *Cross-user* calibration (use other users' residuals): approximately exchangeable if users i.i.d. from the same population. Practical.
  - *Within-user sequential* calibration: violates exchangeability if μ drifts. Use the EnbPI / sequential conformal variant (Xu & Xie 2023, arXiv:2010.09107) which assumes stationarity and strong mixing. Coverage becomes approximate.

- **Calibration-set sizing** (Angelopoulos & Bates 2023): claimed n=22 for 90% coverage with ε=0.1 slack, n=102 for ε=0.05. Specific numbers **not fact-check-verified from primary source** — must be checked against the tutorial directly before shipping.

- **Negative finding:** No peer-reviewed study has applied conformal prediction to menstrual-cycle interval estimation as of May 2026. Tideline would be the first.

### Status

**v2 addition** (high priority, ~30–60 LOC).
Implementation: split conformal on a population calibration set (frozen at build time from validation data) → store empirical quantile vector → wrap NIG predictive interval with `point ± conformal_offset`. Document that on-device drift may violate exchangeability long-term; recalibrate by app update if observed coverage diverges.

---

## 4. Covariates: BMI, stress, sleep, exercise

### Verified findings — population (between-person) effects only

- **BMI** (AWHS 2023, [PMC10226714](https://pmc.ncbi.nlm.nih.gov/articles/PMC10226714/)) vs. healthy BMI (18.5–25):
  - Overweight: **+0.26 days** (95% CI 0.07–0.45)
  - Class 1 obesity (30–35): **+0.54** (0.32–0.77)
  - Class 2 (35–40): **+0.76** (0.48–1.03)
  - Class 3 (≥40): **+1.54** (1.24–1.85)

- **Stress, perceived (PSS-10)** — Nillni 2018 ([PMC6118267](https://pmc.ncbi.nlm.nih.gov/articles/PMC6118267/)) n=3346: **no significant effect on cycle length in days.** Effect on irregularity: PR = 1.31 (95% CI 1.15–1.48).
- **Stress, daily** — Schliep 2015 ([PMC4315337](https://pmc.ncbi.nlm.nih.gov/articles/PMC4315337/)): **no significant effect on cycle length** (p=0.72). Effect on anovulation: OR = 2.2 (1.0–4.7) for high vs. low stress.
- **Exercise / energy expenditure**: ≤750 kcal/week associated with cycles ~2.4 days longer (Bernstein 1987 adolescent study — **not the 2002 AJE paper a prior research pass mis-cited**). Between-person effect only.

### Key missing data

No published study reports within-person variance reduction from any of these covariates after subject-level random effects are partialled out. The between-person effect sizes are all small relative to within-person SD (~2–4 days for typical women), so even a perfectly-specified model would likely explain <10–15% of residual within-person variance.

### Status

- **Skip user-asked stress / sleep / exercise.** Friction not worth the gain.
- **BMI:** consider as a one-time self-report to *select a population prior bin* (e.g., shift prior μ by ~1.5 days for self-reported BMI ≥ 40). Treat as prior-selection flag, not within-cycle predictor. **v3 only**, low priority.
- **Age:** already encoded in the v2 population prior via AWHS within-person SD age bands. No new feature required.

---

## Roadmap summary

| Technique | MAE / interval gain | Cost | Phase |
|---|---|---|---|
| **Conformal wrapper** | Exact coverage guarantee; narrower intervals when v2 over-covers | ~30–60 LOC | **v2 (ship together)** |
| **State-space drift on μ** | Better tracking of slow trends; better post-event recovery | ~20–50 LOC | **v2.5** |
| **Wrist-temperature within-cycle** | ~10–18% MAE reduction (Hum Reprod 2025) for nightly-wear users | ~400–700 LOC + HealthKit | **v3** |
| **BMI prior-bin** | Modest prior shift for extreme BMI | ~20 LOC | **v3+, low pri** |
| **Stress/sleep/exercise covariates** | <5% within-person gain, self-report noise | n/a | **Skip** |

---

## Citation hygiene notes

Prior research-analyst passes contained the following errors that were caught and corrected here:

- "46% MAE reduction" attributed to Fukaya was misquoted; actual is **0.361-day median reduction**.
- Fukaya 2017 used **oral BBT, not wrist sensors** — do not anchor wrist-temperature estimates to it.
- Hum Reprod 2025 wrist-temperature paper was originally cited at the wrong DOI (the analyst's cited DOI resolved to a PCOS paper); correct numbers are at [40(3):469](https://academic.oup.com/humrep/article/40/3/469/7989515).
- "Bernstein 2002 AJE 156(5):402" is a fabricated citation — AJE 156(5):402 is Sternfeld; the 2.4-day exercise finding is from Bernstein's 1987 adolescent study.
- "Harlow 2012" should be **Huang/Elliott/Harlow 2013** (PMC3979630).
- Oliveira et al. 2021 was mis-attributed to "Guo et al. 2021" — both publish on state-space cycle models, but the verified parameter set is Oliveira's.
