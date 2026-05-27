# 2026-05-24 — Design Research Deep Dive

**Date:** 2026-05-24
**Type:** Research note (write-once per project convention).
**Purpose:** Design-level research on five specific NEW-* candidates from the morning wave. Complements `2026-05-24-feature-research-wave.md` (broader survey across all candidates). Each section becomes the citation target for the corresponding future design doc.

**Why a second research note same day:** The morning note produced 18 candidates and the integration roadmap placed them by phase. This note goes one level deeper on the five highest-stakes candidates — converging on specific design decisions, primary citations, and the open questions that block the next phase of work (design docs + co-design + clinician input).

---

## 0. Scope and methodology

Five specialist agents dispatched in parallel:

| Target | Agent | Output length |
|---|---|---|
| NEW-P Perimenopause self-declared mode | ux-researcher | ~3,800 words, 12 PMC sources |
| NEW-Q Quantitative hormone log | scientific-literature-researcher | ~3,500 words, 13 sources |
| NEW-Y Inclusive language + T-suppression (pre-co-design groundwork) | search-specialist | ~4,200 words, 23 sources |
| NEW-W + NEW-X DRSP-format PDF + intra-day stamps schema migration | research-analyst | ~5,000 words, 13 sources |
| Fehring NFP dataset verification (blocks Phase 3 conformal wrapper) | fact-checker | ~1,400 words, 10 sources |

Hard constraints baked into every prompt: on-device only, no cloud, EU MDR wellness classification, no diagnostic interpretation, no contraceptive/conception efficacy claims, no streaks, AI summaries only never AI prediction, probabilistic predictions with credible intervals, 28-day notification suppression post-loss, lockscreen-content redaction.

---

## 1. NEW-P — Perimenopause Self-Declared Mode

### 1.1 Verified clinical framework

**STRAW+10 staging** is the operative international standard for perimenopause definition.
- Early transition (Stage −2): ≥7-day persistent difference between consecutive cycle lengths recurring within 10 cycles
- Late transition (Stage −1): first ≥60-day amenorrhea gap
- Menopause: confirmed retrospectively at 12 months of amenorrhea

**Source:** International Menopause Society STRAW+10 statement (imsociety.org).

**German FSH clinical threshold:** >30 IU/L measured in **two independent draws ≥4 weeks apart** — single-draw FSH not diagnostic because of perimenopausal fluctuation. Sources directionally confirmed (gesundheits-lexikon.com, lifeline.de); **verify against DGGG guidelines before any product copy references clinical thresholds**.

### 1.2 Verified longitudinal data — the 3.4-year window

**Harlow et al. PMC3979630** (n=617 TREMIN cohort, 95,246 segments, hierarchical Bayesian change-point model):
- Variance change-point at mean age **42.84 years** (95% CI 42.49–43.17)
- Mean-length change-point at **46.23 years** (95% CI 45.91–46.55)
- Gap: **3.39 years** (verified directly in paper)

**Product implication:** A user in early 40s whose cycle variability is rising is at the *beginning* of a decade-long transition. A mode designed only for "obvious" perimenopause (irregular cycles + hot flashes + late 40s) misses the addressable window. The soft-suggest path (triggered by B2 variance change pattern) reaches users earlier and more accurately than any self-report.

### 1.3 Recognition gap (verified)

**PMC12014197 (2025):** ~⅓ of respondents had little or no familiarity with perimenopause; >½ lacked knowledge of available treatments; only 63% sourced information from friends; fewer than half consulted a health professional.

**Product implication:** A "Perimenopause Mode" button requires self-concept the app cannot create. Two-path design is necessary:
- **Path A (Active):** User declares via settings, single-screen confirmation
- **Path B (Soft suggest):** Triggered when posterior variance crosses STRAW −2 threshold (B2 pattern fires), surfaces a non-diagnostic nudge

### 1.4 Recommended symptom vocabulary (10 items, German + English)

Derived from DACH survey PMC12562409 (n=26,338 women across DE/AT/CH, MRS prevalence) + MRS validation PMC516787 + cluster study PMC11699220 (n=4,789 individuals, 147,501 logs).

| # | German | English | Domain |
|---|---|---|---|
| 1 | Hitzewallungen | Hot flash | Somato-vegetative |
| 2 | Nachtschweiß | Night sweats | Somato-vegetative |
| 3 | Schlafstörung | Sleep trouble | Somato-vegetative (90.3% DACH prevalence) |
| 4 | Erschöpfung | Exhaustion | Psychological (highest mean score 2.17) |
| 5 | Stimmungsschwankungen | Mood shifts | Psychological |
| 6 | Konzentrationsprobleme | Brain fog | Psychological |
| 7 | Niedergeschlagenheit | Low mood | Psychological |
| 8 | Gelenk- oder Muskelschmerzen | Joint / muscle pain | Somato-vegetative |
| 9 | Vaginale Trockenheit | Vaginal dryness | Urogenital (DIVA-validated phrasing per PMC8360914) |
| 10 | Herzrasen / Herzstolpern | Palpitations | Somato-vegetative |

**Cycle-locked vs. constant:** PMC11699220 confirms hot flashes are **not predictively phase-locked** in perimenopause. Do not display vasomotor symptoms on cycle-phase overlay; use calendar heatmap instead. Psychological symptoms may retain partial phase-locking (extrapolation — not directly cited).

