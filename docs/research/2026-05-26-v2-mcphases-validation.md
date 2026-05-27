# v2 Mixture Predictor — MCPhases Validation Deepening

**Date:** 2026-05-26
**Builds on:** `docs/research/2026-05-26-v2-empirical-validation.md` (V6 Fehring) + `docs/research/2026-05-26-v2-prior-tuning-results.md` (V7 tuning)
**New tests:** V8 (MCPhases v1-vs-v2 replication), V9-lite (biology correlation), V10 (combined evidence with bootstrap CI)
**Decision:** **Pause the planned Session 6 selective-routing implementation.** Evidence from two independent datasets does not justify shipping v2 routing. Recommended next path is design reconsideration, not implementation.

---

## Headline findings

### 1. V8 replicates V6's pattern on independent data (qualitatively)

MCPhases per-user leave-last-out, min train size = 2 (vs Fehring's 7). 9 users with ≥3 cycles → 10 predictions per model.

| Subset | v1 cov₉₀ | v2 cov₉₀ | v1 MAE | v2 MAE | v1 w₉₀ | v2 w₉₀ |
|---|---|---|---|---|---|---|
| MCPhases (V8) | 100.0% | 100.0% | **2.33 d** | 2.50 d | **12.4 d** | 23.3 d |
| Fehring (V6, regular) | 94.6% | 98.0% | **1.82 d** | 2.33 d | **9.4 d** | 15.1 d |

Same shape: both over-cover; v2 is ~similar on MAE; v2's width is ~80% wider. n=10 is statistically weak but the directionality is the same as Fehring's n=590. **Pattern replicates.**

### 2. V9-lite: v2's mixture mechanism does NOT capture biology

Spearman correlation between v2's posterior P(component 2 | cycle) and biological ovulation signals across 28 cycle-observations:

| Signal | Expected sign | Observed |
|---|---|---|
| Max LH during cycle | NEGATIVE (more ovulation → lower P(comp 2)) | **+0.266** (wrong sign) |
| Max PDG | NEGATIVE | +0.025 (essentially zero) |
| LH-surge detected (binary) | Group mean P(comp 2) lower for surge | **0.080 vs 0.063** (wrong direction) |
| Cycle length stratification | Sanity check | <30d: 0.049, ≥35d: 0.256 (correct — confirms mechanism works on length) |

**Interpretation:** v2's component-2 assignment is essentially cycle-length classification. Longer cycles get assigned to comp 2 (sanity check ✓), but this doesn't track biological anovulation independently. The wrong-sign LH correlation reflects a known confound: long cycles tend to have higher max LH (delayed surge from prolonged follicular phase), so the length signal v2 uses correlates *positively* with LH peak rather than identifying genuinely-anovulatory cycles.

**This is a genuine surprise.** The v2 design doc framed the mixture as modeling "ovulatory vs anovulatory" components. The empirical finding is: v2 models "short vs long" cycles. These are correlated but not identical, and on MCPhases data the divergence is visible.

### 3. V10: pooled-evidence MAE difference is statistically significant

Combined Fehring + MCPhases predictions, n=634 per model, baseline v2 priors:

```
Pooled MAE difference (v2 − v1): +0.486 days
Bootstrap 95% CI: [+0.396, +0.576]
Statistically significant: YES (CI excludes 0)
```

**Baseline v2 is significantly worse than v1 on cycle-length point estimation across both datasets.**

Caveat: V10 uses baseline v2 priors `Beta(8, 2)`. The V7-tuned `tighter-pi` priors would close most of this gap (V7 showed Fehring v2 MAE 2.14 vs 1.82 — closer). A V7-on-combined test would be the right comparison; not done in this session.

---

## What changed about the Session 7 plan

The pre-Session-6 plan was: tune priors (Session 5 → done), then ship selective routing in Session 7. V9-lite's biology finding complicates that.

### The original case for v2 routing
"v2's mixture model is better suited to PCOS users because it explicitly models anovulatory cycles as a separate component (Harlow & Zeger 1991 + Guo 2006). Route PCOS-like users through v2 and they get more honest predictions."

### What MCPhases evidence shows
v2's component 2 doesn't actually identify anovulatory cycles in this data — it identifies LONG cycles, which is most of the information cycle-length data carries anyway. The mixture mechanism's *biological* claim is unsupported.

### What this changes
The routing's *practical* justification weakens. The argument "send irregular users to v2 because v2 captures their biology better" becomes "send irregular users to v2 because v2 gives wider intervals on long cycles" — which is true but doesn't require a 540-LOC mixture sampler. A simpler heuristic (e.g., widen v1's β when recent cycle history shows variance > threshold) could deliver the same UX outcome with much less code.

---

## Three honest paths from here

### Path A: Ship selective routing anyway, with re-framed justification

Accept that v2 = "statistical classifier of cycle length into wider/narrower" rather than "biological model of ovulation." The honest user-facing benefit is "wider intervals when your recent cycles vary more." Ship the routing per Session 5 plan with this re-framed motivation.

**Risk:** we're shipping math complexity (Gibbs sampler, mixture priors, recovery profiles, badge UX) whose biological premise the data refutes. Maintainability burden + 540 LOC of math that delivers what a 50-LOC heuristic could.

### Path B: Don't ship v2 routing; keep v2 sidecar-only (badge + late-mode + recovery)

v2 stays exactly as it ships today (after Sessions 1–3). The badge gives users a descriptive summary; the late-mode interval gives wider conditional intervals for users with mixed cycles; the recovery profiles handle Category C events. None of these uses depend on v2's mixture mechanism corresponding to biology — they just use v2's outputs as derived features.

**Don't expand v2's footprint to the main prediction path.** v1 + ConformalCalibrator stays.

**Pros:** honest. Doesn't make claims the data can't support.

**Cons:** the substantial Sessions 4+5+6 validation work doesn't lead to a shippable expansion. We end up where we were after Session 3, with stronger evidence that we *shouldn't* expand.

### Path C: Redesign v2 to actually capture biology

If the goal is a predictor that genuinely captures anovulatory cycles (not just long cycles), the model needs **direct biological signal input**, not cycle-length alone. Candidates:

- **Wrist temperature** integration: post-ovulation temperature shift confirms ovulation. Wave A research already established this for v3.
- **HK cycle-tracking data**: ovulation test results, basal body temperature
- **OPK manual entry**: quantitative LH levels
- **Time-since-last-period-only modeling** (degenerate v2 → fancier v1)

This is a Phase 4+ research direction, not a Session 7 candidate. Re-opens the predictor roadmap.

---

## My recommendation

**Path B**: don't ship v2 routing. Keep the sidecar uses from Sessions 1–3 (they pay their way without depending on the biology claim). Don't expand into the main prediction path.

Reasoning:
- The Fehring evidence said v2 underperforms v1 on regular users
- The V7 tuning showed v2 *can be* near-equivalent to v1 with tighter priors — but no better
- The MCPhases biology test (V9-lite) showed v2's mechanism doesn't independently capture anovulation
- Combined: there's no empirical basis for claiming v2 is *better* than v1 on the cycle-length prediction task
- The remaining argument ("wider intervals are honest for irregular users") is real but achievable via simpler means

The Session 6 finding shifts the question from "how should we ship v2 routing?" to "should we ship v2 routing at all?" Honest answer: not without better data or a redesigned model.

What stays:
- Badge (Session 1) — descriptive of logged cycle distribution; no biology claim required
- Late-mode interval (Session 2) — wider conditional CIs are correct for any data with right-tail mass
- Recovery profiles (Session 3) — event-specific priors are still good for Category C events even if the underlying mixture mechanism is just length-classification

What pauses indefinitely:
- Selective routing (Session 5/216) — pending biology-grade data or redesigned predictor
- ConformalCalibrator on mixture (#124) — same dependency

---

## Caveats on this session's evidence

1. **V8 sample (n=10) is statistically weak.** Could replicate V6 by chance.
2. **V9-lite n=28** is also weak. The wrong-sign correlation could partially reflect noise. But the direction (positive, not strongly negative) is consistent across multiple stratifications, which is harder to dismiss.
3. **MCPhases also lacks true PCOS users.** Both datasets are regular-cohort biased.
4. **Tuning was not re-run on combined data.** Maybe tighter-pi closes the V10 gap entirely.
5. **PDG is sparse in MCPhases** (32% of users) — the most rigorous anovulation signal was unavailable.

These caveats argue for "don't conclude too strongly" but **none of them rescue the case for shipping v2 routing**. The evidence weight is consistently negative.

---

## Files

- `data/validate_phase_predictor.py` § V8, V9-lite, V10 (added this session)
- `docs/design/mixture-predictor.md` — needs amendment with finding
- `docs/research/2026-05-26-v2-empirical-validation.md` + `docs/research/2026-05-26-v2-prior-tuning-results.md` — superseded conclusions documented here
