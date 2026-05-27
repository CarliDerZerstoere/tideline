# Edge Case Catalog

**Status:** Living document, append-only
**Last updated:** 2026-05-19
**Purpose:** A working catalog of edge cases — clinical, technical, safety, legal, privacy — that Tideline must handle, has decided to defer, or has explicitly decided to ignore. Each entry has a state.

When a new edge case is identified: add to the bottom of the relevant section with state `open`. When handled: update state to `handled` and link to the design doc/code. When decided not to handle: update state to `wontfix` with a reason.

---

## Status legend

- 🟢 **handled** — covered by a design doc and (eventually) implementation
- 🟡 **planned** — acknowledged, design pending
- 🔴 **open** — known issue, no plan yet
- ⚫ **wontfix** — explicitly out of scope, with justification

---

## 1. Clinical edge cases

### 1.1 Pregnancy-related
| Case | State | Notes |
|---|---|---|
| Confirmed pregnancy | 🟡 planned | Category B pause mode (per `disrupted-cycles.md`). Need pregnancy mode UI. |
| Miscarriage (early, <10wk) | 🟡 planned | Category C in `disrupted-cycles.md` |
| Miscarriage (late, 10–20wk) | 🟡 planned | Same; longer recovery / widened β |
| Induced abortion (medical) | 🟡 planned | Category C in `disrupted-cycles.md` |
| Induced abortion (surgical) | 🟡 planned | Category C; mention Asherman's risk in info content |
| Ectopic pregnancy | 🔴 open | App MUST NOT try to detect. UX implication: if user logs "pregnancy" then later logs heavy/unusual bleeding, do not predict normal cycle return — defer to user-declared follow-up event |
| Molar pregnancy / GTD | 🔴 open | Extremely rare; bleeding/hCG patterns are atypical. Likely just: support user-declared event, defer to medical follow-up |
| Postpartum hemorrhage / lochia | 🔴 open | Bleeding after birth is NOT a period. Logging UI must distinguish "postpartum bleeding" from "period." |
| Implantation bleeding | 🔴 open | Light bleeding ~6–12 days post-ovulation in conception cycles. Predictor could misinterpret as period start. Need to handle: if logged flow is "spotting" and cycle day is in implantation window, prompt user to consider logging as "spotting" vs. "period" |
| Birth control method as emergency contraception (Plan B) | 🔴 open | Disrupts the current cycle in unpredictable ways. Likely Category C with shorter recovery |

### 1.2 Cycle-related conditions
| Case | State | Notes |
|---|---|---|
| PCOS (self-declared) | 🟡 planned | Category E in `disrupted-cycles.md`; widened β |
| Endometriosis | 🔴 open | Heavy bleeding, severe pain, often irregular. Need pain-tracking integration and looser cycle expectations |
| Adenomyosis | 🔴 open | Similar to endometriosis |
| Uterine fibroids | 🔴 open | Heavy/prolonged bleeding; predictor will see "long periods" rather than "long cycles" — different problem |
| Polycystic ovaries without full PCOS | 🔴 open | Sub-clinical pattern; user may not know to self-declare |
| Hypothalamic amenorrhea | 🟡 planned | Category B in `disrupted-cycles.md` |
| Functional hypothalamic amenorrhea — early signal | 🔴 open | If app detects pattern of lengthening cycles + user logs high training load / low energy availability, should we surface educational content? Borderline medical advice. Defer. |
| Primary Ovarian Insufficiency (POI) | 🔴 open | Premature menopause-like. User may not self-declare. App should not try to detect. |
| Perimenopause | 🔴 open | Mentioned in `late-and-missed-periods.md` open question #5. Need self-declared mode that loosens thresholds. |
| Post-menopause | 🔴 open | App should support a "no longer menstruating" state. Critical: **postmenopausal bleeding is a red flag** — if a user in this state logs bleeding, the app should suggest medical attention (in the same neutral way as pregnancy test suggestion). |
| Adolescent cycles (within 5 years of menarche) | 🔴 open | Highly irregular by design. Mentioned in `late-and-missed-periods.md` open question #4. |
| Athletes / endurance training | 🔴 open | Cycle disruption from training load; HRV/RHR baselines also shifted. Different defaults needed. |