### 1.5 Predictor behavior changes (concrete spec)

| Condition | UI state | Predictor behavior |
|---|---|---|
| Mode declared; posterior 90% CI < 20d | Range bar ("18–46 days") | Category E with **`beta *= 4.0`** (vs. current PCOS 2.5×; recommended for predictor team to validate against verified AWHS data) |
| Posterior 90% CI ≥ 20d OR first 60d gap | "Irregular cycle — tracking your pattern" | Suppress countdown; monthly symptom heatmap |
| User logs 60+ day gap | Soft prompt: "Mark as irregular period or skipped cycle?" | Outlier-reject if confirmed skip |
| 12 consecutive months no logged period | Single neutral transition prompt | Predictor retired; offer symptom-only mode |

**MDR boundary phrasings — verified safe vs. forbidden table is in the agent output**, summarized:
- ✅ "Your cycle lengths have varied more in the last 6 months than in the previous 12."
- ✅ "Your cycles have shown increased variability. Would you like to switch to pattern-tracking mode?"
- ❌ "You may be entering perimenopause."
- ❌ "Many people *your age* experience..." — age-anchoring is itself a diagnostic proxy
- ❌ "Your luteal phase is shortening, which is typical of perimenopause."

### 1.6 Open questions blocking design doc

Eight DACH-specific open questions identified (full list in agent output). Highest-priority:
1. **Soft-suggest acceptance** — will DACH users find data-pattern-triggered mode suggestion empowering or presumptuous? Single most important usability question for Path B.
2. **Mode naming** — "Pattern-Tracking Mode" vs. "Wechseljahre-Modus"; user preference unverified
3. **HRT logging willingness** — does it belong in a cycle app at all, or feel orphaned without partner communication features?
4. **Vaginale Trockenheit phrasing** — comfortable in self-logging context, or clinical-cold?
5. **B2 surfacing** — informative + empowering, or anxiety-inducing without clinical context?

**These require 6–8 DACH user interviews** (perimenopausal, recruited through Frauenarzt networks or German menopause forums) before any code is written. Lightweight version (3–4 interviews) would still substantially de-risk vs. shipping blind.

### 1.7 Primary sources (verified directly this pass)

- Harlow et al. PMC3979630 — variance precedes mean by 3.39 years
- DACH MRS survey PMC12562409 — n=26,338, prevalence data
- MRS validation PMC516787 — instrument structure
- PMC11699220 — vasomotor symptoms not phase-locked
- Sillence et al. PMC12034958 — qualitative menopause app study (empowerment / HCP-comms themes)
- PMC12014197 — perimenopause perception survey
- PMC8360914 — German DIVA questionnaire validation
- Caria RCT PMC12187029 — JMIR mHealth 2025, hot flash distress reduction

### 1.8 Future design doc

`docs/design/perimenopause-mode.md` should cite this section as its evidence base. Should NOT be drafted before the DACH user interviews land.

---

## 2. NEW-Q — Quantitative Hormone Log

### 2.1 Device ecosystem inventory

| Device | Measures | Units | Cloud / local |
|---|---|---|---|
| Inito | E3G, LH, PdG, FSH (single strip) | E3G ng/mL, LH mIU/mL, PdG µg/mL, FSH mIU/mL | Inito app only; no confirmed public API or HK write |
| Mira | E3G, LH, PdG, FSH (separate sticks) | Same as Inito | API exists per developer page but undocumented publicly; no confirmed HK write |
| Proov | PdG primary (threshold 5 µg/mL); some kits LH/E3G/FSH | µg/mL | Proov app; no confirmed API |
| Oova | LH, E3G, PdG (smartphone scan) | LH mIU/L, PdG µg/mL | Oova app only |
| Femometer | LH | mIU/mL via app camera + strip | Femometer app; no confirmed HK bridge |

**Key engineering finding:** No device has confirmed public HealthKit write channel. v1 requires manual numeric entry (user types value from device app). Automated import requires per-device partnership.

**Sources:** Lavorini et al. PMC9866173; Inito validation PubMed 37286704; Proov FDA 510(k) K191462.

### 2.2 German lab integration

German Frauenarzt-ordered panel + units:

| Hormone | Standard German unit | Conversion factor |
|---|---|---|
| Estradiol (E2) | **Split: pg/mL OR pmol/L** | pmol/L × 0.2724 = pg/mL |
| Progesterone (P4) | ng/mL (occasional nmol/L) | nmol/L × 0.314 = ng/mL |
| LH | mIU/mL = IU/L (identical) | n/a |
| FSH | mIU/mL | n/a |
| AMH | ng/mL (occasional pmol/L) | pmol/L × 0.140 = ng/mL |
| Prolactin | ng/mL | n/a |
| TSH | mIU/L | n/a |

**Critical UI implication:** E2 is the only hormone where DACH labs split on units. App must accept both formats on input, convert to canonical pg/mL storage. Same pattern for P4 (ng/mL canonical) and AMH (ng/mL canonical).

**ePA (elektronische Patientenakte):** Rollout completed October 2025; all DACH practices upload lab records. **No standardized FHIR endpoint for third-party app pull confirmed** as of this pass. OCR of Befund-PDF is the realistic v3 path; deferred from v1.

