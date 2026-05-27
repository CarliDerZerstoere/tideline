import Testing
import Foundation
@testable import Tideline

/// Pins the behaviour of `PhaseBoundaries.mensesEnd(bleedingDays:todayDayInCycle:defaultMenses:)`.
///
/// This is the single function both `TidelineHomeView.refresh()` and
/// `CalendarSheet.computeMensesEndByCycle()` use to decide where the
/// menses-to-follicular boundary sits. Two real user-reported bugs were
/// caused by inconsistencies between two earlier copies of this logic
/// (see tasks #88, #98). The function lives in one place now and these
/// tests pin every interesting scenario.
@Suite("PhaseBoundaries.mensesEnd — consecutive-bleeding heuristic")
struct MensesHeuristicTests {

    // MARK: - Empty / cold-start cases

    @Test("No bleeding days yet → returns default")
    func emptyBleedingReturnsDefault() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [],
            todayDayInCycle: 3
        )
        #expect(result == PhaseBoundaries.defaultMensesDuration)
    }

    @Test("Custom default is respected")
    func customDefault() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [],
            todayDayInCycle: 3,
            defaultMenses: 4
        )
        #expect(result == 4)
    }

    // MARK: - Partial-log padding (the bug #88 fix)

    @Test("Only Day 1 logged on Day 1 → padded to default (period may still continue)")
    func day1OnlyOnDay1() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1],
            todayDayInCycle: 1
        )
        #expect(result == 5)  // max(1, 5)
    }

    @Test("Only Day 1 logged on Day 7 → still padded to default (user may have forgotten to log)")
    func day1OnlyOnDay7() {
        // This was the user-reported bug: previously collapsed to 1,
        // making days 2-6 appear as follicular phase.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1],
            todayDayInCycle: 7
        )
        #expect(result == 5)
    }

    @Test("Days 1-3 logged on Day 10 → padded to default (assume period possibly went 4-5 days)")
    func threeDaysLoggedDayTen() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3],
            todayDayInCycle: 10
        )
        #expect(result == 5)  // max(3, 5)
    }

    // MARK: - Full-log cases (consecutive ≥ default)

    @Test("Days 1-5 logged → returns 5")
    func fiveDaysLogged() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 4, 5],
            todayDayInCycle: 5
        )
        #expect(result == 5)
    }

    @Test("Days 1-7 logged (long period) → returns 7, NOT collapsed to default")
    func sevenDayPeriod() {
        // This is the FIGO upper-bound normal: ≤8 days. We must honor
        // the user's actual data when it exceeds the default.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 4, 5, 6, 7],
            todayDayInCycle: 7
        )
        #expect(result == 7)
    }

    @Test("Days 1-7 logged, viewing later (Day 20) → still returns 7")
    func sevenDayPeriodViewedLater() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 4, 5, 6, 7],
            todayDayInCycle: 20
        )
        #expect(result == 7)
    }

    // MARK: - Consecutive break

    @Test("Days 1, 2, 4 logged (1 dry day on day 3) → Belsey rescues day 4, padded to default")
    func gapBreaksConsecutive() {
        // Under Belsey (#156): day 3 dry counts as 1 dry day < 3, so the
        // episode continues to day 4. lastBleeding=4, max(4, 5)=5. Same
        // numeric result as the pre-#156 consecutive-walk version, but
        // the algorithm reaches it differently. The new tests below pin
        // the cases where the two algorithms actually diverge.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 4],
            todayDayInCycle: 5
        )
        #expect(result == 5)
    }

    // MARK: - Belsey ≤2-day rule (task #156)

    @Test("Belsey: Days 1,2,3,5,6,7 (1 dry day on day 4) → returns 7")
    func belseyAllowsOneDrySkip() {
        // The headline #156 regression: a real 7-day period with one
        // mid-period light day the user forgot to log. Before #156 this
        // returned 5 (consecutive walk broke at day 4), creating a
        // visible contradiction with the Cycle table's Belsey grouping
        // which (correctly) sees one 7-day episode.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 5, 6, 7],
            todayDayInCycle: 7
        )
        #expect(result == 7)
    }

    @Test("Belsey unification: {1,2,3,5,6,7} produces ONE cycle in cycleStarts")
    func belseyUnificationCycleStartsSingleEpisode() {
        // Task #156 — the unification regression. Before the rebuild
        // path adopted the shared Belsey impl, the same {1,2,3,5,6,7}
        // input that `mensesEnd` correctly grouped as ONE 7-day episode
        // would (incorrectly) split in the cycle table as two episodes
        // (day-1 episode of length 3 + day-5 episode of length 3),
        // because the rebuild used a different gap threshold.
        //
        // This test pins the unification: feeding civilDay-normalised
        // dates for cycle days 1,2,3,5,6,7 of an arbitrary anchor must
        // produce exactly ONE cycleStart — and that start must match the
        // anchor (day 1), not day 5.
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        // Map cycle days 1,2,3,5,6,7 → absolute Date instants.
        let offsets = [0, 1, 2, 4, 5, 6]
        let bleedingDates = offsets.map { offset in
            cal.date(byAdding: .day, value: offset, to: anchor)!
        }

        let starts = PhaseBoundaries.cycleStarts(
            fromBleedingDays: bleedingDates,
            calendar: cal
        )

        #expect(starts.count == 1,
                "cycleStarts must Belsey-group {1,2,3,5,6,7} into ONE episode")
        #expect(starts.first == anchor,
                "the single cycle must start at day 1 (the first bleed), not day 5")
    }

    @Test("Belsey: Days 1,2,3,6,7,8,9 (2 dry days on days 4-5) → returns 9")
    func belseyAllowsTwoDrySkips() {
        // Belsey allows up to 2 consecutive dry days inside the episode.
        // Two dry days (4, 5) followed by bleeding on day 6 keeps the
        // episode alive — lastBleeding walks all the way to day 9.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 6, 7, 8, 9],
            todayDayInCycle: 9
        )
        #expect(result == 9)
    }

    @Test("Belsey: Days 1,5 (3 dry days on days 2-4) → episode closes at day 1, padded")
    func belseyClosesAtThreeDryDays() {
        // Three consecutive dry days (2, 3, 4) close the episode at the
        // last bleeding day before the gap (day 1). Day-5 bleeding is
        // intermenstrual / a new episode under Belsey — not counted as
        // part of the day-1 episode's end. lastBleeding=1, padded → 5.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 5],
            todayDayInCycle: 6
        )
        #expect(result == 5)
    }

    @Test("Belsey: Days 1,2,6,7,8 (3 dry days on 3-5) → does not resurrect after close")
    func belseyDoesNotResurrectAfterClose() {
        // Once Belsey has closed the episode (dryRun hits 3 at day 5),
        // the walk breaks — subsequent bleeding days (6, 7, 8) do NOT
        // extend `mensesEnd`. The day-1 episode ends at day 2, padded
        // to default → 5. (Day-6 bleeding starts a new episode in the
        // rebuild's cycle-grouping logic, but that's a separate concern
        // from this per-cycle mensesEnd derivation.)
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 6, 7, 8],
            todayDayInCycle: 8
        )
        #expect(result == 5)
    }

    @Test("Belsey: today caps the walk before the episode would close")
    func belseyRespectsTodayCap() {
        // User has logged days 1-3 plus a backfilled day-7 light entry.
        // Today is day 4 — the algorithm cannot see day 7 yet. Walk:
        // 1✓, 2✓, 3✓, 4✗(dryRun=1) — loop ends at today=4 with dryRun=1
        // (< 3), lastBleeding=3. max(3, 5)=5.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 7],
            todayDayInCycle: 4
        )
        #expect(result == 5)
    }

    // MARK: - NEW-171 — Per-user mensesEnd floor

    @Test("NEW-171: personal median 7 raises floor above default 5")
    func personalMedianFloorsAboveDefault() {
        // User typically bleeds 7 days. Today is day 6, days 1-3 logged.
        // Belsey walk → lastBleeding=3. Floor = max(7, 5) = 7. Result = 7.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3],
            todayDayInCycle: 6,
            personalMedianMenses: 7
        )
        #expect(result == 7)
    }

    @Test("NEW-171: personal median 3 does NOT lower below default 5")
    func personalMedianDoesNotLowerBelowDefault() {
        // Edge case: short personal median (suspected under-logging).
        // Floor = max(3, 5) = 5 (default kept; we ratchet up never down).
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3],
            todayDayInCycle: 4,
            personalMedianMenses: 3
        )
        #expect(result == 5)
    }

    @Test("NEW-171: personal median nil → unchanged default behaviour")
    func personalMedianNilFallback() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3],
            todayDayInCycle: 5,
            personalMedianMenses: nil
        )
        #expect(result == 5)
    }

    @Test("NEW-171: observed 8 consecutive days dominates personal median 7")
    func dataDominatesPersonalFloor() {
        // User has 7-d personal median but logged 8 days this cycle.
        // Floor 7 < lastBleeding 8 → returns 8 (data wins).
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 4, 5, 6, 7, 8],
            todayDayInCycle: 8,
            personalMedianMenses: 7
        )
        #expect(result == 8)
    }

    @Test("NEW-171: personal median 6, today day 5, only day 1 logged → 6")
    func personalMedianAppliesEvenWhenLittleLogged() {
        // User typically 6-d periods; today day 5, only day 1 logged.
        // lastBleeding=1, Belsey dryRun=3 by day 4 → break. Floor=max(6, 5)=6.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1],
            todayDayInCycle: 5,
            personalMedianMenses: 6
        )
        #expect(result == 6)
    }

    @Test("NEW-171: floor parameter precedes Belsey walk results")
    func floorAppliesBeforeWalk() {
        // todayDayInCycle = 0 → guard returns floor directly.
        // With personalMedianMenses=7 → returns 7 (not default 5).
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3],
            todayDayInCycle: 0,
            personalMedianMenses: 7
        )
        #expect(result == 7)
    }

    @Test("Days 1, 2 logged but NOT day 0 (which doesn't exist) → counts from 1")
    func startsAtDay1() {
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2],
            todayDayInCycle: 2
        )
        #expect(result == 5)  // max(2, 5)
    }

    @Test("Non-consecutive: only day 5 logged → episode never started → default")
    func nonConsecutiveOnlyDay5() {
        // Days 1-3 dry → dryRun hits 3 → break before day 5 is seen.
        // lastBleeding stays at 0 → the `lastBleeding == 0` guard returns
        // defaultMenses without padding.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [5],
            todayDayInCycle: 6
        )
        #expect(result == 5)  // dryRun >= 3 at day 3 → break, lastBleeding=0
    }

    // MARK: - Today guard

    @Test("Bleeding days past today are ignored")
    func futureBleedingIgnored() {
        // User logged days 1-3 and ALSO a future-dated day 10.
        // Today is day 5. The future entry must not extend consecutive.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 10],
            todayDayInCycle: 5
        )
        // Day 4 is absent → consecutive stops at 3 → max(3, 5) = 5.
        #expect(result == 5)
    }

    @Test("todayDayInCycle = 0 returns default (edge case)")
    func todayZero() {
        // Shouldn't happen in practice (cycle day is 1-indexed), but
        // the function must not crash on a 0.
        let result = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3],
            todayDayInCycle: 0
        )
        #expect(result == 5)  // guard skips loop, lastBleeding=0 → default
    }
}

