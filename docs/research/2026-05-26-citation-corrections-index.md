# Citation Corrections Index (task #157)

**Date**: 2026-05-26
**Task**: #157 — Fix citation errors in predictor + cycle-grouping docs
**Status**: Consolidated index; corrections themselves applied across
prior research notes via §10-style errata sections (per the
`write-once / supersede` convention from `docs/README.md`).

This is a single-page lookup so future readers don't have to traverse
eight research notes to find which earlier claim was corrected.

## Active corrections

| Original claim | Source | Status | Correct attribution | Where errata applied |
|---|---|---|---|---|
| "Dian et al. 2022" for endometriosis 10.4y delay | research/2026-05-24-feature-research-wave.md early draft | ✅ **Corrected** to Hudelist G et al., Hum Reprod 2012;27(12):3412, **PMID 22990516** | `feature-research-wave.md` §verification + roadmap-resync.md line 127 |
| "Bekele D et al." for PMC9580771 postpartum cohort | research/2026-05-24-implementation-depth-research.md §2.1 | ✅ **Corrected** to Daniel Gashaneh Belay & Melaku Hunie Asratie (2 authors, NOT "et al.") | `implementation-depth-research.md` §10.3 |
| "Maybin 2025 Nat Comms supersedes Visible/Goodship preprint" | research/2026-05-24-implementation-depth-research.md initial R20 | ✅ **Corrected** — independent corroborating sources, not super/sub | `implementation-depth-research.md` §10.1 |
| "Menstrual migraine 6-day window" | research/2026-05-24-implementation-depth-research.md initial draft | ✅ **Corrected** — 5 calendar days; ICHD-3 specifies day 1 = first day of bleeding, no day 0, offsets {−2,−1,+1,+2,+3} | `implementation-depth-research.md` §10.2 |
| "ovul.ai 82% PCOS prediction failure" | research/2026-05-24-design-research-deep-dive.md initial draft | 🔴 **Likely fabricated** — no matching npj DM 2023 paper exists. Remove from competitive analysis | `implementation-depth-research.md` §verification table |
| "Embody tagline: no logins, no data sharing, no fertility questions" | research/2026-05-24-implementation-depth-research.md initial draft | 🔴 **Fabricated** — not in source Hypepotamus article. Paraphrase verified positioning instead | `implementation-depth-research.md` §verification table |
| "vzbv 77% would grant Frauenarzt access to app data" | research/2026-05-24-feature-research-wave.md line 79 | 🔴 **Could not be verified** — fact-checker found no matching vzbv publication. Treat as fabricated. Remove from product copy | `feature-research-wave.md` §verification + roadmap-resync.md line 130 |
| "Bosman RC, Jung SE, Miloserdov K. Daily fluctuations in mood. Hum Reprod 38(11):2126–2133 (2023)" | research/2026-05-25-phase-prediction-synthesis.md initial draft | 🔴 **Fabricated** — does not exist in PubMed, Hum Reprod TOC, or Google Scholar (Claude hallucination). Possible confusion with Pierson et al. 2021 Nat Hum Behav | `phase-prediction-synthesis.md` §research-discipline + `empirical-validation-results.md` table |
| "Flo settlement finalized Sept 2025" | early research/roadmap | ✅ **Corrected** — "$56M/$59.5M preliminary, final approval pending" | roadmap-resync.md |
| "Postpartum median 14.5 months" | early research | ✅ **Corrected** to 14.6 months | roadmap-resync.md |
| "Flo writes to Apple Health" — basis for "Flo migrant" Cycle Archaeology marketing | research/2026-05-24-implementation-depth-research.md §3 (NEW-S) | ✅ **Verified NO** per Flo's own help docs. Cycle Archaeology marketing scope shrunk to Apple Health Cycle Tracking / Clue / possibly Stardust | `implementation-depth-research.md` §verification |

## Where the in-code predictor + cycle-grouping citations live

Predictor (`CyclePredictor.swift` + `MixturePredictor.swift`) and
cycle-grouping (`PhaseBoundaries.cycleStarts` in `CyclePhase.swift` +
`CycleStore.rebuildCyclesFromDayEntries`) reference:

- **Murphy 2007** — NIG conjugate derivation (textbook, no PMID; bookchapter)
- **Mahalingaiah et al. 2023, PMC10226714** — AWHS μ=28.7, age-stratified σ
- **Belsey 1988, PMID 3048871** — WHO/Belsey ≤2-day rule for menses-episode grouping
- **FIGO 2018** — 21-day floor for new-cycle detection
- **Bull et al. 2019, PMC6710244** — Bull luteal mean 12.4d
- **Harlow & Zeger 1991** — 43-day anovulatory threshold
- **Guo et al. 2006** — mixture-model structure for cycle length
- **Fehring 2013, PMID 23153900** — NFP dataset basis of conformal residuals
- **Vovk, Gammerman, Shafer 2005** — split-conformal theory
- **Angelopoulos & Bates 2023, arXiv:2107.07511** — conformal primer
- **Nassaralla et al. 2011, PMC7643763** — post-OCP cycle 1 stats

All are real, verified, and cited correctly in-code. No corrections
needed in predictor/cycle-grouping production code paths.

## What this doc replaces

Before this index, finding a citation correction required:
1. Knowing the corrected claim was wrong in the first place
2. Knowing which research note documented the correction
3. Reading that note's §10 errata section

Now: search this single file for the suspect claim; the table tells
you where the correction lives.

## How to maintain

When a new fact-check pass uncovers a citation error:
1. Apply the correction in a §-errata section of the next dated
   research note (the existing notes are write-once per docs/README.md)
2. Add one row to the table above with the correction + the location
   of the errata

## Out of scope for this task

- **Re-verifying the corrections themselves** — that was done in the
  May-2026 fact-check passes per the verification graduations in the
  source notes
- **Removing wrong citations from research notes in-place** — the
  write-once convention is explicit; the §10 errata + this index is the
  documented pattern
- **Auditing every research note for additional errors** — out of
  scope; this task addresses the known corrections only
