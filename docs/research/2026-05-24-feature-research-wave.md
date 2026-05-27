# 2026-05-24 — Feature Research Wave

**Date:** 2026-05-24
**Type:** Research note (write-once per project convention).
**Purpose:** Source-of-record for the feature candidates documented in `docs/roadmap/2026-05-24-research-findings-integration.md`. Every citation, every claim, every agent output the roadmap relies on is recorded here. If the roadmap says "per NEW-O, postpartum survival curve from PMC9580771," the evidence trail is in §3.2 below.

**Why this exists:** Earlier research outputs (the 2026-05-19 batch) contained citation hallucinations that were only caught later by fact-checking. This note keeps the evidence-to-decision lineage explicit so future-me (and the owner) can re-verify any claim without re-running the research.

---

## 0. Methodology

Two parallel waves of specialist agents dispatched from a single session, each tackling a complementary angle. Hard constraints baked into every prompt (no MDR violations, no cloud, no streaks, no diagnostic claims, on-device only). Each agent told what was already on the roadmap so they didn't duplicate.

### Wave 1 (4 agents, parallel)
| Agent | Angle | Output summary location |
|---|---|---|
| market-researcher | DACH-specific unmet needs (Frauenarzt visit context, NFP tradition, German clinical vocabulary, menstrual cup market, GDPR posture) | §3.1, §3.6 below |
| competitive-analyst | Feature gap matrix across Flo, Clue, Natural Cycles, Stardust, Glow, Apple Health, Cyclotest mySense, Trackle, FemSense, Drip, Euki, Premom, Inito, Mira, Oura | §3.5 below |
| trend-analyst | Femtech trends 2024–2026 (post-Dobbs privacy migration, perimenopause market, wearable signal convergence, iOS 26 Foundation Models, CGM × cycle) | §3.4 below |
| ux-researcher | Underserved segments (postpartum, perimenopause, PCOS, endo, loss survivors, trans/NB, adolescents, athletes, shift workers, chronic illness) | §3.3 below |

### Wave 2 (3 agents, parallel)
| Agent | Angle | Output summary location |
|---|---|---|
| scientific-literature-researcher | Peer-reviewed cycle/hormone research not yet productized | §3.2 below |
| search-specialist | Reddit / App Store / German forums / GitHub issues for user-voiced complaints | §3.7 below |
| product-manager | Synthesis pass — v1.0 bundle composition, pricing band, kill list | §4 below |

### Wave 3 (2 agents, parallel)
| Agent | Angle | Output summary location |
|---|---|---|
| fact-checker | Verification of high-stakes citations from Waves 1+2 | §5 below |
| research-analyst | Pattern-recognition deep dive for Mein Zyklus Layer 2 extensions | §3.8 below |

Total: 9 agent dispatches, run in 3 parallel batches.

---

## 1. Hard constraints all agents worked within

Same as CLAUDE.md product pillars + hard rules. Repeated here so this doc can be read standalone:

- On-device only. No cloud analytics, no accounts, no third-party SDKs phoning home.
- No medical / diagnostic interpretation. No "you may have PCOS" / "your luteal phase is short."
- No contraceptive efficacy claims (MDR Class IIb trigger). No conception-facilitation claims (Class I).
- No streaks, no shame loops, no daily-login engagement hooks.
- Predictions always probabilistic with credible intervals — no false precision.
- AI for summaries only, never for prediction or diagnosis.
- 28-day notification suppression after a logged loss.
- No notification preview text revealing cycle/pregnancy info on lockscreen.

Any candidate that violated these was either rejected upfront or flagged as "do not pursue."

---

## 2. What was already on the roadmap before this research wave

To prevent duplicate proposals, each agent was given this baseline:

**Shipped per 2026-05-24 roadmap update:**
#46 Doctor PDF, #71 HK Import + Review, #74 Resume-Sheet, #75 LogEventSheet, #76 onboarding, #79 calendar range-select, #80 LogDaySheet hint, #81 privacy microcopy, #85 notification scaffolding, #90 refresh() race fix, #91 HK round-trip, #95 21–45d clinical clamp, #96 Category D outlier rejection, #97 age-stratified within-person SD prior, #103 startPeriod orphan rows, #120 Mein Zyklus 3-layer (NEW-A), #121 German recognition templates (NEW-B), #123 privacy disclosure (NEW-D).