**Source:** Springermedizin.de / Die Gynäkologie 2018; kinderwunschklinik.at hormone interpreter.

### 2.3 Cycle-day reference ranges (canonical sources for citation)

**Estradiol (E2, pg/mL):** From PMC8042396 (Gałczyński et al. 2021, Elecsys assay, serum):
| Phase | Cycle days | Range | Median |
|---|---|---|---|
| Early follicular | 1–5 | 30–100 | 54 |
| Late follicular | 6–13 | 100–400 | 126 |
| Ovulatory peak | 12–15 | 200–600 | 206 |
| Mid-luteal | 22–25 | 100–300 | 112 |
| Late luteal | 26–28 | 30–100 | 54 |

**LH (serum, mIU/mL):** From PMC8042396 — follicular 2–10, surge 20–70 (median 22.6), luteal 2–13.

**Progesterone (P4, ng/mL):** From PMC8042396 — follicular <1, luteal 5–25 (mid-luteal >10 confirms ovulation per Springermedizin reference).

**FSH (mIU/mL, day 2–5 baseline):** 3–9 normal reserve; 10–13 diminished reserve signal; >30 menopausal. **FSH is only meaningful as day 2–5 snapshot** — app must enforce/strongly suggest cycle-day annotation on FSH entry.

**AMH (ng/mL, age-stratified, not cycle-dependent):** From Aslan et al. PMC12226283 (n=22,920, age 18–45):
| Age | Median | 25th–75th percentile |
|---|---|---|
| 20 | 4.2 | 2.5–6.7 |
| 25 | 3.3 | 1.9–5.7 |
| 30 | 2.5 | 1.2–4.3 |
| 35 | 1.4 | 0.5–2.9 |
| 40 | 0.5 | 0.2–1.3 |

**Canonical sources to cite in design doc** (these replace any prior speculative citation):
- E2 / LH / P4 reference ranges: **PMC8042396** (Gałczyński et al. 2021)
- AMH age-stratified: **PMC12226283** (Aslan et al. 2025)
- FSH thresholds: Springermedizin.de 2018 gynecology reference

### 2.4 SwiftData model sketch

```swift
enum HormoneType: String, Codable, CaseIterable {
    case estradiol      // E2 serum, canonical pg/mL
    case progesterone   // P4 serum, canonical ng/mL
    case lh             // serum or urinary, canonical mIU/mL
    case fsh            // serum, canonical mIU/mL
    case amh            // serum, canonical ng/mL
    case prolactin      // serum, canonical ng/mL
    case tsh            // serum, canonical mIU/L
    case e3g            // urinary OPK, canonical ng/mL
    case pdg            // urinary OPK, canonical µg/mL
}

enum HormoneUnit: String, Codable {
    case pgPerML, pmolPerL, ngPerML, nmolPerL
    case mIUPerML, mIUPerL, ugPerML
}

enum HormoneSource: String, Codable {
    case manualBloodLab, inito, mira, proov, oova, femometer, other
}

@Model final class HormoneReading {
    var hormone: HormoneType
    var value: Double              // canonical unit
    var enteredValue: Double       // as typed
    var enteredUnit: HormoneUnit   // what user selected
    var source: HormoneSource
    var cycleDay: Int?             // nil ok for AMH on amenorrhea
    var stimDay: Int?              // non-nil only for IVF stim cycles
    var measuredAt: Date           // date of blood draw / test
    var dayEntry: DayEntry?        // back-link
    var notes: String?
}
```

Multiple readings per day: permitted (Mira morning + afternoon = two rows).

### 2.5 Doctor PDF section spec

Single use case: replace 3 years of paper lab slips.

1. Per-hormone table: cycle # / cycle day / date / value / unit / source — sorted by date
2. Per-hormone chart: multi-cycle overlay, cycle-day X-axis, value Y-axis, population reference band shaded with citation footnote
3. IVF stim flag triggers separate stim-day-axis section
4. Footer disclaimer: "This document contains user-logged observations and population reference data. It is not a medical report."

### 2.6 MDR boundary table (verified specific phrasings)

- ✅ Display user value + labeled population reference band
- ✅ Show multi-cycle overlay across 6 cycles
- ⚠️ Color-code "above population range" (neutral wording) — acceptable; avoid "high/low" (clinical judgment)
- ⚠️ AMH age-percentile display — acceptable as "where your value sits in [age] year-olds from [Aslan 2025]"
- ❌ "Your LH suggests ovulation in 24h" — predictive claim
- ❌ Compute "fertile window" from hormone data — MDR Class IIb/I trigger
- ❌ Show PdG with "ovulation confirmed" — diagnostic claim

### 2.7 Open questions

1. **HealthKit bridge** — do any of 5 devices write quantitative hormone values to HK? Mira's status particularly unconfirmed. If yes, manual entry could be auto-import.
2. **FSH cycle-day enforcement** — UX for "FSH is only meaningful on day 2–5" warning
3. **Prolactin / TSH charting** — not cycle-day-dependent; separate "metabolic panel" section or flat single-value view?
4. **ePA pull** — FHIR R4 patient-facing API timeline for DACH; flag for v3
5. **IVF stim-day axis** — separate "IVF mode" or optional tag in same model?

