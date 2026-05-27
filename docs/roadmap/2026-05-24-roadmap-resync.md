# Tideline — Roadmap Resync

**Date:** 2026-05-24 (third snapshot today)
**Status:** Reconciles `2026-05-24-roadmap-update.md` (phase reorder + TestFlight-first decision D8) with `2026-05-24-research-findings-integration.md` (NEW-I…NEW-BB feature candidates + R1–R7 decisions + verification debt). Tracker items now exist for everything proposed.

**Why a third doc today** — the integration doc landed after I'd already created the Phase 2B/C TestFlight tracker items (#128–#134). The integration doc proposed slots #128–#148 for its 22 candidates, which collide. Rather than renumber existing items, the new candidates went into #135–#155. This doc records the actual IDs and the new tracker shape.

---

## 0. What's in the tracker now

**Total open tasks: 38** (up from 17 yesterday → 24 after Phase 2B/C → 38 now).

By phase:

| Phase | Open count | Notes |
|---|---|---|
| **Phase 2A** (active sprint) | 9 | Original 6 cleanup-and-#122 items + NEW-I/J/K (#135/#136/#137) |
| **Phase 2B** (TestFlight commerce + i18n) | 3 | #128 StoreKit, #129 EN strings, #130 locale audit |
| **Phase 2C** (TestFlight a11y + assets) | 4 | #131 VoiceOver, #132 Dynamic Type, #133 contrast, #134 App Store assets |
| **Phase 3** (Predictor v2) | 8 | #83, #124, #11, #10, #110, **+ #138 adolescent prior, #139 SkipTrack, #140 postpartum Gompertz, #155 Fehring verification (BLOCKING #124)** |
| **Phase 4** (post-launch) | 14 | Original 4 (#47/#125/#126/#127) + 10 new (#141–#150 + #154 pattern extensions) |
| **Phase 5** (differentiation) | 4 | Original 1 (#86) + 3 new (#151–#153) |
| **Deferred** (D9) | 1 | #109 duress passcode |

(Plus 90 completed items that don't show up in active counts.)

---

## 1. New decisions formally accepted: R1–R7

Recorded in the integration doc §7; restating here for decision-lineage durability:

| # | Decision | Status |
|---|---|---|
| **R1** | One-time IAP price = **€4.99** (defensible range €3.99–€6.99). | Locked for v1.0 launch. Tracker #128 (StoreKit) implementation parameter. |
| **R2** | No supporter-tier IAP at launch. Defer to v1.2 if post-launch users ask. | Locked. |
| **R3** | Mein Zyklus Layer 2 v1.0 patterns (phase length + cycle trend + bleeding days, #120) confirmed correct. v1.1 extensions B3+B4+C3 queued as **#154**. | Locked. |
| **R4** | Seasonality pattern surfacing — **NEVER**. PMC10872302 effect ≤0.16 days, smaller than logging resolution. Anti-pattern. | Locked. Added to §4 out-of-scope. |
| **R5** | T-suppression mode (part of NEW-Y #150) requires **co-design with 6–10 trans/NB users BEFORE any string is written**. | Locked. Phase 4 prerequisite. |
| **R6** | AI summary layer timing — iOS 26 Foundation Models API is production-stable; not a blocker. Defer build to v1.2. | Locked. Currently unscheduled (not in tracker — add when v1.2 planning starts). |
| **R7** | Sensiplan NFP-Modus with fertile-window computation — **out of scope for v1**. Legal complexity > value. | Locked. Added to §4 out-of-scope. |

---

## 2. Phase 2A updated scope (TestFlight active sprint)

The active sprint now has **9 items**, up from 6:

| ID | Item | Effort |
|---|---|---|
| #82 | Hide placeholder tabs on first launch | 0.5d |
| #92 | CyclePhaseStrip Bearbeiten async race | 0.5d |
| #93 | phaseNamingClinical_v2 toggle UI | 0.5d |
| #105 | Sparkline in paused/retired states | 0.5d |
| #106 | CalendarSheet stale averageLength | 0.5d |
| #122 | NEW-C Loss-aware 28-day suppression | 0.5d (post-#85) |
| **#135** | NEW-I Vaccine/illness event subtype | 0.5d |
| **#136** | NEW-J Standalone "I had a loss" log | 0.5d |
| **#137** | NEW-K Privacy onboarding screen | 0.5d |

Total: ~4.5 days. Phase 2A grows from "~3 days" to "~4.5 days" — still within the original 4–5d budget.

The three NEW items fit Phase 2A's "TestFlight-compatible polish" frame:
- **#135** is a copy-only chip; no predictor change.
- **#136** is a new event subtype; reuses the existing event UI.
- **#137** is a re-arrangement of existing privacy copy onto an earlier screen.

---

## 3. Phase 3 updated scope (Predictor v2)

The mixture-predictor work gained four neighbouring items:

| ID | Item | Why bundled |
|---|---|---|
| #83 | v2 mixture predictor (Gibbs sampling) | The headline |
| #124 | NEW-E Conformal wrapper | D4 — ships paired with #83 |
| **#155** | **Fehring NFP dataset verification** | **BLOCKING #124** — the conformal calibrator's empirical basis must be primary-source-verified before ship |
| #138 | NEW-L Gynecologic-age-stratified adolescent prior | Extends #97 (already shipped) |
| #139 | NEW-M SkipTrack long-cycle disambiguation | Sharpens the Gibbs posterior |
| #140 | NEW-O Postpartum Gompertz survival curve | Per-event recovery profile (NEW-N bundled in #83) |
| #11 | Synthetic cycle generator for tests | Foundation for v2 validation |
| #10 | DSP temperature pipeline | v3 scaffolding lands here |
| #110 | Timezone display drift after travel | Reliability cleanup |

**Critical path**: #155 (Fehring verification) must complete BEFORE #124 ships. Treat as Phase 3 entry-gate.

---

## 4. New open questions added to the queue

From integration doc §6, plus carry-forward:

**Carried forward from prior roadmap:**
- Q1 (loss-aware-silence trigger semantics) — blocks **#122** in Phase 2A. Recommendation: timer starts at event date, restarts on re-logged loss, ends only on manual override OR new logged period start.
- Q5 (iCloud sync CRDT-merge policy) — blocks **#126** (NEW-G) in Phase 4.

**New from research wave:**
- Q_NEW1 (vaccine/illness #135): copy-only or formal soft-reset? **Recommendation: copy-only.**
- Q_NEW2 (intra-day stamps #148): schema migration cost vs benefit? **Decision needed before Phase 4.**
- Q_NEW3 (Long COVID clustering #145): explicit opt-in (chronic-illness self-tag) or surface for all clustering users? **Decision needed during design.**
- Q_NEW4 (inclusive language #150): strings parameterized by user identity or universally neutralized? **Decision needed during co-design (R5).**
- Q_NEW5 (T-suppression mode #150): co-design process design (recruiting, ethics, compensation). **Prerequisite to #150 starting.**
- Q_NEW6 (privacy-first onboarding #137): risk of raising threat-model anxiety. **Test in TestFlight beta.**
- Q_NEW7 (pattern-extensions design doc): write `docs/design/mein-zyklus-pattern-extensions.md` BEFORE #154 ships. **Phase 4 prerequisite.**

---

## 5. Out-of-scope additions

Extending the 2026-05-22 / 2026-05-24 lists:

- ❌ **Seasonality pattern surfacing** (R4, NEW). PMC10872302 effect smaller than logging resolution.
- ❌ **Sensiplan NFP-Modus with fertile-window computation** (R7, NEW). Legal complexity > value for v1; would shift app into MDR Class I territory.
- ❌ **AI cycle/ovulation prediction** (already implicit from CLAUDE.md; integration doc made it explicit). Different from the allowed AI summary layer.
- ❌ **Camera-based OPK / strip scanning** (NEW). Manual numeric OPK entry (#142 NEW-Q) covers the need.
- ❌ **FDA / MDR contraceptive-efficacy certification** (NEW). €500k–1M validation cost, 3–5 years; undermines wellness classification.
- ❌ **Community / social features** (NEW). Moderation nightmare, requires server.

---

## 6. Citation corrections to apply where they appear

Already documented in integration doc §4 and the CLAUDE.md "Last updated" entry — re-stated here for searchability:

- Endometriosis 10.4-year delay → **Hudelist et al. 2012, PMID 22990516**, NOT "Dian 2022"
- Flo settlement → **"$56M/$59.5M preliminary, final approval pending"**, NOT "finalized Sept 2025"
- Postpartum median → **14.6 months**, NOT 14.5
- vzbv "77% would grant Frauenarzt access" → **REMOVE** (could not be verified, treat as fabricated)
- Menopause app market size → **Grand View Research $345.6M/17.2% CAGR** (not VMR; VMR has separate $1.5B/12.5% figure)
- Sensiplan efficacy → cite **both PI 0.4 perfect + PI 1.6 typical** (Frank-Herrmann 2007)
- COVID vaccine cycle effect → **n=30,320** (meta-analysis), NOT n=747,763
- Flo MAU → **"~75M MAU per Flo's own reporting"** (no independent audit; latest 77M)

---

## 7. Verification debt remaining (cite-before-use)

From integration doc §4 / §7; not blocking individual phase exits but must verify before each NEW-* feature ships:

- ✅ **Fehring NFP dataset** → tracker #155 (blocks #124 conformal ship)
- ⏳ ICHD-3 migraine PMC10512516 → verify before #146 NEW-U
- ⏳ Long COVID medRxiv 10.1101/2025.01.24.25321092 → verify before #145 NEW-T
- ⏳ Wrist-temperature MAE 1.70 vs 1.90 (HR 2025) → verify before Phase 5 v3 planning solidifies
- ⏳ ovul.ai "82% PCOS calendar-prediction failure" → vendor source; find underlying 340-woman 2023 ultrasound study before citing
- ⏳ PMC11666598 BPM/ms digits → verify Table 2 before #143 NEW-R copy ships
- ⏳ PMC12886881 wearable fertility 0.88 accuracy → verify before #151 NEW-Z copy ships
- ⏳ Embody app download count + launch date → verify before App Store positioning copy uses it
- ⏳ Stardust Privacy International report → verify before any "local-first claims caught lying" copy uses it

---

## 8. Where to read what

After this resync, the canonical doc set is:

| File | Role |
|---|---|
| `roadmap/2026-05-22-consolidated-roadmap.md` | Original Phase 0–5 structure + D1–D7 decisions |
| `roadmap/2026-05-24-roadmap-update.md` | Phase reorder (TestFlight before v2) + D8/D9/D10 + status of what shipped |
| `roadmap/2026-05-24-research-findings-integration.md` | NEW-I…NEW-BB candidates + pattern-extensions taxonomy + R1–R7 + citation corrections |
| `roadmap/2026-05-24-roadmap-resync.md` *(this file)* | Tracker IDs assigned, decision register reconciled, open-tasks count current |
| `research/2026-05-24-feature-research-wave.md` | Primary evidence trail for the integration doc (write-once, do not edit) |

Read in this order to reconstruct the decision lineage.

---

## 9. Where we actually go next

Phase 2A is still the active sprint. The cleanup batch is still the natural next workblock — 5 unrelated 0.5-day items that can ship in one TDD pass without architectural conversation.

After the cleanup batch:
- **#122** if you can decide Q1 (loss-aware suppression trigger semantics). If not, skip it for now and bundle with NEW-J #136 — both touch the same code path.
- **#135 / #136 / #137** are independent of each other; pick one. #137 (privacy onboarding screen) has the highest user-visible impact for the smallest LOC; reasonable first pick.

Phase 2B (StoreKit + EN + locale) is the second TestFlight gate; Phase 2C (a11y + App Store assets) is the final gate.

---

## Document conventions

Same write-once dated convention. When priorities shift materially again, write a new `docs/roadmap/YYYY-MM-DD-*.md`. This third snapshot exists because the second snapshot was written before the integration doc landed; consolidating to one file would have meant rewriting yesterday's work, which the convention forbids.