### 1.3 Bleeding not from menstruation
| Case | State | Notes |
|---|---|---|
| Breakthrough bleeding on hormonal contraception | 🔴 open | Common with progestin-only methods. Logging UI must distinguish from "period." |
| IUD insertion bleeding | 🔴 open | First weeks after insertion. Educational note in pill/contraception tracking. |
| Postcoital bleeding | 🔴 open | Separate from cycle. Logging should support it as a discrete event, not absorbed into the cycle predictor. |
| Bleeding from infection (STI, PID) | 🔴 open | App must not try to detect. Logging supports it as "spotting" or "other"; no diagnostic prompts. |
| Bleeding from fibroids/polyps | 🔴 open | Same as above |
| Bleeding from sexual trauma | 🔴 open | App must NEVER prompt assumptions about cause. UX: a "log bleeding" interaction must allow the user to log without categorizing it. No "did you have rough sex?" or similar prompts. |

### 1.4 Other physiological disruptions
| Case | State | Notes |
|---|---|---|
| Significant illness / surgery | 🟡 planned | Category C in `disrupted-cycles.md` |
| Major weight change (gain or loss) | 🔴 open | Affects cycle regularity. No specific app handling planned — falls under "stress/lifestyle disruption" generic bucket |
| New medication (SSRI, antipsychotic, BP, etc.) | 🔴 open | Many drugs affect cycle. App should support a free-text "medication change" event marker; no drug-specific handling |
| Substance use (alcohol, opioids, recreational) | 🔴 open | Sensitive to surface in UX. Defer. |
| Chemotherapy | 🔴 open | Often causes temporary or permanent amenorrhea. Likely a Category B "treatment pause" mode |
| Pelvic radiation | 🔴 open | Same |
| GnRH agonists (Lupron, etc.) for endometriosis/fibroids | 🔴 open | Chemical menopause — likely Category B |
| Thyroid medication adjustment | 🔴 open | Cycles regularize as TSH normalizes. Generic "lifestyle change" event marker is probably sufficient |
| Hyperprolactinemia treatment | 🔴 open | Same |
| COVID infection | 🔴 open | Documented cycle disruption in literature. Generic event marker. |
| COVID/flu vaccine | 🔴 open | Documented short-term cycle disruption (1 cycle, typically). Generic event marker. |
| Major travel (>3 time zones) | 🔴 open | Circadian disruption can shift cycle. Generic event marker. |
| Daylight saving time | ⚫ wontfix | Documented but tiny effect; not worth UI |

### 1.5 Gender identity / hormonal context
| Case | State | Notes |
|---|---|---|
| Trans men on testosterone | 🔴 open | Cycles typically stop within months of starting T; may resume if T paused. App must use inclusive language ("you" not "she"); avoid pink/feminine-coded visual themes. Beach theme is gender-neutral — good. |
| Non-binary users | 🔴 open | Same: language and visual neutrality. |
| Cisgender women on gender-affirming care for partners | 🔴 open | Edge case but worth noting: privacy of cycle data matters in households where partners may be hostile to women's reproductive autonomy |
| HRT for menopause | 🔴 open | Different from gender-affirming HRT. Cycles may or may not occur depending on regimen. Self-declared mode probably needed. |
| GnRH agonists for puberty suppression | ⚫ wontfix | Pediatric scope, out of MVP |

---

## 2. Technical edge cases

### 2.1 Device & data
| Case | State | Notes |
|---|---|---|
| User loses phone / phone stolen | 🔴 open | All data is on-device + encrypted. If iCloud backup is on, data restored to new device. If not, data is lost. **Need to document this clearly in onboarding.** |
| App migration from competitor | 🔴 open | Import from Apple Health works (cycle data is HealthKit). Other apps (Flo, Clue) require export/import flows or scraping. **Defer to post-MVP.** |
| Multiple users on shared phone | ⚫ wontfix | iOS is single-user. Not our problem. |
| iOS backup and restore | 🔴 open | SwiftData via CloudKit private DB or local-only. **Need decision:** if local-only (privacy-purest), users lose data when they upgrade phones without backup. If iCloud private DB, data leaves the device (Apple is processor under GDPR). Lean: **opt-in iCloud sync**, default off, with clear consent. |
| iCloud sync conflicts (two devices, same user) | 🔴 open | If we enable iCloud sync, conflict resolution. SwiftData + CloudKit handles this but needs testing. |
| Watch app dependency | 🔴 open | Apple Watch wrist temperature is the main hormone proxy. If user has no Apple Watch, app must remain useful. |

### 2.2 HealthKit
| Case | State | Notes |
|---|---|---|
| User denies HealthKit permission | 🔴 open | App must work without HealthKit — manual logging only |
| User grants partial HealthKit permissions | 🔴 open | E.g., reads flow but not temperature. Handle gracefully — degrade features, don't crash |
| HealthKit data from other apps conflicts with Tideline's | 🔴 open | E.g., user logs in Apple Health that her period started, but Tideline thinks otherwise. Last-write-wins is the iOS default. Surface conflicts to user? Defer. |
| HealthKit category type changes between iOS versions | 🔴 open | Apple sometimes adds new types (pregnancy loss, postpartum, etc.). Need version checks. |