### 2.8 Future design doc

`docs/design/hormone-log.md` should cite this section. Can be drafted before primary user research because the feature is largely a logging + visualization tool — no MDR-sensitive UX language to validate beyond the boundary table.

---

## 3. NEW-Y — Inclusive Language Layer + T-Suppression Mode

### 3.1 Verified clinical reality of T-suppression

**Breakthrough bleeding on long-term T:** PubMed 38181830 (AJOG 2024):
- 34% experienced breakthrough bleeding during study period
- 64% with retained uterus eventually had ≥1 episode
- **Median time to first episode: 22 months** from T initiation
- Risk factors: lower serum T (mean 389 vs 513 ng/dL), higher E2, earlier initiation age

**Persistent vaginal bleeding during GAHT:** Springer 2024 — confirms 25–34% breakthrough rate on stable T; associated with lower free androgen index.

**Dysphoria prevalence:** Schwartz et al. 2022 (PubMed 35123055) — 93% of TGD adolescents AFAB report menstrual-related dysphoria; 88% want suppression.

**Product implication:** Breakthrough bleeding is clinically significant enough that the app should frame it as something to discuss with clinician, not log passively. T formulation + dose schedule are the variables clinicians need to evaluate the bleeding — these belong in the log.

### 3.2 Inclusive language conventions in comparable apps

**Clue (Berlin, gender-neutral by policy since ~2016):**
- Eliminated "she/her" from all in-app copy (verified from their primary blog post)
- Chose "female health" as domain descriptor after rejecting "people who menstruate" (inaccurate post-menopause), "uterus-havers" (reductive per user feedback), "reproductive health" (implies fertility focus)
- Added "No Period" tracking mode
- Custom tags allow "dysphoria" or "testosterone injection" as logged events
- Source: helloclue.com/articles/culture/accessibility-gendered-language-at-clue (verified)

**Drip (Berlin/Hamburg, open source, F-Droid + Play Store):**
- GitLab gitlab.com/bloodyhealth/drip — uses Weblate for localization
- Described as "gender neutral design, neutral encouraging language"
- Prototype Fund funding required inclusive design commitments
- **Direct inspection of `locales/` files is the next step** — wasn't completed in this pass

**Euki (501c3, US):** Founded explicitly to serve queer/trans/NB users; specific string conventions not publicly documented; inclusivity is in UX structure more than verifiable strings.

**Apple Health Cycle Tracking:** Anatomically neutral UI; 2019 keynote used "women" repeatedly while in-app already more neutral (marketing was the failure). HKCategoryValueMenstrualFlow is the medically neutral data type name.

### 3.3 German-language conventions for DACH launch

**Bundesverband Trans* official position:**
- **Asterisk (*) preferred** as gender-inclusive marker
- **Colon (:) explicitly rejected** as symbolizing binary
- Pronounced as glottal stop (brief speech pause)

**Mainstream DACH press trend (verified, European Sociological Review 2024):**
- Colon has overtaken asterisk in press since 2021 (better screen-reader compatibility)
- Asterisk remains preferred in trans community / activist contexts
- Underscore (Lehrer_innen) declining

**Screen reader accessibility:** None of *, :, _ are reliably parsed by German screen readers as gender markers. Unresolved as of 2025.

**Implications for Tideline strings:**
- "Du" register (informal) — universal for DACH health apps
- "Person die menstruiert" vs. "menstruierende Person" — function-based forms, no authoritative preference between them
- Asterisk vs. colon for inflected nouns — **co-design participants must decide**, not engineering

### 3.4 Co-design plan (structured, not pre-decided)

**Recruitment — DACH-specific organizations:**
- Bundesverband Trans* e.V. (Germany) — federation, member-org referrals
- dgti (Deutsche Gesellschaft für Transidentität und Intersexualität) — 50+ counseling centers
- Deutsche Aidshilfe — supported TASG study PMC9594587, demonstrated participation
- Transgender Team Austria (TTA)
- Türkis Rosa Lila Villa (Vienna)
- Drip user community — privacy-conscious, German-origin overlap

**Format:**
- Stage 1: Individual 1:1 interviews (60–90 min, 6–10 participants) — narrative of current app experience, pain points
- Stage 2: Group workshop (2–3 hours, 4–6 participants) — string evaluation, wireframe annotation, German-formulation rating
- Remote acceptable (video + Figma/Mural); in-person higher quality for detailed language work
- **Individual interviews must precede groups** — dysphoria experiences not freely discussed with strangers

**Compensation:** €50–70/hour, prompt payment (within 1 week), flexible payment method (gift cards, Wise, PayPal — NOT default bank transfer which may require deadname).

**Disclosure (pre-consent):** Commercial nature (one-time IAP, solo dev, no VC), on-device data architecture, that co-design output may be published as design doc, no health data collected from participants.

### 3.5 Eight decisions co-design must resolve

Listed here without proposed answers — co-design produces those:
1. Onboarding language signal mechanism (gender field vs. language preference vs. implicit)
2. Default language (universal neutral vs. femme default + neutral toggle)
3. String architecture (parameterized templates vs. per-mode tables vs. runtime selection)
4. Visual / illustration layer treatment
5. Notification copy stricter standard (always-neutral regardless of mode?)
6. Body-part terminology (uterus / Gebärmutter / functional description / nothing)
7. T-suppression mode declaration trigger + storage
8. Breakthrough bleeding log fields (free-text only vs. structured)

