# Tideline Differentiators

**Date:** 2026-05-20
**Status:** Living doc — consolidates the differentiator analysis from the design and research notes to date. Only verified claims; unverified claims are flagged or omitted.

---

## Why this doc exists

After ~20 design and research notes across the project, the differentiators are scattered. This file consolidates them in one place so we can:

1. Articulate to ourselves what Tideline *is* relative to Flo, Clue, Natural Cycles, Apple Health, Ovia, Veiltrack.
2. Identify which differentiators are **architectural** (structurally enforced — competitors can't easily copy) vs. **functional** (could be copied but currently aren't).
3. Catch ideas that came up in conversation but were never written down.

All numerical claims have been fact-checked against primary sources by the fact-checker agent. Author attributions corrected from earlier research-analyst hallucinations.

---

## Tideline's positioning in one sentence

**Tideline is a privacy-by-architecture cycle tracker that treats prediction as a calibrated probabilistic statement, life events as first-class data, and the user — not the app — as the interpreter of her own patterns.**

That sentence is the test for every feature. If a feature violates one of the four clauses (privacy / probabilistic / event-aware / non-interpretive), it doesn't ship.

---

## Architectural differentiators (structurally enforced)

These are properties of the codebase, not marketing claims. They cannot be turned off without rewriting the app.

### 1. On-device only — no backend, no accounts, no telemetry

- SwiftData (SQLite under the hood) is the only persistence layer.
- HealthKit reads/writes stay on device per Apple's sandbox.
- iCloud private DB sync is opt-in default-off; even when on, only the user's own devices can read.
- Verified absent in source: `URLSession`, `URL(string:`, Network, third-party SDKs.

**Differentiates from**: Flo (FTC consent order June 2021; $56M Google class-action settlement May 2025 for data sharing), Clue (server-side processing for advanced predictions), Natural Cycles (cloud-backed FDA-cleared service), Apple Health (Apple cloud-backed).

### 2. GDPR Article 9 compliance via architecture, not policy

Cycle data is "special category" health data under GDPR Art. 9. Without server processing, Tideline has **no controller obligation** — there is no central place where data can be subpoenaed, leaked, or sold. This is a structural property, not a privacy policy.

**Relevance**: post-Dobbs US legal landscape, EU GDPR enforcement, growing DACH market skepticism of US health-data apps.

### 3. PDF export generated on-device

Flo and Clue both offer "Report for a Doctor" features — but these are rendered through their cloud infrastructure. Tideline can generate the same PDF entirely on the user's phone, going directly to AirDrop / Mail / Print, with nothing crossing the network boundary.

**Differentiates by privacy, not by existence of the feature.**

### 4. Year-long dense correlation analysis at zero marginal cost

Server-backed apps paywall longitudinal analytics partly because compute cost scales linearly with user-years. On-device, the cost is zero. A user with 4 years of tracking can see all 1,460 days un-sampled, un-summarized, un-paywalled.

**Differentiates from**: Clue Plus (12-month predictions, advanced Analysis tab paywalled — verified via support docs), Flo Premium (extended Insights paywalled).

---

## Functional differentiators (could be copied — currently aren't)

These are decisions our predictor and UX make that competitors haven't matched as of mid-2026.

### 5. Disruption taxonomy with mode transitions

Five categories (Complete / Pause / Recoverable / Single anomaly / Ongoing irregularity), 25 specific event kinds, per-event recovery profiles informed by clinical literature:

- Miscarriage: ~2 cycles before pre-event μ is trusted again (Schreiber et al. 2011, PMID 21843685 — mean ovulation 20.6 ± 5.1 days)
- Medical abortion: ~2 cycles (Schreiber 2011, same paper)
- Postpartum no breastfeeding: ~2–3 cycles (Jackson & Glasier 2011, PMID 21343770 — mean first ovulation 45–94 days)
- Postpartum with breastfeeding: ~3 cycles (Gray et al. 1990, PMID 1967336 — Baltimore 27 wks vs. Manila 38 wks)
- Stopping combined OCP: ~9 cycles for full normalization (Gnoth et al. 2002, PMID 12396560 — 175 women, 3,048 cycles, only 57.9% of cycle 1 ovulatory)
- DMPA: highly variable, mean 180 ± 60.5 days to ovulation (IM 150mg)
- Emergency contraception: 1 cycle only (Tirelli et al. 2008, PMID 18402847 — follicular-phase EC shortens cycle by 10.9 ± 1 days, no effect on next cycle)

