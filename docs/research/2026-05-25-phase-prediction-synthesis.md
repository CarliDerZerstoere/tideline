---
date: 2026-05-25
status: research synthesis (PARTIALLY SUPERSEDED — see notice below)
supersedes: nothing (new arc; complements 2026-05-24 four-wave research bundle)
superseded_by_for_q1: docs/research/2026-05-25-empirical-validation-results.md
provenance: 8 research-analyst / scientific-literature-researcher agents + 2 fact-checker passes + 1 empirical-validation run (Fehring n=1,508)
---

# Phase-prediction research synthesis (Q1 + Q2 + Q3)

> **⚠️ Partial supersession notice (2026-05-25 evening):** The Q1 conclusion "SHIP per-user learned luteal length" below was **reversed** by the empirical validation against the Fehring NFP dataset later the same day. Fair head-to-head V3b showed per-user luteal estimation from cycle dates alone is **0.89 d MAE worse** than population. NEW-170 was **dropped**; NEW-176 (uncertainty propagation only) ships instead. See `docs/research/2026-05-25-empirical-validation-results.md` for the data-grounded conclusions. Q2 and Q3 sections below remain valid.

This document consolidates the three-wave research arc launched 2026-05-25 to decide what additional phase-prediction features Tideline should build. All headline numbers have been cross-checked by a dedicated fact-checker pass; PMID corrections and verification status are inline.

## Decision summary (the three-line answer)

- **Q1 — Learned per-user luteal length:** SHIP. Evidence-supported, competitively necessary (Natural Cycles already does it), and there is a genuine literature gap on the *date-only* variant we'd build.
- **Q2 — Cross-cycle symptom prediction:** SHIP CAREFULLY. The base rate is low (cycle phase explains 1-6% of mood variance in healthy women), but per-individual repeatability does exist for specific symptom domains (migraine, cramps). Frame as recognition copy, not forecast.
- **Q3 — Sympto-only ovulation tightening:** PARTIAL. Mucus logging is the only added input with strong evidence (peak day ±2 d of LH in ~84% of cycles). Mittelschmerz, libido, energy — too noisy/inconsistent. Worth building only as a Phase 4 follow-on to the wrist-temp Kalman work.

The rest of this document is the evidence trail.

---

## Q1 — Per-individual luteal-length stability

**Question:** Replace `cycleLength − 14` with a per-user learned luteal mean?

### Verified evidence

| Claim | Source | Status |
|---|---|---|
| Population mean luteal = 12.4 d (SD 2.4); 18% < 11 d; follicular drives cycle-length variance | Bull et al. 2019, PMC6710244, n=612,613 cycles | ✅ verified verbatim |
| Within-person luteal "variance" 3.0 d < follicular 5.2 d (Wilcoxon p<0.001) | Henry et al. 2024, PMC11532606, PMID 39320898, n=53 women, ~12.8 cycles each | ⚠️ unit ambiguity (days vs days²) but conclusion robust — SD ≈ 1.7 d either way |
| Within-user luteal stability ±1.25 d | Berglund Scherwitzl 2015, PMID 25592280, n=317 | ✅ verbatim |
| Between-person luteal SD 1.41 d | Lenton, Landgren, Sexton 1984, **PMID 6743610** (not 6743608) | ✅ verbatim |
| Within-individual cycle SD by age (35-39: 3.79 d; 45-49: 5.42 d; 50+: 11.19 d) | Mahalingaiah/Li AWHS 2023, PMC10226714 | ✅ verbatim; AWHS does NOT report luteal-specific variability |
| Closest published Bayesian-hierarchical cycle-length predictor with per-user prior | Bortot, Masarotto, Scarpa 2010, PMID 20400622 | ✅ exists, but does not target luteal directly |

### What competitive products do

| App | Per-user learned luteal | Required sensor | Methodology source |
|---|---|---|---|
| Natural Cycles | YES (rolling BBT-confirmed mean) | BBT or wrist temp | Bull 2019; **FDA DEN170052** (not K183179) |
| Sensiplan | NO — observes BBT shift event | BBT required | Frank-Herrmann 2007 PMID 17314078 |
| Marquette | NO — observes LH event | Clearblue monitor | Fehring & Schneider |
| Apple Health | NO — fixed −13 offset | None (sensor optional) | Apple support docs |
| Flo | claimed in help docs | None | No published methodology |
| Drip / Euki | NO | None | Open source |

### Decision