### 3.6 Primary sources (verified this pass)

- PMC12117836 (2025) — menstrual app inclusiveness systematic review (50% gender-inclusive)
- PMC10305890 — "Inclusion means everyone" position paper
- CHI 2023 dl.acm.org/doi/10.1145/3544548.3581040 — Infrastructuring Care, n=64 trans/NB
- PubMed 38181830 — AJOG 2024 breakthrough bleeding incidence
- Schwartz 2022 PubMed 35123055 — TGD adolescent menstrual dysphoria
- PMC11654398 — BMC Public Health 2024, menstrual stigma navigation
- PMC9874991 — TGHIR participatory design study methodology template
- Bundesverband Trans* — bundesverband-trans.de/geschlechtergerechte_sprache

### 3.7 Future design doc + co-design

**Cannot draft `docs/design/inclusive-language-t-suppression.md` until co-design completes.** This research note becomes the pre-read material for co-design participants. The design doc is a co-authored output, not solo-authored.

---

## 4. NEW-W + NEW-X — Intra-Day Symptom Stamps + DRSP-Format PDF

These two features are coupled because the primary user segment (PMDD users) needs both — but the order of operations is non-obvious.

### 4.1 DRSP instrument — verified item structure

**Source:** Endicott J, Nee J, Harrison W. "Daily Record of Severity of Problems (DRSP): reliability and validity." *Arch Womens Ment Health* 2006;9(1):41–49. PMID 16172836.

**Structure:** 24 items. 21 symptom/mood + 3 interference. 1–6 rating ("not at all" → "extreme"). **Evening-anchored** ("over the past 24 hours"). Items 20 and 22–24 not included in DSM-5 criteria scoring (per C-PASS worksheet page 1, verified directly).

DSM-5 symptom groupings (from C-PASS worksheet page 2, verified):
- Core DEPRESSION: items 1–3
- Core ANXIETY: item 4
- Core MOOD LABILITY: items 5–6
- Core ANGER: items 7–8
- Secondary INTEREST: 9 / CONCENTRATION: 10 / LETHARGY: 11 / APPETITE: 12–13 / SLEEP: 14–15 / OVERWHELM: 16–17 / PHYSICAL: 18–21
- Interference (not scored): 22–24

**ICD-11 code:** GA34.41 (verified WHO ICD-11 MMS + IAPMD position statement 2019).

**German clinical term:** "Prämenstruelle Dysphorische Störung (PMDS)" — verified Haußmann et al. *Der Nervenarzt* 2024, PMC10914875.

**Critical gap:** **No official published German DRSP translation exists.** The SIPS (Screening Instrument für Prämenstruelle Symptome, Bentz/Steiner 2011 PubMed 21221519) is the validated German PMDD screening tool but it is **retrospective** screening, not a prospective diary — cannot substitute for DRSP in clinical handoff context. **Tideline German DRSP item labels must be clinician-reviewed before shipping.** PMDS Hilfe e.V. (pmds-hilfe.de) is the natural collaboration partner.

### 4.2 C-PASS algorithm — what it computes + MDR risk analysis

**Source:** Eisenlohr-Moul T et al. "Toward the Reliable Diagnosis of DSM-5 Premenstrual Dysphoric Disorder: The Carolina Premenstrual Assessment Scoring System (C-PASS)." *AJP* 2016;173(11):1071–1076. PMID 27523500. PMC5205545. Cycle-level worksheet published at UNC Women's Mood Disorders — read directly this pass.

