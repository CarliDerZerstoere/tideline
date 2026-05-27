# Disrupted Cycles — Design Note

**Status:** Draft for review
**Date:** 2026-05-19
**Scope:** How Tideline handles events that disrupt the normal menstrual cycle (abortion, miscarriage, birth, hormonal contraception, illness, hypothalamic amenorrhea, PCOS).

---

## Context

The current `CyclePredictor` is a Bayesian model that assumes cycle lengths are i.i.d. samples from a Normal distribution. This assumption breaks badly when the user's biology is disrupted:

- After a pregnancy loss, the interval to the next bleeding event can be 4–10+ weeks. Naively logged as a "cycle," it corrupts `μ`, inflates `β`, and produces wrong predictions for cycles afterward.
- During breastfeeding, periods may be absent for 9–18+ months. A "cycle" entered after that gap is biologically meaningless to the model.
- On hormonal contraception, "cycles" are pharmacological, not physiological — they tell us nothing about the user's natural cycle.

Beyond the math being wrong, the **UX of showing a predicted next period the day after a miscarriage** is documented as actively harmful (Andalibi 2021, "Symbolic Annihilation Through Design," *New Media & Society*). Ovia, Flo, Apple Health, and Clue all have well-known failure modes here. Avoiding these is the most important product principle Tideline can adopt.

This document defines how Tideline handles these events at three layers: **data model**, **algorithm**, and **UX**.

---

## Principles

These are non-negotiable. Everything else flows from here.

1. **Silence is a valid app state.** "There's nothing to predict right now, and that's appropriate" is a first-class UI state. The app must be able to show no prediction without that feeling like a bug.

2. **Never notify about cycle predictions within 4 weeks of a logged loss event.** Hard rule. No exceptions. This is the single most important UX rule and the one every competitor has failed.

3. **No streaks for logging.** Period. Streaks shame absence — illness, loss, recovery. We can gamify engagement without punishing legitimate breaks. (This reverses an earlier product idea; see the gamification rework note below.)

4. **The user is the authority on their own data.** Every disruption event is user-declared, never inferred. Users can retroactively flag any interval as "not a real cycle" and remove it from the posterior. The model never overrides the user.

5. **Don't classify the user's emotional state.** No "how are you feeling?" prompts after loss. One short sentence of warmth, an optional information link, then get out of the way.

6. **Honest uncertainty over false precision.** Wider credible intervals after disruption are not a failure — they are accurate. We always show ranges, not single dates.

7. **No medical advice. Ever.** Information about what's typical ("most people's first period is 4–8 weeks after this kind of event") is fine if framed as "what research shows for most people" + "everyone is different, talk to your healthcare provider." Personal predictions for the user's body cross into MDR territory and are forbidden.

---

## Event Taxonomy

Five first-class event categories. The user picks one when they log an event. Each maps to a specific algorithm reaction and UX treatment.

### Category A: Complete biological disruption — cycle tracking is no longer the right tool

| Examples | Algorithm | UX |
|---|---|---|
| Hysterectomy (uterus removed) | Retire the cycle predictor permanently. Archive the posterior. | Warm acknowledgment. Offer to switch to a symptom/hormone-cycle mode if ovaries are retained. No more period predictions, ever. |
| Bilateral oophorectomy (ovaries removed → surgical menopause) | Retire predictor. Archive posterior. | Acknowledge surgical menopause. Offer menopause symptom tracking mode. |

### Category B: Extended pause — duration unknown, predictions actively misleading

| Examples | Algorithm | UX |
|---|---|---|
| Live birth + breastfeeding | Pause mode. No posterior updates. No predictions shown. Posterior snapshot archived under label. | Acknowledge. Note that periods often pause during breastfeeding. Low-frequency gentle check-in (monthly): "Still breastfeeding? [Yes] [My period returned]." User-initiated resume. |
| Starting systemic hormonal contraception (pill, injection, implant) | Pause mode. Archive pre-contraception posterior. | Inform that cycles on hormonal contraception are pharmacological, not natural. Offer to switch to a symptom-only tracking mode. |
| Hypothalamic amenorrhea (self-reported) | Pause mode. | Warm, non-clinical acknowledgment. User controls when to resume. |

### Category C: Recoverable disruption — predictable recovery arc

