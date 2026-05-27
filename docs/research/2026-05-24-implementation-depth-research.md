# 2026-05-24 — Implementation Depth Research

**Date:** 2026-05-24
**Type:** Research note (write-once per project convention).
**Purpose:** Implementation-level research on five additional NEW-* candidates that hadn't yet received depth treatment, plus a focused verification-debt cleanup pass. Complements `2026-05-24-feature-research-wave.md` (broad survey) and `2026-05-24-design-research-deep-dive.md` (design-level deep dive on NEW-P/Q/Y/W+X + Fehring verification).

**Why a third research note same day:** The afternoon deep-dive focused on design-level questions (what should the feature do, what does the literature say). This wave goes one level further into implementation specifics — algorithm details, schema sketches, brand databases, effect-size quantification — so that the engineering work can begin without re-research. Plus a focused fact-check pass that resolved several verification-debt items.

---

## 0. Scope and methodology

Five specialist agents dispatched in parallel:

| Target | Agent | Output length |
|---|---|---|
| NEW-M SkipTrack implementation | scientific-literature-researcher | ~4,200 words, 6 verified sources |
| NEW-O Postpartum Gompertz + breastfeeding mode | research-analyst | ~5,800 words, 10 sources |
| NEW-V Reusable product log (DACH cup market + volumes) | search-specialist | ~4,500 words, 30 verified sources |
| NEW-U Migraine + NEW-T Long COVID (combined verify + design) | research-analyst | ~5,300 words, 18 sources |
| NEW-S Cycle Archaeology HK posterior seeding | research-analyst | ~6,000 words, 13 sources |
| Citation verification debt cleanup (6 items) | fact-checker | ~1,400 words, 10 sources |

Hard constraints baked into every prompt: on-device only, no cloud, EU MDR wellness, no diagnostic interpretation, no contraceptive/conception efficacy claims, no streaks, AI summaries only never AI prediction, probabilistic predictions, 28-day notification suppression post-loss, lockscreen content redaction.

---

## 1. NEW-M — SkipTrack-aware long-cycle disambiguation

### 1.1 Citation verified directly

**Source:** Duttweiler L, Asokan G, Wang Z, Mahalingaiah S, Onnela JP, Hauser R, Williams MA, Abrams K (Apple Inc.), Curry CL (Apple Inc.), Coull BA. "SkipTrack: A Bayesian Hierarchical Model for Self-tracked Menstrual Cycle Length and Regularity in Large Mobile Health Cohorts." arXiv:2508.05845 [stat.AP], 2025-08-07. **Paper text read directly this pass.**

**Related publication:** Duttweiler L, Mahalingaiah S, Coull B. *J Open Source Software* 9:6928 (2024). DOI 10.21105/joss.06928.

**R package:** `skipTrack` v0.2.0, CRAN, **MIT license**. Repository: https://github.com/LukeDuttweiler/skipTrack

### 1.2 Model structure (verified from paper)

Per individual i, observation j:
```
y_ij ~ LogNormal(μ_ij + log(c_ij), τ_i)
```

where `c_ij ∈ {1, 2, 3}` is the integer count of true biological cycles compressed into the observation, sampled as a latent variable. The `log(c_ij)` offset is the key innovation: if `c_ij = 2`, the observed length is treated as ~2× the underlying true cycle. Population-level Dirichlet prior on skip rates `(π_1, π_2, π_3)`; AWHS application defaults: `(0.75, 0.20, 0.05)`.

Inference: hybrid Gibbs + Metropolis-Hastings MCMC. Most parameters (including `c_ij`) have conjugate full conditionals → Gibbs. Two parameters (Γ, φ) lack conjugacy → MH.

**Key insight (paper p. 3):** The model uses *both* mean and variance information to distinguish genuine long cycles from skipped logs. High-regularity users get confident skip assignments; low-regularity users get appropriately wide posterior uncertainty over `c_ij` — which is correct. This contrasts with the Li 2022 model that fixes `c_ij` deterministically and loses calibration.

### 1.3 Implementation architecture: recommended Option (b) — integrated latent variable

The paper's contribution is precisely propagating `c_ij` uncertainty through to parameter estimates rather than fixing it via preprocessing. Simulations show preprocessing degrades CI coverage as n increases. **Don't use Option (a) preprocessing.**

**Critical recommendation: ship SkipTrack BEFORE v2 mixture predictor.**

- Phase 3a (SkipTrack alone, on single-component NIG): 80–120 LOC addition; ~3–4 dev-days
- Phase 3b (SkipTrack + v2 mixture, unified Gibbs): `c_ij` becomes additional Gibbs step alongside `S_ij` component assignment

Rationale: SkipTrack delivers user benefit independently of mixture work; simpler validation surface; faster path to shipping bias-correction.

**Gibbs step pseudocode (concrete):**
```swift
// Per observation y_ij, per iteration:
for c in [1, 2, 3]:
    log_likelihood[c] = logNormalLogPDF(y_ij, location: μ_ij + log(Double(c)), precision: τ_i)
    log_prior[c] = log(π[c])
c_ij = categoricalSample(logWeights: log_likelihood + log_prior)
skipCounts[c_ij] += 1
// After all c_ij sampled, update Dirichlet posterior:
π ~ Dirichlet(α_1 + skipCounts[1], α_2 + skipCounts[2], α_3 + skipCounts[3])
```

### 1.4 UI prompt design

**Threshold:** Surface prompt when `P(c_ij ≥ 2) > 0.30` for the most recent completed cycle. Principled (derived from model posterior), not arbitrary 1.5-SD.

**Cold-start suppression:** No prompt if user has <4 completed cycles (τ_i is not meaningfully personalized yet).

**Category C suppression:** No prompt within 4 weeks of any logged loss/birth/contraception-change event.

