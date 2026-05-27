---
date: 2026-05-25
status: research plan (waves in flight)
owner: solo dev
decision: whether to invest in features that improve intra-cycle phase prediction beyond the current `cycleLength − 14` heuristic
---

# Research Plan: Improving phase prediction with medical literature + symptom patterns

## What we're deciding

The Tideline predictor (Bayesian NIG on cycle length) is well-grounded for *next-period-date* prediction. But the **phase boundaries** inside a cycle (menses end, follicular start, ovulation, luteal start/end) are computed via heuristics:
- `mensesEnd` — Belsey-aligned walk over user's logged bleeding days (just fixed in #156).
- `ovulation` — `cycleLength − 14`. The textbook folk rule.
- `lutealStart` / `lutealEnd` — derived from `ovulation` + 3 / `cycleLength`.

Three open questions determine whether shipping additional phase-prediction features is worth the effort:

1. **Q1 — Per-individual luteal-length stability.** If one woman's luteal is reliably stable (say SD < 1 d), we can replace the `−14` with her own learned value. If it's noisy (SD > 3 d), the folk rule isn't materially worse.
2. **Q2 — Cross-cycle symptom repeatability.** If Anna's "cramps on day 1–2, headache day 14" pattern repeats month to month, we can grow Mein Zyklus Layer 2 from "showing what happened" to "showing what's probable." If patterns don't repeat, pattern panels stay descriptive.
3. **Q3 — Ovulation timing without wearables.** Most users will not have an Apple Watch (yet) and will not manually log OPK. Is there a defensible Bayesian method using cycle date + self-reported cervical mucus + Mittelschmerz that meaningfully beats `cycleLength − 14`? Or is the honest answer "wait for wearable hardware"?

Each question maps to a real product feature with real cost. We don't ship any of them without primary-literature support, and we explicitly accept "wontfix" as a valid outcome.

## Research waves

### Wave 1 — Q1 luteal stability (IN FLIGHT, launched 2026-05-25)

4 parallel agents:
- **W1.A** — Within-person luteal SD primary literature (Bull 2019, Lenton 1984, Crawford 2017, Hambridge 2013, Mahalingaiah AWHS 2023, Fehring 2006).
- **W1.B** — Predictors of inter-individual luteal length (age, BMI, parity, LPD prevalence per ASRM, postpartum recovery, post-pill recovery).
- **W1.C** — Date-only luteal inference methods (does the "follicular dominates variance" claim hold? Are there published latent-variable models?).
- **W1.D** — Competitor approaches (Natural Cycles published method via Bull 2019; Marquette/Fehring; Sensiplan/Frank-Herrmann; Clue/Flo claims).

### Wave 2 — Q2 cross-cycle symptom repeatability (LAUNCHING NOW)

2 parallel agents:
- **W2.E** — Cycle-to-cycle symptom autocorrelation in primary literature. DRSP repeatability (Endicott 2006), within-person symptom consistency, premenstrual symptom calendar studies (Halbreich, Eisenlohr-Moul C-PASS 2017 PMC5205545), Mittelschmerz repeatability, dysmenorrhea pattern consistency.
- **W2.F** — Commercial app pattern-detection methodology. Clue Insights, Flo predictions, Ovia personalized insights, any academic accuracy studies of these features.

### Wave 3 — Q3 ovulation without wearables (LAUNCHING NOW)

2 parallel agents:
- **W3.H** — Cervical mucus + Mittelschmerz + symptothermal primary literature. Billings Ovulation Method, Creighton Model, Sensiplan (Frank-Herrmann 2007 Hum Reprod), WHO multinational NFP studies, Standard Days Method (Arevalo/Sinai 2002), Two-Day Method, Marquette without temp.
- **W3.I** — Bayesian statistical fusion of self-reported indicators without temperature. Calendar method historical efficacy bound (Pearl Index baseline), composite symptom indices, MDR-compatible visualization approaches.

## Fact-check protocol

Per CLAUDE.md and user memory `feedback_fact_check_research.md`:
> research-analyst hallucinates citations and effect sizes; always fact-check before quoting.

After each wave:
1. Cross-reference all PMIDs/DOIs in the synthesis against actual PubMed records.
2. Verify all effect sizes against the primary paper (not abstracts).
3. Flag any unverifiable claim with "🤷 — could not verify" rather than removing it silently.
4. Promote/demote claim-confidence (✅ verified / ⚠️ partial / 🤷 unverified / 🔴 fabricated).

Cross-references against verified baseline knowledge:
- AWHS 2023 — Mahalingaiah PMC10226714 ✅
- Bull 2019 npj DM — DOI 10.1038/s41746-019-0152-7 ✅
- Goodale 2025 Hum Reprod 40(3):469 — wrist-temp MAE 1.70 vs 1.90 ✅
- DRSP — Endicott 2006 PMID 16172836 ✅
- Belsey 1988 — PMID 3048871 ✅
- HRV ovulation null — Oura PMC9005074 p=0.13 ✅
- Apple Watch sleep stages — PMC11511193 50.5% deep-sleep sensitivity ✅
- Long COVID × cycle — Maybin 2025 PMC12441152 ✅
- Fehring NFP dataset — PMID 23153900 ⚠️ partial; licensing block per #155

## Synthesis (after fact-check)

Single consolidated document per wave:
- `docs/research/2026-05-25-q1-luteal-stability.md`
- `docs/research/2026-05-25-q2-symptom-repeatability.md`
- `docs/research/2026-05-25-q3-ovulation-without-wearables.md`

Cross-wave decision matrix:
- Feature × evidence-strength × MDR-compatibility × effort × dependency.

## Implementation plan (only after research + fact-check converge)

Will produce:
- New tracker items with priority and phase.
- Effort estimates per item (single dev-days; conservative).
- Dependency chains (which items block which).
- Explicit "wontfix" items with rationale.

Standing rules (CLAUDE.md):
- Pillar 2: never claim diagnostic / contraceptive / conception efficacy. Anything we ship must be a *display of user data* or *population context*, never *interpretation of personal data*.
- Pillar 3: honest uncertainty over false precision. New features either tighten the credible interval with real evidence or do nothing.
- Pillar 4: silence is valid. If a feature can't ship MDR-compatibly, it stays out.

## Out of scope for this research arc

- v2 mixture predictor (#83) — already designed, doesn't need more research.
- Conformal calibrator (#124) — blocked on Fehring licensing (#155), separate workstream.
- Wrist-temp Kalman (Phase 4b) — already documented in data-fusion research wave 2026-05-24.
- v2.5 μ-drift random walk — documented in `project_tideline_predictor_roadmap`.
- Symptoms as predictor inputs for cycle-LENGTH — explicitly null per data-fusion wave 2026-05-24.

This research arc is specifically about **intra-cycle phase boundary** improvement and **cross-cycle symptom pattern surfacing**, not about cycle-date prediction (which is solved-enough at v1).
