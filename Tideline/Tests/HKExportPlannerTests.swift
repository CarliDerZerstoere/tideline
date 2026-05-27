import Testing
import Foundation
@testable import Tideline

/// Unit tests for `HKExportPlanner` (task #91). Pure function — every
/// branch exercisable without HealthKit or SwiftData.
@Suite("HKExportPlanner — grouping + HK conflict detection")
struct HKExportPlannerTests {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(
            timeZone: TimeZone.current,
            year: y, month: m, day: d, hour: 12
        ))!
    }

    private func entry(_ y: Int, _ m: Int, _ d: Int, _ flow: FlowLevel = .light)
        -> (date: Date, flow: FlowLevel)
    {
        (date: date(y, m, d), flow: flow)
    }

    // MARK: - Trivial inputs

    @Test("Empty input → empty plan")
    func emptyInput() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: [],
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.isEmpty)
        #expect(plan.totalWritableDays == 0)
    }

    @Test("Single entry → one group with one writable day")
    func singleEntry() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: [entry(2026, 3, 1)],
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].writableDays.count == 1)
        #expect(plan.groups[0].lengthDays == nil)  // most-recent (open) cycle
    }

    // MARK: - Belsey episode rule

    @Test("5 consecutive days → one episode of 5")
    func belseyConsecutiveDays() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: (1...5).map { entry(2026, 3, $0) },
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].writableDays.count == 5)
    }

    @Test("5 days + 1 dry + 2 days = one episode (Belsey ≤2 dry)")
    func belseyOneDryDayMerges() {
        var days = (1...5).map { entry(2026, 3, $0) }
        days.append(contentsOf: [entry(2026, 3, 7), entry(2026, 3, 8)])
        let plan = HKExportPlanner.plan(
            tidelineEntries: days,
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].writableDays.count == 7)
    }

    // MARK: - FIGO cycle rule

    @Test("Two episodes ≥21 days apart → two cycles")
    func figoFloorSplitsCycles() {
        var days = (1...5).map { entry(2026, 3, $0) }
        days.append(contentsOf: (30...30).map { entry(2026, 3, $0) })
        days.append(contentsOf: [entry(2026, 3, 31), entry(2026, 4, 1)])
        let plan = HKExportPlanner.plan(
            tidelineEntries: days,
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 2)
        #expect(plan.groups[0].lengthDays == 29)
        #expect(plan.groups[1].lengthDays == nil)
    }

    // MARK: - HK conflict detection

    @Test("Day already in HK → counted as conflict, not writable")
    func hkConflictDetected() {
        let mar1 = date(2026, 3, 1).civilDay(in: cal)
        let plan = HKExportPlanner.plan(
            tidelineEntries: [entry(2026, 3, 1), entry(2026, 3, 2), entry(2026, 3, 3)],
            existingHKDates: [mar1],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].alreadyInHKCount == 1)
        #expect(plan.groups[0].writableDays.count == 2)
        #expect(plan.groups[0].hasConflicts == true)
        #expect(plan.skippedAlreadyInHK == 1)
    }

    @Test("Every day already in HK → group present but writableDays empty")
    func allDaysAlreadyInHK() {
        let dates = (1...3).map { date(2026, 3, $0).civilDay(in: cal) }
        let plan = HKExportPlanner.plan(
            tidelineEntries: (1...3).map { entry(2026, 3, $0) },
            existingHKDates: Set(dates),
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].writableDays.isEmpty)
        #expect(plan.groups[0].alreadyInHKCount == 3)
        #expect(plan.totalWritableDays == 0)
    }

    // MARK: - Future-dated drop

    @Test("Future-dated entry is dropped + counted")
    func futureDropped() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: [entry(2026, 3, 1), entry(2026, 12, 1)],
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.skippedFutureCount == 1)
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].writableDays.count == 1)
    }

    // MARK: - Flow-level filters

    @Test(".none flow is filtered out before planning")
    func noneFlowFiltered() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: [entry(2026, 3, 1, .none), entry(2026, 3, 2, .light)],
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.totalWritableDays == 1)
        #expect(plan.groups[0].writableDays[0].date == date(2026, 3, 2).civilDay(in: cal))
    }

    @Test(".spotting flow is included (FlowMapping writes it as HK .light)")
    func spottingIncluded() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: [entry(2026, 3, 1, .spotting)],
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.totalWritableDays == 1)
        #expect(plan.groups[0].writableDays[0].flow == .spotting)
    }

    // MARK: - Dedupe

    @Test("Multiple entries on same day → keep heaviest flow")
    func dedupeKeepsHeaviest() {
        let plan = HKExportPlanner.plan(
            tidelineEntries: [
                entry(2026, 3, 1, .light),
                entry(2026, 3, 1, .heavy),
                entry(2026, 3, 1, .medium)
            ],
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.totalWritableDays == 1)
        #expect(plan.groups[0].writableDays[0].flow == .heavy)
    }

    // MARK: - selectedDays(skipping:)

    @Test("isCycleStart true on day-1 of each cycle, false on subsequent days")
    func isCycleStartFlagging() {
        // Two cycles ≥21 days apart, 5 days each. Each cycle's day-1
        // (the cycle start) must be flagged; all other writable days
        // must be flagged false.
        var days = (1...5).map { entry(2026, 3, $0) }
        days.append(contentsOf: [
            entry(2026, 3, 31), entry(2026, 4, 1), entry(2026, 4, 2)
        ])
        let plan = HKExportPlanner.plan(
            tidelineEntries: days,
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 2)
        // Cycle 1: Mar 1 is day-1 → true; Mar 2–5 → false
        for day in plan.groups[0].writableDays {
            let expectedStart = day.date == date(2026, 3, 1).civilDay(in: cal)
            #expect(day.isCycleStart == expectedStart,
                    "\(day.date) isCycleStart should be \(expectedStart)")
        }
        // Cycle 2: Mar 31 is day-1 → true; Apr 1, Apr 2 → false
        for day in plan.groups[1].writableDays {
            let expectedStart = day.date == date(2026, 3, 31).civilDay(in: cal)
            #expect(day.isCycleStart == expectedStart,
                    "\(day.date) isCycleStart should be \(expectedStart)")
        }
    }

    @Test("isCycleStart false on all writable days when day-1 is in HK")
    func isCycleStartFalseWhenDay1Conflicts() {
        // Mar 1 already in HK, Mar 2-5 are writable. None of the
        // writable days should claim isCycleStart=true — we don't
        // re-tag HK's existing day-1.
        let mar1 = date(2026, 3, 1).civilDay(in: cal)
        let plan = HKExportPlanner.plan(
            tidelineEntries: (1...5).map { entry(2026, 3, $0) },
            existingHKDates: [mar1],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        for day in plan.groups[0].writableDays {
            #expect(day.isCycleStart == false,
                    "Writable day \(day.date) must not claim cycle start (day-1 is in HK already)")
        }
    }

    @Test("selectedDays honors user opt-out")
    func selectedDaysHonoursOptOut() {
        var days = (1...3).map { entry(2026, 3, $0) }
        days.append(contentsOf: [
            entry(2026, 3, 31), entry(2026, 4, 1), entry(2026, 4, 2)
        ])
        let plan = HKExportPlanner.plan(
            tidelineEntries: days,
            existingHKDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 2)
        let skipped: Set<UUID> = [plan.groups[0].id]
        let selected = plan.selectedDays(skipping: skipped)
        #expect(selected.count == 3)
    }
}
