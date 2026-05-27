import Testing
import Foundation
@testable import Tideline

/// Tests for `PhaseBoundaries.episodeStarts` + `cycleStarts` — the
/// shared Belsey + FIGO helpers extracted (2026-05-22) from
/// `CycleStore.rebuildCyclesFromDayEntries`, `HKImportPlanner.plan`,
/// and `HKExportPlanner.plan`. Algorithm parity with the previous
/// three inlined implementations is the contract these tests pin.
@Suite("PhaseBoundaries — Belsey + FIGO cycle grouping")
struct PhaseBoundariesCycleGroupingTests {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(
            timeZone: TimeZone.current,
            year: y, month: m, day: d, hour: 0
        ))!
    }

    // MARK: - Trivial inputs

    @Test("Empty bleeding days → empty episodes + empty cycles")
    func emptyInput() {
        #expect(PhaseBoundaries.episodeStarts(from: [], calendar: cal).isEmpty)
        #expect(PhaseBoundaries.cycleStarts(fromBleedingDays: [], calendar: cal).isEmpty)
    }

    @Test("Single day → one episode, one cycle")
    func singleDay() {
        let days = [date(2026, 3, 1)]
        #expect(PhaseBoundaries.episodeStarts(from: days, calendar: cal) == days)
        #expect(PhaseBoundaries.cycleStarts(fromBleedingDays: days, calendar: cal) == days)
    }

    // MARK: - Belsey episode rule

    @Test("Five consecutive days → one episode")
    func fiveConsecutive() {
        let days = (1...5).map { date(2026, 3, $0) }
        #expect(PhaseBoundaries.episodeStarts(from: days, calendar: cal) == [days.first!])
    }

    @Test("2 dry days between → still one episode (Belsey ≤2)")
    func twoDryDaysSameEpisode() {
        // Mar 1, 2, 3 then gap (Mar 4, 5 dry), Mar 6, 7
        // dry days between Mar 3 and Mar 6 = 2 → same episode
        let days = [date(2026, 3, 1), date(2026, 3, 2), date(2026, 3, 3),
                    date(2026, 3, 6), date(2026, 3, 7)]
        let episodes = PhaseBoundaries.episodeStarts(from: days, calendar: cal)
        #expect(episodes == [date(2026, 3, 1)])
    }

    @Test("3 dry days between → new episode (Belsey >=3)")
    func threeDryDaysNewEpisode() {
        // Mar 1, 2, 3 then 3 dry days (Mar 4, 5, 6), Mar 7
        let days = [date(2026, 3, 1), date(2026, 3, 2), date(2026, 3, 3),
                    date(2026, 3, 7)]
        let episodes = PhaseBoundaries.episodeStarts(from: days, calendar: cal)
        #expect(episodes == [date(2026, 3, 1), date(2026, 3, 7)])
    }

    // MARK: - FIGO cycle floor

    @Test("Episodes <21 days apart → same cycle (intermenstrual bleeding)")
    func figoFloorMergesEpisodes() {
        // Two episodes 14 days apart — well below 21d FIGO floor → 1 cycle.
        let episodes = [date(2026, 3, 1), date(2026, 3, 15)]
        let cycles = PhaseBoundaries.cycleStarts(fromEpisodeStarts: episodes, calendar: cal)
        #expect(cycles == [date(2026, 3, 1)])
    }

    @Test("Episodes exactly 21 days apart → new cycle (boundary inclusive)")
    func figoBoundaryInclusive() {
        let episodes = [date(2026, 3, 1), date(2026, 3, 22)]
        let cycles = PhaseBoundaries.cycleStarts(fromEpisodeStarts: episodes, calendar: cal)
        #expect(cycles == [date(2026, 3, 1), date(2026, 3, 22)])
    }

    @Test("Episodes ≥21 days apart → new cycle")
    func figoFloorSplitsCycles() {
        let episodes = [date(2026, 3, 1), date(2026, 3, 30)]  // 29 days apart
        let cycles = PhaseBoundaries.cycleStarts(fromEpisodeStarts: episodes, calendar: cal)
        #expect(cycles == [date(2026, 3, 1), date(2026, 3, 30)])
    }

    // MARK: - Worked end-to-end scenario (from reviewer)

    @Test("Worked scenario: 5d + 3-dry-gap + 2d + 25-dry-gap + 3d → 2 cycles")
    func workedScenarioFromReviewer() {
        // Bleeding days: Mar 1-5 + Mar 9-10 + Apr 4-6.
        // Belsey: Mar 1-5 is one episode; Mar 9 is a new episode
        //         (3-day gap from Mar 5); Apr 4 is a new episode
        //         (24-day gap from Mar 10 → ≥3 dry).
        // FIGO: cycle 1 = Mar 1, cycle 2 = Apr 4 (34 days apart, ≥21).
        //       Mar 9 episode is within 8 days of Mar 1 → same cycle.
        var days: [Date] = (1...5).map { date(2026, 3, $0) }
        days.append(contentsOf: [date(2026, 3, 9), date(2026, 3, 10)])
        days.append(contentsOf: [date(2026, 4, 4), date(2026, 4, 5), date(2026, 4, 6)])

        let cycles = PhaseBoundaries.cycleStarts(fromBleedingDays: days, calendar: cal)
        #expect(cycles == [date(2026, 3, 1), date(2026, 4, 4)])
    }

    // MARK: - DST resilience (with civilDay-normalised inputs)

    @Test("Days spanning a DST transition still group correctly")
    func dstTransitionDoesNotBreakGrouping() {
        // CET → CEST happens Mar 30 2026. Bleeding days that straddle
        // the transition must still produce the same grouping with
        // civilDay-normalised inputs.
        let days = [
            date(2026, 3, 28).civilDay(in: cal),
            date(2026, 3, 29).civilDay(in: cal),
            date(2026, 3, 30).civilDay(in: cal),
            date(2026, 3, 31).civilDay(in: cal)
        ]
        let episodes = PhaseBoundaries.episodeStarts(from: days, calendar: cal)
        #expect(episodes.count == 1, "4 consecutive days across DST should be 1 episode")
    }
}