| Examples | Algorithm | UX |
|---|---|---|
| Induced abortion (medical or surgical) | Outlier-reject the disrupted interval. Soft reset (see below). | Full-screen quiet acknowledgment. No predictions for 4 weeks minimum. First prediction shown with wide credible interval and inline note: "Early estimate — your cycles may take a few months to settle." Wide CI for first 3 cycles. |
| Miscarriage (early or late) | Same as above; for late miscarriage, widen `β` further to encode higher uncertainty in recovery. | Same as above; first prediction window may be 6 weeks instead of 4 for late miscarriage. |
| Live birth without breastfeeding | Outlier-reject pregnancy interval. Soft reset. | Acknowledge. First prediction ~6 weeks post-birth with wide CI. |
| Stopping hormonal contraception | Soft reset using archived pre-contraception posterior if available, otherwise from prior. | Inform user that cycles may be irregular for 1–3 months. Wide CI for first 3 cycles. |
| Significant illness or surgery | Outlier-reject affected interval. No reset (single-event anomaly). | Neutral acknowledgment. Next cycle resumes from prior posterior. |

### Category D: Single anomaly — user-initiated exception

| Examples | Algorithm | UX |
|---|---|---|
| "This wasn't a normal cycle" (user flag, available on any past cycle) | Outlier-reject only that cycle from the posterior. No reset. | Brief neutral acknowledgment. No follow-up. |

This is the catch-all escape hatch for events not covered by Categories A–C: travel, jet lag, one-off stress, an unusual cycle the user wants to exclude for any reason. Always accessible.

### Category E: Ongoing irregularity — user-declared condition

| Examples | Algorithm | UX |
|---|---|---|
| PCOS (self-reported) | Widen `β` permanently (e.g., 2–3x the prior). Display predictions as explicit ranges, never point estimates. | Persistent inline note: "Your cycles are naturally variable. These are estimates, not certainties." |
| Recovering from eating disorder (user-declared) | Same as PCOS handling. | Same. Optional user control to switch back to point-estimate mode once confidence in regularity returns. |

---

## Algorithm Reactions

How the five categories map onto the NIG conjugate predictor (`CyclePredictor.swift`).

### Soft reset (Categories B-resume and C)

