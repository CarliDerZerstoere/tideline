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
- **Bayesian Normal-Inverse-Gamma conjugate model** over cycle length (`CyclePredictor.swift`). Math is textbook (Murphy 2007); see file header for derivation.
- **Population prior:** μ=29, κ=2, α=3, β=41.07 (calibrated to within-person SD ~3.7 days; from Apple WHS 2023, not the often-misquoted between-person SD of ~7 days).
- **Cycle predictions are always probabilistic** — point estimate + credible interval, never a single date.

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