### 2.3 Foundation Models / Apple Intelligence
| Case | State | Notes |
|---|---|---|
| Device not Apple Intelligence capable (iPhone < 15 Pro) | 🟡 planned | Mentioned in earlier discussion — deterministic fallback (template strings) for AI summary feature |
| Apple Intelligence offline | 🔴 open | Some features may require network. Need graceful degradation. |
| Model output violates medical-advice guardrails | 🔴 open | Need regex post-filter rejecting any output containing diagnostic terms. Hard-fail with a static fallback summary if filter rejects. |
| Model output is wrong but plausible-sounding | 🔴 open | Hallucination risk. Mitigation: keep AI in summary role only, never prediction; show source data alongside summary so user can verify |
| Model latency unacceptable | 🔴 open | Generate summaries proactively in background, cache. Show "thinking..." only on first-run. |

---

## 3. Safety edge cases (most important)

### 3.1 Domestic abuse / coercive control
| Case | State | Notes |
|---|---|---|
| Partner has access to user's phone | 🔴 open | **High priority.** Need duress PIN mode like Euki. App icon and notification text must be neutral/disguisable. Pregnancy logging must be hideable. |
| Partner is hostile to user's reproductive autonomy | 🔴 open | Same. Most-recent activity log must be wipeable in <3 taps. |
| Reproductive coercion (forced pregnancy / forced abortion) | 🔴 open | Most extreme version. App's existence on the phone may itself be evidence. Need: option to fully hide the app (icon swapping; on iOS this is constrained to alt-icon sets bundled at build time). |
| Stalkerware / spyware on phone | 🔴 open | Tideline can't defend against system-level compromise. Onboarding should briefly note this and link to resources (e.g., the Coalition Against Stalkerware). |
| Notification preview leaks sensitive info on lockscreen | 🟡 planned | Mentioned in design docs. All notification text must be content-free in preview. |

### 3.2 Legal / surveillance
| Case | State | Notes |
|---|---|---|
| Subpoena / law enforcement request for user data | 🟢 handled by architecture | On-device only = nothing to give. Document in privacy policy. |
| User in a country with anti-abortion laws | 🔴 open | Logging an abortion, even on-device, is a legal risk if the device is seized. Mitigations: PIN lock, ability to delete specific events without trace, no telemetry that records event types. |
| Right to be forgotten request (GDPR Art. 17) | 🔴 open | Trivially: uninstall the app. Better: a "delete all data and reset" button in settings that wipes SwiftData and HealthKit-written entries (where possible — HealthKit deletion semantics are tricky). |
| Death of user — data inheritance | 🔴 open | iOS has Digital Legacy. Tideline data inherited via Apple ID. Some users may not want this. **Add to settings: "exclude Tideline data from Digital Legacy."** Need to verify this is technically possible. |

### 3.3 Underage / consent
| Case | State | Notes |
|---|---|---|
| Users under 16 (GDPR digital consent threshold in most EU countries; varies 13-16) | 🔴 open | GDPR Art. 8 requires parental consent for users under the national threshold. App Store age rating + age gate during onboarding. Probably: age 13+ App Store rating, age 16+ effective minimum (no special handling for minors in MVP). |
| Users under 13 (US COPPA threshold) | ⚫ wontfix | Out of scope. App Store rating excludes. |
| Self-reported age for cycle-tracking purposes (different from account-creation age) | 🔴 open | We don't have accounts, so the only "age" we know is self-declared. Used for adolescent vs. adult cycle threshold (see clinical section). |

---

## 4. Privacy / data edge cases

| Case | State | Notes |
|---|---|---|
| Data export | 🔴 open | GDPR right to portability. Should support CSV or JSON export of all user data. |
| Selective deletion (e.g., delete pregnancy log but keep cycles) | 🔴 open | Required for users in legal-jeopardy contexts |
| Anonymous mode (no account, no telemetry) | 🟢 handled by architecture | Default state — no accounts exist |
| Encryption at rest | 🟡 planned | iOS Data Protection class default (NSFileProtectionComplete or Comprehensive). Document explicitly. |
| App removed from device | 🔴 open | iOS may or may not delete app data depending on user's "Offload App" vs. "Delete App" choice. Document so users know. |
| Third-party SDK exfiltration | 🟢 handled by policy | No third-party SDKs allowed. No analytics, no crash reporters that upload, no ads. |
| Photo of a strip uploaded for OCR (if we ever add it) | ⚫ wontfix for MVP | Camera-based OPK scanning was deferred to Tier 3 in hormone-tracking analysis. If added later, must be 100% on-device. |
| Apple as data processor for iCloud sync | 🟡 planned | If we enable iCloud sync, Apple becomes a processor. Document in privacy policy. User opt-in. |
| Notification text logged by iOS (rate-limited diagnostics) | 🔴 open | iOS may log notification metadata. Cannot prevent. Mitigation: notification text reveals nothing. |

