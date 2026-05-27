# Tideline — Research Findings Integration

**Date:** 2026-05-24
**Status:** **Additive** to `2026-05-22-consolidated-roadmap.md` and `2026-05-24-roadmap-update.md`. Does not supersede either. Brings the output of a parallel research wave (7 specialist agents + 1 fact-check pass) into the existing phase structure.

**Synthesized from this session's agents:**
- DACH market gaps (market-researcher)
- Competitive feature gaps (competitive-analyst)
- Femtech trends 2024–2026 (trend-analyst)
- Underserved user segments (ux-researcher)
- Peer-reviewed cycle/hormone research (scientific-literature-researcher)
- User-voiced unmet needs from Reddit/App Store/forums (search-specialist)
- Product synthesis + monetization (product-manager)
- Pattern recognition deep dive (research-analyst)
- Citation verification pass (fact-checker)

---

## 0. What this document adds

The 2026-05-22 consolidated roadmap set the Phase 0–5 structure. The 2026-05-24 update re-ordered the phases (TestFlight readiness before v2 mixture predictor) and recorded what shipped since. This document adds:

1. **New feature candidates** placed into the existing phase structure (~18 net-new vs. de-duplicated against shipped work)
2. **Pattern-detection extensions** beyond the three patterns shipped in #120 (Mein Zyklus Layer 2)
3. **Monetization specifics** firming up D3 (€4.99 recommended price band + reasoning)
4. **Citation corrections** that must propagate to existing design and research docs
5. **New open questions** raised by the research that need decisions before the corresponding features ship

D1–D10 from the prior roadmaps all carry forward unchanged. Out-of-scope list extended at §8.

---

## 1. New feature candidates, placed by phase

