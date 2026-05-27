# Tideline Documentation

Documentation for the Tideline iOS app. Structured so future contributors (human or AI) can orient quickly.

## Layout

```
docs/
├── README.md                ← you are here
├── design/                  ← design decisions, source of truth for behavior
├── research/                ← raw research outputs from sub-agents (dated, immutable)
├── roadmap/                 ← dated planning snapshots; latest = current direction
└── memory/                  ← living, append-only project memory
```

(See individual sections below for full file inventories — this tree is not exhaustive.)

## Design docs

Source of truth for product behavior. Reviewed before implementation. Updated when behavior changes; never deleted.

| Doc | Scope | Status |
|---|---|---|
| `design/disrupted-cycles.md` | How user-declared disruption events (abortion, miscarriage, birth, contraception, illness) affect the predictor and UX | Draft for review |
| `design/late-and-missed-periods.md` | Behavior when a period is late or absent without a user-declared cause | Draft for review |
| `design/mixture-predictor.md` | **Option D**: 2-component Bayesian mixture (Normal ovulatory + log-normal anovulatory), Gibbs sampling, per-event recovery profiles. Supersedes the single-component model. | Draft for review |

## Research notes

Dated, immutable archives of sub-agent research output. These are the evidence base behind design decisions. Cite them when the question "why does the app do X" comes up.

| Note | Topic | Date |
|---|---|---|
| `research/2026-05-19-femtech-market.md` | Market sizing, competitor analysis, feature gaps in current cycle apps | 2026-05-19 |
| `research/2026-05-19-prediction-methodology.md` | How existing apps technically predict cycles (algorithms, signals, accuracy) | 2026-05-19 |
| `research/2026-05-19-disrupted-cycles.md` | Clinical/UX literature on handling abortion, miscarriage, birth, contraception in cycle apps | 2026-05-19 |
| `research/2026-05-19-accuracy-improvements.md` | Techniques to improve cycle prediction accuracy beyond a basic Bayesian model | 2026-05-19 |
| `research/2026-05-19-hormone-tracking.md` | Consumer methods for hormone tracking; accuracy vs. clinical lab; regulatory implications | 2026-05-19 |
| `research/2026-05-19-late-period-clinical.md` | Clinical handling of late/absent periods; differential diagnosis; conditional prediction | 2026-05-19 |
| `research/2026-05-19-mixture-predictor-verified.md` | **Web-enabled verification pass**. Primary-source extraction of numerical priors for the mixture-model predictor. Supersedes earlier notes where they conflict. | 2026-05-19 |
| `research/2026-05-20-cycle-app-calendar-ux-market.md` | Cycle-app calendar UX patterns + market positioning | 2026-05-20 |
| `research/2026-05-20-v2-improvement-techniques-verified.md` | Verified techniques for v2 predictor improvements | 2026-05-20 |
| `research/2026-05-21-market-research-synthesis.md` | Cross-source synthesis of market research outputs | 2026-05-21 |
| `research/2026-05-21-mein-zyklus-tab-research.md` | Research informing the Mein Zyklus tab redesign (NEW-A / #120) | 2026-05-21 |
| `research/2026-05-24-feature-research-wave.md` | **9-agent parallel research wave** (DACH market, competitive gaps, femtech trends, segments, peer-reviewed studies, user-voiced needs, PM synthesis, fact-check, pattern detection). Source-of-record for the NEW-I through NEW-BB feature candidates and the citation corrections. | 2026-05-24 |
| `research/2026-05-24-design-research-deep-dive.md` | **5-agent design-level deep dive** on the highest-stakes NEW-* candidates: NEW-P perimenopause (STRAW staging, 10-item symptom vocab, β×4.0 predictor), NEW-Q hormone log (reference range citations, Swift schema, MDR table), NEW-Y inclusive language + T-suppression (co-design plan), NEW-W intra-day stamps + NEW-X DRSP PDF (schema migration + C-PASS boundary). Includes **Fehring NFP dataset verification update** (graduated 🤷 → ⚠️ with 3 action items before Phase 3). | 2026-05-24 |
| `research/2026-05-24-implementation-depth-research.md` | **5-agent implementation-ready research** on remaining NEW-* candidates: NEW-M SkipTrack (arXiv paper read directly, MIT-licensed R package, 80–120 LOC port, recommended Phase 3a before v2 mixture), NEW-O postpartum Gompertz (DACH data gap discovered: German exclusive BF only 13% at 6mo invalidates Ethiopian curve), NEW-V reusable product log (30 cup brand capacities verified, schema sketch), NEW-T+U long COVID + migraine combined (Maybin 2025 Nature Comms upgraded to primary; migraine mechanism framing reversed). Includes **fact-check graduation pass** (6 items: ovul.ai "82% PCOS failure" 🔴 fabricated; Embody tagline 🔴 fabricated; Flo HK write status verified NO — invalidates "Flo migrant" pitch). Note §10 errata: Maybin and Visible preprint are **independent** corroborating sources (not super/sub); menstrual migraine window is **5 calendar days** (not 6); PMC9580771 authorship = **Belay & Asratie** (not Bekele). | 2026-05-24 |
| `research/2026-05-24-data-fusion-research.md` | **4-agent cross-cutting research** on combining Tideline's multi-modal data: peer-reviewed multi-signal cycle prediction literature (no formal ablation studies exist — genuine gap; HRV too noisy at individual level p=0.13; Apple Watch sleep stages 50.5% sensitivity = below signal), technical architecture (modular Bayesian factor graph with per-modality conjugate sub-models + DailySummary pre-aggregation via BGProcessingTask), feature catalog (F1–F10 combination categories, top 6 prioritized), and DACH-specific value vs. creepiness UX (only 15% Germans willing to share with tech companies per PMC11836014; copy direction principles + opt-in tier structure). Decisions R21–R26. Unlocks `docs/design/data-fusion-architecture.md`. | 2026-05-24 |

## Roadmap

Dated planning snapshots. Each is write-once; the most recent reflects current direction. Read in chronological order to reconstruct decision lineage.

| Doc | Scope | Date |
|---|---|---|
| `roadmap/2026-05-22-consolidated-roadmap.md` | Initial Phase 0–5 consolidation; decisions D1–D7 | 2026-05-22 |
| `roadmap/2026-05-24-roadmap-update.md` | Phase reordering (TestFlight before v2 mixture predictor); decisions D8–D10; records Phase 1 ship status | 2026-05-24 |
| `roadmap/2026-05-24-research-findings-integration.md` | **Additive** to the above two. Integrates the 2026-05-24 research wave: NEW-I through NEW-BB feature candidates, pattern-detection extensions, monetization specifics (€4.99 price band), citation corrections | 2026-05-24 |

## Memory

Living, append-only documents that capture project knowledge across sessions. New findings, edge cases, decisions get added here.

| Doc | Purpose |
|---|---|
| `memory/edge-cases.md` | Catalog of edge cases (clinical, technical, safety, legal, privacy) with current handling status |

## Conventions

- **All design decisions live in `design/`.** If it's not there, it isn't decided.
- **Research notes are write-once.** They date a snapshot of evidence. If new research supersedes old, write a new dated note; don't edit the old one.
- **`memory/` is append-only.** Add to it. Don't delete entries; mark them resolved or superseded.
- **Cite research from design.** Design docs should link to the specific research notes that justify their decisions.
- **The `CLAUDE.md` at the repo root** is the project's persistent context for AI sessions. Update it when long-lived principles change.