/// Cross-surface consistency: verify that the same scenario produces the
/// same phase boundaries on both the home view and the calendar surfaces.
/// Both consume `PhaseBoundaries.mensesEnd` + `PhaseBoundaries.from`, so
/// this is now algebraic, not behavioural — but the test pins the
/// invariant.
@Suite("Cross-surface phase consistency")
struct CrossSurfacePhaseConsistencyTests {

    @Test("Day 7 of a 7-day period: phase(7)=menses, phase(8)=follicular")
    func day7Of7DayPeriod() {
        // User logged days 1-7 and is now on day 7 (the last bleeding day).
        // The consecutive walk caps at todayDayInCycle, so it sees all 7
        // bleeding days → mensesEnd=7. This was the user-reported bug:
        // before the fix, day 7 showed as follicular because the calendar
        // hardcoded mensesEnd=5.
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 4, 5, 6, 7],
            todayDayInCycle: 7
        )
        #expect(mensesEnd == 7)
        let bounds = PhaseBoundaries.from(cycleLength: 29, mensesEnd: mensesEnd)
        #expect(bounds.phase(forDay: 6) == .menses)
        #expect(bounds.phase(forDay: 7) == .menses)
        #expect(bounds.phase(forDay: 8) == .follicular)
    }

    @Test("On day 6 with future-logged days 7+: heuristic doesn't peek ahead")
    func heuristicDoesNotPeekAhead() {
        // User has logged days 1-7 in advance (planning her period) but
        // is currently only on day 6. The heuristic caps at today, so
        // consecutive=6 → padded mensesEnd=6 (max with default 5). The
        // calendar may show drops for day 7 but the phase calculation
        // for "today" can only know about days ≤ today.
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 4, 5, 6, 7],
            todayDayInCycle: 6
        )
        #expect(mensesEnd == 6)
    }

    @Test("Day 2 with only day-1 logged: still menses (default padding)")
    func day2WithOnlyDay1() {
        // Regression for the user-reported bug: logging day 1 was making
        // day 2 appear as follicular.
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: [1],
            todayDayInCycle: 2
        )
        let bounds = PhaseBoundaries.from(cycleLength: 29, mensesEnd: mensesEnd)
        #expect(bounds.phase(forDay: 2) == .menses)
        #expect(bounds.phase(forDay: 5) == .menses)
        #expect(bounds.phase(forDay: 6) == .follicular)
    }

    @Test("populationDefault matches the algorithm result for an empty cycle")
    func populationDefaultMatchesAlgorithm() {
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: [],
            todayDayInCycle: 1
        )
        let bounds = PhaseBoundaries.from(
            cycleLength: PhaseBoundaries.defaultCycleLength,
            mensesEnd: mensesEnd
        )
        #expect(bounds.mensesEnd == PhaseBoundaries.populationDefault.mensesEnd)
        #expect(bounds.cycleLength == PhaseBoundaries.populationDefault.cycleLength)
        #expect(bounds.ovulation == PhaseBoundaries.populationDefault.ovulation)
    }

    @Test("Belsey: {1,2,3,5,6,7} produces menses through day 7, follicular at day 8")
    func belseyAlignedPhasePainting() {
        // Cross-surface invariant for #156: a 7-day period with one
        // skipped day in the middle must paint days 1-7 as .menses on
        // the calendar / phase strip, matching the Cycle table's Belsey
        // grouping. Day 8 is the first follicular day.
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: [1, 2, 3, 5, 6, 7],
            todayDayInCycle: 7
        )
        #expect(mensesEnd == 7)
        let bounds = PhaseBoundaries.from(cycleLength: 29, mensesEnd: mensesEnd)
        #expect(bounds.phase(forDay: 4) == .menses)   // the dry day inside the episode
        #expect(bounds.phase(forDay: 7) == .menses)
        #expect(bounds.phase(forDay: 8) == .follicular)
    }
}
