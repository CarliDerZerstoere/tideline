# Test Validation Extensions — Plan

**Status:** Planned / ready to implement
**Created:** 2026-05-21
**Trigger:** Audit identified gaps between what the validation tests cover
(normal-population predictor accuracy via Fehring + mcPHASES) and the
real-world behavior the app needs to guarantee. Current 60 tests pass but
several recent bugs (out-of-order backfill, calendar mensesEnd, future-
dated entries, LogDaySheet load) had **no regression test before they
shipped to production**.

This plan adds the missing test layers in one block.

---

## Goals

1. Pin every previously-fixed user-visible bug with a regression test so
   it can't silently re-emerge.
2. Test the predictor's behavior in edge cases not covered by the
   peer-reviewed datasets (outliers, soft reset, conditional interval
   under various overdue scenarios, age-stratified prior if implemented).
3. Test the SwiftData ↔ UI round-trip — write data, re-read, verify it
   matches what the user saw.
4. Test the cross-surface consistency that's been the source of multiple
   bugs (home strip vs calendar showing different phases for the same day).

---

## Non-goals

- UI tests via Playwright/XCUITest — those are slow, flaky, and out of
  scope for this block. We test the *data* and *math* layers.
- Re-running Fehring/mcPHASES validation in this block — already green.
- Performance benchmarks — separate concern.
- Property-based fuzzing — useful but not the highest-leverage thing
  right now.

---

## Test layers to add

### Layer 1: Regression tests for previously-fixed bugs

Each row gets a dedicated `@Test` in the right suite.

| Bug | Task # | Test name | Suite |
|---|---|---|---|
| Backfill in reverse order produces same Cycle table as forward order | #59 | `rebuildIsOrderIndependent` | CycleStoreTests |
| Future-dated bleeding entry does NOT create a future Cycle row | #60 | `futureBleedingDoesNotCreateCycle` | CycleStoreTests |
| Phase-strip gradient: day 2 shows menses-coral, not turquoise (with mensesEnd=5) | #61 | `barGradientCoralAtDay2` | (already structurally guaranteed by clamp math; document in comment) |
| LogDaySheet on re-open populates from existing DayEntry | #88 | `dayEntrySnapshotRoundTrip` | CycleStoreTests |
| Calendar phase rings reflect actual logged menses length, not default | #98 | `calendarMensesEndUsesLoggedData` | new CalendarPhaseTests |
| mensesEnd holds at default when only 1 day logged (no silent collapse to 1) | #98+ | `mensesEndPadsToDefaultOnPartialLog` | new MensesHeuristicTests |

### Layer 2: Predictor edge cases

