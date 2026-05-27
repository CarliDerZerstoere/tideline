import Testing
import Foundation
@testable import Tideline

/// Tests for the pure range-computation helper used by the
/// CalendarSheet range-select feature (task #79). UI-free —
/// these only exercise the math behind anchor → [Date] expansion.
@Suite("CalendarRangeSelection — anchor pair → civilDay list")
struct CalendarRangeSelectionTests {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(
            timeZone: TimeZone.current,
            year: y, month: m, day: d, hour: 0
        ))!
    }

    @Test("Same-day anchors → single-element list")
    func sameDay() {
        let d = date(2026, 3, 10)
        let out = CalendarRangeSelection.materialise(firstAnchor: d, secondAnchor: d, calendar: cal)
        #expect(out.count == 1)
        #expect(out.first == d.civilDay())
    }

    @Test("Forward range of 5 days → 5 contiguous civilDays")
    func forwardFiveDays() {
        let a = date(2026, 3, 8)
        let b = date(2026, 3, 12)
        let out = CalendarRangeSelection.materialise(firstAnchor: a, secondAnchor: b, calendar: cal)
        #expect(out.count == 5)
        #expect(out.first == date(2026, 3, 8).civilDay())
        #expect(out.last == date(2026, 3, 12).civilDay())
    }

    @Test("Backward selection is normalised forward")
    func backwardSelection() {
        let a = date(2026, 3, 12)
        let b = date(2026, 3, 8)
        let out = CalendarRangeSelection.materialise(firstAnchor: a, secondAnchor: b, calendar: cal)
        #expect(out.count == 5)
        #expect(out.first == date(2026, 3, 8).civilDay())
        #expect(out.last == date(2026, 3, 12).civilDay())
    }

    @Test("31-day cap — forward extension clamps tail")
    func capForwardClampsTail() {
        let a = date(2026, 3, 1)
        let b = date(2026, 5, 1) // ~61 days forward → exceeds cap
        let out = CalendarRangeSelection.materialise(firstAnchor: a, secondAnchor: b, calendar: cal)
        #expect(out.count == CalendarRangeSelection.maxRangeDays)
        // First-anchor preserved as the fixed end.
        #expect(out.first == date(2026, 3, 1).civilDay())
        // Tail is 30 days after the start (max-1 since first day counts).
        let expectedLast = cal.date(byAdding: .day, value: 30, to: date(2026, 3, 1).civilDay())!
        #expect(out.last == expectedLast)
    }

    @Test("31-day cap — backward extension clamps head")
    func capBackwardClampsHead() {
        // First anchor is the LATER date — user tapped May 1 first, then Mar 1.
        // The earlier date (Mar 1) is the runaway end; clamp it forward.
        let a = date(2026, 5, 1)
        let b = date(2026, 3, 1)
        let out = CalendarRangeSelection.materialise(firstAnchor: a, secondAnchor: b, calendar: cal)
        #expect(out.count == CalendarRangeSelection.maxRangeDays)
        // Last day is the first-anchor (May 1).
        #expect(out.last == date(2026, 5, 1).civilDay())
        // Head was clamped backward to May 1 - 30 days.
        let expectedFirst = cal.date(byAdding: .day, value: -30, to: date(2026, 5, 1).civilDay())!
        #expect(out.first == expectedFirst)
    }

    @Test("exceedsCap is true above 31 days, false at boundary")
    func exceedsCapBoundary() {
        // Exactly 31 days inclusive → not exceeding.
        let a = date(2026, 3, 1)
        let bAtCap = cal.date(byAdding: .day, value: 30, to: a)!  // 31 inclusive
        #expect(CalendarRangeSelection.exceedsCap(firstAnchor: a, secondAnchor: bAtCap, calendar: cal) == false)

        let bOver = cal.date(byAdding: .day, value: 31, to: a)!  // 32 inclusive
        #expect(CalendarRangeSelection.exceedsCap(firstAnchor: a, secondAnchor: bOver, calendar: cal) == true)
    }

    @Test("DST transition inside range — civilDay normalisation keeps the count correct")
    func dstResilience() {
        // CET → CEST 2026-03-29 in central Europe. A range straddling
        // the boundary must still count exactly N days.
        let a = date(2026, 3, 28)
        let b = date(2026, 3, 31)
        let out = CalendarRangeSelection.materialise(firstAnchor: a, secondAnchor: b, calendar: cal)
        #expect(out.count == 4)
    }
}