**Differentiates from**: Flo / Clue / Apple Health, which silently continue predicting through life events. No mainstream app has a "this is a paused state, predictions are suspended" mode.

**Implementation status**: `PredictorService.apply()` and `PredictorMode` are built and tested (24 tests pass). UI surface (event sheet) is Phase 1 Block 3.

### 6. Honest uncertainty as a visual property

Predictions are probabilistic with calibrated credible intervals. The interval is **rendered as a fading gradient over a 5–10 day window**, with opacity derived from the user's empirical residual distribution, not from a Gaussian assumption.

**Backed by**:
- Worsfold et al. 2021 (PMID 34629005, *Women's Health*): of 10 cycle apps tested, ovulation predictions were only **8% accurate**.
- PMC9047811 (Broad, Biswakarma, Harper 2022, n=330): 6.7% said apps "always" predict correctly; 54.9% experienced earlier periods than predicted; 72.1% experienced later; 10.9% made sexual behavior decisions on these predictions.
- Frontiers 2023 "Reimagining the Cycle" (DOI 10.3389/fcomp.2023.1166210): "apps present predictions with a sense of confidence, precision, and the tone of a medical authority, without informing the user of the margin of error."

**Differentiates from**: every mainstream app — none renders prediction uncertainty visually. Verified across Clue, Flo, Apple Health, Natural Cycles, Ovia, Eve, Period Tracker.

### 7. Conformal-prediction calibration

We use split-conformal prediction (Vovk, Gammerman & Shafer 2005; Angelopoulos & Bates 2023) on a Fehring-derived population residual set (n=1,223, MAE 2.115 days, 90th-percentile residual 4.571 days). This gives a **distribution-free finite-sample coverage guarantee** that the 90% interval will actually contain the next cycle 90% of the time, independent of whether the underlying NIG model is correctly specified.

**Differentiates from**: no peer-reviewed application of conformal prediction to menstrual cycle interval estimation has been published. We would be the first — verified by fact-checker against literature search.

**Implementation status**: `ConformalCalibrator.swift` ships with v1.

### 8. Cycle Variance River visualization

Multi-cycle comparison as the primary history canvas. Last 6–12 cycles stacked vertically, all aligned to cycle day 1 (not Gregorian date), phase-colored backgrounds, prediction as a gradient on the current row.

**Differentiates from**: only Natural Cycles has a multi-cycle Compare Mode (verified against their help docs), and it's BBT-chart-based, not calendar-based. Zero other apps have it.

**Implementation status**: Phase 1 Block 2.

### 9. Age-stratified Bayesian priors

Within-person cycle SD from AWHS 2023 (Mahalingaiah et al., PMC10226714): 5.33 days (<20) → 3.79 days (35–39) → 11.19 days (50+). The prior for a 17-year-old differs from the prior for a 47-year-old by a factor of ~3 in width.

**Differentiates from**: no app publicly documents using age-stratified priors. Apple Health, Flo, Clue use single defaults.

### 10. DRSP-mode for PMS/PMDD journaling

Optional mode using the **24-item validated DRSP** (Endicott, Nee & Harrison 2006, *Arch Womens Ment Health* 9:41–49 — 21 symptom items + 3 functional impairment items, 6-point severity scale, 2-cycle prospective tracking per DSM-5 PMDD criteria). The C-PASS scoring system (PMC5205545) operationalizes this for clinical use, achieving 98% correct classification against expert diagnosis at the 2–4 cycle threshold.

The user gets a clinically validated journaling instrument; the export goes to her clinician. **Tideline never interprets the result.**

**Differentiates from**: no mainstream app uses a validated PMS/PMDD instrument as input format. Generic symptom checklists are folk taxonomy.

### 11. No streaks, no gamification of absence

CLAUDE.md Hard Rule #9. Streaks shame illness, loss, recovery, breaks. Verified absent in source — no streak counter, no daily-log badge logic.

**Differentiates from**: Flo's daily check-in mechanics. Aligns with the "silence is a valid app state" doctrine (CLAUDE.md Principle 4).

### 12. No notifications within 4 weeks of a logged loss

CLAUDE.md Hard Rule. The `PredictorService` records loss-type events; the notification layer checks this before scheduling. A user logging a miscarriage doesn't get "your period is in 3 days" two weeks later.

**Differentiates from**: every mainstream app continues notifying through life events. Humane feature with no competitive equivalent.

### 13. Temporal Echo (retrospective pattern surfacing)

UI surfaces user's own logged patterns as descriptive recall, not forward prediction:

> "Du hast in 4 von 5 Zyklen Krämpfe an Tag 1–2 geloggt."

**Backed by**: fact-checker verified that *retrospective* logged-data display is wellness-safe under MDR. *Forward* symptom prediction ("you may experience cramps in 3 days") is a regulatory grey zone per MDCG 2019-11 Rev.1 — Tideline deliberately does NOT do forward symptom prediction.

---

## Ideas surfaced in conversation but not yet documented elsewhere

These came up in this project's chat history and would extend the differentiator set. They are **not yet design-doc'd**; this section is the record so we don't lose them.

### 14. Open-source predictor / verifiable math

The predictor uses textbook math (Murphy 2007 NIG), public priors (AWHS 2023), and public validation data (Fehring NFP, mcPHASES). Nothing in the predictor is a proprietary trade secret. **We could publish `CyclePredictor.swift` + `PredictorService.swift` as a Swift Package under an OSI license** without losing any competitive advantage.

**Differentiator**: trust signal for DACH technical audience. No cycle app currently open-sources its prediction algorithm — Flo's and Clue's "AI" claims are opaque (Worsfold 2021 confirms apps don't disclose prediction methods).

**Status**: Not started. Would require a clean module extraction and an `OpenSource/` directory.

### 15. One-time purchase pricing

Without backend infrastructure, marginal cost per user per year approaches zero. We can sustainably offer one-time purchase rather than subscription, swimming against the entire market (Flo: subscription, Clue: subscription, Natural Cycles: subscription, Ovia: free-with-data-deal).

**Differentiator**: positions Tideline as "we don't rent your cycle to you."

**Status**: Not yet decided. Business-model design block pending.

### 16. Transparency-as-USP — in-app research notes

The `docs/research/` directory contains 9 dated research notes with primary sources, fact-check passes, and citation hygiene logs. **We could bundle these as an in-app "How we predict" section** — every claim the app makes can be traced to a primary source.

**Differentiator**: directly addresses the Frontiers 2023 finding that apps "fail users precisely because they surface co-occurrence without interpretive scaffolding." We provide the scaffolding *as a feature*, not a paywalled white paper.

**Status**: Not yet designed. Would require a Markdown rendering layer in the app.

### 17. Apple-Watch-native fertility tracking without cloud

Natural Cycles requires their own thermometer and operates as an FDA-cleared Class II contraceptive. We could position as the **on-device equivalent that uses Apple Watch wrist temperature** via `appleSleepingWristTemperatureRelativeToBaseline` — without a dedicated device and without cloud processing.

**Backed by**: Hum Reprod 2025 study (n=216, 889 cycles) showed wrist-temperature-augmented predictions reduce MAE from 1.90 to 1.70 days — modest but real.

**Differentiator**: Tideline could be the open Apple-Watch wrist-temperature interpreter, contrasting with Natural Cycles' closed device-dependent model.

**Status**: Phase 3 work block ("Wrist-temperature DSP pipeline"), already in roadmap.

### 18. Verifiable export receipts

Every PDF export could embed an on-device SHA-256 hash + timestamp. A clinician can verify the file hasn't been tampered with. For users facing legal scrutiny over their cycle data (US post-Dobbs forensic contexts), this is a real-world differentiator.

**Differentiator**: niche but defensible. No competitor offers cryptographic export integrity.

**Status**: Not yet designed. Trivial implementation (~30 LOC).

---

## What we explicitly do NOT differentiate on

- **Symptom prediction**: forward-looking "you may have cramps in 3 days" is MDR grey zone (fact-checked). We deliberately don't do it.
- **Diagnostic interpretation**: never. Hard Rule #5 of CLAUDE.md.
- **AI-generated insights as cycle prediction**: Apple Intelligence summaries are descriptive only; Hard Rule #7.
- **Body-literacy education**: Block 2 market research showed the market moved on from this; Spot On (Planned Parenthood) is the historical comparator and not a strong differentiator in 2026.
- **Phase narrative** (Flo's Instagram-story cards): heavily exploited + MDR risk.

---

## Citation hygiene notes

Fact-checker (2026-05-20) caught multiple author-attribution errors in earlier research-analyst passes. Corrections applied:

- **PMC7250828** is **Li et al. 2020, NPJ Digital Medicine**, not "Masterson 2020" or "Symul 2020" as previously cited.
- **PMC9517532** is **Sung-Hee Kim 2022, 13-study review**, not "Sarsenbayeva 2022, 56-study review."
- **PMC10623599** is **Frans et al. 2023, *Assessment***, not "Coppock 2023, JAMIA."
- "Sanchez-Sepulveda et al. 2025 six ethical concerns" is actually **Mittelstadt et al. 2016, *Big Data & Society***, DOI 10.1177/2053951716679679.
- **Endicott DRSP** has **24 items** (21 symptom + 3 functional impairment), not 11 as previously stated.
- **Worsfold 2021** EXISTS (PMID 34629005); earlier analyst pass flagged it as not locatable.
- **MDCG 2019-11 Rev.1** (June 2025) — direct quotes need re-verification against the official PDF before being included in user-facing copy.

## Primary sources for the verified differentiator claims

- Worsfold et al. 2021 — Period tracker accuracy across 10 apps: https://pubmed.ncbi.nlm.nih.gov/34629005/
- Broad, Biswakarma, Harper 2022 — User-experience survey n=330: https://pmc.ncbi.nlm.nih.gov/articles/PMC9047811/
- Frontiers 2023 "Reimagining the Cycle": https://www.frontiersin.org/articles/10.3389/fcomp.2023.1166210/full
- Mahalingaiah et al. 2023 — AWHS: https://pmc.ncbi.nlm.nih.gov/articles/PMC10226714/
- Harlow et al. 2013 — Perimenopause changepoint: https://pmc.ncbi.nlm.nih.gov/articles/PMC3979630/
- Schreiber et al. 2011 — Ovulation after medical abortion: https://pubmed.ncbi.nlm.nih.gov/21843685/
- Jackson & Glasier 2011 — Postpartum ovulation: https://pubmed.ncbi.nlm.nih.gov/21343770/
- Gnoth et al. 2002 — Cycles after OCP: https://pubmed.ncbi.nlm.nih.gov/12396560/
- Tirelli et al. 2008 — LNG-EC effects: https://pubmed.ncbi.nlm.nih.gov/18402847/
- Endicott et al. 2006 — DRSP: https://pubmed.ncbi.nlm.nih.gov/16172836/
- Eisenlohr-Moul 2017 — C-PASS: https://pmc.ncbi.nlm.nih.gov/articles/PMC5205545/
- Li et al. 2020 — NPJ Digital Medicine (Clue dataset): https://pmc.ncbi.nlm.nih.gov/articles/PMC7250828/
- Murphy 2007 — Conjugate Bayesian: https://www.cs.ubc.ca/~murphyk/Papers/bayesGauss.pdf
- Angelopoulos & Bates 2023 — Conformal prediction: https://arxiv.org/abs/2107.07511
