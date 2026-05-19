# Research Note — Improving Cycle Prediction Accuracy

**Date:** 2026-05-19
**Researcher:** research-analyst sub-agent
**Fact-checked:** No (queued)
**Drove decisions in:** Predictor roadmap (priorities for accuracy improvements)

---

## Question driving this research

Beyond the basic Bayesian NIG predictor, what techniques would improve cycle prediction accuracy, and which make sense for a solo iOS developer working privacy-first on-device?

---

## Key findings

### Algorithmic upgrade ladder

| Technique | Accuracy gain | Complexity | On-device viable? |
|---|---|---|---|
| Hierarchical Bayesian with population prior | ~10% bias reduction vs. fixed priors | Medium | Yes |
| Adherence-aware latent variable (Li 2022 / SkipTrack 2025) | 96-98% skip detection | Medium | Yes |
| State-space / Kalman filter (temporal drift) | RMSE ~1.64d (vs. ~2.3 naive) | Low-Medium | Yes |
| Hidden Semi-Markov Model for phase labeling | 76-94% phase accuracy | High | Marginal |
| LSTM / Transformer on cycle sequences | MAE ~2.3d (vs. 2.92 median) | High (CoreML conversion needed) | Yes via CoreML |
| Gradient boosting (XGBoost/LightGBM) tabular | Comparable to LSTM | Low | Yes (small model) |
| Mixture / Student-t likelihoods (heavy tails for PCOS) | Substantially reduced bias for tail users | Low | Yes |
| Bayesian Model Averaging | 4-23% point forecast improvement | Medium | Yes |

### Additional signals beyond cycle length

| Signal | Source | Accuracy gain | Cost |
|---|---|---|---|
| Apple Watch wrist temperature | HealthKit, free if user has watch | Retrospective ovulation MAE 1.22 days (Apple WHS 2025) | $0 |
| RHR + HRV | HealthKit | Weak (luteal phase ~8-12% HRV drop) | $0 |
| Sleep architecture | HealthKit | Weak corroborating signal | $0 |
| Respiratory rate (sleep) | HealthKit (Apple Watch Series 9+) | Weak | $0 |
| LH urine strips (basic OPK) | Manual entry | 90-97% sensitivity, ~100% specificity for surge | $0.20-0.50/strip |
| Quantitative LH/E3G/PdG (Inito, Mira) | Manual entry; Inito plugs into iPhone | r² = 0.99 vs. ELISA | $99-199 + strips |
| Mail-in blood spot (Everlywell, Modern Fertility) | Manual entry of PDF results | Clinical-grade | $79-199/test |
| Cervical mucus observation | Manual | Strong leading-edge of fertile window | $0 |
| CGM data | Manual / Bluetooth | Emerging research; PCOS-relevant | $$$ |

### Theoretical accuracy ceiling

The literature converges on these limits:
- **Next-period prediction:** MAE ~1.5-2.5 days for users with regular cycles + temperature data. ~3-5 days for irregular without temperature. Below ~1 day MAE is impossible — biology has irreducible day-to-day noise.
- **Retrospective ovulation:** MAE 1-2 days with quality temperature data. Below 1 day requires LH or PdG confirmation.
- **Prospective ovulation:** Only LH strips (or quantitative hormone monitoring) give reliable advance warning. Temperature is post-hoc.

### What Flo, Apple, Oura actually achieve (from validation studies)

| System | Next-menses prediction | Ovulation detection |
|---|---|---|
| Flo NN (vendor figure, irregular cycles) | MAE 2.6 days | Not validated |
| Apple Watch wrist temp (Algorithm 3) | 89.4% within ±3 days | MAE 1.22 days |
| Oura Ring | Not the primary metric | 96.4% detection, MAE 1.26 days |
| Natural Cycles (BBT + LH) | Tight green/red day assignments | <0.08% wrong green day rate |
| Calendar-only baseline | MAE ~5-7 days (irregular users) | ~20% accurate on day 14 |

### Cold-start improvements

- **Demographic priors** (age, BMI, parity, contraception history) — narrow the starting distribution
- **Onboarding self-report** (typical cycle length, regularity) — equivalent to ~2-3 cycles of data
- **HealthKit import** — if user has cycle history in Apple Health, ingest as priors
- **Transfer learning from population** — requires backend, not feasible on-device

### Personalization beyond the user themselves

- **Cohort matching** — would require backend; out of scope
- **Federated learning** — out of scope for solo dev (no fleet)
- **Synthetic data augmentation in development** — useful for testing predictor robustness

---

## Decisions made from this research

Prioritized accuracy improvements (highest ROI first):

### Tier 1 (build in MVP)
1. **Wrist temperature integration from HealthKit** — single biggest accuracy lift available for free
2. **HealthKit import of existing cycle data** — instant cold-start improvement
3. **Demographic + onboarding priors** — narrows starting distribution
4. **Adherence-aware extension to NIG model** — handle "I forgot to log" without corrupting the posterior

### Tier 2 (post-MVP)
1. **Heavy-tailed likelihood (Student-t)** for users with declared irregularity
2. **HRV/RHR integration** as weak corroborating signals
3. **Manual quantitative LH/PdG entry** (for Inito/Mira/Proov users)

### Tier 3 (defer / never)
1. LSTM/Transformer — accuracy gain not worth complexity for solo dev
2. Federated learning — requires backend
3. Cohort matching — requires backend
4. Voice F0 hormone proxy — privacy issue, unreliable
5. Camera-based strip scanning — Premom does it well; not worth building

---

## Verification status

Not yet fact-checked. Many specific accuracy numbers are quoted from app vendor materials and may be optimistic. The theoretical ceiling discussion is well-supported but the specific MAE numbers should be treated as directional. Fact-check pending; will be added when complete.