**SHIP** per-user learned luteal length. Three reasons:

1. **Evidence supports it.** Luteal is more within-person-stable than follicular (Henry 2024, p<0.001). Berglund Scherwitzl confirms ±1.25 d within-user variability — small enough that learning meaningfully tightens the prior.
2. **Competitively necessary.** Natural Cycles ships this; we can't be behind their published baseline.
3. **The date-only variant is novel.** No published method learns luteal from cycle dates alone — Tideline would be the first publicly documented implementation.

### Constraints

- **Cold-start fallback:** Use Bull 2019 population mean (12.4 d) instead of the folk rule (14 d) until ≥3 user cycles observed. Then converge toward personal median.
- **Wider uncertainty in flagged populations:** anovulation indicators, postpartum (<6 cycles since birth), recent OC cessation (<9 cycles since last pill). Use wider β until additional cycles confirm.
- **No diagnostic claim.** "Your typical luteal length is ~13 days" = wellness display. "Your luteal is short" = MDR-regulated, do NOT say.

---

## Q2 — Cross-cycle symptom repeatability

**Question:** Surface symptom patterns *predictively* ("you may experience X tomorrow") rather than just descriptively?

### Verified evidence

| Claim | Source | Status |
|---|---|---|
| Cycle phase explains only 1-6% of daily mood variance in healthy women (sadness 4.0%; irritability 5.4%; fatigue 1.1%; nervousness 5.7%); day-to-day dominates (79-98%) | Lorenz TK, Gesselman AN, Vitzthum VJ 2017, PMC5708589 (**NOT** Forrester-Knauss as research-agent claimed) | ✅ numbers verified; author attribution corrected |
| Menstrual migraine test-retest consistency 70% across 3+3 cycle blocks; 80% within those diagnosed | Verhagen et al. 2022, PMC9535967, PMID 35514214, n=157 | ✅ exact quote |
| Cramp duration cycle-to-cycle consistency ~54% | longitudinal college cohort (no PMID extracted) | ⚠️ source confirmed but no PMID |
| Individual-level symptom prediction in commercial datasets is "complicated if not impossible" due to engagement artifacts | Li K, Urteaga I, Wiggins CH et al. 2020, PMC7250828 (NOT Symul as first author of this paper) | ✅ quote verified, context: distinguishing experienced from tracked symptoms |
| DSM-5 PMDD requires 2 prospective cycles → diagnostic protocols **assume** repeatability | Endicott 2006 PMID 16172836; C-PASS Eisenlohr-Moul 2017 PMC5205545 | ✅ assumption documented |
| Bloch 1997 PMID 9396955: ICC values per symptom in PMS samples | paywalled | ⚠️ qualitative conclusions confirmed; numerical ICCs not retrieved |

### Competitive framing (FDA wellness safe harbor)

Verified that under FDA 2026 General Wellness Final Guidance + EU MDR, the **"you may experience X based on your past cycles"** framing is the load-bearing legal marker:

- **Flo** uses "you may be experiencing breast tenderness today" (most explicit forward framing)
- **Clue Plus** uses "possible PMS", "potential fertile window" (probabilistic hedges)
- **Apple Health** does NOT predict symptoms (historical logs only — the most conservative posture)
- **Drip / Euki** do NOT predict symptoms (open-source benchmark, also conservative)
- No academic audit of any commercial app's symptom-prediction accuracy exists in literature.

### My own citation hallucination caught

The fact-checker confirmed:
- 🔴 **Bosman RC, Jung SE, Miloserdov K. "Daily fluctuations in mood..." Hum Reprod 38(11):2126-2133 (2023)** is **fabricated**. I introduced this in my brief; no such paper exists in PubMed, Hum Reprod TOC, or Google Scholar. Likely confused with Pierson et al. 2021 Nature Human Behaviour.

This is exactly the failure mode the user's memory warned about. Recording for future arcs.

### Decision

**SHIP CAREFULLY.** Three observations:

1. **Predicting symptoms from population priors does NOT work.** Cycle phase explains 1-6% of mood variance in healthy women. We cannot say "many women experience X on day 26" because most women don't.
2. **Per-user pattern recognition IS evidence-supported, for specific domains.** Menstrual migraine (70% test-retest); cramps (~54% consistency); DSM-5 PMDD diagnosis explicitly relies on 2-cycle repeatability.
3. **Wellness safe harbor is well-charted.** "Based on your last N cycles, X may happen" with required cycle count ≥3 is legally defensible — it's how Flo and Clue both operate.

