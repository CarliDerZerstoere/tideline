# Tideline Documentation

Documentation for the Tideline iOS app. Structured so future contributors (human or AI) can orient quickly.

## Layout

```
docs/
├── README.md                ← you are here
├── design/                  ← design decisions, source of truth for behavior
│   ├── disrupted-cycles.md
│   └── late-and-missed-periods.md
├── research/                ← raw research outputs from sub-agents (dated, immutable)
│   ├── 2026-05-19-femtech-market.md
│   ├── 2026-05-19-prediction-methodology.md
│   ├── 2026-05-19-disrupted-cycles.md
│   ├── 2026-05-19-accuracy-improvements.md
│   ├── 2026-05-19-hormone-tracking.md
│   └── 2026-05-19-late-period-clinical.md
└── memory/                  ← living, append-only project memory
    └── edge-cases.md
```

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
