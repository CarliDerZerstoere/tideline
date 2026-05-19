# Late and Missed Periods — Design Note

**Status:** Draft for review
**Date:** 2026-05-19
**Scope:** What Tideline shows and does when the user's period is late or absent without a user-declared disruption event.

**Related docs:**
- `disrupted-cycles.md` — handles events the user explicitly logs (abortion, miscarriage, birth, contraception, illness)
- `research/2026-05-19-late-period-clinical.md` — evidence base for this design

---

## Context

The cycle predictor produces a probabilistic estimate of the next period start date. Sometimes the period doesn't arrive when predicted. This document covers what happens then.

Earlier draft had the app simply stop predicting at 15+ days late. **That's wrong.** Silence reads to the user as either app failure or quiet judgment — both bad. The user opens the app at the moment they most need information, and we hide. Clinically, a doctor in the same situation does not say "I have no information for you" — they say "let's rule out pregnancy first, then here's what the common explanations are."

Tideline must match that posture. Confident, calm, informative, non-catastrophizing, and honest about uncertainty.

---

## Principles

1. **Never go silent.** At every delay milestone, the app shows useful information.
2. **Information, not diagnosis.** Show what's normal, what's clinically known, what the user might consider — never tell the user what's wrong with them.
3. **Pregnancy test suggestion is the one medical-adjacent action we allow.** Framed as population behavior ("many people take a pregnancy test at this point"), not as a recommendation.
4. **Continue showing a probabilistic prediction with widening confidence intervals.** A wide range is not a failure — it's an honest representation of biology.
5. **No countdown framing.** "Day 18 late" amplifies anxiety. Phrase it as "your cycle is running longer than usual" or "it's been about three weeks past your expected date."
6. **No differential diagnosis suggestions.** The app never says "this could be PCOS / thyroid / hypothalamic amenorrhea." That's medical territory.

---

## Clinical baseline

What's actually normal for a "late" cycle, from peer-reviewed sources (see `research/2026-05-19-late-period-clinical.md`):

| Statistic | Value | Source |
|---|---|---|
| Mean cycle length (population) | 29.3 days ± 5.2 SD | Bull et al. 2019 (612K cycles) |
| Cycles 25–30 days | 65% | Bull et al. 2019 |
| Cycles 31–35 days | 19% | Bull et al. 2019 |
| Cycles 36–50 days | 7% | Bull et al. 2019 |
| Cycles >50 days | <1% | Bull et al. 2019 |
| Users whose median cycle is >38 days | 10% | Apple Women's Health Study 2023 |
| Users reporting their period arrived later than app predicted | High % (specific figure pending verification) | App-user research literature; specific "72.1%" figure attributed to Broad et al. 2022 could not be independently confirmed by fact-check; treat directionally |
| Pregnancy test sensitivity at day of missed period | ~90% | PubMed 14749643 |
| Pregnancy test sensitivity 7 days after missed period | ~97% | PubMed 11594902 |
| Clinical threshold for "secondary amenorrhea" (previously regular) | 3 consecutive missed cycles | ASRM Practice Committee opinion (most recent published version); also ACOG, Endocrine Society |
| Clinical threshold for secondary amenorrhea (previously irregular) | 6 months of absent cycles | Same |

**Key insight:** a single late cycle is statistically normal. ~19% of all cycles run 31–35 days. The app's UX must reflect this — being a few days late is not an event, even though many users experience it as one.

---

## The conditional prediction model

The math from the existing Bayesian predictor naturally handles "late" cycles. Once the cycle has reached day D past the last period start, the conditional probability of bleeding on day D+k is:

```
P(cycle_length ≤ D+k | cycle_length > D) = [F(D+k) − F(D)] / [1 − F(D)]
```

where `F` is the user's posterior predictive CDF from the NIG model.

In practice:
- At day D = μ (expected day), the probability mass is distributed symmetrically — predictions are tight.
- At day D = μ + 2σ, most of the probability mass has been "consumed" — the remaining distribution is right-skewed and stretched.
- At day D ≫ μ + 3σ, the remaining mass is in the tail. The interval is genuinely wide because biology is genuinely uncertain at this point.