**Planned but not yet built (in roadmap):**
v2 mixture predictor #83, conformal wrapper NEW-E, late-mode UI completion, #122 loss-aware suppression, DRSP-Modus #47, iCloud sync NEW-G, adolescent onboarding NEW-H, partner sharing #86, open-source predictor SPM, SHA-256 export receipts, v3 wrist-temp pipeline, app-lock duress passcode (#109 — deferred D9 in 2026-05-24 update).

---

## 3. Findings by topic (with primary citations)

### 3.1 DACH market context

| Finding | Primary source | Verified? |
|---|---|---|
| Endometriosis median diagnostic delay 10.4 years in Austria/Germany cohort n=171 | Hudelist G et al., **Hum Reprod 2012;27(12):3412**, PMID **22990516** | ✅ Verified by fact-checker. **Correction:** earlier mis-cited as "Dian et al. 2022." |
| Sensiplan symptothermal method: perfect-use Pearl Index 0.4, typical-use 1.6, n=7,866 cycles | Frank-Herrmann P et al., **Hum Reprod 2007;22(5):1310–1319** | ✅ Verified |
| Europe menstrual cup market CAGR 10.5%, 2025–2030 | Grand View Research | 🤷 Paid market projection; directional only |
| German DiGA / ePA framework relevance to long-term DACH positioning | BfArM DiGA portal, gematik.de ePA docs | ✅ Frameworks confirmed; market relevance is interpretive |
| German users' Frauenarzt-sharing preference (77% would grant access) | claimed vzbv survey | 🔴 **Could not verify.** Fact-checker found no vzbv publication matching. **Treat as fabricated until owner produces primary URL.** Drop from all product copy. |
| Stiftung Warentest rating Drip top for privacy among cycle apps | Stiftung Warentest, taz.de, mobilsicher.de coverage | ⚠️ Coverage exists; specific rating language requires direct check |

### 3.2 Peer-reviewed cycle / hormone research (Wave 2)

