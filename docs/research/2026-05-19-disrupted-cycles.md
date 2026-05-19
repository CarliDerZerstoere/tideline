# Research Note — Disrupted Cycle Handling (Medical + UX)

**Date:** 2026-05-19
**Researcher:** research-analyst sub-agent
**Fact-checked:** Yes; see Verification status
**Drove decisions in:** `design/disrupted-cycles.md`

---

## Question driving this research

How should the app handle events that disrupt the normal cycle (abortion, miscarriage, birth, breastfeeding, hormonal contraception, illness, eating disorders, PCOS)?

---

## Key findings

### Cycle resumption timelines

| Event | First bleed (typical) | Stable cycles by | Notes |
|---|---|---|---|
| Medical abortion | 4–6 weeks | Cycle 2–3 | Ovulation resumes mean 20.6 ± 5.1 days post-mifepristone (Schreiber 2011, n=14) |
| Surgical abortion / D&C | 4–8 weeks | Cycle 2–4 | Asherman's syndrome: 1.6% symptomatic, up to ~13% on systematic hysteroscopy follow-up |
| Early miscarriage (<10wk) | 4–6 weeks | Cycle 2–3 | Similar to medical abortion |
| Late miscarriage (10–20wk) | 6–10 weeks | Cycle 3–6 | Longer hCG clearance; 1-2 anovulatory cycles common |
| Live birth, non-breastfeeding | 6–8 weeks (mean ~74 days first ovulation) | Cycle 2–4 | Heavier/longer first cycles typical |
| Live birth, breastfeeding (LAM) | 9–18 months median (very wide range) | Highly variable | 8–33% ovulate before first postpartum bleed |
| Hysterectomy | N/A (no uterus) | N/A | Ovarian cycling continues if ovaries retained |
| Bilateral oophorectomy | N/A | N/A | Immediate surgical menopause |
| Stopping combined OCP | 2–8 weeks | 1–3 months | ~30-40% anovulatory first cycles (earlier "25%" figure was understated) |
| Stopping hormonal IUD | Days–2 weeks | 1–2 months | Local effect, fast return |
| Stopping Nexplanon | Days–3 months | 2–6 months | 74.7% conceive within 12 months (Girum & Wasie 2018 meta-analysis) |
| Depo-Provera | 55% amenorrhea at 12 months (Pfizer label); ~68% at 24 months | N/A during use | Earlier "up to 50%" figure was understated |
| Hypothalamic amenorrhea (eating disorder, over-training) | 3 months – >2 years | Variable | ~57.7% recover, mean 18.7 ± 14.8 months (one cohort); other studies 65-86% |
| PCOS | Often months between bleeds | N/A — chronically irregular | Standard Gaussian model is structurally wrong |

### App behavior failure patterns (well-documented)

- **Ovia:** Continues to show "X weeks until your original due date" after a subsequent loss. Documented in Andalibi 2021 and journalism.
- **Flo:** Users report receiving "are you on your period?" prompts after logging a pregnancy loss. Loss → next pregnancy reset is unreliable.
- **Apple Health:** Logging a miscarriage does NOT reset the period predictor. Users have to log a fake "period" the day of the loss as a workaround.
- **Clue:** No first-class miscarriage bleeding type — confirmed in Clue's own support docs. Users instructed to use "Spotting" + Daily Note. So the predictor sees loss bleeding as a normal period.

### The academic framing: "Symbolic annihilation through design"

Andalibi 2021 (verified: *New Media & Society*, n=166 apps):
- 72% of pregnancy-related apps don't account for loss at all
- 18% do explicitly; 10% passively
- The phrase coined is "symbolic annihilation through design" — extending Tuchman's 1978 concept of symbolic annihilation in media to algorithmic systems

This is the canonical theoretical framing for the harm pattern.

### Algorithm strategies considered

1. **Hard reset** — discard posterior, restart. For category A events (hysterectomy).
2. **Soft reset** — keep μ as hint, decay κ to 2, restore prior β. For category C events (recoverable disruptions).
3. **Segmentation** — multiple posteriors per regime. Useful for OCP on/off, complex but powerful.
4. **Outlier rejection** — skip the predictor update for disrupted intervals. For single anomalies.
5. **Pause mode** — stop updates and predictions entirely. For category B events (extended pauses).

The chosen approach combines these per event type (see design doc § Category-to-action lookup).

### UX research on trauma-informed design

- Andalibi 2021 framework is the negative case (what not to do)
- Frontiers 2023 (Søndergaard et al.) recommends embracing uncertainty
- CHI 2025 "Little Cloud" paper — companion app for pregnancy loss; concept-stage, not deployed
- Trauma-informed design literature converges on: provide agency, don't assume recovery timelines, warm-not-saccharine tone, minimalism at moments of pain, user-initiated resumption

---

## Decisions made from this research

1. **5-category event taxonomy** (A: Complete, B: Pause, C: Recoverable, D: Single anomaly, E: Ongoing irregularity)
2. **First-class `CycleEvent` SwiftData model** rather than flags on `Cycle`
3. **Notification embargo** of 4-6 weeks after Category C events
4. **No streaks** (Principle 3 in disruption doc) — invalidates earlier gamification idea
5. **AI summary layer for "what to expect" information links**, with strict guardrails
6. **Soft reset preserves μ but resets confidence** — the math implementation

---

## Verification status

Fact-checked 2026-05-19:

✅ Verified strong:
- Andalibi 2021 paper (correct journal, year, n, percentages)
- Schreiber 2011 mifepristone ovulation data (correct, small n caveat)
- Jackson & Glasier 2011 postpartum review (correct)
- Frontiers 2023 (Søndergaard et al.) "Reimagining the Cycle"
- Li et al. 2022 JAMIA (correct citation, methodology accurate)
- ESHRE 2023 PCOS guideline
- Pfizer Depo-Provera prescribing info (~55% amenorrhea at 12 months)
- Girum & Wasie 2018 meta-analysis (PMC6055351)
- ASRM/ACOG/Endocrine Society amenorrhea evaluation thresholds

⚠ Verified with caveats:
- Asherman's syndrome rate is wider than originally stated (1.6% symptomatic up to ~13% on systematic screening)
- Stopping OCP anovulatory rate is ~30-40%, not 25%
- Lactational amenorrhea timeline is wide; "9–18 months median" is on the high end
- Late miscarriage "1-2 anovulatory cycles" is clinical convention, not strongly cited
- Natural Cycles 60-day FDA labeling: NOT a "recalibration period," but a warning about elevated pregnancy risk during the 60-day post-HC transition window
- "Symbolic annihilation through design" not "algorithmic symbolic annihilation" (Andalibi's actual term)

⚠ Wrong / needs correction:
- MDCG 2025-4 was attributed to the "manually entered data ≠ medical device" qualification; that's actually MDCG 2019-11
- EU AI Act high-risk trigger for medical AI is Article 6(1) + Annex I, NOT Annex III
- EU AI Act deadlines moving via Digital Omnibus (Annex I medical device deadline proposed Aug 2028)
- "Anorexia recovery 57.7% / mean 18.7 ± 14.8 months" is one cohort; range is 65-86% in others
