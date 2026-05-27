import Testing
import Foundation
@testable import Tideline

/// Unit tests for `HKImportPlanner` (task #71). Pure function — exercises
/// every branch without HealthKit or SwiftData.
@Suite("HKImportPlanner — grouping + conflict detection")
struct HKImportPlannerTests {

    private let cal = Calendar(identifier: .gregorian)

    /// Helper: build a date for (y, m, d) at noon — the planner civilDay's
    /// it internally, so we just feed midday values.
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(
            timeZone: TimeZone.current,
            year: y, month: m, day: d, hour: 12
        ))!
    }

    private func sample(_ y: Int, _ m: Int, _ d: Int, _ flow: FlowLevel = .light) -> FlowSample {
        FlowSample(date: date(y, m, d), flow: flow)
    }

    // MARK: - Empty / trivial inputs

    @Test("Empty samples → empty plan")
    func emptySamples() {
        let plan = HKImportPlanner.plan(
            samples: [],
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.isEmpty)
        #expect(plan.totalSamples == 0)
        #expect(plan.totalImportableDays == 0)
    }

    @Test("Single sample → one group with one day")
    func singleSample() {
        let plan = HKImportPlanner.plan(
            samples: [sample(2026, 3, 1)],
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].importableDays.count == 1)
        #expect(plan.groups[0].lengthDays == nil)  // most-recent cycle has no length
    }

    // MARK: - Belsey episode rule (≤2 dry days = same episode)

    @Test("5 consecutive bleeding days → one group, no episode split")
    func fiveConsecutiveDays() {
        let plan = HKImportPlanner.plan(
            samples: (1...5).map { sample(2026, 3, $0) },
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].importableDays.count == 5)
    }

    @Test("5 days + 1 dry + 2 days = one episode (Belsey ≤2 dry days)")
    func belseyOneDryDayMergedIntoEpisode() {
        // Mar 1-5, gap on Mar 6, Mar 7-8. Belsey: 1 dry day = same episode.
        var days = (1...5).map { sample(2026, 3, $0) }
        days.append(contentsOf: [sample(2026, 3, 7), sample(2026, 3, 8)])
        let plan = HKImportPlanner.plan(
            samples: days,
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)  // one cycle
        #expect(plan.groups[0].importableDays.count == 7)  // 7 bleeding days
    }

    @Test("5 days + 3 dry + 2 days = two episodes, still one cycle (FIGO ≥21 rule)")
    func belseyThreeDryDaysClosesEpisodeButCycleStays() {
        // Mar 1-5, gap Mar 6-8 (3 dry days), Mar 9-10. Belsey: episode
        // closed. But the next episode start (Mar 9) is only 8 days after
        // Mar 1 — far less than FIGO's 21-day floor, so still ONE cycle.
        var days = (1...5).map { sample(2026, 3, $0) }
        days.append(contentsOf: [sample(2026, 3, 9), sample(2026, 3, 10)])
        let plan = HKImportPlanner.plan(
            samples: days,
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        // The intermenstrual bleed (Mar 9-10) is still a bleeding day in
        // this cycle's bucket — we keep the data, the algorithm just
        // declines to declare it a new cycle start.
        #expect(plan.groups[0].importableDays.count == 7)
    }

    // MARK: - FIGO cycle rule (≥21 days = new cycle)

    @Test("Two episodes ≥21 days apart → two cycles")
    func twoCyclesByFigoFloor() {
        // Cycle 1: Mar 1-5. Cycle 2: Mar 30 - Apr 3. Spacing = 29 days.
        var days = (1...5).map { sample(2026, 3, $0) }
        days.append(contentsOf: (30...30).map { sample(2026, 3, $0) })
        days.append(contentsOf: [
            sample(2026, 3, 31), sample(2026, 4, 1), sample(2026, 4, 2), sample(2026, 4, 3)
        ])
        let plan = HKImportPlanner.plan(
            samples: days,
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 2)
        #expect(plan.groups[0].cycleStart == date(2026, 3, 1).civilDay(in: cal))
        #expect(plan.groups[1].cycleStart == date(2026, 3, 30).civilDay(in: cal))
        #expect(plan.groups[0].lengthDays == 29)
        #expect(plan.groups[1].lengthDays == nil)  // latest, length unknown
    }

    @Test("Exactly 21 days spacing → boundary case, counts as new cycle")
    func figoBoundaryIsInclusive() {
        let days = [sample(2026, 3, 1), sample(2026, 3, 22)]
        let plan = HKImportPlanner.plan(
            samples: days,
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 2)
    }

    // MARK: - Conflict detection

    @Test("Existing entry on bleed day → silent skip, marked in conflict count")
    func conflictDetection() {
        let mar1 = date(2026, 3, 1).civilDay(in: cal)
        let plan = HKImportPlanner.plan(
            samples: [sample(2026, 3, 1), sample(2026, 3, 2), sample(2026, 3, 3)],
            existingEntryDates: [mar1],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].conflictingCount == 1)
        #expect(plan.groups[0].importableDays.count == 2)
        #expect(plan.groups[0].hasConflicts == true)
    }

    @Test("Every day conflicts → importableDays empty, group still present")
    func allDaysConflict() {
        let dates = [date(2026, 3, 1), date(2026, 3, 2), date(2026, 3, 3)]
            .map { $0.civilDay(in: cal) }
        let plan = HKImportPlanner.plan(
            samples: dates.enumerated().map { sample(2026, 3, $0.offset + 1) },
            existingEntryDates: Set(dates),
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].importableDays.isEmpty)
        #expect(plan.groups[0].conflictingCount == 3)
    }

    // MARK: - Future-dated samples

    @Test("Future-dated sample is dropped + counted in summary")
    func futureSampleDropped() {
        let plan = HKImportPlanner.plan(
            samples: [
                sample(2026, 3, 1),
                sample(2026, 12, 1)  // future relative to `now`
            ],
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].importableDays.count == 1)
        #expect(plan.skippedFutureCount == 1)
    }

    // MARK: - Dedupe

    @Test("Multiple samples on same day → keep heaviest flow")
    func dedupeKeepsHeaviest() {
        let plan = HKImportPlanner.plan(
            samples: [
                sample(2026, 3, 1, .light),
                sample(2026, 3, 1, .heavy),
                sample(2026, 3, 1, .medium)
            ],
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].importableDays.count == 1)
        #expect(plan.groups[0].importableDays[0].flow == .heavy)
    }

    // MARK: - selectedDays(skipping:)

    @Test("selectedDays excludes user-opted-out groups")
    func selectedDaysHonoursSkipSet() {
        // Two cycles, user opts out of cycle 1.
        var days = (1...3).map { sample(2026, 3, $0) }
        days.append(contentsOf: [
            sample(2026, 3, 31), sample(2026, 4, 1), sample(2026, 4, 2)
        ])
        let plan = HKImportPlanner.plan(
            samples: days,
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        #expect(plan.groups.count == 2)
        let skipped: Set<UUID> = [plan.groups[0].id]
        let selected = plan.selectedDays(skipping: skipped)
        #expect(selected.count == 3)
        #expect(selected.first?.date == date(2026, 3, 31).civilDay(in: cal))
    }

    @Test("selectedDays empty when all groups skipped")
    func selectedDaysAllSkipped() {
        let plan = HKImportPlanner.plan(
            samples: (1...3).map { sample(2026, 3, $0) },
            existingEntryDates: [],
            now: date(2026, 6, 1)
        )
        let skipped = Set(plan.groups.map { $0.id })
        #expect(plan.selectedDays(skipping: skipped).isEmpty)
    }
}
