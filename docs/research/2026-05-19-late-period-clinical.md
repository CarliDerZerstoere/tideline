# Research Note — Clinical Handling of Late and Absent Periods

**Date:** 2026-05-19
**Researcher:** research-analyst sub-agent
**Fact-checked:** Yes (2026-05-19); see § Verification status at bottom
**Drove decisions in:** `design/late-and-missed-periods.md`

---

## Question driving this research

When the user's predicted period doesn't arrive, what does clinical medicine actually do? Tideline initially proposed "stop predicting at 15+ days late." That's wrong — silence is unhelpful. So: what's the right behavior?

---

## Key findings

### Clinical terminology (verified strong)

| Term | Definition |
|---|---|
| Oligomenorrhea | Cycles consistently >35 days (adults); fewer than 9 periods/year |
| Secondary amenorrhea | 3 consecutive missed cycles in a previously regular person, or 6 months absent in a previously irregular person |
| Primary amenorrhea | No period by age 15 with normal secondary sexual development, OR by age 13 without secondary characteristics |

The "15 days late" threshold I initially used is **not a clinical concept** — it's an app convention only.

### Differential diagnosis (verified directionally — exact prevalences are guideline-cited)

For established secondary amenorrhea (multi-month, not a single late cycle):

| Cause | Approx. share |
|---|---|
| Functional Hypothalamic Amenorrhea (stress, weight loss, training) | ~20–35% |
| PCOS | 30–40% |
| Hyperprolactinemia | 10–15% |
| Primary Ovarian Insufficiency | 4–10% |
| Thyroid dysfunction | 1–5% |
| Pituitary / other CNS | 1–2% |
| Other (Asherman's, severe systemic illness) | rare |

For a single late cycle in someone with otherwise regular history: pregnancy and stress/lifestyle disruption dominate.

### Clinical workup thresholds (verified strong, attribution caveats)

- 1–7 days late: normal variation, no clinical action
- 7–14 days late: pregnancy test if sexually active
- 2–4 weeks late: pregnancy test mandatory; note context
- 1–3 months: see GP if pregnancy excluded
- 3+ months regular / 6+ months irregular: full secondary amenorrhea workup

ASRM, ACOG, Endocrine Society all converge on these.

### Conditional prediction is statistically defensible

For a Bayesian cycle predictor with posterior predictive distribution F:
```
P(period at day D+k | no period yet at day D) = [F(D+k) − F(D)] / [1 − F(D)]
```

As D increases, the conditional distribution naturally widens and shifts right. **This means we can keep showing predictions all the way through late phases — they just become honestly wider.** This is the math basis for "no silence, but widening uncertainty."

Published work on this approach: Urteaga (MLHC 2021), Bortot/Masarotto/Scarpa (Biostatistics 2010), Harlow & Zeger (1991) on cycle length mixture models.

### App behavior comparison (verified for Flo, Natural Cycles; others approximate)

| App | Behavior when period is late |
|---|---|
| Natural Cycles | Prompts pregnancy test if temperature remains elevated past expected date (FDA-cleared algorithm feature) |
| Flo | "Your period is late" notification + pregnancy test calculator |
| Clue | Status indicator; conservative tone |
| Apple Health | Very passive; no explicit late handling |
| Ovia | Late period alert; family-planning focus |

### Pregnancy test sensitivity (verified strong, foundational literature)

- ~90% sensitivity at day of missed period
- ~97% by 1 week post-missed period
- Up to 10% of pregnancies implant after expected period date (Wilcox et al. 1999, NEJM) — causing legitimate day-1 false negatives

---

## Decisions made from this research

1. **Never go silent.** At every delay milestone, show useful information.
2. **Continue predicting with widening conditional credible intervals.** Switch from date-prediction UI to "no clear estimate" UI when 90% CI width exceeds ~14 days.
3. **Pregnancy test suggestion at 10–14 days late**, framed as population behavior, never personalized recommendation. This is the one medical-adjacent action permitted.
4. **No differential diagnosis suggestions.** Ever.
5. **Adolescent and perimenopausal users need different thresholds** — flagged as open questions in design doc.

---

## Verification status

Fact-checked on 2026-05-19. Key issues:

| Item | Status |
|---|---|
| Clinical terminology / thresholds | ✅ Verified strong (ASRM, ACOG, Endocrine Society) |
| Pregnancy test sensitivity numbers | ✅ Verified strong (Wilcox 1999 NEJM, Cole 2011) |
| Secondary amenorrhea differential prevalences | ✅ Roughly correct; minor adjustments noted |
| Bull et al. 2019 npj Digital Medicine existence | ✅ Verified |
| Apple Women's Health Study 2023 existence | ✅ Verified |
| Conditional prediction methodology (Urteaga, Bortot et al.) | ✅ Methodology verified; exact citation titles need confirmation |
| "Broad et al. 2022" specific 72.1% / 6.4% figures | ⚠ Unverified — fact-check could not confirm |
| "ASRM 2024" guideline year | ⚠ Likely earlier reaffirmed version, not a 2024 publication |
| "Fukaya et al. 2017 Statistics in Medicine" citation | ⚠ Likely misattributed — Bortot et al. 2010 Biostatistics is the verified equivalent |
| Recovery timelines (stress amenorrhea 70% in 3-6 months, HA 90% recovery) | ⚠ Optimistic — real recovery rates and timeframes are more variable |
| Perimenopause onset "40–44" | ⚠ Actually averages later, ~mid-40s, average ~47 (SWAN study) |

Where citations were unverified, design docs were updated to flag them or quote ranges rather than specific numbers.
