import Foundation

/// Pure helpers for the calendar range-select feature (task #79). All
/// math here is civilDay-anchored — the UI hands in raw `Date` anchors
/// (taps), this module normalises, sorts, clamps to the 31-day cap, and
/// returns the contiguous list of civilDays to write.
enum CalendarRangeSelection {

    /// Hard cap on a single bulk-write. Year-wide ranges would silently
    /// rewrite cycle math; a month-and-a-bit is the right cognitive
    /// granularity for "I forgot to log my period last month."
    static let maxRangeDays: Int = 31

    /// Given the user's first and second tap dates, return the
    /// chronologically-sorted contiguous civilDay list for the range,
    /// inclusive on both ends. Clamps the range to `maxRangeDays`
    /// preserving the *first* anchor as the fixed point (the user's
    /// intent is "start here, extend to there" — clamp the runaway end).
    static func materialise(
        firstAnchor: Date,
        secondAnchor: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let a = firstAnchor.civilDay()
        let b = secondAnchor.civilDay()
        let lo = min(a, b)
        let hi = max(a, b)
        let totalDays = calendar.dateComponents([.day], from: lo, to: hi).day ?? 0
        let count = totalDays + 1  // inclusive
        if count <= maxRangeDays {
            return enumerate(from: lo, count: count, calendar: calendar)
        }

        // Range exceeds cap. Preserve the FIRST anchor as fixed; clamp
        // the second toward it. If `firstAnchor` is the earlier of the
        // two, the clamp extends forward `maxRangeDays` from `firstAnchor`;
        // if it's the later, the clamp extends backward.
        let firstIsEarlier = firstAnchor.civilDay() == lo
        if firstIsEarlier {
            return enumerate(from: lo, count: maxRangeDays, calendar: calendar)
        } else {
            let newLo = calendar.date(byAdding: .day, value: -(maxRangeDays - 1), to: hi) ?? hi
            return enumerate(from: newLo, count: maxRangeDays, calendar: calendar)
        }
    }

    /// True if the requested range exceeds the cap. UI uses this to show
    /// the "max. 31 Tage" inline message after the second tap.
    static func exceedsCap(
        firstAnchor: Date,
        secondAnchor: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let lo = min(firstAnchor.civilDay(), secondAnchor.civilDay())
        let hi = max(firstAnchor.civilDay(), secondAnchor.civilDay())
        let total = calendar.dateComponents([.day], from: lo, to: hi).day ?? 0
        return (total + 1) > maxRangeDays
    }

    private static func enumerate(
        from start: Date,
        count: Int,
        calendar: Calendar
    ) -> [Date] {
        guard count > 0 else { return [] }
        var out: [Date] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            if let d = calendar.date(byAdding: .day, value: i, to: start) {
                out.append(d)
            }
        }
        return out
    }
}