| Finding | Primary source | Verified? | Roadmap candidate |
|---|---|---|---|
| Mahalingaiah AWHS 2023, n=165,668 cycles, μ=28.7 days SD 6.1 | Li et al., **PMC10226714** | ✅ Verified exactly | Already in `CyclePredictor.swift` as core prior |
| WHOOP cardiovascular amplitude across cycle, n=11,590 / 45,811 cycles; OCP attenuates RHR swing dramatically | Jasinski et al., npj Digital Medicine 2024, **PMC11666598** | ✅ PMC + n verified. Specific 2.73 vs 0.28 BPM / 4.65 vs 0.51 ms digits PARTIAL — verify against Table 2 before product collateral. | **NEW-R** (Phase 4) |
| Adolescent cycle variability: <1y post-menarche → OR 2.6 highly-variable, OR 5.0 short cycles vs 6+y post-menarche, n=6,486 Clue users / 38,916 cycles | JPAG 2024, **PMID 38570085** | ✅ Verified exactly including CIs | **NEW-L** (Phase 3) extends #97 |
| AWHS time-to-regularity n=60,789, prolonged regularization → AOR 3.53 for PCOS | **PMC12459127** | ✅ PMC + n verified. Specific 1.27→1.40 and 76%→56% trend numbers PARTIAL — verify Tables. | Informs **NEW-P** perimenopause framing |
| SkipTrack Bayesian hierarchical model for skip-log-aware cycle estimation | **arXiv:2508.05845**, Harvard HSPH / Apple / NIEHS, 2025 | ✅ Verified | **NEW-M** (Phase 3) |
| COVID-19 vaccination cycle effect: +0.34d dose 1, +0.62d dose 2; meta-analyses pooled | **PMC12083795**, **PMC12168487** | ✅ PMC + effect sizes verified. **Correction:** n=30,320 not 747,763 (latter was a separate population study count, conflated). | **NEW-I** (Phase 2A) |
| Postpartum return Gompertz-IG model: median 14.6 months (not 14.5); 7–24mo breastfeeding AHR 0.64 | **PMC9580771** Ethiopian DHS | ✅ Verified with median correction | **NEW-O** (Phase 3) |
| Menstrual migraine ICHD-3 attack window days −2 to +3; estrogen-withdrawal mechanism | **PMC10512516** | ⚠️ PMC ID not yet verified by fact-checker; ICHD-3 criteria themselves are standard | **NEW-U** (Phase 4) — verify before shipping |
| Long COVID / ME-CFS perimenstrual symptom clustering, n=948 Visible app | medRxiv **10.1101/2025.01.24.25321092** | ⚠️ DOI not yet verified | **NEW-T** (Phase 4) — verify before shipping |
| Phase-length within-person variance: luteal σ≈3.0d, follicular σ≈5.2d, n=53 / 676 cycles | Oxford **PMC11532606** | ⚠️ Not in primary fact-check pass; informs pattern-detection min-N gates | Pattern-detection toolkit §3.8 |
| Hierarchical change-point methods for perimenopause variance precedes mean by ~3.4y | Harlow et al., **PMC3979630** | ⚠️ Not in primary fact-check pass | Pattern-detection method 3, **NEW-P** rationale |
| Seasonal effect on cycle length: max 0.16d between months (n large US digital cohort) | **PMC10872302** | ⚠️ Not verified | Cited as **anti-feature** evidence: do NOT ship seasonality surfacing |
| Wrist-temperature MAE 1.70 vs 1.90 days improvement | "HR 2025" (Human Reproduction) | 🤷 Verify exact citation before Phase 5 work | Phase 5 v3 pipeline rationale |
| Wrist-temperature cosinor method for anovulatory detection | **PMC11294004** | ⚠️ Not verified in primary pass | Pattern-detection B5, Phase 4 |
| Wearable fertility-window pooled accuracy 0.88 (95% CI 0.86–0.90) | **PMC12886881** systematic review | ⚠️ Not verified in primary pass | Phase 4 / 5 signal-confidence layer rationale |
| CGM × cycle biphasic glucose pattern, n=49 Dexcom G6 | **PMC10421863** npj Digital Medicine 2023 | ⚠️ Not verified in primary pass | **NEW-AA** (Phase 5) |
| Apple Foundation Models framework production-stable iOS 26 | Apple Newsroom 2025-09 | ✅ Verified | AI summary layer enabling technology |
| Fehring NFP dataset: 159 subjects, 1665 cycles, MAE 2.115d (basis of conformal calibrator) | claimed origin of `ConformalResiduals.swift` | ⚠️ **HIGH PRIORITY VERIFY.** This is the primary calibration data for the conformal wrapper that ships with v2 (#83 + NEW-E). Verify against Fehring's published cohort papers before Phase 3 ships. | Phase 3 prerequisite |

### 3.3 Underserved user segments (ux-researcher)

| Segment | Need | Roadmap candidate |
|---|---|---|
| Pregnancy loss survivors (post-28d-silence re-entry) | Graduated 3-cycle banner + acknowledgment; co-design required | Adjacent to existing #122 (Phase 2A) + recovery profile work in **NEW-N** |
| Endometriosis / adenomyosis | Pain timeline + Doctor-PDF section | Adjacent to **NEW-X** (DRSP) + **NEW-U** (migraine); dedicated endo pain log is separate candidate |
| Trans men / NB on testosterone | T-suppression mode + universal language neutralization | **NEW-Y** (Phase 4) — **co-design before any code** |
| Athletes (RED-S risk, training-load correlation) | Training-load context tag on day-log | Candidate, not yet tracked; lightweight S effort |
| Shift workers (~18% German employed) | Schedule declaration + temperature signal-quality filter | **NEW-BB** (Phase 5, depends on v3 temp pipeline) |
| Competitor-app migrants (Flo/Clue refugees post-privacy-scandal) | Cycle Archaeology — seed posterior from past HK records | **NEW-S** (Phase 4) |
| Postpartum / breastfeeding users | Survival-curve display instead of "6–12 weeks" boilerplate | **NEW-O** (Phase 3) |
| Adolescents | Wider priors + honest "irregularity is normal for first 2–3 years" copy | **NEW-L** (Phase 3) |

### 3.4 Femtech trends 2024–2026 (trend-analyst)

| Trend | Evidence | Window | Tideline response |
|---|---|---|---|
| Privacy-jurisdiction migration from US-cloud apps to on-device / EU | FTC actions against Premom, GoodRx, Flo, BetterHelp; Flo $56M/$59.5M preliminary settlement | 3–5 years minimum | Architecture-as-marketing; **NEW-K** privacy-first onboarding |
| Perimenopause market growth | Menopause app market $345.6M / 17.2% CAGR (Grand View Research — paid projection); 1B+ women in menopause by 2025 | 5+ years | **NEW-P** self-declared perimenopause mode |
| Wearable signal convergence (wrist-temp + HRV + sleep) | PMC12886881 pooled accuracy 0.88; Mira-Oura partnership | 3–4 years | Phase 4 HK reads + **NEW-Z** signal-confidence layer (Phase 5) |
| Quantitative hormone logs as differentiating tier-1 | Inito, Mira, Proov, Oova consumer adoption; PMC validation studies | 2–3 years | **NEW-Q** Phase 4 |
| Inclusive language as genuine UX differentiator | Euki, Drip user-research basis | Durable | **NEW-Y** Phase 4 |
| Foundation Models / Apple Intelligence iOS 26 stable | Apple Newsroom 2025-09 | Build now | Existing AI-summary plan unblocked |
| CGM × cycle correlation emerging | PMC10421863 (n=49) | 18–36 months | **NEW-AA** Phase 5 |

**Trends Tideline must NOT chase** (per trend-analyst, confirmed by other agents):
- AI cycle prediction (Flo's Databricks direction) → MDR reclassification
- Camera-based OPK strip scanning → ML model + validation burden, privacy risk if cloud
- FDA/MDR contraceptive-efficacy certification (Natural Cycles route) → €500k–1M validation cost, undermines wellness classification

### 3.5 Competitive feature gap analysis (competitive-analyst)

**Cluster summaries** (full agent output available on request):

| Cluster | Examples | What they can't do |
|---|---|---|
| Cloud-architecture engagement apps | Flo, Glow, Stardust, Natural Cycles | Store data on-device by design; "anonymous mode" is UI layer over unchanged backend |
| European clinical hardware apps | Cyclotest mySense, Trackle, FemSense | Work without proprietary hardware; no disruption handling; no probabilistic intervals |
| German-market generalists | WomanLog, MyCycle DACH | Privacy; HK write-back; AI summaries; disrupted-cycle handling |
| Apple Health Cycle Tracking | (built-in) | Engagement; symptom library; export; late-period guidance; DRSP |
| Specialty hardware-paired | Premom, Inito, Mira, Oura, Whoop, Garmin | Work without proprietary hardware; German-language UX; cycle calendar without cloud |
| Privacy-first bare-bones | Drip, Euki, Kindara | Be useful to non-technical users; Apple Watch; AI summaries; probabilistic predictions |

**Unoccupied territory features identified** (cross-mapped to roadmap candidates):
- Calibrated uncertainty display → already shipped via predictor + late-mode
- Quantitative OPK + cycle-day-anchored hormone log → **NEW-Q**
- Perimenopause-aware predictor mode → **NEW-P**
- Loss-aware notification with lockscreen redaction → #122 + #85 already shipped
- DRSP-validated PMDD export separate from general symptom log → **NEW-X**
- Open-source predictor as Swift Package → already in Phase 5 roadmap
- Cycle-contextualized lab value timeline view → **NEW-Q** extension
- Symptom-pattern export for chronic conditions → **NEW-X** + endo pain log

### 3.6 DACH-specific candidates surfaced (market-researcher)

| Candidate | Evidence | Roadmap |
|---|---|---|
| Frauenarzt visit-prep PDF (lighter than Doctor PDF, narrative format) | Hudelist 2012 documentation barrier; German visit-prep norms | Variant of #46, optional |
| Dysmenorrhoe work-impact log | German Krankmeldung culture, no menstrual leave law unlike Spain | Symptom-log extension candidate |
| Vaccine/illness cycle marker | Vaccine cycle effect well-documented in German press post-COVID | **NEW-I** |
| Reusable product log (cup/disc volume) | Grand View Research DACH cup CAGR 10.5% | **NEW-V** |
| Confidential mode with alt app icon | Edge-case catalog "partner has access to user's phone" flagged high priority | Adjacent to #87 App-Lock; #109 duress passcode was deferred per D9 |
| German clinical vocabulary auto-complete | German users use Lutealphase/Mittelschmerz/Dysmenorrhoe vocabulary readily | Tier 2 candidate; not yet tracked |

### 3.7 User-voiced unmet needs (search-specialist)

Sources searched: Reddit (r/TwoXChromosomes, r/PMDD, r/endometriosis, r/PCOS, r/perimenopause, r/ftm, r/Mommit, r/MenstrualCups, r/birthcontrol, r/Miscarriage, r/privacy, r/de), App Store reviews of Flo / Clue / Natural Cycles / Stardust / MyCycle / Cyclotest / Trackle / FemSense / Apple Health in US + DE stores, GitHub issues on Drip and Euki, Mozilla Privacy Not Included coverage, German-language privacy press (mobilsicher.de, heise.de, taz.de).

| Need | Evidence source | Roadmap |
|---|---|---|
| "I log stuff and nothing comes back" (loop-closing) | PMC11687174 PMDD user research; arXiv 2409.03853 multimodal study; JMIR e53146 Gen Z; recurring across PMDD/Gen Z/PCOS | Foundation Models summary layer (existing plan); pattern surfaces (§3.8) |
| Intra-day symptom stamps | PMC11687174 Interview 4 quote ("my mood changes dramatically from one moment to the next"); confirmed in multimodal study | **NEW-W** schema migration |
| DRSP-format Doctor PDF section | IAPMD DRSP instrument standard; PMC11687174 confirmed gap | **NEW-X** |
| Zero-fertility-framing setup | PMC12131320 quotes; Embody app 100k downloads (⚠️ unverified) as positioning validation | Adjacent to **NEW-K** onboarding; copy-only decision |
| "I had a loss" as standalone log (pre-clinical losses) | Clearblue App Store review (developer-acknowledged gap); Flo only allows from day 29 of pregnancy | **NEW-J** Phase 2A |
| Visible first-screen privacy onboarding | "Fake data defense" loop documented PMC12131320; Stiftung Warentest top-rated Drip | **NEW-K** Phase 2A |

**Forbidden user demands** (document for marketing-copy use to communicate what Tideline deliberately doesn't do):
1. "Tell me if I might have PCOS / endometriosis / PMDD" — recurring user request; would trigger MDR. Tideline shows the pattern, leaves inference to user + doctor.
2. "Use my cycle data for natural contraception" — recurring in r/privacy and NFP communities; MDR Class IIb trigger. Natural Cycles holds the license; Tideline shows the same underlying signals without the claim.
3. "Tell me why my period is late — pregnant? stress? diet?" — late-and-missed-periods.md design correctly identifies this as off-limits differential diagnosis.

### 3.8 Pattern recognition for Mein Zyklus Layer 2 (research-analyst)

**Confirmed: #120 shipped the correct v1.0 picks** (phase length stability + cycle-length trend + bleeding-days vs average).

**Recommended v1.1 additions** (post-TestFlight beta feedback):

| Pattern | Min-N gate | Method | Evidence basis |
|---|---|---|---|
| B4 Phase-conditional symptom frequency | 5 cycles | Bayesian binomial proportion comparison; 99% CI for multiple-testing | Premenstrual dysphoric disorder research; catamenial migraine literature |
| B3 Symptom severity trend | 6 cycles | Bayesian NIG regression (extends #97 / #83 machinery) | No primary citation needed (standard Bayesian approach) |
| C3 Skip-log transparency | None | Log-timestamp counter | SkipTrack (arXiv 2508.05845) demonstrates skip-log bias on cycle-length estimates |

**Phase 4+ patterns gated by HK wearable reads or data depth:** A4 wearable within-cycle, B2 cycle-length variability change (Harlow PMC3979630), B5 anovulatory cosinor frequency (PMC11294004), C1 sleep × mood phase-corrected, C2 lifestyle event × cycle-length.

**Detection-method toolkit** (8 methods documented in research-analyst output; reusable across patterns):
1. Bayesian NIG regression on scalar sequences
2. Bayesian binomial proportion comparison
3. Posterior predictive variance ratio
4. Cosinor analysis on temperature time series
5. Phase-conditional lagged correlation
6. Bayesian run-length detection
7. **99% credible interval threshold** as multiple-testing correction (conservative; required when checking ~12 simultaneous patterns)
8. **Minimum-N gating layer** as pre-filter before any pattern surfaces

**The "no pattern detected" UX contract** — Tideline's doctrinal differentiation from Flo's invent-content approach. Three states: pre-gate (progress framing), post-gate-null (first-class "no consistent pattern" UI), pattern-detected (lead with frequency count, denominator always visible).

**Phase 4+ ambitions post-v2:** causal inference via per-event recovery profile inversion; symptom-as-covariate in Gibbs sampler; PACTS phase normalization (ScienceDirect 2025); sparse Bayesian network for symptom co-occurrence (requires 20+ cycles).

**Anti-feature:** seasonality surfacing. PMC10872302 found 0.16-day max month difference — smaller than logging resolution. This is the "Flo statistical noise as personalized insight" anti-pattern that Tideline's pattern-detection doctrine specifically rejects.

---

## 4. Product synthesis (product-manager output)

### 4.1 v1.0 minimum payable bundle (6 features)

Six features that MUST ship together for €4.99 one-time IAP to feel like a complete product. All 6 are already shipped or are Phase 2 work:

1. On-device PDF export for clinicians (#46 ✅)
2. v2 mixture predictor + conformal coverage (Phase 3, #83 + NEW-E)
3. Loss-aware 28-day silence + event taxonomy (#75 ✅, #122 pending Phase 2A)
4. Mein Zyklus retrospective 3-layer view (#120 ✅)
5. HealthKit import + backfill (#71 ✅, #91 ✅)
6. Onboarding + privacy disclosure + transparency (#76 ✅, #123 ✅, potential **NEW-K** addition)

**Tension:** v1.0 bundle assumes v2 mixture ships. Per 2026-05-24 update D8 (TestFlight-first), v1 predictor goes to TestFlight first. Two readings: (a) TestFlight uses v1 + label predictor as "v1," market v2 as headline feature of v1.0 launch later; (b) v1.0 launch waits for v2. Owner decision pending — flag as new open question.

### 4.2 Price band

**€4.99 one-time** recommended; **€3.99–€6.99** defensible. Reasoning:
- DACH price sensitivity caps at ~€7 for one-time purchases
- App Store comparables: cycle trackers €1.99–€2.99 basic, €4.99–€7.99 full
- Sustainability: at €4.99 × 2k conservative Year-1 DACH = ~€10k gross, ~€7k net after Apple 30%
- Trust signal: €4.99 says "not squeezing you" vs Flo's €9.99/month + dark patterns
- Refund tolerance: low price = low refund pain

**Defer to v1.2:** Optional "supporter tier" non-consumable IAP (~€9.99) framed as "fund future updates," not feature unlock. Adds only if post-launch users explicitly ask.

**Off-limits:** Freemium feature walls (requires cloud accounts or device-local DRM, both Pillar 1 violations).

### 4.3 v1.1 / v1.2 delight drops (free updates within 6 months)

Sequenced for "I'm glad I bought this" psychology reset every 4–6 weeks post-launch:
1. v1.1 wk 2–4: DRSP-Modus PMDD tracking (#47)
2. v1.1 wk 3–6: Phase-contextual symptom prompting
3. v1.2 wk 6–8: Foundation Models post-log summary (iOS 26 stable)
4. v1.2 wk 8–12: Cycle Archaeology — deep HK import (**NEW-S**)
5. v1.2 wk 10–16: iCloud private DB sync opt-in (**NEW-G** / #126)
6. v1.2 wk 12–16: In-app research notes (transparency view, differentiator #16)

### 4.4 Kill list (additions to existing out-of-scope)

Documented in roadmap §8 (`2026-05-24-research-findings-integration.md`). Highlights:
- Symptom prediction (forward-looking interpretation = MDR diagnostic territory)
- Diagnostic AI chatbot ("Ask Tideline")
- Freemium feature walls
- Community / social features
- Subscription tier
- Sensiplan NFP-Modus with fertile-window computation
- Camera-based OPK scanning
- Cross-app CSV import (HK import handles highest-value case)
- Seasonality pattern surfacing

### 4.5 Launch positioning (proposal)

Subtitle (30-char): **"Deine Zyklusvorhersagen. Dein Gerät. Punkt."**

First sentence: "Tideline respects you: honest, on-device cycle tracking with no account, no backend, no ads, no nonsense. One purchase, full access forever."

Five-screenshot suite: (1) privacy-as-architecture, (2) retrospective recognition, (3) Doctor PDF, (4) honest uncertainty / credible interval, (5) loss-aware silence settings.

---

## 5. Fact-check audit trail

Wave 3 fact-checker dispatched against high-stakes citations after Waves 1+2. Findings categorized:

### 5.1 ✅ Verified — safe to cite
- Mahalingaiah AWHS PMC10226714 (μ=28.7, n=165,668)
- WHOOP PMC11666598 study existence + sample (specific digits PARTIAL)
- JPAG 2024 PMID 38570085 (OR 2.6 / OR 5.0 with CIs verified exactly)
- AWHS time-to-regularity PMC12459127 (n=60,789; specific trend numbers PARTIAL)
- SkipTrack arXiv:2508.05845 (Harvard/Apple/NIEHS)
- COVID vaccine PMC12083795 + PMC12168487 (0.34d / 0.62d effect sizes)
- Postpartum PMC9580771 (median 14.6 months — corrected from 14.5)
- Hudelist endo delay PMID 22990516 (10.4 years DACH cohort) — **correct citation (NOT Dian 2022)**
- Meta jury verdict August 2025 (SF federal, CIPA)
- Apple Foundation Models iOS 26 production (Sept 2025)
- Sensiplan PI 0.4 perfect-use, **1.6 typical-use** (Frank-Herrmann 2007)

### 5.2 ⚠️ Needs correction — real but misstated
- Flo settlement: **$56M/$59.5M preliminary** (Google $48M + Flo $8M + others), preliminary approval April 2026, **final approval pending** — NOT "$59.5M finalized September 2025"
- Postpartum median 14.6 months (not 14.5)
- COVID vaccine n was 30,320 in meta-analysis, NOT 747,763 (latter was unrelated population study)
- Menopause app market $345.6M / 17.2% CAGR is **Grand View Research, not VMR**; VMR has separate $1.5B / 12.5% CAGR figure; treat both as paid projections, directional only
- Flo 75M MAU — verified but **per Flo's own reporting** only, no independent audit

### 5.3 🔴 Hallucinated / cannot verify — do NOT use
- **vzbv "77% would grant Frauenarzt access to app data"** — fact-checker found no matching vzbv publication. Remove from all design notes, product copy, and App Store positioning until owner produces primary URL.

### 5.4 🤷 Not yet verified — verification debt
- Long COVID medRxiv DOI 10.1101/2025.01.24.25321092
- Menstrual migraine ICHD-3 PMC10512516
- **Fehring NFP dataset (159 subjects, 1665 cycles, MAE 2.115d)** — high-priority, blocks conformal wrapper shipping in Phase 3
- PMC11687174 PMDD user research full claim ("no current menstrual app has full DRSP")
- FTC actions on Premom / GoodRx / BetterHelp (Premom and Flo are widely-documented; verify dates)
- Stardust Privacy International report (phone-number leakage despite local-first claims)
- Embody app: 100k downloads since August 2024 + zero-fertility-framing positioning
- Mira-Oura partnership (MobiHealthNews)
- DACH menstrual cup CAGR 10.5% (Grand View Research)
- ovul.ai "82% PCOS prediction failure" — vendor-source claim; find underlying 340-woman 2023 ultrasound study
- Wrist-temp MAE 1.70 vs 1.90 days (HR 2025)
- Wearable fertility-window 0.88 pooled accuracy PMC12886881

**Verification debt is tracked as a single roadmap task (#148 in `2026-05-24-research-findings-integration.md` §7).** No NEW-* feature relying on a 🤷 citation should ship until that citation graduates to ✅.

---

## 6. The plan — how these findings flow into roadmap

All findings have been routed into `docs/roadmap/2026-05-24-research-findings-integration.md` as candidate features with tracker IDs **NEW-I through NEW-BB** + a pattern-extensions task. The integration doc is the **plan**; this note is the **evidence**.

Cross-reference summary:

| Research §  | Integration roadmap §                       |
|------------|---------------------------------------------|
| §3.1 (DACH)                | §1.1 Phase 2A (NEW-I) + §1.4 Phase 4        |
| §3.2 (peer-reviewed)       | §1.2 Phase 3 (NEW-L, NEW-M, NEW-O) + §1.3 Phase 4 (NEW-R, NEW-T, NEW-U) + §1.4 Phase 5 (NEW-AA) |
| §3.3 (segments)            | §1.3 Phase 4 (NEW-P, NEW-S, NEW-Y) + §1.4 Phase 5 (NEW-BB) |
| §3.4 (trends)              | §1.3 Phase 4 (all convergent items) + §1.4 Phase 5 (NEW-Z) |
| §3.5 (competitive)         | §1.3 Phase 4 (NEW-Q, NEW-X) + reinforces §3 monetization     |
| §3.6 (DACH)                | §1.1 Phase 2A (NEW-K) + §1.3 Phase 4 (NEW-V) |
| §3.7 (user-voiced)         | §1.1 Phase 2A (NEW-J, NEW-K) + §1.3 Phase 4 (NEW-W) |
| §3.8 (patterns)            | §2 pattern-extensions design + Phase 4 #147  |
| §4 (PM synthesis)          | §3 monetization + §5 launch positioning      |
| §5 (fact-check)            | §4 citation corrections + §7 verification debt task #148 |

---

## 7. Decisions captured during this wave

These were taken implicitly during research but should be elevated to formal decision status:

| # | Question | Resolution | Source |
|---|---|---|---|
| **R1** | Recommended v1.0 price band? | €4.99 one-time (range €3.99–€6.99 defensible) | PM agent §4.2 |
| **R2** | Supporter-tier non-consumable IAP at launch? | No — defer to v1.2 based on feedback | PM agent §4.2 |
| **R3** | Pattern v1.0 set in Mein Zyklus Layer 2 (#120)? | Confirmed correct: phase length stability + cycle-length trend + bleeding-days. Research-analyst recommends 3 v1.1 extensions (B3, B4, C3). | research-analyst §3.8 |
| **R4** | Seasonality pattern in Mein Zyklus? | NEVER — anti-pattern; PMC10872302 effect smaller than logging resolution | research-analyst §3.8 |
| **R5** | T-suppression mode design process? | Co-design with 6–10 trans men / NB users **before** any string is written | ux-researcher; emphasized as harm-if-wrong |
| **R6** | Foundation Models / AI summary layer timing? | iOS 26 API is stable (production, Sept 2025); not a research blocker any more. Defer build to v1.2 per PM agent §4.3 sequencing. | trend-analyst §3.4 |
| **R7** | Sensiplan NFP-Modus with fertile-window computation? | Out of scope for v1 (legal complexity > value); user-logged mucus observations alongside temperature is technically safe but creates ambiguity worth avoiding | trend-analyst + DACH market-researcher convergence |

Decisions R1–R7 are recorded in the integration roadmap §3 and §8.

---

## 8. Verification debt and open follow-ups

Owner-action items derived from the fact-check:

1. **Remove vzbv "77%" claim** wherever it appears in design notes; do not use in product copy until primary source produced.
2. **Verify Fehring NFP dataset** characteristics (159 subjects / 1665 cycles / MAE 2.115d) against primary source. Blocks shipping conformal wrapper in Phase 3.
3. **Update Flo settlement language** wherever it appears: "$56M/$59.5M preliminary, final approval pending" — NOT "finalized September 2025."
4. **Fix endometriosis delay citation** to Hudelist et al., Hum Reprod 2012, PMID 22990516 — NOT "Dian et al. 2022."
5. **Verify remaining 🤷 citations** (§5.4) before any NEW-* feature relying on them ships. Highest-priority: Fehring (blocks v2/conformal), ICHD-3 migraine (NEW-U), Long COVID DOI (NEW-T), wrist-temp HR 2025 (Phase 5).

---

## 9. Agent IDs for follow-up

If any agent's output needs to be probed deeper, the agent IDs are retained from this session's dispatch (also captured in conversation transcript):

| Agent | Wave | Approximate output length |
|---|---|---|
| market-researcher (DACH) | 1 | ~2,800 words + 17 sources |
| competitive-analyst | 1 | ~3,200 words + 9 sources |
| trend-analyst | 1 | ~2,400 words + 12 sources |
| ux-researcher | 1 | ~2,200 words |
| scientific-literature-researcher | 2 | ~3,600 words + 13 sources |
| search-specialist | 2 | ~3,400 words + 15 sources |
| product-manager | 2 | ~3,100 words |
| fact-checker | 3 | ~1,300 words + 15 sources |
| research-analyst (patterns) | 3 | ~4,800 words + 13 sources |

Full agent outputs are in the conversation transcript for this session. If the conversation is lost, the citations and findings here should be sufficient to reconstruct the reasoning chain without re-running.

---

## Document conventions

Per project convention: **research notes are write-once**. Don't edit this file. If new research supersedes findings here, write a new dated note and supersede explicitly. The fact-check audit (§5) is the only living-by-reference part — when a 🤷 citation graduates to ✅ or 🔴, update the integration roadmap §4 (not this note) with the correction.

This note is the citation target for `docs/roadmap/2026-05-24-research-findings-integration.md`. Future design docs touching any of the NEW-I through NEW-BB candidates should cite this note as the evidence basis.