**Per-item, per-cycle:** Four binary gates must all be Y for an item to "meet criteria":
1. Premenstrual max ≥4
2. Premenstrual days with rating ≥4 must be ≥2
3. Relative change: (premenstrual mean − postmenstrual mean) / (user's max rating ever − 1) ≥30%
4. Postmenstrual max ≤3

**Cycle-level:** PMDD cycle = ≥1 core emotional domain Y AND ≥5 total domains Y. MRMD = core Y but <5 total. Person-level PMDD diagnosis = ≥2 PMDD cycles.

**Timing windows:** Premenstrual = days −7 to −1; postmenstrual = days 4–10.

**MDR boundary (verified analysis):**

| Action | Status | Tideline decision |
|---|---|---|
| Record 1–6 ratings | ✅ Safe | Ship |
| Display raw ratings in grid | ✅ Safe | Ship |
| Compute + display per-phase means per item | ✅ Safe (arithmetic on user's data) | Ship |
| Display percent change between phases | ✅ Safe with copy: "your logged data," NOT "your score" | Ship with care |
| Display "N of 11 domains were more severe in premenstrual week" | ⚠️ Grey — stops short of diagnosis but is a step toward it | **Defer; needs MDR legal review** |
| Binary "meets criteria" Y/N display | ⚠️ Grey, approaching diagnostic decision support | **Do not ship** |
| "Consistent with PMDD" statement | ❌ MDR Class IIa diagnostic claim | **Forbidden, hard stop** |
| Export grid for clinician handoff | ✅ Safe (clinician makes diagnosis) | Ship |

**Recommended Tideline boundary:** Compute arithmetic internally to produce the grid (phase means, phase-average comparison per item). Surface the per-item ratings and phase means on the PDF. **Do not compute or display binary gate Y/N outcomes** or any summary claim about diagnostic criteria. The clinician runs C-PASS on the grid.

### 4.3 PDF layout spec (A4 portrait, two-cycle stacked)

- Header: title (German primary, English secondary) + app name/version + generated date + optional patient label
- Legend: 1–6 scale (gar nicht → extrem) + phase shading key
- Cycle 1 block: domain rows × day columns; phase shading (luteal in distinct color from C-PASS days −7 to −1); each cell = rating or "—"; right margin = premenstrual mean + postmenstrual mean per item
- Cycle 2 block: same structure below
- Interference section (items 22–24): separate "Beeinträchtigung" group below main grid
- Logging density warning if <50% of cycle days logged
- Footer: "Dieses Dokument gibt Ihre selbst erfassten Daten wieder. Es ersetzt keine ärztliche Diagnose."

**Render path:** SwiftUI `ImageRenderer` at 300 dpi — same infrastructure as existing `DoctorPDFRenderer` (#46 shipped).

### 4.4 Intra-day stamps schema migration (NEW-W)

**Target schema:** `DayEntry` becomes parent of `[SymptomStamp]`. `SymptomStamp` has `timestamp: Date`, `symptoms: [String]`, `moodRaw: Int?`, `note: String`. Flow remains on `DayEntry` (day-level aggregate). For DRSP mode: parallel `drspRatings: [String: Int]?` on `SymptomStamp` (cheapest schema; normalized `DrspRating` child would add another migration).

**SwiftData migration pattern (custom MigrationStage):**

```swift
static let migrateV1toV2 = MigrationStage.custom(
    fromVersion: SchemaV1.self,
    toVersion: SchemaV2.self,
    willMigrate: nil,
    didMigrate: { context in
        // Promote each existing DayEntry's scalar mood+symptoms
        // into a single SymptomStamp at noon on that day
        let entries = (try? context.fetch(FetchDescriptor<SchemaV2.DayEntry>())) ?? []
        for entry in entries {
            guard entry.moodRaw != nil || !entry.symptoms.isEmpty || !entry.note.isEmpty else {
                continue
            }
            let noon = Calendar.current.date(
                bySettingHour: 12, minute: 0, second: 0, of: entry.date
            ) ?? entry.date
            let stamp = SchemaV2.SymptomStamp(
                timestamp: noon,
                symptoms: entry.symptoms,
                moodRaw: entry.moodRaw,
                note: entry.note,
                isSynthetic: true
            )
            context.insert(stamp)
            entry.stamps.append(stamp)
        }
        try? context.save()
    }
)
```

**Key migration design:**
- `didMigrate` (not `willMigrate`) — runs after SwiftData schema conversion
- Noon local time as synthetic timestamp (not midnight — ambiguous; not real time — unknowable)
- `isSynthetic: Bool` flag distinguishes promoted historical records from real intra-day stamps; UI signals "logged as daily summary"
- Keep scalar `symptoms` + `moodRaw` on `DayEntry` as "daily summary cache" — backward-compatible with all existing read paths (Option A in agent output)

### 4.5 Migration impact on existing code paths

| Code path | Change required |
|---|---|
| `CycleStore.logDay(...)` | Append new `SymptomStamp` on each call + keep scalar cache (Option A) |
| `CycleStore.dayEntry(for:) -> DayEntrySnapshot` | Add `stamps: [SymptomStamp]` for DRSP users; existing snapshot unchanged |
| `CycleStore.doctorPDFData(includeSymptoms:)` | New DRSP section reads stamps; existing symptoms section unchanged |
| `loggedDays()` / `loggedDays(in:)` | No change if scalar cache retained |
| `importHealthKitSamples` / `logDayRange` | No change (flow-only) |
| Pattern detection (#120 Mein Zyklus Layer 2) | Needs spec: when day has multiple stamps, what is "symptom severity on day D"? Max? Mean? Last stamp? **Must be decided before Phase 4 pattern work (B3, B4) starts.** |
| `HKExportPlanner` | Verify it doesn't need per-stamp timestamps (HK has no equivalent concept) |
| `HeroStateBuilder` | Check whether it reads `DayEntry.symptoms` for hero state |

**Predictor: untouched.** Predictor only consumes cycle lengths derived from bleeding days. Migration does not affect predictor pipeline.

**`#Predicate` closures:** Continue to compile and run correctly even when `DayEntry` gains relationship property. SwiftData filters relationships in Swift after fetch, not in SQL predicate. No rewrites needed.

### 4.6 The critical insight: DRSP does NOT need intra-day stamps

**DRSP is strictly evening-anchored by design.** Lindner Center of Hope DRSP reference sheet: "Each evening, you should note the degree to which you experienced each of the problems listed." Ratings reflect "over the past 24 hours."

Multiple daily entries would violate DRSP design. The PMC11687174 user complaint about intra-day variation was about **free-form symptom logging**, not DRSP ratings. The two features are coupled at the schema level (both benefit from `SymptomStamp` infrastructure) but uncoupled at the UX level.

**Recommended UX (Bearable model — verified):** Discrete unscheduled stamps, 2–4 per day max, no forced schedule. "+" button on LogDaySheet launches lightweight stamp sheet (time pre-filled to now, editable; mood slider; symptom picker; optional note). Day summary shows mood range (min–max) + symptom union + "N entries" indicator if multi-stamp.

### 4.7 v1.0 vs. v1.x split recommendation

**DRSP PDF (NEW-X): post-v1.0 (v1.x).** Requires DRSP-Modus #47 (logging UI design pending) to ship first — without it, PDF is a grid of blanks. Ship order: (1) intra-day stamps migration, (2) DRSP-Modus logging UI, (3) DRSP PDF section.

**Intra-day stamps migration (NEW-W): Phase 4 first item, after v1.0 stable.** SwiftData breaking-change migration during TestFlight with real users is risky. Recommended: do it as first Phase 4 task, after v1.0 shipped and data model stable.

### 4.8 Open questions

1. **German DRSP item translations** — blocker for PDF section. Need clinical collaborator (PMDS Hilfe e.V. natural contact).
2. **DRSP evening-reminder notification policy** — interaction with 28-day loss suppression rule needs explicit decision.
3. **Logging-density threshold for clinical validity** — what completion rate before DRSP PDF section unlocks?
4. **Stamp-to-day aggregation contract for pattern detection** — max? mean? last? must be specified before Phase 4 pattern work reads symptom data.
5. **GKV reimbursement angle** — whether structured DRSP export materially accelerates German PMDS treatment reimbursement. Couldn't verify; single Frauenarzt interview would resolve.

### 4.9 Future design docs

- `docs/design/intra-day-stamps.md` — schema migration spec, citation target for NEW-W (Phase 4)
- `docs/design/drsp-pdf.md` — PDF layout + C-PASS boundary, citation target for NEW-X (Phase 4)
- Both should cite this research note + the C-PASS worksheet + PMC11687174 + Haußmann 2024

---

## 5. Fehring NFP Dataset — Verification Update

**Status change: 🤷 → ⚠️ Partial verification with material caveats.**
**This entry supersedes** the 🤷 entry for Fehring in `2026-05-24-feature-research-wave.md` §5.4.

### 5.1 What is verified

✅ **The dataset exists** as a citable published resource:
- Fehring RJ. *Menstrual Cycle Data.* Source data for "Randomized Comparison of Two Internet-Supported Methods of Natural Family Planning," Marquette University ePublications, item 7. URL: https://epublications.marquette.edu/data_nfp/7/

✅ **The parent study paper exists:**
- Fehring RJ, Schneider M, Raviele K, Rodriguez D, Pruszynski J. "Randomized comparison of two Internet-supported fertility-awareness-based methods of family planning." *Contraception* 2013;88(1):24–30. PubMed: https://pubmed.ncbi.nlm.nih.gov/23153900/
- Randomized 667 women into EHFM (N=197) and CMM (N=164) arms with 12-month follow-up

✅ **The extractor script EXISTS in the Tideline repo** at `/Users/nr/Developer/CycleApp/data/extract_conformal_residuals.py` (76 lines, runnable, math matches the Swift predictor's NIG update exactly with priors μ=29.0, κ=2.0, α=3.0, β=41.07)

✅ **The raw CSV EXISTS at** `/Users/nr/Developer/CycleApp/data/raw/fehring_cycles.csv` with full schema match: `ClientID, CycleNumber, LengthofCycle, EstimatedDayofOvulation, LengthofLutealPhase, LengthofMenses, Age, BMI, ReproductiveCategory, CycleWithPeakorNot`

✅ **Residual statistics are plausible.** MAE 2.115d / median 1.5d / P90 4.571d are within the expected band for a personal Bayesian model on a healthy motivated NFP cohort (cf. Bortot 2010 PubMed 20400622; Urteaga 2021 PMLR v149 — both report 1.8–2.5d MAE on healthy cohorts).

✅ **`FehringValidationTests.swift` correctly documents** that the raw CSV is NOT bundled into the shipping app — only derived sorted residual magnitudes are shipped.

### 5.2 What is NOT verified

⚠️ **The 159 subjects / 1665 cycles counts cannot be confirmed from the published source alone.** The Marquette page does not state cohort size. The published 2013 paper had 667 women in the parent trial. The 159/1665 figures are almost certainly post-filter survivors (subjects with valid `LengthofCycle` values, plus the script's ≥4-cycle filter for leave-one-out splitting).

**Owner can confirm in 2 minutes:**
```bash
wc -l /Users/nr/Developer/CycleApp/data/raw/fehring_cycles.csv
awk -F, '{print $1}' /Users/nr/Developer/CycleApp/data/raw/fehring_cycles.csv | sort -u | wc -l
```

### 5.3 Corrections to prior claims

🔴 **Fehring is alive.** I claimed in the prompt to the fact-checker that Fehring died in 2020. The fact-checker verified he is professor emeritus at Marquette via https://www.marquette.edu/nursing/directory/richard-fehring.php. **Wherever a "Fehring deceased 2020" note appears in the codebase (if any), it must be corrected.**

### 5.4 Licensing — the actual blocker

The Marquette ePublications page states: *"This human subject data has been anonymized for dissemination. Data reuse agreed to by subjects in consent form."*

**This is NOT an OSI license — it is consent-grounded permission for research reuse.**

- Shipping **derived sorted residual magnitudes** in a commercial iOS app is a much weaker reuse claim than redistributing raw cohort data, but it is still a derivative work
- The 1223 residual values contain no PHI, no subject linkage, no cycle index, no demographics — privacy posture is sound
- The legal posture for commercial reuse without explicit permission is unsettled

### 5.5 Three blockers before Phase 3 conformal wrapper ships

1. **Run the script** and confirm reproduced cohort counts match source comment byte-for-byte. If not, regenerate `ConformalResiduals.swift` and update header.
2. **Obtain written permission** from Richard Fehring or Marquette Institute for Natural Family Planning for residual-only redistribution in commercial iOS app, OR migrate calibration set to a dataset with explicit redistribution license. **Email contact: Professor Richard Fehring at Marquette University College of Nursing.**
3. **Add citation line** in the app's "How we predict" surface (differentiator #16, Phase 5) regardless of permission status.

### 5.6 Fallback datasets (if Fehring permission unobtainable)

Ranked by usability:

1. **Symul et al. 2019** — Kindara/Sympto synthetic data on GitHub https://github.com/lasy/semiM-Public-Repo. Real cohort proprietary. **Suitable for code testing only, NOT shipping calibration.**
2. **Urteaga / Li / Elhadad** menstrual_cycle_analysis https://github.com/iurteaga/menstrual_cycle_analysis. Uses Clue data, proprietary cohort.
3. **Bortot et al. 2010 PubMed 20400622** — published cycle-length distributions could parametrically simulate calibration set, but loses "real residual" claim. Acceptable backup if permission paths fail.
4. **Bull et al. 2019** Natural Cycles npj Digital Medicine — proprietary, not available.

### 5.7 Action items for owner

| Priority | Action | Effort |
|---|---|---|
| HIGH | `wc -l` and unique-ClientID count to verify 159/1665 | 2 min |
| HIGH | Email Fehring at Marquette for written permission to ship residuals in commercial app | 1 email + waiting |
| HIGH | If permission delayed beyond Phase 3 timeline, switch to Bortot-parametric fallback (option 3) | M effort |
| MED | Grep codebase for any "Fehring deceased" reference and correct | 5 min |
| LOW | When Phase 5 "How we predict" surface ships (differentiator #16), include explicit Fehring citation | bundled |

---

## 6. Follow-ups summary

### 6.1 Design docs unlocked (can be drafted from this research)

- `docs/design/hormone-log.md` — citation target §2 of this note. No primary user research blocker.
- `docs/design/intra-day-stamps.md` — citation target §4 of this note. Schema migration spec is complete.

### 6.2 Design docs blocked on user research

- `docs/design/perimenopause-mode.md` — needs 6–8 DACH user interviews on the 8 open questions in §1.6 before drafting. Even 3–4 lightweight interviews would substantially de-risk.

### 6.3 Design docs blocked on co-design

- `docs/design/inclusive-language-t-suppression.md` — must be co-authored output, not solo-drafted. Co-design plan in §3.4.

### 6.4 Design docs blocked on clinician input

- `docs/design/drsp-pdf.md` — needs clinical collaborator review of German DRSP item translations + GKV reimbursement question. PMDS Hilfe e.V. natural contact.

### 6.5 Phase 3 blockers (predictor v2 work)

- Fehring dataset verification (§5.5) — three actions before conformal wrapper ships
- Predictor team to validate recommended `beta *= 4.0` for perimenopause mode (NEW-P) against AWHS data

### 6.6 Verification debt cleared

- ✅ Fehring dataset — graduated 🤷 → ⚠️ with action items (§5)
- ✅ Perimenopause primary sources (Harlow, DACH MRS, MRS validation, cluster study) all verified directly
- ✅ Inclusive language clinical T-suppression data (AJOG 2024) verified
- ✅ DRSP + C-PASS verified directly from primary worksheet
- ✅ ICD-11 GA34.41 + PMDS German term verified

### 6.7 Verification debt remaining (from morning's note)

Carried forward unchanged:
- Long COVID medRxiv DOI (NEW-T)
- Menstrual migraine ICHD-3 PMC10512516 (NEW-U)
- PMC11687174 PMDD claim ("no current menstrual app has full DRSP capabilities") — partially verified by this note's §4 finding that PMDS Hilfe e.V. confirms DRSP unfamiliarity in DACH clinicians, but full claim verification still pending
- ovul.ai "82% PCOS prediction failure" — vendor source
- Wrist-temp MAE 1.70 vs 1.90 (HR 2025)
- Wearable fertility-window 0.88 PMC12886881
- vzbv "77% Frauenarzt access" — 🔴 still not found; remove from all docs

---

## Document conventions

Per project convention: research notes are write-once. The Fehring update in §5 is the only living-by-reference part (it supersedes the prior 🤷 entry); when the Fehring permission situation resolves (✅ permission granted / ❌ migrated to fallback), update §5.5 entries inline in this note or write a new dated note.

This note is the citation target for the four future design docs listed in §6.1–§6.4. The integration roadmap `2026-05-24-research-findings-integration.md` does NOT need an immediate update — the candidates NEW-P, NEW-Q, NEW-W, NEW-X, NEW-Y are already tracked there; this note adds the design-level depth those candidates will need before code.