Soft reset keeps `μ` as a hint, but resets confidence in everything else. The
β value is age-band-aware (task #162) so a menopausal user's variance prior
isn't actively collapsed to the reproductive-band default after a Category C
or Category F event.

```swift
extension CyclePredictor {
    /// Soft reset after a recoverable disruption.
    /// Keeps the location estimate (the user's body probably still has roughly
    /// their old average), but discards confidence so the next few cycles dominate.
    ///
    /// Task #162 (2026-05-24) — band-aware variant. The no-arg `softReset()`
    /// resolves to `.unspecified` (σ=5.0, β=50.0) as a safe wider fallback,
    /// but the service layer (`PredictorService`) plumbs the user's declared
    /// AgeBand through `softReset(forBand:)` so the post-event prior matches
    /// the user's true within-person variability.
    mutating func softReset(forBand band: AgeBand = .unspecified) {
        // mu: keep — pre-event mean is still our best location hint
        self.kappa = 2.0
        self.alpha = 3.0
        // Standard NIG β = (α−1)·σ² so E[σ²] = σ_band². Task #158 fix; task
        // #162 routes σ through the AgeBand (reproductive=3.79 → β=28.7282;
        // adolescent=5.33 → β=56.84; perimenopausal=5.42 → β=58.78;
        // menopausal=11.19 → β=250.43; unspecified=5.0 → β=50.0).
        let sigma = band.withinPersonSDDays
        self.beta = 2.0 * sigma * sigma
        self.observedCount = 0
    }
}
```

`PredictorService` calls `softReset(forBand: ageBand)` for Category C
(recoverable disruption) AND Category F (resumeAfterPause) so both reset
paths honour the same band-aware prior. The default-arg `.unspecified`
fallback exists for cold-starts where the user hasn't completed the age-band
onboarding step yet.

After soft reset, the first 3–5 logged cycles will dominate the posterior. By cycle 5 post-event, the model is effectively fully personalized to post-event physiology. Pre-event history has contributed a soft starting point but no longer constrains predictions.

### Outlier rejection (Categories C, D, illness)

The disrupted interval is excluded from `observe()` calls. The posterior is unchanged. Simpler than reset:

```swift
extension CyclePredictor {
    /// Caller skips calling observe() for this interval. No-op at the model layer;
    /// the predictor never sees the disrupted cycle length.
}
```

This is enforced at the **caller layer** (the service that drives the predictor), not in the predictor itself. The predictor stays a pure math object.

### Pause mode (Categories A, B, B-during)

Implemented at the caller layer. The predictor's state is archived. While paused:
- No `observe()` calls.
- No `nextPeriodDate(...)` calls — the UI shows "no prediction" instead.

```swift
enum PredictorMode: Codable {
    case active(CyclePredictor)
    case paused(archived: CyclePredictor, since: Date, reason: PauseReason)
    case retired(reason: RetirementReason)  // hysterectomy, oophorectomy
}
```

### Widened-variance mode (Category E)

For PCOS and similar, the model still updates normally but the prior `β` is increased on declaration:

```swift
extension CyclePredictor {
    mutating func declareOngoingIrregularity() {
        self.beta *= 2.5           // ~1.58x wider SD → much wider intervals
    }
}
```

The UI also switches to range-only display.

### Category-to-action lookup table

| Category | observe() the disruption interval? | Soft reset on event? | Pause predictions? | Retire predictor? |
|---|---|---|---|---|
| A. Complete | n/a | n/a | n/a | **Yes** |
| B. Pause | No | On resume: **Yes** | **Yes (immediate)** | No |
| C. Recoverable | No | **Yes (immediate)** | Yes, for 4–6 weeks | No |
| D. Single anomaly | No | No | No | No |
| E. Ongoing irregularity | Yes (normal updates) | No | No | No (but widen β) |

---

## Data Model Additions

The existing `Cycle` and `DayEntry` models stay as-is. Add one sibling type:

```swift
@Model final class CycleEvent {
    var date: Date
    var kind: EventKind
    var note: String        // user free-text; never used by algorithm, only displayed

    init(date: Date, kind: EventKind, note: String = "") {
        self.date = date
        self.kind = kind
        self.note = note
    }
}

enum EventKind: String, Codable, CaseIterable {
    // Category A
    case hysterectomy
    case oophorectomy

    // Category B
    case birthBreastfeeding
    case startedHormonalContraception
    case hypothalamicAmenorrhea
    case resumeAfterPause          // user-declared resume

    // Category C
    case abortion
    case miscarriage
    case birthNotBreastfeeding
    case stoppedHormonalContraception
    case illnessOrSurgery

    // Category D
    case singleAnomaly             // "this wasn't a normal cycle"

    // Category E
    case pcosDeclared
    case ongoingIrregularityDeclared
}
```

`CycleEvent` is purely declarative — it records *what happened*. The interpretation (which category, what reaction) is logic in the service layer, not embedded in the data.

### Why this design

- **Forward compatible.** New event kinds can be added without migrating data.
- **User free-text note is never seen by the algorithm.** Privacy-preserving — the algorithm operates only on the event type and date, never on user-written text.
- **Events are first-class.** They are not flags on `Cycle` objects, because they may not correspond to any single cycle (a hysterectomy doesn't sit on a cycle; it ends them).

---

## UX Rules

The non-negotiable UX patterns derived from the principles.

### When a Category B or C event is logged

The screen immediately after logging is quiet and minimal:

```
[Soft color — no red, no bright green]

We're sorry.
[OR: "Got it." for neutral events like stopping birth control]

There's nothing to predict right now, and that's okay.
When you're ready to start tracking again, your history will be here.

[Close]

[Small text link: "What to expect — cycle information after [this event]"]
```

No graphs. No predictions. No streaks. No mood prompts.

### The information link

The optional "What to expect" link opens a brief, accurate, non-clinical summary of what the literature says about cycle resumption for the specific event. This is where the on-device Foundation Models layer (Gemini Nano / Apple Intelligence) does useful work — it can compose a 3-sentence summary that's warm, factual, and ends with "everyone is different, check with your healthcare provider."

The model **never sees the user's personal data** for this — it only sees the event type. The output is general population information, not personalized prediction.

### Notification embargo

- **Hard rule:** No predictive notifications for 4 weeks after a Category C event (6 weeks for late miscarriage and birth).
- During Category B pause: no notifications at all. Optional monthly gentle check-in if the user opted in.

### Calendar and home screen during disruption

- **Paused:** No predicted date on the calendar. Past cycles still visible. Small dismissible note: "Cycle predictions are paused. [Resume when ready]"
- **Soft-reset recovery (first 3 cycles post-event):** Predicted date shown with a wider credible interval ring (not a sharp dot). Inline tap-to-explain: "Early estimate. Your cycle may take a few months to settle."
- **After cycle 3+ post-event:** Normal prediction display.

### Resumption flow

When the user logs anything after a long gap (≥60 days, configurable — code uses inclusive `>=` boundary, see `ResumeSheetGate.minPauseDuration`):

```
It's been a while. How would you like to continue?

→ Restart predictions fresh         [Soft reset]
→ Keep using our earlier estimate    [Resume from archived posterior]
→ Just skip predictions for now      [Continue pause]
```

No shame. No streak loss. No "welcome back!" cheerfulness.

### Language and tone

| Avoid | Use instead |
|---|---|
| "Your pregnancy has ended. Update your tracking." | "We're sorry. There's nothing to track right now." |
| "Your cycle is 183 days! That's unusual." | (No notification.) |
| "Ready to get back on track?" | "When you're ready, we'll be here." |
| "Prediction: June 14" three days after a miscarriage | (Calendar is blank.) |
| "Your streak ends if you don't log today." | (No streaks for logging at all.) |

---

## Gamification Rework

This design note **invalidates the original streak/XP gamification idea** from the development plan.

Streaks fundamentally conflict with Principle 3 (no shaming absence). A user recovering from a loss, an eating disorder, or a major illness should not see "your 47-day streak ended."

**Alternative gamification approach to evaluate later:**
- Pattern discoveries instead of streaks ("you've now logged enough cycles for me to spot a pattern in your mood — want to see it?")
- Cycle phase achievements that unlock content, not stats ("you've completed your first full luteal phase — here's what your data shows")
- Cosmetic customization (the beach theme) unlocked by event diversity, not consecutive-day pressure

This needs a separate design pass before any gamification code is written. **Marked as open question below.**

---

## Regulatory Posture

The disrupted-cycles handling **must not** cross into medical device territory. To stay in wellness/lifestyle classification under EU MDR:

- ✅ Show population statistics ("research suggests most people's first period is 4–8 weeks after this kind of event") as general information
- ✅ Always pair with "everyone is different — talk to your healthcare provider"
- ❌ Never make personalized clinical predictions ("your risk of pregnancy on day 20 is X%")
- ❌ Never claim contraceptive or conception-facilitating efficacy
- ❌ Never frame information as diagnosis or prognosis

The information link (Foundation Models output) needs **strict prompt guardrails**:
- System prompt must constrain to "general population information, not personalized advice."
- Output must always end with the safety disclaimer.
- Regex post-filter to reject outputs containing diagnostic language ("you may have," "suggests you have," specific condition names in predictive context).

These guardrails are tracked in the AI summaries design (separate doc, to be written before AI integration).

---

## Open Questions

Decisions deferred pending more research or discussion.

1. **Gamification rework** — what replaces streaks? Needs a design pass before any logging-UX work begins.

2. **PCOS-specific algorithm** — widening `β` is a pragmatic patch but not principled. A heavy-tailed distribution (log-normal, mixture model) or a regime-switching model would be technically better. For MVP, the patch is sufficient; revisit in v2.

3. **Late miscarriage threshold for the longer notification embargo** — 6 weeks vs. 4 weeks. Need to decide where the line is drawn (gestational age threshold? user-declared?).

4. **Pause-mode monthly check-in opt-in default** — opt-in or opt-out? Defaulting to opt-out is more conservative (less risk of unwanted notification); opt-in requires the user to remember to enable it. Lean toward opt-out (no check-ins unless user enables them).

5. **HealthKit integration with events** — should `CycleEvent` writes flow into HealthKit's pregnancy/loss data types? Apple Health has limited support here. Probably skip for MVP, revisit when HealthKit service is built.

6. **Multi-language event language** — the warm-tone copy needs review by native German and Danish speakers before launch. English copy is the placeholder.

---

## What This Means for the Code

Once approved, the implementation work splits into:

1. **Add `CycleEvent` SwiftData model** — small change.
2. **Add `softReset()`, `declareOngoingIrregularity()` to `CyclePredictor`** — small change.
3. **Build `PredictorMode` enum + `PredictorService` actor** at the caller layer that owns the mode transitions and decides when to call `observe()`, `softReset()`, or pause — this is the new logic surface.
4. **Update tests** to cover all five categories with synthetic disrupted-cycle scenarios.
5. **Design UI states** for the disrupted/paused/recovery scenarios — separate UX design pass before code.

The predictor file itself (`CyclePredictor.swift`) grows by ~30 lines. The `PredictorService` is new — maybe 150 lines. The UI work is the larger lift.

---

## References

Peer-reviewed and primary sources cited:

- Andalibi, N. (2021). "Symbolic Annihilation Through Design: Pregnancy Loss in Pregnancy-Related Mobile Apps." *New Media & Society*. DOI: 10.1177/1461444820984473
- Schreiber, C. A., et al. (2011). "Ovulation resumption after medical abortion with mifepristone and misoprostol." *Contraception* 84(3):230–233. PMID 21843685. (n=14 completers; mean ovulation 20.6 ± 5.1 days post-mifepristone, range 8–36)
- Jackson, E. & Glasier, A. (2011). "Return of ovulation and menses in postpartum nonlactating women: a systematic review." *Obstetrics & Gynecology* 117(3):657–662. PMID 21343770.
- Sondergaard, M. L. J., et al. (2023). "Reimagining the cycle: interaction in self-tracking period apps." *Frontiers in Computer Science*. DOI: 10.3389/fcomp.2023.1166210
- Li, K., et al. (2022). "A predictive model for next cycle start date that accounts for adherence in menstrual self-tracking." *JAMIA* 29(1):3–11. DOI: 10.1093/jamia/ocab182
- Mahalingaiah, S., et al. (2023). Apple Women's Health Study cycle characteristics paper. *npj Digital Medicine*. PMC10226714. (n=12,608 participants, 165,668 cycles; mean 28.7 days, population SD 6.1, within-person SD age-stratified 3.79–11.19 days.)
- Bull, J. R., et al. (2019). "Real-world menstrual cycle characteristics of more than 600,000 menstrual cycles." *npj Digital Medicine* 2:83. (Natural Cycles data — separate from AWHS.)
- Nassaralla, C. L., et al. (2011). "Characteristics of the menstrual cycle after discontinuation of oral contraceptives." *J Womens Health* 20(2):169–177. PMID 21219248. PMC7643763. (n=70 post-OCP; cycle 1 length 31.5 ± 11.1 days.)
- Gnoth, C., et al. (2002). "Cycle characteristics after discontinuation of oral contraceptives." *Gynecol Endocrinol* 16(4):307–317. PMID 12396560. (Disturbance persistent through cycle 9; 10.24% strict anovulatory cycle 1 vs. 3.44% controls.)
- DMPA-IM prescribing information (DailyMed). Median ovulation 183 days; median conception 10 months; 55% amenorrhea at 12 months.
- HRU 2024 IUA systematic review. First-trimester D&C 17% IUA (95% CI 11–25%).
- Girum, T. & Wasie, A. (2018). "Return of fertility after discontinuation of contraception: a systematic review and meta-analysis." PMC6055351.
- EU MDR 2017/745, Rule 11 and Rule 15
- MDCG 2019-11, "Qualification and classification of software"
- Swiss Federal Administrative Court, Decision C-1256/2020 (2022), re: Sympto app

**Authoritative correction log (supersedes earlier text where it conflicts):**

The earlier "fact-checked corrections applied" list in this doc carried over imprecise numbers. The web-enabled verification pass on 2026-05-19 produced the following authoritative values, recorded in `research/2026-05-19-mixture-predictor-verified.md`:

- Within-person SD is **age-stratified**, not a flat 3–5 days. AWHS 2023: 5.33 (under 20), 3.79 (35–39, lowest), 5.42 (45–49), 11.19 (50+).
- Asherman syndrome rate after first-trimester D&C: **17% (95% CI 11–25%) per HRU 2024 systematic review** — supersedes the earlier "1.6% to 13%" range.
- Anovulatory rate post-OCP cycle 1: **10.24% strict anovulatory** (Gnoth 2002 verified). Earlier "30–40%" combined strict anovulatory + insufficient luteal phase, which is a different metric.
- Depo-Provera: **median time to ovulation 183 days; median time to conception 10 months. These are distinct quantities.**
- Post-OCP cycle 1: **31.5 ± 11.1 days (Nassaralla 2011, n=70 verified, full text accessed)** — the source for the SD figure is Nassaralla, not the previously misattributed "Mansour 2011."

For implementation, treat `mixture-predictor.md`'s table values as the operative parameters; treat `mixture-predictor-verified.md` as the authoritative numerical evidence base.

---

**Awaiting review.** Once approved, this doc becomes the source of truth for both the algorithm changes and the UX implementation. Any deviation in implementation requires updating this doc first.