### Constraints

- **Minimum data:** Per-symptom pattern surfacing requires ≥3 cycles with that symptom logged for that user. Fewer = display historical data only, no forward language.
- **Required framing:** "may", "based on your logged history", explicit cycle-count attribution.
- **No diagnostic interpretation:** "you logged headache on day 1-2" = OK. "your headaches are menstrual migraines" = NOT OK (ICHD-3 classification needs clinical confirmation).
- **Engagement-artifact aware:** Per Li/Urteaga/Wiggins 2020, we can't distinguish "didn't have the symptom" from "had it but didn't log." Frame patterns as "of the days you logged, X% included symptom Y" — not "you had Y X% of the time."

---

## Q3 — Ovulation timing without wearables

**Question:** Tighten the predicted ovulation day beyond `cycleLength − 14` using only self-reported cervical mucus + Mittelschmerz + cycle date?

### Verified evidence

| Claim | Source | Status |
|---|---|---|
| Mucus peak day within ±2 d of LH surge in 91% of cycles; mean offset +0.9 d (ovulation follows peak) | Fehring 2002, PMID 12413617, pooled 4 studies, 108 cycles, 53 women | ⚠️ ±4 d at 97.8% verified verbatim; ±1d 78% / ±2d 91% need full-text |
| Woman-picked peak ±1 d of LH 58%; ±2 d 84%; kappa 0.71 | Stanford JB, Schliep KC, Chang CP, O'Sullivan, Porucznik 2020, PMC8495767 (**NOT** Barron & Fehring as research-agent claimed) | ✅ numbers verified; citation corrected |
| Conception probability 0.003 (no mucus) → 0.29 (most fertile mucus type) | Scarpa, Dunson, Colombo 2006, **PMID 16154254** (not 15990223), n=193, 2,755 cycles | ✅ verbatim |
| Calendar+mucus Bayesian decision-rule precedent | Scarpa, Dunson, Giacchi 2007, PMID 17601602, n=191, 2,536 cycles, 161 pregnancies | ✅ verified |
| Mittelschmerz pre-ovulatory (coincides with follicular enlargement, not rupture); ~40% prevalence; not every cycle in affected women | O'Herlihy BMJ 1980; StatPearls PMID 31747229 | ⚠️ qualitative; quantitative offset and repeatability ICC not extractable |
| Sensiplan perfect-use 0.4 pregnancies per 100 women per 13 cycles; typical-use 1.8 per 100 woman-years | Frank-Herrmann et al. 2007, PMID 17314078, n=900 women, 17,638 cycles | ⚠️ phrasing — use "per 13 cycles" not "per woman-year" for perfect-use; annualized conversion is approximate |
| Standard Days Method perfect-use 4.75%, typical-use 11.96% cumulative 13-cycle pregnancy | Arevalo, Jennings, Sinai 2002, PMID 12057784, n=478 | ✅ verbatim |
| Calendar/rhythm methods typical-use 24% (Trussell categorises as "fertility awareness-based") | Trussell 2011, PMID 21477680 | ⚠️ use 24%, not 25% |
| **Temperature adds negligible *prospective* precision over mucus.** BBT advantage in sympto-thermal is retroactive (closing the fertile window earlier in luteal). | Multiple sources, agent synthesis | ✅ inference from literature pattern |
| **No published implementation of per-user Bayesian model that seeds prior from longitudinal cycle history AND updates within-cycle via self-reported symptom likelihoods.** | Literature gap | ✅ genuine novelty for Tideline |

### Decision

**PARTIAL.** Two parts:

1. **Add cervical mucus logging:** YES, eventually. It's the only added self-reported input with strong published accuracy data (±2 d of LH in 84-91% of cycles). Without it, Tideline's ovulation estimate cannot meaningfully beat `cycleLength − 14`.

2. **Mittelschmerz / libido / energy / breast tenderness as fusion inputs:** NO. Mittelschmerz is informative when present but absent in 75-80% of cycles. Breast tenderness is *late luteal* (post-ovulatory) per PMC12068584 — useless for forward ovulation timing. Libido has effect size d=0.26-0.74 but no day-level temporal precision.