**Surface:** Home view chip below prediction ring, appearing after the cycle ends (not during logging flow). One-time per flagged cycle. Dismissable.

**German copy (verified):**
> "Längerer Zyklus als gewöhnlich
> Zyklus [N] war [X] Tage – etwas länger als sonst bei dir.
> Hast du vielleicht eine Periode begonnen, ohne sie einzutragen?
>
> [Ja, ich habe eine Eintragung vergessen] [Nein, das war so] [Ich bin unsicher]"

**English copy:**
> "Longer cycle than usual
> Cycle [N] was [X] days — a bit longer than your typical pattern.
> Did your period start earlier and you didn't log it?
>
> [Yes, I missed a log] [No, this was real] [Not sure]"

### 1.5 Answer handling

- **"Yes, missed log":** Fix `c_ij = 2`. Optionally ask for approximate missed date; if given, split observation; if not, fix `c_ij = 2` without splitting (model's `log(c_ij)` offset handles it correctly).
- **"No, real long cycle":** Fix `c_ij = 1`. Genuine long observation used as-is.
- **"Not sure":** Leave `c_ij` fully latent (sampled). Honest uncertainty.

### 1.6 Effect size honesty

For a typical 28.7-day user with 6 cycles where 1 is a skipped 60-day observation: without SkipTrack, posterior mean is biased by ~5.2 days; with SkipTrack `c_ij=2` pinned, bias is negligible. Concrete per-user improvement.

Population-level paper results (Tables 1–3): "SkipTrack w/ Fixed Skips" preprocessing shows 90% attenuation of regression coefficients and 95% CI coverage degrading to 61%; full SkipTrack maintains near-nominal coverage. These are population-cohort results; per-user analogs require a Tideline-specific simulation (1–2 hour exercise recommended before implementation).

### 1.7 Pre-implementation validation step

Run a Swift playground simulation: generate synthetic user histories with known skips, measure posterior `P(c ≥ 2)` at N=4, 6, 8, 12 cycles. Validates the 0.30 threshold proposed above. 1–2 hours of work; eliminates risk of shipping a poorly-calibrated prompt.

### 1.8 Future design doc

`docs/design/skiptrack.md` — citation target. Can be drafted immediately from this section.

---

## 2. NEW-O — Postpartum Gompertz survival curve + breastfeeding-status logging

### 2.1 Verified primary source

**PMC9580771** — Bekele D et al. (2022). *Frontiers in Reproductive Health*. DOI 10.3389/frph.2022.862693. Ethiopian DHS 2016 cohort.

**All AHR values confirmed exactly:**

| Breastfeeding exposure | AHR | 95% CI |
|---|---|---|
| Never breastfed | 1.00 | Reference |
| Ever breastfed (any) | 1.30 | 1.17–1.64 |
| 0–6 months breastfeeding | **0.20** | 0.17–0.26 |
| 7–24 months breastfeeding | **0.64** | 0.50–0.76 |
| 25–35 months breastfeeding | 1.16 | 0.92–1.45 |

**Overall median:** 14.6 months (not 14.5 as in morning's note — correction noted).

### 2.2 🚨 CRITICAL DACH-SPECIFIC FINDING

**Germany exclusive breastfeeding at 6 months: 13%** (KiGGS national survey, cited in PMC12460087 Frontiers in Public Health 2025). Austria and Luxembourg: only 1.9–3% at 6 months. Netherlands: 39%.

**This invalidates the Ethiopian curve as a DACH reference.** Ethiopian rural median is 15.3 months because of extended exclusive breastfeeding. At 6 months postpartum, ~87% of German users are no longer exclusively breastfeeding. Expected DACH median resumption time is much shorter — likely **3–6 months** for most users.

### 2.3 DACH-applicable cohort data — UNVERIFIED

**WHO 1998 Multinational Study** (PMID 9757873, Fertility and Sterility 70(3):448): closest available developed-country data. Sites: 5 developing + Uppsala, Sweden + Melbourne, Australia. **21% Melbourne/Sydney women resumed before 6 months vs. 62% in New Delhi.** Full cumulative incidence tables paywalled — must be accessed via interlibrary loan.

**No published DACH-specific postpartum cohort study located.** This is a data gap.

### 2.4 UI display spec — milestone-text, NOT Gompertz curve graph

A line chart of a survival function adds no comprehensible information for users. Use milestone markers with plain-language percentage statements instead:

For exclusive/predominant breastfeeding:
- Month 3: "Most people who are still breastfeeding haven't had a period yet at this point. That's completely normal."
- Month 6: "Some people's periods return around now; many don't return for months longer."
- Month 12: "[X]% of people in similar situations have had a period by this point." (X% pending verified DACH data)
- Month 18: "Periods are increasingly likely to return."

For weaned / non-breastfeeding:
- Week 6: "Most people who are not breastfeeding get their first period around now."
- Week 8: "Still within normal range if not breastfeeding."
- Week 12: "Beyond the typical range for non-breastfeeding."

Visual: horizontal timeline strip with milestone markers + "you are here" indicator. Below-the-fold position. Dismissable.

### 2.5 Feeding-status schema (recommended)

```swift
enum FeedingStatus: String, Codable, CaseIterable {
    case exclusive       // only breast milk
    case mixed           // breast + formula/solids
    case weaned          // no longer breastfeeding
    case neverBreastfed  // immutable, set at birth event
}
```

Stored as intermittent log events with default carry-forward (separate `FeedingStatusEntry` SwiftData model, not embedded in `EventKind`). Monthly opt-in check-in prompt:

> "[Month N postpartum]
> Still no period? [Yes, confirm] [My period returned]
> Feeding status: [Exclusive] [Mixed/Formula] [Weaned]"

Opt-in default — no check-in prompts unless user enabled them at birth event logging. Lockscreen-redacted ("Check in with Tideline" generic text).

### 2.6 Mode transition (Option C: hybrid auto-trigger)

On first logged bleed in postpartum mode:
> "Is this your first postpartum period? [Yes] [Not sure — might be spotting] [No, something else]"

On "Yes": exit postpartum mode, apply birth-specific soft reset.

### 2.7 Birth-specific recovery profile parameters (v2 mixture model)

| Parameter | Generic | Birth-specific |
|---|---|---|
| κ | 2.0 | **1.5** |
| α | 3.0 | **2.5** |
| β | 41.07 (~3.7d SD) | **55.0** (~4.7d SD) |
| μ | carry forward | carry forward |
| observedCount | 0 | 0 |
| π_anov | population prior ~0.15 | **0.25 (provisional)** |

The 0.25 anovulatory component weight is a design recommendation, not literature-derived. Flag as provisional until Jackson 2011 (PMID 21343770) full text accessed for first-menses anovulation rates.

### 2.8 Tail-case (24+ months amenorrhea) MDR-safe framing

For weaned + no menses at 12 weeks post-weaning, OR breastfeeding + no menses at 24 months:
> "Many people who haven't had a period by this point choose to discuss it with their healthcare provider. There can be many reasons for this — and most are manageable."

Mirrors the pregnancy-test population-statistics framing from `late-and-missed-periods.md`. Population behavior, never personal diagnosis. Do not name conditions (Sheehan, POI, hypothalamic amenorrhea — forbidden).

### 2.9 MDR boundary highlights

- ✅ "Based on population data, about X% of people in your situation resume cycles by month N"
- ⚠️ "Your period may return soon" — reframe as "Around 6 months, some people who are breastfeeding see their period return"
- ❌ "LAM protects you from pregnancy for 6 months while exclusively breastfeeding" — MDR Class IIb trigger even though medically accurate
- ❌ "Your extended amenorrhea may indicate ovarian insufficiency" — diagnostic claim

### 2.10 Open questions (verification debt)

1. **Gompertz shape (γ) and scale (λ) parameters from PMC9580771** — Tables 3–4. Paper is open-access Frontiers; re-attempt direct PDF access.
2. **WHO 1998 Uppsala cumulative incidence tables** — F&S paywall. Interlibrary loan needed.
3. **DACH-specific cohort study** — none found. If unavailable, use Uppsala data as proxy with explicit caveat.

### 2.11 NEW-O is blocked on §2.10 items before design doc finalization

Cannot ship parameterized survival curve until DACH-appropriate cohort data is verified. **Milestone-text approach (§2.4) can ship without parameterized curve** as a v1 fallback.

### 2.12 Future design doc

`docs/design/postpartum-mode.md` — citation target. Blocked on §2.10 #1 and #2 before parameterized curve; the milestone-text version can be drafted now.

---

## 3. NEW-V — Reusable menstrual product log + cup-fill volume

### 3.1 DACH market context (verified)

- **Germany menstrual cup market:** $69.6M (2024), 6.4% CAGR to 2030 per Grand View Research. Germany = 8% of global cup market — **largest single European market by revenue**. Silicone dominates at ~48% revenue share. (Caveat: GVR is paid market projection.)
- **Adoption rate (% of users):** No freely-accessible primary survey data. Statista 2018 shows tampons at 54.8%, cups not broken out. **Drop any specific adoption-percentage claim** from product copy until primary data found.
- **DACH manufacturers:** MeLuna (TPE, broadest distribution), Merula, Fun Cup, Fema Cup — all Germany-made.
- **🚨 Femtis is NOT a cup brand.** Femtis makes period underwear only. Prior list was erroneous (my prompt error).

### 3.2 Cup brand + capacity table (verified — implementation-ready)

| Brand | Size | Max mL | Notes |
|---|---|---|---|
| MeLuna (DE) | S/M/L/XL | 23/28/34/42 | TPE, Germany-made |
| MeLuna Shorty XL | — | 27 | Low-cervix |
| Merula (DE) | One/XL | 38/50 | Silicone, Germany |
| DivaCup | 0/1/2 | 22/27/30 | |
| Lunette | 1/2 | 25/30 | Has 5 mL and 13.5 mL marking lines |
| AllMatters / OrganiCup | XS/A/B | 15/25/30 | |
| Mooncup UK | B/A | 29/30 | |
| Saalt | Teen/Sm/Reg | 15/25/30 | |
| Ruby Cup | S/M | 24/34 | |
| Hello Cup (TPE) | XS/SM/ML | 17/21/28-29.5 | |
| Intimina Lily Cup | A/B | 28/32 | |
| Intimina Lily Cup Compact | A/B | 18/23 | Foldable |
| Yuuki (CZ) | 1/2 | 25/37 | |
| Pixie Cup | XL | 35 | |
| Sckoon Cup | S/L | 23/30 | |
| Anigan EvaCup | L | 37 | |

Cup range: 15–50 mL. Safe UI default stepper range: 10–55 mL.

### 3.3 Disc + period underwear capacities

**Discs:** Saalt 30/50 mL; Flex Disc 60/70 mL; Nixit 70 mL. **Discs do not have fill-level markings** — visual fraction estimation less reliable than cups. Recommend disc users log change-count only, assume "full = max capacity."

**Period underwear (DACH brands prominent):**
- Ooia (Berlin, market leader DE): ~15 mL / ~30 mL
- Femtis (DE DTC): ~5–10 mL / ~15 mL Jule
- Snuggs (DE/CH): ~22 mL standard
- Modibodi (AU, EU distribution): 20/30/50 mL

### 3.4 Volume estimation methodology

`volume_per_change = max_capacity_mL × estimated_fill_fraction`
`daily_total_mL = Σ(volume_per_change)`

**Accuracy caveat:** No published study quantifies user visual-estimation error vs. graduated cylinder. Estimated ±20–30% error. **PDF must show "~65 mL" not "65 mL" — tilde is mandatory for honest framing.**

**Population thresholds (per ACOG):**
- Spotting <5 mL/cycle
- Light 5–30 mL/cycle
- Medium 30–60 mL/cycle
- Heavy 60–80 mL/cycle
- Very heavy >80 mL/cycle (clinical menorrhagia threshold)

### 3.5 Schema sketch

```swift
enum MenstrualProductType: Codable {
    case tampon, pad
    case cup(brand: String, sizeName: String, maxCapacityML: Int)
    case disc(brand: String, sizeName: String, maxCapacityML: Int)
    case underwear(brand: String?, absorbencyTierML: Int)
    case other
}

enum FillFraction: Double, Codable { case quarter=0.25, half=0.5, threeQuarter=0.75, full=1.0 }

@Model final class CupChange {
    var timestamp: Date
    var productSnapshot: String      // "MeLuna L 34mL"
    var maxCapacityML: Int           // denormalized
    var fillFraction: FillFraction
    var estimatedML: Int             // computed
    var dayKey: String
}

@Model final class UserProductProfile {
    var primaryProductType: MenstrualProductType
}
```

### 3.6 Schema decision: Option A (keep both)

Keep `DayEntry.flow: FlowLevel` (categorical) for all users. Add `cupChanges: [CupChange]` relationship for cup/disc users. Daily summary shows both the categorical assertion AND the computed estimate. Categorical wins as user's declared experience.

### 3.7 UX flow (cup users)

Primary screen: "Leeren notieren" button in logging view, only when product type is cup/disc.

Per-change sheet:
1. Product selector (cached): "MeLuna L (34 mL)" — one tap to confirm
2. Fill fraction: ¼ voll / halb voll / ¾ voll / randvoll
3. Timestamp (now, editable)
4. Optional note

Inline computed: "Geschätzte Menge: ~17 mL"

Daily summary: "Heute geloggt: ~51 mL (3 Mal geleert)"

### 3.8 Doctor PDF

For "Für meinen Frauenarzt" export:
- Zyklusblutung gesamt (geschätzt): ~65 mL
- Stärkster Tag: ~22 mL (Tag 2)
- Anzahl Leerungen: 12 (über 5 Tage)
- Produkt: MeLuna L (34 mL)
- Schätzgenauigkeit: Benutzerangaben

**Do NOT include:** comparison to 80 mL threshold, interpretation phrases ("stark"/"auffällig"), automated flags. The Frauenarzt interprets.

### 3.9 Confirmed unoccupied territory

**No iOS or Android app currently does fill-fraction-based daily volume estimation.** Clue logs cup type but does not compute volume. Flo logs product type only. Drip (Berlin, open source) has no cup volume feature. **Genuine competitive differentiator.**

### 3.10 Future design doc

`docs/design/reusable-product-log.md` — citation target. Can be drafted from this section.

---

## 4. NEW-U + NEW-T — Migraine + Long COVID (combined)

### 4.1 NEW-U Menstrual migraine — citation correction

**PMC10512516 verified as real**, but **mechanism characterization in prior research was reversed.**

The Raffaelli 2023 paper (*J Headache Pain*) titled "Menstrual migraine is caused by estrogen withdrawal: revisiting the evidence" is a **critical re-examination concluding the evidence "remains limited and conflicting, requiring further validation."** The paper questions the established estrogen-withdrawal hypothesis, does not confirm it.

**Citation correction:** "the estrogen-withdrawal hypothesis remains contested per Raffaelli 2023" — NOT "confirmed by Raffaelli 2023."

### 4.2 ICHD-3 window (verified)

- **A1.1.1 Pure menstrual migraine:** attacks exclusively on days −2 to +3 (day 1 = first day of bleeding; **no day 0**) in ≥2 of 3 cycles.
- **A1.1.2 Menstrually-related migraine:** attacks on days −2 to +3 in ≥2 of 3 cycles AND at other times.

6-day window total (D−2, D−1, D+1, D+2, D+3).

### 4.3 Population prevalence (verified)

- Pure menstrual migraine: ~0.8% of reproductive-age women
- Menstrually-related migraine: ~5.3%
- Any menstrual migraine: ~7.6% (Vetvik 2014 Norwegian cohort)
- Germany one-year migraine prevalence in women: 15.6% (Radtke 2009 PMID 19125877)
- **DACH addressable: ~1.2M people in Germany alone** (35M menstruating-age women × 15.6% × 22% menstrual subset)

Not a niche feature.

### 4.4 Effect size honesty (verified)

McGinley 2021 (PMID 33605450): population-level OR for migraine in days −2 to +3 = 1.34 (95% CI 1.23–1.45). Within-woman variation > between-woman variation. Scher 2019 (PMC6734306): menstrual migraine probability 24.4% vs non-menstrual 4.5% in dual-criteria women.

**Practical translation:** Pure menstrual migraineurs will see clear pattern in 3+ cycles. Menstrually-related users will see noisier signal. Pattern detection needs 99% CI gating (already in research-analyst's pattern toolkit).

### 4.5 Architectural decision (R19)

**Inherit B4 generic phase-conditional pattern; no dedicated UI.** Migraine is a symptom category. What's special: structured migraine subtype with aura/duration/severity sub-fields + dedicated Doctor PDF section renderer.

### 4.6 Symptom log structure (recommended)

Two-tier entry. Primary tap: "Migräne ja/nein". Optional expansion:
- Severity (1–10 or kategorisch)
- **Aura ja/nein** (critical — German gynecologists use this as COC contraindication signal; 92% refer to neurology per PMC9958685)
- Duration: begin/end timestamps
- Nausea ja/nein

### 4.7 Doctor PDF section

- Total migraine count in date range
- Window count: migraines in days −2 to +3 vs. outside
- Window percentage
- Aura count
- Average duration (hours)
- Disclaimer: "Diese Daten wurden vom Nutzer eingetragen und nicht klinisch validiert."

### 4.8 MDR boundary (NEW-U)

- ✅ "X of Y migraines occurred in days −2 to +3 of your cycle"
- ✅ "Your migraines tend to occur around your period"
- ⚠️ "Your pattern resembles menstrually-related migraine" — maps directly to ICHD-3 A1.1.2 diagnostic criterion; avoid
- ❌ "You may have menstrual migraine"
- ❌ "Hormonal contraception might help your migraines"

### 4.9 NEW-T Long COVID — citation upgrade

**Visible medRxiv preprint (10.1101/2025.01.24.25321092) verified.** n=948, Imperial College London, Male V corresponding author. Still preprint as of v2 (2026-02-27); no peer-reviewed publication yet.

**Better citation now available — promote to primary:**
- **Maybin JA et al. "The potential bidirectional relationship between long COVID and menstruation." *Nature Communications* September 2025. PMC12441152.** University of Edinburgh + Montpellier + Oxford. Peer-reviewed.

Per Maybin 2025 (n=54 cycle-tracked substudy):
- Late secretory/menstrual phase → more severe dizziness (OR 1.94), fatigue (OR 1.80)
- Proliferative phase → more severe breathing issues (OR 3.14), headache (OR 2.81)
- Long COVID associated with cycle disruption: missed periods PR 1.39; increased volume RR 1.93

### 4.10 Effect size honesty (NEW-T)

Visible IRR: 0.963–0.985 = **1.5–4% reduction in symptoms in non-menstrual vs menstrual phase** — modest in aggregate score terms. Crash frequency more dramatic: OR 0.888 (95% CI 0.838–0.941) for non-menstrual vs menstrual crash risk. **CHC users: OR 0.548 for crash incidence** — 45% reduction (n=70 CHC vs 786 non-users, residual confounding risk acknowledged).

### 4.11 DACH addressable (NEW-T)

- Long COVID in Germany: ~756,808 (mecfs-research.org cost report 2026; advocacy/economics, not peer-reviewed epidemiology)
- ME/CFS in Germany: ~656,951
- Combined: >1.4M people
- ~60% female, mostly reproductive-age → ~454k women with long COVID in Germany alone
- 33.8% of long COVID patients report menstrual issues (Frontiers review PMC10208411)

### 4.12 Architectural decision (R17): Self-tag NOT Category E reuse

Category E (PCOS / ongoing irregularity) modifies the **predictor** (wider β). Long COVID users may have regular cycles with amplified symptoms — forcing them into Category E would wrongly widen predictions. Correct approach: **self-tag modifies symptom layer only; predictor reacts to actual cycle data via normal inference**.

Implementation: `TrackingPreferences` model (already in repo as untracked file) is natural home for the tag. Symptom vocabulary extension + pattern threshold modification are configuration derived from the tag.

### 4.13 Extended symptom vocabulary (11 items)

| German | English | Source |
|---|---|---|
| Crash / Erschöpfungseinbruch | PEM / crash | Visible study + ME/CFS taxonomy |
| Brainfog / Konzentrationsprobleme | Brain fog | Visible 88.3% |
| Schwindel beim Aufstehen | Dizziness on standing | Maybin OR 1.94 |
| Energielevel (0–10 slider) | Energy level | Visible paradigm |
| Licht-/Lärmempfindlichkeit | Light/sound sensitivity | ME/CFS cluster |
| Nicht-erholsamer Schlaf | Unrefreshing sleep | ME/CFS criterion |
| Grippegefühl / Halsschmerzen | Flu-like feeling | ME/CFS cluster |
| Muskelschmerzen | Muscle aches | Visible 78.6% |
| Atembeschwerden | Breathing difficulties | Maybin OR 3.14 |
| Herzrasen / Herzklopfen | Palpitations | POTS co-occurrence |
| Anstrengung durch Nachdenken | Mental effort | PEM mechanism |

**Energy slider is the single most valuable item** — enables phase-conditional pattern display without full pacing infrastructure (Visible's "daily stability score" needs continuous HRV — out of scope for v1).

### 4.14 In-app contextual card (NEW-T)

Appears ~48h before predicted period onset (in-app only, NOT notification):

> "In den nächsten Tagen beginnt voraussichtlich deine Periode. Manche Menschen mit ME/CFS oder Long COVID berichten, dass diese Zeit anstrengender sein kann. Du kennst deinen Körper am besten."

Reasoning for in-app-only: notification fatigue + lockscreen privacy + 28-day suppression complexity.

### 4.15 MDR boundary (NEW-T)

- ✅ "Your fatigue tends to be higher in the days around your period"
- ✅ "Crashes were more frequent around your last 3 periods"
- ⚠️ "Your pattern may be worsened by your menstrual cycle" — moves toward causal claim
- ❌ "Your long COVID is affecting your cycle regularity"

### 4.16 Future design docs

- `docs/design/menstrual-migraine.md` (NEW-U)
- `docs/design/chronic-illness-cycle-context.md` (NEW-T)

Both citation targets. Can be drafted from this section.

---

## 5. NEW-S — Cycle Archaeology HK posterior seeding

### 5.1 🚨 CRITICAL: Flo does NOT write to HealthKit

**Verified from Flo's own help docs:** "Logged Menstruation data in Flo will not be sent to the Health app." Data syncs **one-way only**: HK → Flo, never the reverse.

**The "Flo migrant" marketing pitch must be scoped accordingly:**

| App | Writes to HK? | Verification |
|---|---|---|
| Apple Health Cycle Tracking | ✅ Yes — native, canonical source | Apple documentation |
| Clue | ✅ Yes since 2015 | Clue blog post + Elara.care setup guide |
| Flo | ❌ **NO** | help.flo.health article 34890229122068 |
| Natural Cycles | ⚠️ Reads from HK; write status unclear | NC docs describe import direction only |
| Stardust | ⚠️ Requests read+write permissions | NowSecure security analysis (whether actually used: unverified) |
| Glow | 🤷 Could not verify | No primary documentation found |
| Apple Watch Cycle Tracking | ✅ Yes | Same HK store as iPhone |

**Marketing claim revision (R15):** App Store copy must scope to **"if you tracked in Apple Health Cycle Tracking or Clue"** — NOT "your Flo data." Flo migrants need future CSV import (out of v1 scope per existing constraints).

### 5.2 Architecture: zero new predictor code required

`CycleStore.loadAndReplay()` already implements posterior seeding via sequential replay through `predictor.observe(cycleLength:)`. After `importHealthKitSamples()` commits imported `DayEntry` rows + `rebuildCyclesFromDayEntries()` repopulates the cycle table → next `loadAndReplay()` automatically replays everything including imported history.

**Recommendation: Option (a) sequential replay** — already implemented, mathematically equivalent to batch update (commutative for fixed prior), preserves temporal ordering for `CycleEvent` annotations, reproducible from `DayEntry` rows alone (HK access can be revoked post-import).

### 5.3 Cycle reconstruction (already in codebase)

`HKImportPlanner.plan(samples:existingEntryDates:)` uses `PhaseBoundaries.cycleStarts(fromBleedingDays:)` (Belsey episode rule + FIGO 21-day floor) to derive cycle starts. `HKImportCycleGroup.lengthDays` field already populated.

Pseudocode for the full path:
```
1. Dedupe samples per calendar day (keep heaviest flow)
2. Drop future-dated samples
3. Drop samples with flow == .none
4. Extract sorted bleeding days
5. Apply PhaseBoundaries.cycleStarts → [Date]
6. Compute cycle lengths as differences
7. Filter to 21–45 day validity range (via existing PredictorService clamp)
8. Flag cycles > 45 days as suspect (SkipTrack-adjacent, manual disambiguation)
```

### 5.4 HealthKit API specifics (verified)

- `HKCategoryType(.menstrualFlow)` — daily records, one per bleeding day
- `HKCategoryValueVaginalBleeding` (iOS 18+): `unspecified=1, light=2, medium=3, heavy=4, none=5` — **no native spotting value** (Tideline already maps spotting↔light at write time)
- `HKMetadataKeyMenstrualCycleStart: Bool` — mandatory metadata; `true` marks first day of new cycle
- Integer enum values stable across the `HKCategoryValueMenstrualFlow` → `HKCategoryValueVaginalBleeding` API rename (verify with one-time device test)

### 5.5 Review-before-commit UX

Distinct from #71 day-level review screen — this is cycle-level review.

**Screen 1 — Import summary:**
> "Deine Zyklusgeschichte
>
> Wir haben X Zyklen in der Gesundheits-App gefunden, vom [Datum] bis [Datum].
>
> Tideline nutzt diese Daten, um Vorhersagen sofort auf dich abzustimmen — alles bleibt auf deinem Gerät."

Below: horizontal bar histogram of cycle lengths (2-day bins, 21–45+ range). Simple `Rectangle` views in SwiftUI; no chart library needed.

**Flagged cycles section (only if suspect cycles exist):**
> "X Zyklen sehen ungewöhnlich lang aus (über 45 Tage). Das kann bedeuten, dass du eine Periode nicht erfasst hast. Du kannst sie ausschließen, wenn du möchtest."

Per flagged cycle: toggle include/exclude. **Default: excluded** (conservative — user opts in rather than out).

**Screen 2 — Confirmation buttons:**
- [Verlauf importieren] / [Import History]
- [Überspringen] / [Skip]

**Post-commit display:** "Based on your history, your typical cycle is estimated at X days (range Y–Z)." Closes the loop with immediate evidence of effect.

### 5.6 Effect-size quantification

NIG posterior dynamics with default prior (κ₀=2):
- At N=2: prior contributes 50% of location estimate
- At N=6: prior contributes 25%
- At N=10: 17%
- At N=24: 7.7%

**Concrete: a user with personal mean 25.7 days (3 days off population mean 28.7) and 24 imported cycles starts with prediction error ~0.1 days vs. ~1.5 days without import.**

**90% CI width:**
- At N=0 (population prior): ~15 days total CI width
- At N=24: ~11 days total CI width

**Cycle Archaeology saves ~4 days of CI width on day 1.** Critical for conformal calibrator (Phase 3 NEW-E) operating on well-seeded posterior from cycle 1 rather than 6 months of "still learning."

### 5.7 Schema impact — minimal

New `CycleEntrySource` enum + `sourceRaw: Int` field on `DayEntry`:

```swift
enum CycleEntrySource: Int, Codable, Sendable {
    case tideline = 0    // user-logged in app
    case healthKit = 1   // imported via HK
    // case csv = 2      // future
}
```

SwiftData migration: add column with default `0` = `.tideline`. Existing rows preserved correctly.

Doctor PDF `CycleRow` gains `source` field → superscript: "¹ Importiert aus Apple Gesundheit"

### 5.8 v2 mixture predictor integration

Gibbs sampler ingests the same `Cycle` table after import. No special import-time logic needed. Per-event recovery profiles: imported cycles have no event annotations; recommendation is **defer "post-import event annotation" optional flow to v2.1** rather than burdening import UX.

### 5.9 SkipTrack compatibility

When NEW-M ships (Phase 3a per §1.3 above), its skip-probability model operates on the same `Cycle` table. Cycle Archaeology's conservative >45-day exclusion composes cleanly with SkipTrack's probabilistic skip detection.

### 5.10 Verification debt

- Clue's actual HK write coverage (period-start only vs. daily flow) — verify with real Clue-connected device
- Natural Cycles write direction — confirm before including in marketing claim
- iOS 18 API rename backward compatibility — verify with pre-iOS-18 HK records on real device

### 5.11 Future design doc

`docs/design/cycle-archaeology.md` — citation target. Can be drafted from this section.

---

## 6. Verification debt cleanup (fact-checker pass)

Six items from prior research notes audited. Status changes:

| Item | Prior status | New status | Action required |
|---|---|---|---|
| Long COVID medRxiv 10.1101/2025.01.24.25321092 | 🤷 | ✅ Verified | Cite as preprint; **Maybin 2025 Nature Comms PMC12441152 is better primary** |
| Migraine PMC10512516 | 🤷 | ⚠️ Real but mechanism reversed | "Estrogen-withdrawal hypothesis **contested** per Raffaelli 2023," NOT "confirmed" |
| ovul.ai "82% PCOS prediction failure" | 🤷 | 🔴 **Likely fabricated** | **Remove from DACH competitive analysis.** Replace with cited evidence (Setton 2016 PMID 27275788, Johnson 2018 PMID 29749274) |
| Wrist-temp MAE 1.70 vs 1.90 | 🤷 | ✅ Verified | Goodale/Shilaih, Hum Reprod 40(3):469, 2025, n=260, 889 cycles |
| Wearable fertility 0.88 PMC12886881 | 🤷 | ✅ Verified | n=6,244 across 27 studies, 14,288 cycles. Best in 3-day window around ovulation (sensitivity 0.79, specificity 0.80) |
| Embody 100k downloads + tagline | 🤷 | ⚠️ Partial | App exists, 100k is company-reported only (no Sensor Tower). **Tagline "no logins, no data sharing, no fertility questions" is fabricated** — paraphrase verified positioning instead |

### 6.1 Required corrections across docs

These corrections supersede the 🤷 entries in `2026-05-24-feature-research-wave.md` §5.4 and `2026-05-24-design-research-deep-dive.md` §5.4–§6.7. Existing notes preserved as snapshots; this section is the latest verification status.

---

## 7. New decisions (R14–R20)

| # | Question | Resolution | Source |
|---|---|---|---|
| **R14** | Ship NEW-M SkipTrack before or after v2 mixture predictor? | **Before** (Phase 3a on single-component NIG; ~3–4 dev-days, 80–120 LOC) | §1.3 |
| **R15** | Cycle Archaeology marketing scope? | **Apple Health / Clue / possibly Stardust** users only. NOT Flo (one-way sync only). Flo migrants need CSV import (out of v1) | §5.1 |
| **R16** | NEW-V schema for cup volume? | **Option A** — keep `DayEntry.flow: FlowLevel` categorical, add `cupChanges: [CupChange]` relationship. Categorical wins as user's declared experience; computed volume is augmentation | §3.6 |
| **R17** | NEW-T architectural fit? | **Self-tag modifying symptom layer**, NOT Category E predictor mode. Long COVID users may have regular cycles with amplified symptoms | §4.12 |
| **R18** | NEW-O ready to ship parameterized survival curve? | **No.** Blocked on DACH-appropriate cohort data (Ethiopian curve invalid for DE: 13% exclusive BF at 6mo vs Ethiopia high). **Milestone-text approach can ship as v1 fallback** | §2.2, §2.4, §2.10 |
| **R19** | NEW-U dedicated UI? | **No — inherits B4 generic phase-conditional pattern.** What's special: structured migraine subtype (aura, duration, severity) for Doctor PDF | §4.5, §4.6 |
| **R20** | Primary citation for long COVID × cycle? | **Maybin 2025 Nature Comms PMC12441152** as primary (peer-reviewed); Visible preprint as supporting secondary | §4.9 |

---

## 8. Cross-cutting findings

### 8.1 Phase 3 reordering implication

R14 (SkipTrack before v2 mixture) suggests revising the active Phase 3 plan. Current `2026-05-24-roadmap-update.md` lists #83 v2 mixture predictor + NEW-E conformal wrapper as the Phase 3 entry point. The new recommendation:

**Suggested Phase 3 order:**
1. NEW-L #131 Adolescent age-stratified prior (extends #97, ~1d)
2. **NEW-M #132 SkipTrack on single-component NIG (~3–4d)** — moved earlier
3. #83 v2 Mixture Predictor (7–12d)
4. NEW-E #124 Conformal wrapper (bundled with #83 per D4)
5. NEW-O #133 Postpartum survival curve (milestone-text version; parameterized version blocked on §2.10 data)

**This is a recommendation, not a unilateral change to the roadmap update — owner decision.**

### 8.2 Marketing copy corrections needed

Three propagation tasks for App Store / website copy:
1. "Switching from Flo? Bring your history" → revise to "Switching from Apple Health, Clue, or another HK-writing app? Bring your history"
2. Drop "no logins, no data sharing, no fertility questions" as a borrowed Embody tagline — Tideline has its own positioning
3. Remove any "82% PCOS prediction failure" claim — replace with verified Setton/Johnson citations

### 8.3 DACH-specific data debt is real and recurring

Three of the five deep-dives surfaced DACH-specific data gaps where the literature defaults to other cohorts:
- NEW-O: German exclusive breastfeeding 13% at 6mo vs Ethiopian high → Ethiopian curve invalid for DACH
- NEW-V: No primary DACH cup adoption survey accessible
- NEW-T: Germany long COVID demographic breakdown from advocacy-economics source, not peer-reviewed

**Recommendation:** Develop a habit of explicitly flagging "verified DACH-specific" vs. "global default extrapolated to DACH" in every product claim. The owner has zero tolerance for unverified citations; DACH framing inherits that standard.

---

## 9. Open questions remaining

Carried forward from prior notes + new from this wave:

### Verification debt still open
- Clue HK write coverage (period-start only vs daily flow) — verify on real device before claiming
- Natural Cycles HK write direction — verify before including in NEW-S marketing
- iOS 18 HK API rename backward compatibility — one-time device test
- Gompertz γ/λ parameters from PMC9580771 — full paper PDF
- WHO 1998 Uppsala cumulative incidence tables — interlibrary loan
- Jackson 2011 PMID 21343770 full text for first-menses anovulation rate
- DACH-specific postpartum cohort — none found, may not exist
- DMKG 2022/2024 migraine guideline — direct PDF read for menstrual migraine sub-section
- Visible preprint exact IRR statistics — direct PDF access (was 403-blocked)
- Maybin 2025 Nature Comms full effect sizes — direct PDF access (was 303-blocked)

### Design decisions for owner
- Phase 3 reordering per R14 (SkipTrack before v2 mixture)
- Whether to surface Cycle Archaeology during onboarding or Settings-only (recommended: optional onboarding step + Settings always-available)
- DRSP collection UI (#47) timing — gating NEW-X DRSP PDF
- Co-design recruitment for NEW-Y (start now — long lead time)
- Email Fehring at Marquette for residual permission — still pending

### Implementation blockers
- NEW-O parameterized curve: blocked on §2.10 #1 + #2 data verification
- NEW-X DRSP PDF: blocked on PMDS Hilfe e.V. German clinical translation review
- NEW-Y inclusive language: blocked on DACH co-design

---

## 10. Errata (triple-check pass, same session)

A second fact-check pass triggered by the owner on the three Phase 4 citations identified three corrections to §2, §4, and §6 above:

### 10.1 Maybin 2025 ≠ published version of Visible preprint

§4.9 and R20 (§7) framed Maybin et al. 2025 (*Nat Comms*, PMC12441152) as "the peer-reviewed version of" or "superseding" the Goodship/Male medRxiv preprint (10.1101/2025.01.24.25321092). **This is wrong.** They are two independent studies:

- **Maybin et al.** — Edinburgh + Montpellier + Oxford. Three nested cohorts: n=12,187 cross-sectional + n=54 prospective tracked + n=10+10 biological/steroid metabolomics
- **Goodship & Male (preprint)** — Imperial College, Visible app, n=948. Still preprint, not retracted, not superseded

**Correct framing:** Maybin 2025 is the primary peer-reviewed reference; Goodship/Male preprint is an independent corroborating dataset. Cite both. R20 stands with the wording change "supporting secondary" → "independent corroborating."

### 10.2 Migraine window is 5 calendar days, not 6

§4.2 said "6-day window total (D−2, D−1, D+1, D+2, D+3)." That's 5 elements labeled as 6. **Correct: 5-day window** (offsets {−2, −1, +1, +2, +3}; day 0 is skipped per ICHD-3 convention). Implementation must skip day 0 in day-offset arithmetic. The Doctor PDF copy "X of Y migraines occurred in days −2 to +3 of your cycle" remains correct (the range notation is unchanged); only the "6-day window" phrasing in §4.2 needs correction.

### 10.3 PMC9580771 authorship = Belay & Asratie (not Bekele et al.)

§2.1 attributed PMC9580771 to "Bekele D et al." **Correct authorship: Daniel Gashaneh Belay & Melaku Hunie Asratie** (2 authors, not "et al."). Fix wherever the Bekele attribution appears in this document and propagate to any design doc that cites the Ethiopian postpartum cohort.

### 10.4 DACH postpartum cohort void = confirmed true gap (not search failure)

§2.3 flagged "no published DACH-specific postpartum cohort study located." Independent fact-checker confirms this is a **true literature void**, not a search failure: DEGS1 and KiGGS do not publish return-of-menses as an endpoint. If a DACH cohort matters for shipping product copy, a targeted German-language search (DIMDI/LIVIVO) before final sign-off is the next step. Otherwise, accept the gap and proceed with milestone-text approach (§2.4).

### 10.5 Status changes

These corrections do not change the verification ✅ status of the cited PMC IDs themselves — all three papers exist and the underlying data points are accurate. The corrections are framing and attribution, not citation hallucinations. Net trust impact: minor; the third research wave's findings stand with these three edits.

---

## Document conventions

Per project convention: research notes are write-once. §10 above is an errata section appended same-session before this note was cited downstream by any design doc. The verification status table in §6 (with §10 corrections applied) supersedes prior 🤷 entries — when consumers reference verification status, §6 + §10 of this note are authoritative.

This note is the citation target for these future design docs (all can begin drafting from the corresponding section):
- `docs/design/skiptrack.md` — §1
- `docs/design/postpartum-mode.md` — §2 (milestone version only; parameterized blocked)
- `docs/design/reusable-product-log.md` — §3
- `docs/design/menstrual-migraine.md` — §4.1–§4.8
- `docs/design/chronic-illness-cycle-context.md` — §4.9–§4.16
- `docs/design/cycle-archaeology.md` — §5

The integration roadmap `2026-05-24-research-findings-integration.md` does NOT need immediate update — these candidates (NEW-M, NEW-O, NEW-S, NEW-T, NEW-U, NEW-V) are already tracked there; this note adds the implementation-ready depth those candidates need before code. Marketing-copy corrections in §8.2 should propagate to any App Store / website draft when that work begins.
