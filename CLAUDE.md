# CLAUDE.md

Persistent context for Claude Code sessions on the Tideline project. Read this first.

---

## Project

**Tideline** — privacy-first, gamified menstrual cycle tracking app for iOS.

- **Repo:** https://github.com/CarliDerZerstoere/tideline (private)
- **Local path:** `~/Developer/CycleApp/`
- **Stage:** Pre-alpha. Project scaffold + numeric core stub + design docs. No working UI yet.
- **Owner:** Solo developer (cybersecurity SOC analyst, master's student, EU-based, German native, English working language)
- **Target markets:** DACH (Germany, Austria, Switzerland) and Denmark primarily; global secondary

---

## Product pillars (load-bearing — read every time)

1. **On-device only.** No accounts. No backend. No telemetry. No third-party SDKs that phone home. SwiftData local + optional iCloud private sync. The architecture itself is the privacy story.
2. **No medical advice. Ever.** App stays in EU MDR wellness/lifestyle classification. The line: showing data = safe; interpreting data into clinical statements = regulated. AI summary layer (Apple Intelligence) is constrained to "summarize what you logged," never "this means X about your health."
3. **Honest uncertainty over false precision.** Predictions are probabilistic with credible intervals. Wider intervals are not failures — they are accurate. The model shows what it knows and what it doesn't.
4. **Silence is a valid app state — but never the *only* response.** After a logged disruption (abortion, miscarriage, etc.), no prediction is shown — that's correct. When a period is just late, the app stays informative without diagnosing.
5. **No streaks.** Streaks shame absence — illness, loss, recovery, breaks. Engagement must come from value, not punishment.

---

## What never to do (hard rules)

- ❌ Never add cloud analytics SDKs (Firebase, Sentry, Mixpanel, etc.)
- ❌ Never add third-party SDKs that exfiltrate any data
- ❌ Never claim contraceptive efficacy (triggers EU MDR Class IIb)
- ❌ Never claim conception-facilitation efficacy (triggers EU MDR Class I)
- ❌ Never display diagnostic interpretations ("you may have PCOS," "your luteal phase is short")
- ❌ Never use AI output for cycle/ovulation prediction — only for summarization
- ❌ Never send a notification about cycle predictions within 4 weeks of a logged loss
- ❌ Never let notification preview text reveal cycle/pregnancy info on lockscreen
- ❌ Never use streaks for logging
- ❌ Never prompt the user to categorize the cause of bleeding
- ❌ Never amend an existing commit (always create new commits)

---

## Tech stack

| Layer | Choice |
|---|---|
| Language | **Swift 6 + SwiftUI** |
| Concurrency | Strict concurrency enabled (`SWIFT_STRICT_CONCURRENCY: complete`) |
| Persistence | **SwiftData** (Core Data underneath); iCloud private DB opt-in only |
| Health data | **HealthKit** (Apple Watch wrist temperature, RHR, HRV, sleep, period flow) |
| On-device AI | **Foundation Models framework** (Apple Intelligence) for summaries; deterministic template fallback for non-AI-capable devices |
| Numeric prediction | Pure Swift, no ML framework: Bayesian NIG conjugate predictor + DSP temperature pipeline |
| Auth | None (no account) |
| Backend | None for MVP |
| Payments | StoreKit 2 (when needed) |
| Crash reporting | MetricKit (on-device, opt-in upload only) |
| CI | Xcode Cloud (free tier) |
| Project generation | **xcodegen** — `project.yml` is committed; `.xcodeproj` is gitignored |
| Build tool | Xcode 26+; iOS 18.0 minimum deployment target |

**Bundle ID:** `com.carliderzerstoere.tideline`

---

## Repo layout

```
~/Developer/CycleApp/
├── CLAUDE.md                       ← this file
├── README.md                       ← user-facing project README
├── project.yml                     ← xcodegen source of truth
├── .gitignore
├── docs/
│   ├── README.md                   ← docs index
│   ├── design/                     ← design decisions
│   │   ├── disrupted-cycles.md
│   │   └── late-and-missed-periods.md
│   ├── research/                   ← dated immutable research outputs
│   │   ├── 2026-05-19-*.md
│   └── memory/                     ← living append-only docs
│       └── edge-cases.md
└── Tideline/
    ├── Sources/
    │   ├── App/                    ← @main entry point
    │   ├── Models/                 ← SwiftData models (Cycle, DayEntry; CycleEvent planned)
    │   ├── Views/                  ← SwiftUI views
    │   └── Services/               ← CyclePredictor, future HealthKit service, future AI service
    ├── Resources/                  ← assets, entitlements
    └── Tests/                      ← Swift Testing framework
```

---

## Working with this repo

### Before doing anything code-related
1. Read this file
2. Read `docs/README.md` for the docs index
3. Read the relevant `design/*.md` for whatever you're touching
4. Check `memory/edge-cases.md` for known issues

### Generating the Xcode project
`.xcodeproj` is gitignored. Regenerate locally:
```sh
xcodegen generate
```

### Building / testing
Requires Xcode 26.4+ with **iOS 26.4 platform installed** (Settings → Platforms → install). CoreSimulator may need a system update if mismatched.

### Conventions
- **Design docs are the source of truth.** If implementation diverges from the doc, update the doc first, then the code.
- **Research notes are write-once.** Date them; don't edit. Supersede with new dated notes.
- **`memory/edge-cases.md` is append-only.** Update entry status, never delete.
- **Cite research from design docs.** Every design decision should link to its evidence.
- **No documentation in code unless WHY is non-obvious.** Identifier names should carry meaning.
- **Tests use Swift Testing framework** (`@Suite`, `@Test`, `#expect`), not XCTest.

---

## Active design decisions

The doctrine that shapes everything:

### Predictor
- **v1 (current):** Bayesian Normal-Inverse-Gamma conjugate model over cycle length (`CyclePredictor.swift`). Single Gaussian likelihood. Math is textbook (Murphy 2007); see file header for derivation.
- **v2 (planned, design approved):** **2-component Bayesian mixture** per `docs/design/mixture-predictor.md` — Normal ovulatory + shifted log-normal anovulatory, fit by Gibbs sampling. Per-event recovery profiles replace uniform soft reset. Estimated 7-12 dev-days.
- **Population prior:** μ=28.7 (verified from AWHS 2023, Mahalingaiah PMC10226714, n=165,668 cycles); within-person SD age-stratified from same source (5.33 under 20; 3.79 at 35-39; 11.19 at 50+).
- **Cycle predictions are always probabilistic** — point estimate + credible interval, never a single date.
- **Inference algorithm choice (Gibbs, not CAVI):** Gibbs gives calibrated posteriors (CAVI underestimates variance). Doctrine alignment with Principle 6 of `disrupted-cycles.md` ("honest uncertainty over false precision") was the decisive factor. Latency budget easily met either way.

### Disruption handling (`design/disrupted-cycles.md`)
Five event categories with explicit algorithm reactions:
- **A. Complete disruption** (hysterectomy, oophorectomy) → retire predictor
- **B. Extended pause** (breastfeeding, hormonal contraception, HA) → pause mode, archive posterior
- **C. Recoverable disruption** (abortion, miscarriage, birth, stopping contraception, illness) → outlier-reject + soft reset
- **D. Single anomaly** ("this wasn't normal") → outlier-reject only
- **E. Ongoing irregularity** (PCOS) → widen β, range-only display

### Late period handling (`design/late-and-missed-periods.md`)
- Never go silent. Show info at every milestone.
- Pregnancy test suggestion at 10–14 days late, framed as population behavior ("many people take a test at this point"), never as personalized advice.
- Continue showing prediction with widening conditional credible interval all the way through. At very late stages (>30 days), switch from date-range UI to "no clear estimate" + information surface.
- No differential diagnosis suggestions. Ever.

### Hormone tracking (research summarized; design doc pending)
- HealthKit reads for wrist temperature, RHR, HRV, sleep — Tier 1, build now
- Manual entry for quantitative OPK values (Inito, Mira, Proov) — Tier 1
- Manual entry for blood lab results (E2, P4, LH, FSH, AMH) with cycle-day context — Tier 1, genuinely differentiating
- Camera-based strip scanning — deferred (Premom does it well)
- AI diagnostic interpretation of hormone values — never

### What the AI layer does
- Apple Intelligence / Foundation Models generates **journal-style summaries** of the user's own logged data
- Strict prompt guardrails: never generate medical interpretation
- Regex post-filter rejects diagnostic language
- Static template fallback for devices without Apple Intelligence

---

## Active questions / decisions deferred

(Mirror of the open questions across design docs; check those for context.)

- Gamification rework (streaks invalidated; what replaces them?)
- Whether to enable iCloud private DB sync (opt-in default off)
- Adolescent vs. adult late-period thresholds
- Perimenopause self-declared mode design
- Pill/contraception tracking design doc (planned)
- Ovulation prediction design doc (planned)
- Hormone tracking design doc (planned)

---

## Research evidence base

Six dated research notes in `docs/research/` (all from 2026-05-19) cover:
- Market sizing and competitor analysis
- How existing apps predict cycles (algorithms, signals)
- Disrupted-cycles literature (medical + UX)
- Accuracy improvement techniques
- Hormone tracking methods and accuracy
- Late period clinical handling

Cite these from design docs. If you're researching something new, save the output as a new dated research note.

---

## Regulatory posture (must understand before shipping any feature)

- **EU MDR (Regulation 2017/745):** Tideline targets Article 2(1) "general wellness" — software for personal logging without diagnosis/prognosis. As long as we don't claim conception, contraception, or diagnostic utility, we are not a medical device.
- **EU AI Act (Regulation 2024/1689):** High-risk classification triggers via Article 6(1) + Annex I if the AI is a safety component of a medical device (MDR Class IIa+). We are not. AI Act deadlines for high-risk medical AI are moving (currently proposed Aug 2028 per Digital Omnibus); not our concern unless classification changes.
- **GDPR Article 9:** Cycle data is special category health data. On-device storage = no controller obligation. iCloud sync (if enabled) = Apple is processor, we disclose.
- **The MDR boundary line:** show user-entered/observed data and population statistics = wellness. Generate personalized clinical interpretation = medical device.

Before shipping any feature that touches medical-adjacent territory, sanity-check against `design/disrupted-cycles.md` § "Regulatory Posture" and the late-periods doc § "Pregnancy test suggestion — the regulatory hairline."

---

## Communication style

- The owner wants substantive engagement, not boilerplate.
- They will push back hard on suspicious claims — be ready to cite sources.
- They will invoke fact-checker on anything that smells off. So get it right the first time.
- They prefer English in technical conversations; German for product UX copy review.
- They are technically literate; you can use stats and ML terminology without dumbing it down. When the math gets dense, supplement with concrete worked examples.

---

## Last updated

2026-05-19 — initial creation. Predictor stub written, design docs in draft, six research notes archived. No UI, no HealthKit integration, no AI integration yet.

2026-05-19 (later, same day) — Option D mixture predictor design approved. New verified research note added (`research/2026-05-19-mixture-predictor-verified.md`) consolidating primary-source values after fact-checking exposed citation hallucinations in earlier research-analyst outputs. New design doc `design/mixture-predictor.md` written. Existing research notes have correction sections appended. Earlier predictor priors superseded by verified AWHS 2023 values.

2026-05-24 — 9-agent parallel research wave + fact-check pass. Outputs documented in:
- `research/2026-05-24-feature-research-wave.md` — evidence trail (every citation, every agent finding, fact-check audit, verification debt)
- `roadmap/2026-05-24-research-findings-integration.md` — the plan (NEW-I through NEW-BB feature candidates by phase, pattern-detection extensions for Mein Zyklus Layer 2 post-#120, monetization specifics, citation corrections to apply across existing docs)

**Citation corrections to apply wherever they appear:** endometriosis 10.4-year delay → Hudelist et al. 2012 (PMID 22990516), NOT "Dian 2022"; Flo settlement → "$56M/$59.5M preliminary, final approval pending," NOT "finalized Sept 2025"; postpartum median → 14.6 months (not 14.5); vzbv "77% would grant Frauenarzt access" → **REMOVE** (could not be verified, treat as fabricated). High-priority verification debt: Fehring NFP dataset (basis of conformal calibrator in `ConformalResiduals.swift`) — verify before v2/conformal ships in Phase 3.

**Decision additions:** R1 €4.99 one-time price band (range €3.99–€6.99). R2 no supporter-tier IAP at launch. R3 Mein Zyklus Layer 2 v1.0 patterns confirmed; v1.1 extensions queued. R4 seasonality pattern surfacing **NEVER** (effect smaller than logging resolution, PMC10872302). R5 T-suppression mode requires co-design before code. R7 Sensiplan NFP-Modus with fertile-window computation out of scope for v1.

2026-05-24 (later, same day) — 5-agent design-level deep dive on highest-stakes NEW-* candidates. Output: `research/2026-05-24-design-research-deep-dive.md`. Unlocks 4 future design docs (perimenopause, hormone log, intra-day stamps, DRSP PDF). Two are blocked on user research / co-design / clinician input — don't draft yet:
- `docs/design/perimenopause-mode.md` — needs 6–8 DACH user interviews on the 8 open questions before drafting (NEW-P)
- `docs/design/inclusive-language-t-suppression.md` — must be co-authored output, not solo-drafted (NEW-Y)
- `docs/design/hormone-log.md` — can be drafted now from §2 of deep-dive note (NEW-Q)
- `docs/design/intra-day-stamps.md` — can be drafted now from §4 of deep-dive note (NEW-W); ship as first Phase 4 task after v1.0 stable; DRSP PDF (NEW-X) follows after DRSP-Modus #47 ships

**Fehring NFP dataset status update** (basis of `ConformalResiduals.swift`): graduated 🤷 → ⚠️ partial verification. Dataset exists (Marquette ePublications item 7, Fehring 2013 PubMed 23153900); extractor script + raw CSV exist in repo at `data/`. Cohort counts (159/1665) cannot be confirmed from published source alone — owner can confirm by running `wc -l data/raw/fehring_cycles.csv`. **Licensing risk:** Marquette consent-bound dataset; shipping derived residuals in commercial app requires written permission from Fehring (alive, not deceased — Marquette professor emeritus) or Marquette Institute for NFP. Three blockers before Phase 3 conformal wrapper ships (see `research/2026-05-24-design-research-deep-dive.md` §5).

**Decision additions:** R8 perimenopause mode: two-path design (active settings declaration + soft suggest triggered by B2 variance pattern at STRAW −2 threshold). R9 recommended predictor β multiplier for perimenopause: **`beta *= 4.0`** (vs PCOS 2.5×); predictor team to validate. R10 DRSP scoring boundary: compute phase means + per-item display = safe; binary "meets criteria" output = forbidden. R11 intra-day stamps schema migration uses Option A (keep scalar `symptoms`+`moodRaw` cache on `DayEntry` for backward compat; append SymptomStamp on each log). R12 ship order: intra-day stamps schema (NEW-W) → DRSP-Modus logging UI (#47) → DRSP PDF section (NEW-X). All Phase 4. R13 DRSP itself is evening-anchored by design — intra-day stamps benefit free-form symptom logging, not DRSP ratings.

2026-05-24 (third wave, same day) — 5-agent implementation-depth research + verification-debt cleanup pass. Output: `research/2026-05-24-implementation-depth-research.md`. Unlocks 6 future design docs (skiptrack, postpartum-mode, reusable-product-log, menstrual-migraine, chronic-illness-cycle-context, cycle-archaeology). Three discoveries materially change earlier framing:

**🚨 Flo does NOT write to HealthKit** (verified from Flo's own help docs). Cycle Archaeology (NEW-S) marketing must be scoped to "Apple Health Cycle Tracking, Clue, or possibly Stardust users" — NOT Flo. Flo migrants need future CSV import (out of v1 scope).

**🚨 Germany exclusive breastfeeding at 6 months = 13%** (KiGGS via PMC12460087), NOT 50–60% as previously assumed. Ethiopian Gompertz cohort (PMC9580771) is NOT directly applicable to DACH. NEW-O parameterized survival curve **blocked** on DACH-appropriate cohort data; milestone-text approach can ship as v1 fallback.

**🚨 Three citations corrected / removed:** "ovul.ai 82% PCOS prediction failure" 🔴 likely fabricated (no matching npj DM 2023 paper exists) — remove from all docs. Embody tagline "no logins, no data sharing, no fertility questions" fabricated (not in Hypepotamus article) — paraphrase or drop. Menstrual migraine PMC10512516 mechanism framing reversed — paper CONTESTS estrogen-withdrawal hypothesis, doesn't confirm it; cite as "contested per Raffaelli 2023."

**Verification graduations:** Long COVID medRxiv ✅ (better citation now: Maybin 2025 Nature Comms PMC12441152, peer-reviewed); wrist-temp MAE 1.70 vs 1.90 ✅ (Goodale/Shilaih Hum Reprod 40(3):469, 2025, n=260); wearable fertility 0.88 ✅ (PMC12886881 n=6,244).

**Decision additions:** R14 ship NEW-M SkipTrack BEFORE v2 mixture predictor (Phase 3a, ~3–4 dev-days, 80–120 LOC on single-component NIG; arXiv:2508.05845 verified + MIT-licensed R package). R15 Cycle Archaeology marketing scope: Apple Health / Clue / possibly Stardust only (NOT Flo). R16 NEW-V schema: Option A (keep `DayEntry.flow` categorical + add `cupChanges: [CupChange]` relationship; categorical wins as user's declared experience). R17 NEW-T architectural fit: self-tag modifying symptom layer NOT Category E reuse (long COVID users may have regular cycles + amplified symptoms). R18 NEW-O parameterized survival curve blocked on DACH data; milestone-text v1 OK. R19 NEW-U inherits B4 generic phase-conditional pattern (no dedicated UI) but with structured migraine subtype (aura, duration, severity) for Doctor PDF. R20 Maybin 2025 Nature Comms PMC12441152 = primary citation for long COVID × cycle (Visible preprint supporting secondary).

**Suggested Phase 3 reordering** (owner decision): #97 already done → NEW-L #131 adolescent prior (~1d) → **NEW-M #132 SkipTrack** (~3–4d) → #83 v2 mixture + NEW-E conformal wrapper (~7–12d) → NEW-O #133 postpartum milestone-text (~M).

2026-05-24 (triple-check pass, same day) — owner-requested independent re-verification of the three Phase 4 citations from the implementation-depth research wave. Three corrections documented in `research/2026-05-24-implementation-depth-research.md` §10:

1. **Maybin 2025 (Nat Comms, PMC12441152) is NOT the published version of the Visible/Goodship preprint** (10.1101/2025.01.24.25321092). They are two independent studies — Maybin = Edinburgh-led, 3 nested cohorts (n=12,187 + n=54 + n=10+10 biological); Visible/Goodship = Imperial College, n=948, still standalone preprint not retracted. Both stand independently as corroborating evidence. Revise R20 framing: "independent corroborating sources," not "supersedes."

2. **Menstrual migraine window is 5 calendar days, not 6.** ICHD-3 specifies day 1 = first day of bleeding with **no day 0**; valid offsets {−2, −1, +1, +2, +3} = 5 elements. The "days −2 to +3" range notation is correct; only the "6-day window" phrasing was wrong. Implementation must skip day 0 in offset arithmetic.

3. **PMC9580771 authorship = Belay & Asratie** (Daniel Gashaneh Belay; Melaku Hunie Asratie) — not "Bekele et al." as written in earlier waves. Fix anywhere the citation appears.

DACH postpartum cohort void confirmed as **true literature gap** (not search failure). DEGS1 and KiGGS do not publish return-of-menses as endpoint. If product copy depends on a DACH-specific curve, targeted German-language search (DIMDI/LIVIVO) is the next step; otherwise milestone-text approach (per R18) is the agreed v1 path.

All three corrections are framing/attribution issues, not citation hallucinations — the underlying PMC IDs all verify ✅.

2026-05-24 (fourth wave, same day) — 4-agent cross-cutting research on **data fusion** (combining the multi-modal data Tideline collects/plans-to-collect into new features). Output: `research/2026-05-24-data-fusion-research.md`. Unlocks 3 future design docs (data-fusion-architecture, fusion-features-catalog, fusion-ux-principles). Key findings:

**Literature reality:** No formal sequential ablation study exists (dates → +temp → +HRV → +sleep MAE at each step) — genuine gap, not search failure. HRV is too noisy at individual level (p=0.13 in Oura PMC9005074). Apple Watch sleep stages have 50.5% deep-sleep sensitivity (PMC11511193) — measurement error exceeds signal. Bayesian fusion of OPK + wrist temperature has **no peer-reviewed implementation** — genuine novel contribution for Tideline.

**Architecture (R21):** Modular Bayesian factor graph with per-modality conjugate sub-models, NOT monolithic state-space. Each layer's failure mode isolated; degrades gracefully when modalities absent. **R22:** Pre-aggregated `DailySummary` SwiftData table via `BGProcessingTask` (NOT `BGAppRefreshTask` — throttled). HK query never on critical foreground path. **R23/R24:** HRV and Apple Watch sleep stages as anomaly flags only, not predictor inputs.

**DACH UX reality:** Only **15% of Germans willing to share health data with technology companies** (PMC11836014, n=1004 representative). 66% actively refuse. The "technology company as adversary" mental model dominates. Architecture is private but presentation must communicate that — "wir haben gemerkt" = highest creepiness; "du hast gemerkt" = correct frame. **R25:** Fusion notifications on-demand default; Tier 2 HK opt-in; Tier 3 explicit per-feature; push prohibited in post-loss window.

**Top 6 priority fusion features:** (1) Wrist-temp Kalman layer Phase 4b; (2) phase-corrected within-person cardiovascular baselines Phase 4a; (3) quantitative OPK Bayesian hormone fusion Phase 4f; (4) symptom-to-symptom historical pattern display Phase 4d; (5) anovulatory-pattern flagging via cosinor Phase 4c; (6) per-event recovery profile personalization Phase 4e. Total Phase 4 fusion work: ~12–17 dev-days sequenced.

**Explicitly punted:** CGM × cycle (1.7pp time-in-range = practically invisible for healthy users), HRV ovulation detection (p=0.13), Apple Watch sleep stages for cycle inference, joint state-space over all modalities (dimensional explosion), per-user neural networks (data too sparse), federated learning (Pillar 1).

**Implementation verification debt:** Gibbs sampler 15–25ms latency is **unverified on Tideline code** — instrument with `PerfSignpost` on release build before treating as hard target. The "Mu 2021 38% no-signal rate" cited in earlier work could NOT be verified in any retrieved paper — closest is 19.2% (Goodale 2025) or 26% (PMC8238491 anovulatory only). **Do not cite the 38% figure.**