3. **Implementation sequence:** Mucus logging is a Phase 4 feature (depends on schema migration #148 for symptom stamps; user must opt in to extra logging). Until then, the better play is just to **fix the `−14` heuristic** by using Bull 2019's population mean (12.4 d) and the per-user luteal learning from Q1.

---

## Cross-wave decision matrix

| Feature | Evidence strength | MDR compatibility | Effort | Dependencies | Decision |
|---|---|---|---|---|---|
| **Per-user learned luteal length** (replace `−14`) | ✅ strong (Bull 2019, Berglund Scherwitzl 2015, Henry 2024) | ✅ wellness display only | 1–2 dev-days | None (data already available from Cycle table) | **SHIP — P1** |
| **Population luteal default ← 12.4 d** (replace fixed 14 in `PhaseBoundaries.from`) | ✅ strong (Bull 2019) | ✅ wellness | <1 dev-day | None | **SHIP — P1** |
| **Per-user mensesEnd floor** (replace defaultMenses=5 with personal median when N≥3) | ✅ user-experience evidence; #156 fix unlocks it | ✅ wellness | 1–2 dev-days | #156 (just shipped) | **SHIP — P1** |
| **Symptom pattern recognition copy** ("based on your last N cycles, you may experience X") | ⚠️ partial (works for migraine, cramps; null for mood) | ✅ wellness with hedging | 3–5 dev-days | #148 intra-day stamps (Phase 4); pattern engine | **SHIP CAREFULLY — Phase 4** |
| **Mucus logging + Bayesian fusion** | ✅ strong (Scarpa-Dunson 2007 precedent; mucus ±2 d in 84%) | ✅ wellness; non-contraceptive framing | 5–8 dev-days | #148; new mucus enum + UI | **PARTIAL — Phase 4** |
| **Mittelschmerz as predictor input** | ⚠️ only ~25% of cycles informative | ✅ wellness | covered by general symptom logging | n/a | **NO standalone feature** — log it via #148, surface descriptively only |
| **Libido / energy / breast tenderness as ovulation predictors** | 🔴 weak / null for forward timing | ✅ if framed as patterns | covered by general symptom logging | n/a | **NO** — log them, do not use for ovulation inference |

---

## Verification debt carried forward

Items the fact-checker could not fully resolve, that future arcs should close:

1. **Henry 2024 unit ambiguity** (days vs days²): conclusion robust either way, but for any published Tideline whitepaper, full-text Table 2 must be consulted.
2. **Fehring 2002 specific ±1 d / ±2 d percentages** (78% / 91%): full text needed before quoting. The ±4 d 97.8% is verified verbatim.
3. **Bloch 1997 ICC values**: paywalled. Qualitative direction confirmed (mood symptoms most stable, lowest ICCs). Specific r-values not quotable.
4. **O'Herlihy 1980 BMJ Mittelschmerz quantitative offset**: full text not accessible. Pre-ovulatory framing confirmed but the day-offset distribution is not.
5. **Cramp ~54% consistency figure**: source confirmed (longitudinal college cohort) but no PMID extracted. Cite as informal evidence only.

## Citation corrections to propagate

For future docs referencing these papers:

| What I said / agent said | Actually correct |
|---|---|
| Barron & Fehring 2005 | **Stanford, Schliep, Chang, O'Sullivan, Porucznik 2020** (PMC8495767, PMID 32101336) |
| Forrester-Knauss & Zemp Stutz 2017 | **Lorenz TK, Gesselman AN, Vitzthum VJ 2017** (PMC5708589) |
| Hambridge 2013 PMID 23193131 | **PMID 23589536** |
| Natural Cycles K183179 | **DEN170052** (de novo); subsequent wearable clearance K223145 |
| Halbreich 1982 PMID 7081438 | **PMID 6892280** |
| Lenton 1984 luteal PMID 6743608 | **PMID 6743610** (companion follicular paper: 6743609) |
| Scarpa Dunson Colombo 2006 PMID 15990223 | **PMID 16154254** |
| Billings 1972 PMID 4109848 | **PMID 4109930** |
| Symul 2020 first author | **Li K, Urteaga I, Wiggins CH** (PMC7250828); Symul is a different 2019 Nature Human Behaviour paper |

## Fabricated citation removed

🔴 **Bosman RC, Jung SE, Miloserdov K et al. "Daily fluctuations in mood in healthy women across the menstrual cycle." Hum Reprod 38(11):2126-2133 (2023)** — does not exist. I introduced this in my own research brief. Removed from all downstream documents. Future arcs: don't cite this; possible confusion with Pierson et al. 2021 Nature Human Behaviour.
