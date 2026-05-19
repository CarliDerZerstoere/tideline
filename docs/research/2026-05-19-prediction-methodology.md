# Research Note — How Existing Apps Predict Cycles

**Date:** 2026-05-19
**Researcher:** research-analyst sub-agent
**Fact-checked:** Partial
**Drove decisions in:** `CyclePredictor.swift` (Bayesian NIG choice); planned DSP temperature pipeline

---

## Question driving this research

What algorithms and signals do leading cycle tracking apps actually use, and how accurate are they?

---

## Key findings

### Input signals (ranked by hormonal information content)

| Signal | What it tells us | Best for |
|---|---|---|
| LH urine strips (OPK) | Imminent ovulation (24–48h warning) | Prospective ovulation prediction |
| Estrogen (E3G) urine strips | Approaching fertile window (~5-day warning) | Earlier ovulation prediction |
| Progesterone (PdG) urine strips | Ovulation confirmation | Retrospective confirmation |
| BBT / wrist-temperature biphasic shift | Progesterone rise (post-ovulation) | Retrospective confirmation |
| Cervical mucus observation | Estrogen-driven; leading edge of fertile window | Prospective indicator |
| HRV (luteal phase drop ~8–12%) | Autonomic shift driven by progesterone | Weak phase marker |
| RHR (luteal elevation ~1-2 bpm) | Same | Weak phase marker |
| Symptoms (cramps, mood, libido) | Downstream of hormones | Engagement / personalization, weak prediction value |
| Self-reported period dates | Cycle boundaries | Calendar prediction foundation |

### Algorithm families used by leading apps

| App | Algorithm |
|---|---|
| **Natural Cycles** | Personalized statistical model on BBT time series with biphasic shift detection. FDA-cleared (Class II, DEN170052). Optional LH integration. |
| **Flo** | Two-stage: per-user pattern extraction + 442-input feedforward neural network. AWS-trained. ⚠ Source is InData Labs case study, not peer-reviewed. |
| **Clue** | Hierarchical Bayesian on cycle lengths with adherence-aware latent variable. Published: Li et al. 2022 JAMIA. |
| **Apple Health** | On-device wrist-temperature biphasic shift detector + cycle history. Apple has published 2024-2025 validation. Algorithm details proprietary. |
| **Oura Ring** | Classical DSP: Butterworth bandpass filter + outlier rejection + hysteresis thresholding on finger temperature. Published validation 2025 (JMIR). |
| **Whoop** | Multi-parameter ML on RHR + HRV + temperature + respiratory rate. White paper only. |

### Published accuracy benchmarks

| System | Metric | Value |
|---|---|---|
| Natural Cycles (BBT + LH) | Wrong "green day" rate | <0.08% per cycle |
| Natural Cycles | Pearl Index (typical use) | 6.9 (range 6.5–8.3) |
| Oura Ring | Ovulation detection rate | 96.4% of cycles |
| Oura Ring | Ovulation timing MAE | 1.26 days (87.9% within ±2 days) |
| Apple Watch (Algorithm 2) | Ovulation timing MAE | 1.22 days (89% within ±2 days) |
| Apple Watch (next-menses prediction) | Within ±3 days | 89.4% |
| Calendar baseline ("day 14 ovulation") | Cycles where day 14 is correct | ~20% of 28-day cycles |
| Flo (irregular cycles) | MAE | 2.6 days (vs. 5.6 calendar; vendor figure) |

### Cycle distribution (population)

From Bull et al. 2019 (Natural Cycles app, >600K cycles):
- Mean: 29.3 days, SD ~5.2 (between-person)
- Within-person SD: 2.6 ± 2.5 days
- Cycle length distribution is right-skewed (heavy tail)

From Apple Women's Health Study 2023:
- Within-person variability ~3–5 days for healthy-BMI adults 35-39
- 10% of users have median cycles >38 days
- ⚠ Important: within-person SD (~3-5d) ≪ between-person SD (~7d). Earlier writeups conflated these.

### Day-14 myth (verified)

- Bull 2019: only ~24% of 28-day cycles ovulate on days 14-15 combined
- Day 15 is the modal ovulation day (27%), day 16 (21%), day 14 (20%)
- 10-day spread within cycles of the same nominal length

This is why apps that predict ovulation as "cycle length − 14" are systematically wrong for ~80% of users.

---

## Decisions made from this research

1. **Implement Bayesian NIG model first** (Clue's approach, simplified). Pure Swift, on-device, deterministic.
2. **Plan DSP pipeline for Apple Watch wrist temperature** (Oura's approach). Classical signal processing, no ML needed.
3. **Never predict ovulation from calendar math alone** — the day-14 myth is too costly in user trust.
4. **With wrist temperature: show retrospective ovulation confirmation** only (Apple's approach). Prospective ovulation prediction requires LH or quantitative hormone data.
5. **Calibrate priors to within-person variability (~3.7 days), not between-person.**

---

## Verification status

Algorithm descriptions verified from peer-reviewed sources where available (Natural Cycles FDA filing, Apple Watch Human Reproduction 2025 paper, Oura JMIR 2025 validation, Clue Li et al. 2022 JAMIA, Symul 2021 HSMM paper). Flo's 442-input NN is from InData Labs case study, **not peer-reviewed** — treat as vendor marketing, not validated science. Day-14 myth quantification is from Bull 2019, verified.