| Scenario | Test |
|---|---|
| Single 60-day "cycle" observation should NOT push posterior μ to ~30 from 28.7 | `outlierCycleDoesNotCorruptPosterior` (once #95 lands) |
| Soft reset preserves μ but reverts κ, α, β to fresh prior values | `softResetParameters` |
| After soft reset, the predictive mean is still μ, but the credible interval widens substantially | `softResetWidensInterval` |
| Posterior μ ≠ arithmetic mean for N < ~10 cycles (verifying the bug #100 exists) | `posteriorVsArithmeticMeanDiverge` |
| `conditionalInterval(daysSinceLastPeriod: D)` widens monotonically as D grows | `conditionalIntervalMonotonic` |
| `conditionalInterval` produces interval entirely in the future when D is well past expected | `conditionalIntervalShiftsFuture` |
| Category D outlier rejection (once #96 lands): observe(x) then reject(x) returns posterior to pre-observe state | `categoryDRejectionRollsBack` |

### Layer 3: SwiftData round-trip

| Scenario | Test |
|---|---|
| `logDay` → `dayEntry(for:)` returns identical snapshot (all 5 fields) | `dayEntryRoundTripPreservesAllFields` |
| `logDay` with symptoms → `dayEntry` returns same Set<String> | `symptomsRoundTrip` |
| `logDay` then `logDay` again same date → upsert overwrites, no duplicate | `logDayUpsertsNotDuplicates` |
| `deleteDay` removes the DayEntry AND triggers rebuild that removes the Cycle row | `deleteDayRebuildsCycle` |
| `addEvent` writes CycleEvent AND triggers predictor re-replay | `addEventReplaysPredictor` |
| `loggedDays(in: range)` returns only entries in the range | `loggedDaysRangeRespected` |

### Layer 4: Cross-surface consistency

| Scenario | Test |
|---|---|
| Given the same `cycleStart` + same `bleedingDays`, home-view `mensesEnd` calculation produces same value as calendar's `computeMensesEndByCycle()` | `homeAndCalendarAgreeOnMensesEnd` |
| `PhaseBoundaries.from(cycleLength:mensesEnd:)` → `phase(forDay:)` gives the same result for every (cycleLen, mensesEnd, day) triple between home and calendar consumers | `phaseLookupConsistent` |

### Layer 5: DST and calendar arithmetic (once #99 lands)

| Scenario | Test |
|---|---|
| Cycle spanning Mar/Oct DST boundary computes 28 days, not 27.96 or 28.04 | `cycleLengthAcrossDST` |
| `startOfDay` normalization survives DST | `startOfDayStableAcrossDST` |
| User logs bleeding 24h ± 1h apart → still counted as the next day, not the same day | `dayBoundariesAcrossDST` |

---

## File layout

**New test files:**

| Path | Owns |
|---|---|
| `Tideline/Tests/MensesHeuristicTests.swift` | Layer 1+4 — the consecutive-bleeding-to-mensesEnd derivation, tested once and reused via a shared helper from both home view and calendar |
| `Tideline/Tests/CalendarPhaseTests.swift` | Layer 1+4 — phase ring per day for canonical scenarios |
| `Tideline/Tests/SwiftDataRoundTripTests.swift` | Layer 3 — DayEntry/CycleEvent serialization integrity |
| `Tideline/Tests/PredictorEdgeCaseTests.swift` | Layer 2 — soft reset, outliers, conditional interval |
| `Tideline/Tests/DateArithmeticTests.swift` | Layer 5 — DST and startOfDay invariants (blocked by #99) |

**Extended files:**

| Path | Adds |
|---|---|
| `Tideline/Tests/CycleStoreTests.swift` | Regression tests for #59, #60, #88 |
| `Tideline/Tests/CyclePredictorTests.swift` | Posterior-vs-arithmetic-mean test, μ stability under various N |

**Refactor to enable cross-surface consistency tests:**

Currently the `mensesEnd` derivation logic is duplicated between:
- `TidelineHomeView.refresh()` lines ~440–455
- `CalendarSheet.computeMensesEndByCycle()` lines ~410–448

Extract a single function (e.g. `static func mensesEnd(forCycleStart:bleedingDays:today:defaultMenses:)`) onto `PhaseBoundaries` or a new `MensesHeuristic` enum. Both views call it. The test then exercises this single function with the canonical scenarios, and the consistency test reduces to "both views call the same helper" — verified by compilation.

This consolidation also closes Task #104 (magic-number duplication for `defaultMenses = 5`).

---

## Implementation order

1. **Refactor first.** Extract `mensesEnd(...)` helper to a single location. Wire both views to it. Run existing 60 tests — must still be green.
2. **Layer 1 (regression).** One test per fixed bug. Verify each FAILS if you temporarily revert the fix, then re-apply the fix.
3. **Layer 4 (cross-surface consistency).** Now trivial because of step 1.
4. **Layer 3 (round-trip).** Build the SwiftData round-trip tests against a fresh in-memory model container.
5. **Layer 2 (predictor edge cases).** Soft reset, conditional interval, posterior-vs-arithmetic — independent of #95 / #96 / #99 landing.
6. **Layer 5 (DST).** Land alongside Task #99 (date arithmetic fix). If you fix it now, write the test too.

---

## Effort estimate

- Mensesheuristic extraction + rewiring: 1 h
- Layer 1 (6 regression tests): 1.5 h
- Layer 2 (7 predictor edge cases): 2 h
- Layer 3 (6 round-trip tests): 1.5 h
- Layer 4 (consistency): 0.5 h (trivial after refactor)
- Layer 5 (DST): 1 h (blocked by #99)

**Total: ~7.5 h, ~1 working day.** Most are small unit-test additions
against existing logic; the main work is the helper extraction and the
soft-reset/conditional-interval tests which need synthetic-data setup.

---

## Coverage outcomes

Before this block: 60 tests, all green, but coverage gaps in:
- Cross-surface consistency (the calendar mensesEnd bug shipped silent)
- Edge cases (outlier, soft reset, DST)
- Round-trip (LogDaySheet load bug shipped silent)
- Regression on user-reported bugs

After this block: ~85 tests, covering all of the above. New bugs in those
areas would fail the test suite before reaching the user.

---

## What this block does NOT cover

- The runtime UI behavior (gestures, animations, sheet detents) — needs
  XCUITest.
- The HealthKit round-trip (Task #91) — needs an HK-mock harness.
- The conformal calibrator's interval coverage on heldout data — would
  need a fresh dataset not yet in the repo.
- v2 mixture predictor (Task #83) — separate body of work.

If we want any of these later, they're each their own ~half-day block.