---

## 5. Product / UX edge cases

| Case | State | Notes |
|---|---|---|
| User opens app for the first time | 🔴 open | Onboarding: ask only essential info (age range, last period start if known, regularity self-assessment). Skip-friendly. No mandatory account. |
| User who has never had a period | 🔴 open | Pre-menarche or primary amenorrhea. App must let them log onset later. |
| User who is currently menstruating when they first install | 🔴 open | Onboarding option: "I'm having my period now" sets cycle day 1 today |
| User skips logging for a long stretch then returns | 🟡 planned | Mentioned in `disrupted-cycles.md` resumption flow |
| User has cycle data in Apple Health from another app | 🔴 open | Should ingest and use as historical priors |
| User changes age (rare but possible — birthday during use) | ⚫ wontfix | Triggered by date math; doesn't need special handling |
| User changes name / gender identifier mid-use | 🔴 open | App uses no name. Pronouns / gender language settable in settings. |
| User wants to track for someone else (partner, daughter) | ⚫ wontfix for MVP | Different user, different app install. We don't do family accounts. |
| User wants partner to see their cycle | 🔴 open | Sharing feature is a future consideration; high privacy risk; defer to v2 |
| Localization beyond English/German | 🔴 open | DACH primary, Danish secondary. Other languages defer. |
| Right-to-left languages (Arabic, Hebrew) | ⚫ wontfix for MVP | Not in target markets |

---

## 6. Edge cases we're explicitly not handling