Candidates de-duplicated against tasks already shipped per the 2026-05-24 update (#46, #71, #74, #75, #76, #79, #80, #81, #85, #90, #91, #95, #96, #97, #103, #120, #121, #123).

### 1.1 Phase 2A additions (small, complement TestFlight sprint)

| Candidate | Source | Notes | Effort |
|---|---|---|---|
| **NEW-I** Vaccine / illness disruption event subtype | PMC12083795, PMC12168487 (vaccine effect +0.34–0.62 days) | Extend `EventKind` in `CycleEvent.swift` with `.illness` / `.vaccination`. Adds a population-fact information chip ("Manche Menschen bemerken einen leicht verlängerten Zyklus nach Impfung oder Krankheit — meist normalisiert er sich in 1–2 Zyklen"). Predictor effect is small enough to defer formal soft-reset; outlier-rejection (#96) absorbs it. | S — ~0.5d |
| **NEW-J** Standalone "I had a loss" log event (pre-clinical losses) | Search-specialist findings on Clearblue / Flo gap; pre-clinical losses unlogged today | Today Category C requires a logged prior pregnancy state. Allow "I had a loss" as standalone log without that prerequisite. Trigger same 28-day suppression (#122) and recovery soft-reset. | S — ~0.5d |
| **NEW-K** Promote privacy disclosure (#123) to first onboarding screen | Search-specialist: "fake data defense" loop documented across PMC12131320; Embody's positioning validates "privacy-first" as conversion lever | Currently the privacy section lives in Mehr tab. Adding a single onboarding screen that shows the architecture diagram (data stays on device, no account, no backend) before any data entry. | S — ~0.5d |

These three are pre-alpha-compatible and fit within the Phase 2A cleanup batch without disturbing the TestFlight cut.

### 1.2 Phase 3 additions (extend the v2 mixture predictor work)

| Candidate | Source | Notes | Effort |
|---|---|---|---|
| **NEW-L** Gynecologic-age-stratified prior branch for adolescents | PMID 38570085 (OR 2.6 for highly-variable, OR 5.0 for short cycles when <1y post-menarche, comparator 6+ years post-menarche, **verified exactly** by fact-checker) | Extends #97 (which shipped age-stratified within-person SD). Adolescent users (asked optionally during onboarding per D10) get dramatically wider μ and β priors for first 1–2 years post-menarche. Display: "Cycles are often irregular for the first 2–3 years — your predictions will have wide ranges, and that's normal." | S — ~1d (math + copy; prior infrastructure exists) |
| **NEW-M** SkipTrack-aware long-cycle disambiguation prompt | arXiv:2508.05845 (Harvard/Apple/NIEHS 2025, **arXiv ID verified**) | When a recorded cycle length exceeds (e.g.) 1.5 SD above posterior mean, surface a one-tap prompt: "Looks longer than usual. Did you start a period that wasn't logged?" Answer updates the posterior cleanly. Inside the Gibbs sampler, unconfirmed long cycles receive appropriate uncertainty weight. | M — paper has open-source R reference implementation; port + UI ~3d |
| **NEW-N** Per-event recovery profile dispatch | `mixture-predictor.md` § "Per-event recovery profiles" | Already in Phase 3 scope (#83). Calling out explicitly: `PredictorService.apply(eventKind:)` line ~46–108 currently calls `softReset()` uniformly for all Category C events; replace with per-event lookup table (postpartum ≠ EC ≠ miscarriage ≠ stopping HC). | Bundled in #83 |
| **NEW-O** Postpartum Gompertz-IG survival curve display | PMC9580771 (Ethiopian DHS cohort, median **14.6 months** — fact-checker correction from 14.5; 7–24 month breastfeeding → AHR 0.64) | When user logs birth, instead of "expect period in 6–12 weeks," display population survival curve conditional on logged breastfeeding status. Updates each cycle logged. Pre-computed parameters; no user data leaves device. | M — ~3d (curve renderer + breastfeeding-status log) |

### 1.3 Phase 4 — net-new candidates (post-launch)

These are the strongest beta-feedback-informed bets. The 2026-05-22 roadmap already lists hormone tracking and HK biometrics as Phase 4. The candidates below extend that list.

| Candidate | Source | Build | MDR |
|---|---|---|---|
| **NEW-P** Perimenopause self-declared mode | Convergent across 4 agents; PMC3979630 Harlow change-point methods; Verified Market Research / Grand View show market growth | M — predictor mode + symptom vocab + reframed "pattern" UI (no countdown). Mixture model's anovulatory component scales up gracefully. | Safe if user-declared; never auto-detect |
| **NEW-Q** Quantitative hormone/lab log (E2, P4, LH, FSH, AMH, numeric OPK) | Already Tier 1 per CLAUDE.md § "Hormone tracking"; convergent across 4 agents; no privacy-safe competitor offers this | M — new data model + cycle-day-anchored timeline view | Safe for display + population reference ranges; borderline if phrasing implies timing prediction — constrain at copy level |
| **NEW-R** Cardiovascular amplitude descriptive view | PMC11666598 (WHOOP n=11,590, **PMC/n verified**; specific BPM/ms digits PARTIAL pending Table 2 check) | S — rolling min-max over cycle window using HK RHR/HRV (Phase 4 prereq: those HK reads exist) | Safe — descriptive only; flattens on hormonal contraception, useful sanity-check signal |
| **NEW-S** Cycle Archaeology — deep HK historical import | UX-researcher (Flo/Clue switching friction); existing `HKImportPlanner.swift` is the infrastructure | M — extends #71 to seed Bayesian posterior from past period-start records rather than population prior | Safe |
| **NEW-T** Long COVID / ME-CFS perimenstrual symptom clustering surface | medRxiv 2025.01.24.25321092 (n=948 Visible app users — **DOI not yet verified by fact-checker**, follow up) | M — symptom-cluster pattern surface + optional chronic-illness self-tag; widen #122 notification suppression window | Safe (display user's own data clustering, no etiology claim) |
| **NEW-U** Menstrual migraine window marker | PMC10512516 (ICHD-3 window days −2 to +3 — **PMC not yet verified by fact-checker**) | S–M — distinct symptom category + phase-distribution chart in Doctor PDF | Safe — pattern display + clinical handoff, never diagnostic |
| **NEW-V** Reusable product log (cup/disc fill → flow volume) | DACH agent: Europe menstrual cup CAGR 10.5% (Grand View Research, **flag as paid projection**) | S–M — product selection UI + fill-to-volume conversion table + hookup to existing `FlowLevelPicker` | Safe |
| **NEW-W** Intra-day symptom stamps | PMC11687174 PMDD user research, arXiv 2409.03853 multimodal study (loop-closing problem) | M — schema migration: `DayEntry` becomes parent of timestamped `SymptomStamp` list; daily summary shows range (min/max), not average. Doctor PDF gets full intra-day record. | Safe |
| **NEW-X** DRSP-format Doctor PDF section | IAPMD DRSP instrument; PMC11687174 — "no current menstrual app has full DRSP capabilities" | M — 11 DSM-5-aligned symptom-dimension grid, two-cycle daily layout, cycle-phase overlay. Pairs with #47 DRSP-Modus. | Safe — exporting user-entered data in clinical format ≠ diagnosis |
| **NEW-Y** Inclusive / configurable language layer + T-suppression mode | Euki precedent; ux-researcher segment analysis | S for vocabulary parameterization (cheap now, expensive to retrofit); M for full T-suppression mode | Safe. **Requires co-design with trans/NB users before any string is written** |

### 1.4 Phase 5 — net-new candidates

| Candidate | Source | Build | Notes |
|---|---|---|---|
| **NEW-Z** Signal-confidence layer (HRV / sleep / wrist-temp quality weighting) | PMC12886881 systematic review (wearable fertility-window accuracy 0.88 — **PMC not yet verified**); Sports Medicine 2025 living systematic review on HRV honesty | M — display layer showing which signals contribute to credible-interval width per cycle | Phase 5 because depends on v3 wrist-temp pipeline existing |
| **NEW-AA** CGM × cycle overlay | PMC10421863 (npj Digital Medicine 2023, n=49, biphasic glucose pattern across cycle) | S–M — HK CGM read + overlay on phase chart, no interpretation | First-mover positioning; competitor catch-up window ~18–36 months |
| **NEW-BB** Shift-worker schedule declaration + temperature signal-quality filter | UX-researcher; ~18% of German employed work shift/night | L — depends on v3 temperature pipeline (Phase 5) | Architect the temperature pipeline to accept per-reading quality weights when v3 lands, so this is a config layer not a rewrite |

---

## 2. Pattern detection — extensions beyond #120

The 2026-05-24 update marked open question #4 (Mein Zyklus Layer 2) **resolved** with #120 shipping three patterns: phase length stability + cycle-length trend + bleeding-days vs average.

The pattern-recognition research confirms those three are correct v1.0 picks. It also recommends extensions for v1.1+ and v2 (Phase 3 / Phase 4 work). The full taxonomy is documented below; design doc to be written at `docs/design/mein-zyklus-pattern-extensions.md` before any of these ship.

### 2.1 Recommended v1.1 additions (post-TestFlight feedback)

| Pattern | What user sees | Min-N gate | Method | MDR |
|---|---|---|---|---|
| **B4** Phase-conditional symptom frequency | "Headaches in your luteal phase: 4 of 5 cycles. Follicular: 1 of 5." | 5 cycles with symptom logged in each | Bayesian binomial proportion comparison; report risk ratio with 99% credible interval (multiple-testing correction); only display when CI excludes 1.0 | Safe — display user's own data, no etiology |
| **B3** Symptom severity trend across cycles | Sparkline of severity by cycle with Bayesian regression line + 90% CI band; only render trend line when slope CI excludes zero | 6 cycles with symptom logged in 4+ | Bayesian NIG regression on severity-by-cycle sequence (same machinery as B1) | Safe |
| **C3** Skip-log transparency | "Logged on 4 of 7 days this cycle — your symptom history may have gaps" | None (meta-observation) | Log timestamp counter | Safe; data-quality framing, not pattern claim |

### 2.2 Phase 4+ candidates (gated by HK wearable reads or data depth)

| Pattern | Gate | Notes |
|---|---|---|
| **A4** Within-cycle wearable biometric shift | Apple Watch wrist temp + RHR + HRV; ≥2 cycles | Lead Phase 4 differentiator for Apple Watch users |
| **B2** Cycle-length variability change | ≥10 cycles split into 5/5 windows | Harlow-style approach; perimenopause precursor signal (do NOT label as such) |
| **B5** Anovulatory frequency via cosinor | Apple Watch wrist temp; ≥6 cycles complete data | Display label must never use "anovulatory" — use "no clear temperature shift pattern" |
| **C1** Sleep × mood next-day correlation (phase-corrected) | ≥30 day-pairs | Phase is a powerful confounder; phase-residualize or include as factor |
| **C2** Lifestyle event × cycle-length response | ≥10 cycles, event present in ≥4 / absent in ≥4 | High user demand, no individual-level competitor |

### 2.3 Detection-method toolkit (reusable across patterns)

For implementation in `Sources/Services/PatternObservationGenerator.swift` (file already exists per untracked git status — extend rather than rewrite):

1. Bayesian NIG regression on scalar sequences (B1, B3)
2. Bayesian binomial proportion comparison (B4, A5)
3. Posterior predictive variance ratio (B2)
4. Cosinor analysis on temperature time series (A4, B5)
5. Phase-conditional lagged correlation (C1)
6. Bayesian run-length detection (A5, C3)
7. **99% credible interval threshold** as multiple-testing correction (12 simultaneous pattern checks → conservative threshold required)
8. **Minimum-N gating layer** as pre-filter before any pattern surfaces

### 2.4 The "no pattern detected" UX contract

This is the doctrinal point Tideline must hold against the engagement-maximizing competitor pattern (Flo invents content; Clue surfaces analysis at 2–3 cycles which is too few).

- Before min-N gate: progress framing — *"Tracking for 4 more cycles unlocks your phase-symptom patterns"*, NOT "premium feature locked"
- After min-N gate but no pattern detected (CI includes null): first-class UI state — *"No consistent phase pattern detected for headaches in your last 6 cycles. This could mean your headaches aren't cycle-related, or we need more cycles to see clearly."*
- Pattern detected: lead with frequency count *"Headaches in your luteal phase: 5 out of 6 recent cycles"*. Never *"you always get headaches in your luteal phase"*. Denominator always visible.

### 2.5 Phase 4+ pattern-detection ambitions (post v2 mixture predictor)

- **Causal inference (interrupted time series)** using per-event recovery profiles as the inversion target
- **Symptom-as-covariate in Gibbs sampler** for per-cycle anovulatory-component membership probability
- **PACTS-style phase normalization** (ScienceDirect 2025) once ovulation timestamps are estimated — substantially sharpens B4
- **Sparse Bayesian network for symptom co-occurrence** (purely observational, no causal claims) — requires 20+ cycles
- **Seasonality detection — explicitly do NOT ship.** PMC10872302 found max 0.16-day difference between seasonal months. This is the "Flo statistical noise as personalized insight" anti-pattern.

---

## 3. Monetization specifics — firming up D3

D3 (one-time IAP, no subscription) carries forward unchanged. Adding price-band recommendation:

**Recommended: €4.99 one-time** (defensible range €3.99–€6.99).

Reasoning:
- **DACH price ceiling.** €10+ signals "premium subscription app," conflicts with Pillar 1.
- **App Store comparables.** One-time cycle trackers price €1.99–€2.99 (basic) to €4.99–€7.99 (full). Tideline's feature set (mixture predictor + Doctor PDF + zero infra cost) justifies upper half.
- **Sustainability math.** At €4.99 × 2,000 conservative Year-1 DACH users = ~€10k gross; Apple 30% cut leaves €7k. Bridgeable for solo dev with no infra costs.
- **Trust signal.** Pricing itself signals "this dev isn't squeezing you" against Flo's €9.99/month + dark patterns.
- **Refund risk.** Low price = low refund pain if v1.0 features feel hollow on day 2.

**Not recommended:** €1.99 (signals race-to-bottom, undervalues v2 mixture + conformal); €9.99+ (invites Flo direct comparison on price).

**Supporter tier proposal.** Defer to v1.2. If post-launch users say "I want to give you more money," add a single optional non-consumable IAP (~€9.99) framed as "fund future updates" — not a feature unlock. Don't add at v1.0 launch (confuses positioning).

**Freemium feature wall — confirmed off-limits.** Requires either cloud backend (violates Pillar 1) or device-local DRM (security theater; users can delete app state). Pillar 1 forces one-time-or-nothing.

---

## 4. Citation corrections — apply across existing design and research docs

The fact-check pass identified several errors in the brain-dump and one apparent fabrication. These must be corrected wherever they appear before being cited in product collateral, App Store copy, or new design docs.

| Where it appears | Wrong | Correct |
|---|---|---|
| DACH market notes / `differentiators.md` (if cited) | Endometriosis 10.4-year delay cited as "Dian et al. 2022" | **Hudelist G et al., Hum Reprod 2012;27(12):3412**, PMID 22990516 (n=171 Austria+Germany) |
| Any reference to Flo settlement | "$59.5M class-action, finalized September 2025" | "$56M/$59.5M combined preliminary settlement (Google $48M + Flo $8M + other defendants), **preliminary approval April 2026, final approval still pending**" |
| Postpartum mode design / NEW-O above | median 14.5 months | median **14.6 months** (PMC9580771) |
| Any reference to menopause app market size | "$345.6M / 17.2% CAGR (Verified Market Research)" | "$345.6M / 17.2% CAGR (**Grand View Research**, not VMR); paid market-research projection — VMR's separate figure is $1.5B / 12.5% CAGR; treat as directional only" |
| Any reference to "vzbv 77% of users would grant Frauenarzt access" | as currently stated | **REMOVE.** Fact-checker could not locate this vzbv publication. Treat as unverified until owner produces primary URL. |
| Any reference to Sensiplan efficacy | "Pearl Index 0.4" alone | "Pearl Index 0.4 perfect-use, **PI 1.6 typical-use** — cite both per Frank-Herrmann et al. 2007, Hum Reprod 22(5):1310" |
| COVID-19 vaccine cycle effect citations | "n=747,763" | n=30,320 (the meta-analysis); 747,763 was a population-study count incorrectly conflated |
| Flo MAU citation | "75M MAU" stated as fact | "~75M MAU **per Flo's own reporting**" (no independent audit; most recent figure 77M as of March 2026) |

**Still requiring verification before use** (fact-checker flagged but did not have time to verify):
- Fehring NFP dataset characteristics (159 subjects, 1665 cycles, MAE 2.115d) — **this is the basis of the conformal calibrator in `ConformalResiduals.swift`**. High-stakes; verify against primary source before predictor v2 ships with the conformal wrapper.
- ovul.ai "82% PCOS calendar-prediction failure" — vendor source; find the underlying 340-woman 2023 ultrasound validation study before citing
- Wrist-temperature MAE 1.70 vs 1.90 days (Human Reproduction 2025) — used in Phase 5 v3 planning rationale
- Long COVID × cycle medRxiv 10.1101/2025.01.24.25321092 (NEW-T source) — DOI exists check
- Menstrual migraine ICHD-3 PMC10512516 (NEW-U source) — PMC ID check
- Embody app download count + launch date (used as monetization-thesis evidence)
- Stardust Privacy International report (used as "local-first claims caught lying" evidence)

---

## 5. Launch positioning — copy proposals

App Store subtitle (PM agent, 30-char limit):
> **"Deine Zyklusvorhersagen. Dein Gerät. Punkt."**

First sentence of description:
> "Tideline respects you: honest, on-device cycle tracking with no account, no backend, no ads, no nonsense. One purchase, full access forever."

Five-screenshot suite (per 2026-05-22 roadmap §5, sharpened):
1. **Privacy-as-architecture** (Datenschutz-Cockpit visible during onboarding, NEW-K)
2. **Retrospective recognition** (Mein Zyklus Layer 1 + Layer 2 patterns, #120 work)
3. **Doctor PDF** (#46 shipped; sharpest competitive screenshot)
4. **Honest uncertainty** (predictor showing credible interval, not single date — directly attacks Flo/Clue false precision)
5. **Loss-aware silence** (notification settings showing 28-day suppression toggle, #122)

These remain proposals — not committed until TestFlight assets sprint (Phase 2C).

---

## 6. New open questions raised by research

Carry forward + new from this wave:

**From prior roadmap, still open:**
- iCloud sync conflict policy (CRDT-like merge for `DayEntry`) — Phase 4 / NEW-G blocker

**New from this wave:**
1. **Vaccine/illness marker (NEW-I):** Should it formally reset the predictor or just inform copy? Effect size (0.3–0.6 days) is small enough to defer formal reset; recommend copy-only for v1.
2. **Intra-day symptom stamps (NEW-W):** `DayEntry` → parent of timestamped `SymptomStamp` list is a schema migration. Cost vs. benefit decision needed before Phase 4.
3. **Long COVID symptom clustering (NEW-T):** Should it require explicit user opt-in (chronic illness self-tag), or surface for all users whose logs cluster?
4. **Inclusive language (NEW-Y):** Strings parameterized by user-declared identity, or universally neutralized for all users? Universal-neutral is cheaper but loses some specificity.
5. **T-suppression mode (NEW-Y):** Co-design required with 6–10 trans men / NB users on T before any code is written. UX-researcher emphasis: harm from getting language wrong is documented and significant.
6. **Onboarding privacy-first screen (NEW-K):** Risk that emphasizing privacy upfront raises threat-model anxiety in users who weren't already privacy-conscious. Test in TestFlight.
7. **Pattern-recognition design doc:** Should be written at `docs/design/mein-zyklus-pattern-extensions.md` before any v1.1 pattern (B3, B4, C3) ships. Captures the 99%-CI multiple-testing convention and the min-N gating table.

---

## 7. Tracker delta proposed

| ID | Phase | Description | Effort |
|---|---|---|---|
| NEW-I (#128) | 2A | Vaccine/illness event subtype | S 0.5d |
| NEW-J (#129) | 2A | Standalone "I had a loss" log | S 0.5d |
| NEW-K (#130) | 2A | First-screen privacy onboarding | S 0.5d |
| NEW-L (#131) | 3 | Gynecologic-age-stratified adolescent prior | S 1d |
| NEW-M (#132) | 3 | SkipTrack-aware long-cycle disambiguation | M 3d |
| NEW-N — bundled in #83 | 3 | Per-event recovery profile dispatch | bundled |
| NEW-O (#133) | 3 | Postpartum Gompertz survival curve | M 3d |
| NEW-P (#134) | 4 | Perimenopause self-declared mode | M |
| NEW-Q (#135) | 4 | Quantitative hormone / lab log | M |
| NEW-R (#136) | 4 | Cardiovascular amplitude descriptive view | S |
| NEW-S (#137) | 4 | Cycle Archaeology deep HK import | M |
| NEW-T (#138) | 4 | Long COVID / ME-CFS clustering surface | M |
| NEW-U (#139) | 4 | Menstrual migraine window marker | S–M |
| NEW-V (#140) | 4 | Reusable product log + flow volume | S–M |
| NEW-W (#141) | 4 | Intra-day symptom stamps (schema migration) | M |
| NEW-X (#142) | 4 | DRSP-format Doctor PDF section | M |
| NEW-Y (#143) | 4 | Inclusive language + T-suppression mode (co-design first) | S+M |
| NEW-Z (#144) | 5 | Signal-confidence layer | M |
| NEW-AA (#145) | 5 | CGM × cycle overlay | S–M |
| NEW-BB (#146) | 5 | Shift-worker schedule + temp quality filter | L |
| Pattern-extensions (#147) | 4 (post-beta) | B3 + B4 + C3 pattern surfaces in Mein Zyklus Layer 2 v1.1 | M |
| Fehring dataset verification (#148) | 3 prerequisite | Verify primary source before conformal wrapper ships with v2 | XS but blocking |

Numbers above are placeholder slots; assign on tracker entry.

---

## 8. Additions to "explicitly out of scope" list

Extending the 2026-05-22 / 2026-05-24 out-of-scope list:

- ❌ **AI cycle / ovulation prediction** (Flo's Databricks direction). MDR Class reclassification trigger. Different from the already-allowed AI summary layer.
- ❌ **Camera-based OPK / strip scanning** (Premom's territory). Bundled ML model + validation cost + privacy risk if cloud-routed. Manual numeric OPK entry (NEW-Q) covers the need.
- ❌ **FDA / MDR contraceptive-efficacy certification** (Natural Cycles route). €500k–1M validation cost, 3–5 years, undermines wellness classification.
- ❌ **Community / social features** (period-buddy groups, forum). Moderation nightmare, requires server.
- ❌ **Sensiplan NFP-Modus with fertile-window computation.** Legal complexity exceeds value for v1; the Sensiplan method itself is Class I medical device territory once the app computes fertile/infertile days. Displaying user-logged mucus observations alongside temperature without computing windows is technically safe but creates ambiguity worth avoiding.
- ❌ **Seasonality pattern surfacing.** Effect size (0.16 days max-month difference, PMC10872302) is smaller than logging resolution. Showing this would be the "Flo statistical noise as personalized insight" anti-pattern that Tideline's pattern-detection doctrine specifically rejects.

---

## 9. What this update deliberately does *not* commit to

- **Exact dates.** Same as prior roadmaps.
- **Per-cycle resource allocation.** No sprint planning here.
- **All candidates in §1 shipping.** This is a candidate pool to prioritize against beta feedback; not a Phase 4 commitment list. The 2026-05-24 update's TestFlight-first decision (D8) means Phase 3 onwards is informed by real users.
- **Pattern-recognition extensions before v1.0 ships.** §2.1 candidates are queued for v1.1+; #120 already shipped the v1.0 set.

---

## Document conventions

Same write-once dated convention as the prior two roadmaps. When priorities shift materially again, write a new `docs/roadmap/YYYY-MM-DD-*.md`. This file is now part of the dated snapshot index alongside `2026-05-22-consolidated-roadmap.md` and `2026-05-24-roadmap-update.md`. All three are read in chronological order to reconstruct the decision lineage.