This means **we can keep showing predictions all the way through** — they just become wider. The UI just needs to honestly visualize the widening, not pretend the prediction is still sharp.

### Implementation

Add to `CyclePredictor.swift`:

```swift
extension CyclePredictor {
    /// Conditional probability that the next period starts on or before
    /// `daysFromLast`, given that no period has occurred yet at `currentDay`.
    func conditionalCDF(daysFromLast x: Double, currentDay D: Double) -> Double {
        let FD = predictiveCDF(daysFromLast: D)
        let Fx = predictiveCDF(daysFromLast: x)
        guard FD < 1.0 else { return 1.0 }
        return max(0, (Fx - FD) / (1 - FD))
    }

    /// Conditional credible interval given the cycle has already exceeded `currentDay`.
    /// Returns a (lower, upper) range of days from last period.
    func conditionalInterval(
        currentDay D: Double,
        confidence: Double = 0.90
    ) -> ClosedRange<Double> {
        // Numerical inversion of the conditional CDF for the confidence quantiles.
        let lowerTarget = (1 - confidence) / 2
        let upperTarget = 1 - lowerTarget
        let lower = inverseConditionalCDF(target: lowerTarget, currentDay: D)
        let upper = inverseConditionalCDF(target: upperTarget, currentDay: D)
        return lower...upper
    }
}
```