(Documented here so we don't re-litigate them.)

- **Fertility predictions for the purpose of conception assistance** — pushes app toward EU MDR Class I; defer to v2 with regulatory consult
- **Contraceptive efficacy claims** — Class IIb medical device; never
- **Auto-detection of pregnancy from data patterns** — diagnostic territory; never
- **AI-generated medical interpretations of hormone levels** — diagnostic territory; never (covered in `disrupted-cycles.md` and hormone research)
- **Community / forum features** — moderation burden too high for solo dev; user privacy risk too high
- **Partner sharing of cycle data** — privacy risk too high for v1; revisit in v2
- **Web app or Android version** — out of scope (iOS only)
- **Telehealth integration** — out of scope for v1
- **Insurance integration** — never (US-specific, privacy nightmare)

---

## 7. Predictor / mixture-specific edge cases (added 2026-05-26)

| Case | State | Notes |
|---|---|---|
| **Mixture conditional interval not conformal-calibrated** | 🟡 planned | `CycleStore.homeSnapshot` routes late-period interval through `MixturePredictor.conditionalInterval` for N ≥ 12. That path bypasses `ConformalCalibrator` (#114), which wraps the single-component predictive only. Trade-off accepted: mixture right-tail honesty over residual-based calibration. Magnitude of calibration loss unmeasured. **Unblocker: #124 (NEW-E) — extend ConformalCalibrator to wrap mixture predictive. Blocked on Fehring licensing #155.** |
| **Mixture sidecar resets on Category A (retire) and B (pause), keeps on Category C (softReset)** | 🟢 handled | Recorded in `docs/design/mixture-predictor.md` § "Disruption-event semantics". Reviewer-flagged decision: single Category C events (miscarriage, illness) preserve the long-run pattern; Category A/B terminate the regime entirely. |
| **Pattern badge invisible for <12 cycles** | 🟢 handled | By design — 2-component mixture is unidentifiable below the threshold. `cyclePattern()` returns nil. |
| **Wider conditional interval triggers "Keine klare Schätzung" surface more often for irregular users** | 🟢 handled | Correct behaviour. The UI gate at CI width > 14 days predates v2 and is the right floor: honest "no clear estimate" beats false-precision interval. Users with PCOS-like pattern will see this more often; the v1 model was hiding the genuine uncertainty. |
| **Asherman flag persistence after D&C events** | 🟢 handled | `RecoveryProfile.ashermanRisk: Bool` set true for `surgicalAbortion` + `miscarriageLate`. When true, `PredictorService.observe()` does NOT auto-graduate the recovery window at `cyclesToBaseline`. User must clear manually via `clearAshermanRecovery()` — surfaced as "wir bleiben aufmerksam" badge subtitle. Driven by HRU 2024 meta-analysis: 17% (95% CI 11–25%) of first-trimester D&C cases develop intrauterine adhesions. |
| **Newer Category C event overwrites older active recovery** | 🟢 handled | If user logs medicalAbortion while a stopped-OCP recovery is active, the medicalAbortion profile replaces the stopped-OCP profile (newer event dominates, no merging). Locked by `newCategoryCReplacesRecovery` test. |
| **Recovery profile σ inflation can be silently mis-cited** | 🟢 handled | Reviewer caught `medicalAbortion` originally tagged `.literature(Schreiber)` for σ=7, but Schreiber 2011 measures first-ovulation TIMING (σ=5.1), not cycle-length SD. Cycle-length SD via convolution ≈ 5.7d; inflated to 7.0 for first-cycle reset uncertainty. Anchor downgraded to `.analystElicited` with the citation + arithmetic in the rationale. Lesson: when literature doesn't directly measure the parameter we're setting, anchor is `.analystElicited` even if a related paper exists. |
| **σ₁ Cycle-2 tapering deferred to Phase 3.1** | 🟡 planned | `RecoveryProfile.sigma1Cycle2` field exists but is not applied in v1 — σ₁ stays at `sigma1Cycle1` for the full recovery window. Per-cycle tapering (cycle 1 wide → cycle 2 narrower) requires re-applying a tapered profile on each `observe()`. Bounded impact: data dominates prior after cycle 1 for high-N users. Tracked. |
| **v2 mixture is over-conservative on regular users at the population prior** | 🟡 planned | Empirically: width₉₀ 1.6× single-component on Fehring n=590 regular cycles, MAE 28% worse. Cause: Beta(8,2) on π keeps ~20% comp-2 mass even for purely ovulatory data; σ₂²=0.45² gives a wide right-tail prior nothing in the data refutes. **Blanket-routing all non-late-mode predictions through v2 would harm 96% of users.** Mitigation: selective routing only (`.occasionallyAnovulatory` + `.oftenAnovulatory` use v2; `.mostlyOvulatory` stays v1+conformal). See `research/2026-05-26-v2-empirical-validation.md` + `design/mixture-predictor.md` § "Empirical validation". |
| **Fehring dataset under-represents the PCOS tail v2 was designed for** | 🟡 planned | Fehring's clinical filter excludes cycles outside [21, 45] d; NFP cohort is self-selected for regularity. Only 4 of 157 women in V6 had any cycle ≥ 43 d. This means the V6 validation **refutes "v2 beats v1 on Fehring"** but **does not refute "v2 beats v1 on PCOS-representative data."** Phase 5 final validation needs a wider dataset before shipping v2 routing decisions are made. |
| **MixturePredictor empty-posterior return divergence** | 🟢 handled | Session 5 / #215 migrated all 5 derived-from-posterior methods to consistent `Optional` returns (nil on empty). Inconsistent `Double.nan` and degenerate `0...0` paths eliminated. Pillar 3 alignment. |
| **Prior tuning closes the v2-vs-v1 gap on regular users** | 🟢 handled | V7 sweep proved Session 4's "v2 structurally bad" framing wrong. `Beta(15, 2) + σ₂²=0.45²` closes half the regular-user MAE gap while retaining 85% of v2's PCOS-subset coverage benefit. Selective routing path for Session 6: `.mostlyOvulatory` users stay on v1, others route through tuned v2. See `research/2026-05-26-v2-prior-tuning-results.md`. |
| **v2's mixture mechanism does NOT capture biological anovulation (V9-lite finding)** | 🟢 handled | MCPhases biology-correlation test: Spearman ρ(P(comp 2), max LH) = +0.266 — *positive*, when negative is expected. v2 classifies by cycle length, not biology. Confound: longer cycles have higher max LH (delayed surge). **Implication**: the design-doc framing of v2 as "modeling ovulatory vs anovulatory cycles" overclaims. v2 is a length-based mixture classifier. The biology argument for selective routing collapses. Session 7 selective-routing plan PAUSED. See `research/2026-05-26-v2-mcphases-validation.md`. |
| **v2 is statistically significantly worse than v1 on combined Fehring+MCPhases (baseline priors)** | 🟢 handled | V10 pooled n=634 per model: MAE difference (v2 − v1) = +0.486 d, 95% bootstrap CI [+0.396, +0.576]. Excludes 0 → significant. With tighter-pi priors the gap narrows but still no positive v2 case. Sidecar uses (badge, late-mode, recovery) keep paying their way; non-late-mode routing does NOT. |
