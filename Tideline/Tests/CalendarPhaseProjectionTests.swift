import Testing
import Foundation
@testable import Tideline

/// Regression suite for the calendar's per-day phase projection.
///
/// The original bug — reported by the user on 2026-05-22 — was that the
/// `(days % cycleLen) + 1` arithmetic in `CalendarSheet.recomputePhasesImpl`
/// invented a phantom next-menses *inside* a long, already-closed cycle.
/// User's exact scenario: light bleed logged Feb 12; next real period
/// logged Mar 19 (so the Feb-12 cycle was 35 days long, not the default
/// 29). The calendar then rendered Mar 13–17 as menses-of-a-projected-
/// next-cycle, contradicting the user's logged Mar 19 start.
///
/// `PhaseBoundaries.projectedPhase(for:...)` is the pure function the
/// calendar now delegates to; testing it here pins the behaviour without
/// spinning up SwiftUI.
@Suite("Calendar phase projection — closed vs forward cycles")
struct CalendarPhaseProjectionTests {

    private let cal = Calendar(identifier: .gregorian)

    /// Helper: build a date for (year, month, day) in the test calendar's
    /// timezone. `civilDay()` is applied inside `projectedPhase`, so we
    /// just feed it midday Date values.
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        let comps = DateComponents(
            calendar: cal,
            timeZone: TimeZone.current,
            year: y, month: m, day: d, hour: 12
        )
        return cal.date(from: comps)!
    }

    // MARK: - The user's exact reported scenario

    @Test("Feb 12 cycle is 35 days; Mar 13–18 must NOT be projected menses")
    func feb12ToMar19LongCycleNoPhantomMenses() {
        // civilDay-normalised, matching CalendarSheet.swift:411 which does
        // `cycleStarts.map { $0.civilDay() }` before passing to the helper.
        let starts = [date(2026, 2, 12).civilDay(), date(2026, 3, 19).civilDay()]
        let cycleLen = 29  // population default — no observed cycles yet
        let mensesEnd: [Date: Int] = [
            date(2026, 2, 12).civilDay(): 5,  // 1 light day → padded to 5
            date(2026, 3, 19).civilDay(): 5
        ]

        // Days 30–34 of the Feb 12 cycle (= Mar 13 – Mar 17) used to be
        // shown as menses because `(days % 29) + 1` wrapped to 1–5. With
        // the fix, they should be lutealLate ("still waiting").
        for day in 13...17 {
            let phase = PhaseBoundaries.projectedPhase(
                for: date(2026, 3, day),
                cycleStarts: starts,
                cycleLength: cycleLen,
                mensesEndByCycle: mensesEnd
            )
            #expect(phase == .lutealLate, "Mar \(day) should be lutealLate, got \(phase as Any)")
            #expect(phase != .menses, "Mar \(day) must NOT be menses (was the bug)")
        }
    }

    @Test("Mar 19 cycle starts a real menses band of 5 days")
    func mar19StartsRealMenses() {
        // civilDay-normalised, matching CalendarSheet.swift:411 which does
        // `cycleStarts.map { $0.civilDay() }` before passing to the helper.
        let starts = [date(2026, 2, 12).civilDay(), date(2026, 3, 19).civilDay()]
        let mensesEnd: [Date: Int] = [
            date(2026, 2, 12).civilDay(): 5,
            date(2026, 3, 19).civilDay(): 5
        ]

        for (offset, day) in (19...23).enumerated() {
            let phase = PhaseBoundaries.projectedPhase(
                for: date(2026, 3, day),
                cycleStarts: starts,
                cycleLength: 29,
                mensesEndByCycle: mensesEnd
            )
            #expect(phase == .menses, "Mar \(day) (day \(offset + 1) of Mar 19 cycle) should be menses, got \(phase as Any)")
        }
    }

    // MARK: - Closed-cycle clamping past cycle length

    @Test("Day 100 of a long closed cycle clamps to lutealLate, not wraps")
    func extremelyLongClosedCycleClampsToLuteal() {
        // Feb 12 cycle was 100+ days long (e.g., user paused tracking).
        // Without the fix, days 30, 60, 90 would each be marked as menses.
        let starts = [date(2026, 2, 12).civilDay(), date(2026, 6, 1).civilDay()]
        let mensesEnd: [Date: Int] = [
            date(2026, 2, 12).civilDay(): 5,
            date(2026, 6, 1).civilDay(): 5
        ]

        // Pick a day deep inside the closed cycle (May 15 = day 92 of Feb 12).
        let phase = PhaseBoundaries.projectedPhase(
            for: date(2026, 5, 15),
            cycleStarts: starts,
            cycleLength: 29,
            mensesEndByCycle: mensesEnd
        )
        #expect(phase == .lutealLate)
    }

    // MARK: - Forward projection (still works for the last cycle)

    @Test("Forward projection past the LAST cycle still uses modulo")
    func forwardProjectionUsesModulo() {
        // Single logged cycle starting May 1. Calendar renders June dates
        // forward-projected from May 1 — day 30 = May 30 = day 30 of cycle.
        // Modulo 29 → day 1 of NEXT projected cycle → menses.
        let starts = [date(2026, 5, 1).civilDay()]
        let mensesEnd: [Date: Int] = [date(2026, 5, 1).civilDay(): 5]

        // Day 1 of next projected cycle = May 30 (29 days after May 1).
        let phaseDay30 = PhaseBoundaries.projectedPhase(
            for: date(2026, 5, 30),
            cycleStarts: starts,
            cycleLength: 29,
            mensesEndByCycle: mensesEnd
        )
        #expect(phaseDay30 == .menses, "Forward projection from the last cycle should still wrap")
    }

    // MARK: - Day-1 sanity

    @Test("Day 1 of any logged cycle is menses")
    func day1IsMenses() {
        let starts = [date(2026, 3, 19).civilDay()]
        let mensesEnd: [Date: Int] = [date(2026, 3, 19).civilDay(): 5]
        let phase = PhaseBoundaries.projectedPhase(
            for: date(2026, 3, 19),
            cycleStarts: starts,
            cycleLength: 29,
            mensesEndByCycle: mensesEnd
        )
        #expect(phase == .menses)
    }

    // MARK: - Boundary: days before the first logged cycle

    @Test("Days before any logged cycle return nil")
    func daysBeforeFirstStartReturnNil() {
        let starts = [date(2026, 3, 1).civilDay()]
        let phase = PhaseBoundaries.projectedPhase(
            for: date(2026, 2, 14),
            cycleStarts: starts,
            cycleLength: 29,
            mensesEndByCycle: [:]
        )
        #expect(phase == nil)
    }

    @Test("Empty cycleStarts array returns nil for any day")
    func emptyCycleStartsReturnsNil() {
        let phase = PhaseBoundaries.projectedPhase(
            for: date(2026, 5, 1),
            cycleStarts: [],
            cycleLength: 29,
            mensesEndByCycle: [:]
        )
        #expect(phase == nil)
    }

    @Test("Zero / negative cycleLength is clamped to 1 by the helper")
    func nonPositiveCycleLengthClampedSafely() {
        // The `max(cycleLength, 1)` guard at the top of `projectedPhase`
        // prevents a divide-by-zero in the modulo branch. Verify it
        // doesn't crash — cycleLen=1 means every projected day cycles
        // back to dayInCycle=1 → menses.
        let starts = [date(2026, 5, 1).civilDay()]
        let mensesEnd: [Date: Int] = [date(2026, 5, 1).civilDay(): 5]
        let phase = PhaseBoundaries.projectedPhase(
            for: date(2026, 5, 15),
            cycleStarts: starts,
            cycleLength: 0,
            mensesEndByCycle: mensesEnd
        )
        // (14 % 1) + 1 = 1 → menses; mensesEnd=5 → still menses.
        #expect(phase == .menses)
    }

    // MARK: - Mid-cycle phase mapping inside a closed cycle

    @Test("Mid-cycle days inside a closed cycle still report their real phase")
    func midCycleDaysInsideClosedCycleAreCorrect() {
        // Feb 12 cycle, mensesEnd=5, cycleLen=29 → day 14 = ovulation.
        // Feb 25 = day 14 of Feb 12 cycle. With a later cycle start, the
        // helper should still hand out the right phase for days WITHIN
        // the expected cycle length — only days *past* it clamp to luteal.
        // civilDay-normalised, matching CalendarSheet.swift:411 which does
        // `cycleStarts.map { $0.civilDay() }` before passing to the helper.
        let starts = [date(2026, 2, 12).civilDay(), date(2026, 3, 19).civilDay()]
        let mensesEnd: [Date: Int] = [
            date(2026, 2, 12).civilDay(): 5,
            date(2026, 3, 19).civilDay(): 5
        ]
        // NEW-169: ovulation day = cycleLength − defaultLutealDuration = 29 − 12 = 17.
        // Feb 12 + 16 days = Feb 28 = cycle day 17 → ovulation under the new
        // Bull-2019-aligned default. Previously tested Feb 25 (day 14) under
        // the old folk-rule `−14`; updated here to track the corrected math.
        let phase = PhaseBoundaries.projectedPhase(
            for: date(2026, 2, 28),
            cycleStarts: starts,
            cycleLength: 29,
            mensesEndByCycle: mensesEnd
        )
        #expect(phase == .ovulation, "Feb 28 (day 17, NEW-169 ovulation) should be ovulation, got \(phase as Any)")
    }
}