`predictiveCDF` is a new helper (Student's-t CDF, can be approximated via the normal-CDF + small-df correction). Inversion is numerical (binary search; cheap, runs in <1ms).

---

## Behavior at each delay milestone

The table below specifies what the app shows at each milestone. **Calibrate "expected period day" to μ — the user's posterior mean — not a hardcoded 28.**

| Days past expected | What's happening clinically | What the app shows | What it doesn't show |
|---|---|---|---|
| **0–4 days late** | Within ±1 SD for most users. Statistically normal. | Calendar unchanged. Prediction window remains visible. No alert. Soft note in the predicted-day cell: "Your cycle window — periods often arrive a few days on either side." | "Your period is late!" — premature, anxiety-inducing |
| **5–9 days late** | Approaching tail for low-variability users; still inside range for high-variability users | Widen the displayed prediction interval. Inline note: "Your cycle is a bit longer than your typical pattern this time. That's common." Hide gamification streaks/celebrations until period is logged. | Explicit "late" labeling, push notification, or count |
| **10–14 days late** | Past ±2 SD for typical users. Clinically still within normal variation. | Show "Your cycle is running longer than usual this time." Continue showing widened prediction interval. **Surface pregnancy test info neutrally** in an inline card: "Many people choose to take a pregnancy test around this point. Home tests are about 90% accurate at the time of a missed period and 97% one week later." Include a soft prompt to optionally log a Category D anomaly note if the user knows of something (stress, illness, travel) — purely optional. | Diagnostic suggestions ("this could be PCOS"). Aggressive notifications. |
| **15–21 days late** | Clinically noteworthy single late cycle. Most common explanations: pregnancy, stress, hormonal change, lifestyle disruption. | Information card: "It's been about three weeks past your expected date. This happens for many reasons — most are temporary. A pregnancy test can help rule out pregnancy if you haven't already taken one." Continue showing the widening prediction band. Offer the optional "anything notable this cycle?" prompt. | Listing causes. Count-up framing. Urgent tone. |
| **22–30 days late** | Approaching one missed cycle. Still within range of common benign causes for one-off late cycle. | "It's been about a month past your expected date. If you haven't taken a pregnancy test, that's the most informative next step. If the test is negative and your period still doesn't arrive in the next few weeks, this can be worth raising with a doctor — most of the time the explanation is simple." Prediction interval is now very wide; consider switching from a date range display to a "ongoing — no clear estimate" display while keeping the conditional probabilities accessible in a "details" view. | Implication that something is wrong. |
| **31–60 days late** | Approaching oligomenorrhea pattern if persistent. One-off occurrence still doesn't warrant full workup. | "It's been over a month since your expected period. A negative pregnancy test combined with an ongoing absence is worth mentioning to a healthcare provider at your convenience — not urgent." Keep the calendar visible; mark the elapsed time non-numerically ("over a month"). | Anxiety-inducing day-counting. Specific differential. |
| **61–90 days late** | Approaching ASRM 3-month threshold for secondary amenorrhea evaluation. | "Your period has been absent for about two months. Clinicians typically recommend a check-in at this point — there are many possible reasons, most treatable. A pregnancy test, plus a conversation with a doctor, are reasonable next steps." | Diagnosis. |
| **90+ days late** | Crosses the ASRM threshold for secondary amenorrhea workup (previously regular users). | "Your period has been absent for around three months. This is the point at which clinicians typically recommend a medical evaluation to understand what's happening. The most common causes are usually straightforward to identify." Offer a one-tap option to switch to a "paused / under medical evaluation" mode that suspends predictions until the user resumes. | Continued prediction-as-usual UX. |

---

## Pregnancy test suggestion — the regulatory hairline

This is the one medical-adjacent prompt the app makes. Justified because:
- It's the universal first step in clinical evaluation of any late period (NHS, ASRM, ACOG, NICE all agree)
- It's a population behavior fact ("many people take a pregnancy test at this point") not a personalized medical recommendation
- Not suggesting it would be a UX failure — users actively want this information

The exact phrasing must always be:
- Framed as population behavior, not personal recommendation
- Includes test-sensitivity numbers as context, not as marketing
- Never says "you should" or "we recommend"
- Never says "you might be pregnant"

**Safe phrasing examples:**
- ✅ "Many people take a pregnancy test around this point."
- ✅ "Home pregnancy tests are about 90% accurate at the time of a missed period, and 97% one week later."
- ✅ "If you haven't already taken a pregnancy test, that's the most informative next step."

**Unsafe phrasing (do not ship):**
- ❌ "You may be pregnant."
- ❌ "We recommend taking a pregnancy test."
- ❌ "Your symptoms suggest pregnancy."

The "many people" framing keeps us in wellness/lifestyle territory under EU MDR. The published clinical guidelines being our source makes the information defensible.

---

## What the app **never** does at late milestones

- Suggest differential diagnoses (PCOS, thyroid, hypothalamic amenorrhea, perimenopause, POI, hyperprolactinemia, etc.) — even probabilistically
- Make any statement about pregnancy beyond suggesting a test
- Display the day-count as the dominant UI element ("DAY 23 LATE")
- Send a push notification with the word "late" or any pregnancy framing in the visible preview
- Imply that the user has caused the delay through behavior ("have you been stressed lately?")
- Surface ads, premium upsells, or partner-product links during late states

---

## Notification rules

| Days past expected | Notification |
|---|---|
| 0–9 | None |
| 10–14 | One quiet notification: "Just a check-in." Body shown only when device unlocked: "Your cycle is running a bit longer than usual." |
| 15–30 | Optional weekly check-in if user opted in. Otherwise silent. |
| 30+ | No automated notifications. App content visible when opened. |

All notifications use neutral preview text. Body content visible only after Face ID/Touch ID unlock. iOS notification preview settings respected.

---

## UI surface: the "no clear estimate" state

When the prediction band gets so wide that it's no longer meaningful as a date, switch the calendar surface from "predicted date" to "no clear estimate." This is **not silence** — it's:

- The calendar continues to mark today and historical cycles.
- In place of a predicted date, an information card explains the current state and what users typically do.
- The widening posterior remains accessible in a "details" view (a chart showing the conditional probability over the next 60 days). For users who want the numbers, they're there. For users who don't, they're not in the way.

This is the difference between "we don't know" (failure) and "the biology itself is uncertain right now — here's what's known about this situation" (helpful honesty).

---

## Open questions

1. **Should the optional "anything notable this cycle?" prompt at the 10-14 day mark trigger a Category D outlier-reject** if the user logs stress/illness? Tentatively yes — it gives the user a way to tell the model "this one wasn't typical" without making them dig through settings. Confirm in implementation.

2. **Threshold for switching the calendar surface from date-prediction to "no clear estimate"** — currently informally set around day 22-30, but the right trigger is statistical: when the conditional 90% CI width exceeds 14 days, switch the surface. This is a calculable threshold; needs to be tested against synthetic users.

3. **Multi-language tone** — the careful "many people take a pregnancy test" phrasing needs review by native German speakers (DACH primary market). Direct translation can land coldly. Defer to localization pass.

4. **Adolescent vs. adult thresholds** — adolescents (within ~5 years of menarche) have legitimately irregular cycles. The 10-14 day "show pregnancy test info" gate is age-sensitive. Tentatively: require an age input during onboarding; for users under 18, soften the prompts and add a one-time "cycles can be irregular for years after they start — that's normal" note. Confirm in implementation.

5. **Perimenopausal users** — users in their 40s with increasingly irregular cycles need a different posture. The "late period" surface should be much more relaxed; the secondary amenorrhea threshold ASRM uses (6 months of absent cycles for previously irregular users) is the right anchor. Tentatively: offer a self-declared "perimenopause" mode in Category E that loosens all the milestone thresholds.

---

## References

Cited in the body and in `research/2026-05-19-late-period-clinical.md`. **Verified by fact-check 2026-05-19** unless noted ⚠.

**Verified strong:**
- Bull, J. R., et al. (2019). *Real-world menstrual cycle characteristics of more than 600,000 menstrual cycles.* npj Digital Medicine. (Existence confirmed; specific percentage breakdowns may be paraphrased — verify against the paper before quoting exact figures in user-facing copy.)
- Apple Women's Health Study (Mahalingaiah et al., 2023). *npj Digital Medicine.* Cycle length statistics in the report are consistent with published values.
- Wilcox et al. (1999). *Time of implantation of the conceptus and loss of pregnancy.* NEJM. (~10% of pregnancies implant after expected period day.)
- Cole et al. (2011) and similar. Home pregnancy test sensitivity benchmarks (~90% at day of missed period, ~97% one week later).
- ACOG, NHS, Endocrine Society clinical guidance pages on amenorrhea evaluation and patient information.

**Verified directionally, exact figures soft:**
- ASRM Practice Committee opinion on evaluation of amenorrhea (the 3-month/6-month thresholds are standard ASRM/ACOG/Endocrine Society — citation year may not be 2024; latest reaffirmed version may be earlier).
- AAFP (2019). *Amenorrhea: A Systematic Approach to Diagnosis and Management.*
- Endocrine Society Functional Hypothalamic Amenorrhea Guideline (2017) — for FHA prevalence and recovery data.
- ESHRE 2023 International Evidence-Based PCOS Guideline — for PCOS prevalence and oligomenorrhea overlap.

**⚠ Unverified — do not quote until confirmed:**
- "Broad, Biswakarma, Harper 2022, *Women's Health*, 72.1% / 6.4%" — fact-check could not confirm. The qualitative finding (most users have experienced periods arriving later than predicted) is supported by other literature; the specific percentages are not.
- "Urteaga et al. 2021 MLHC" — likely refers to "A Generative Modeling Approach to Calibrated Predictions: A Use Case on Menstrual Cycle Length Prediction" (MLHC 2021). Verify exact title before citing.
- "Fukaya et al. 2017 Statistics in Medicine" — fact-check could not confirm this exact citation; related work by Bortot, Masarotto & Scarpa (2010, *Biostatistics*) on sequential cycle length prediction is real and more reliably cited.
- "Mixture distribution / shifted Weibull tail, Biostatistics 2006" — methodology is real (Harlow & Zeger 1991; Bortot et al. 2010); the specific 2006 Biostatistics citation needs verification.

**Pregnancy-test sensitivity sources:** PubMed 14749643, PubMed 11594902 (existence to be confirmed; the underlying numbers are well-established in the literature).
