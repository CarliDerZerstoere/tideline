import Foundation

/// Timezone-stable day normalisation.
///
/// **The bug this fixes (audit #117):** `Calendar.current.startOfDay(for:)`
/// returns different absolute `Date` values for the same calendar day in
/// different timezones (and across DST transitions in a single timezone).
/// A user who logged "May 21" in Munich (CEST → stored as `May 20 22:00 UTC`)
/// became invisible after travelling to NYC, because the same calendar
/// query there resolves to `May 21 04:00 UTC` — a six-hour delta against
/// SwiftData's exact-match `#Predicate { $0.date == dayStart }`.
///
/// **Solution:** extract the (year, month, day) components in the user's
/// current `Calendar`, then reconstruct as **UTC midnight** of those
/// components. Properties of the resulting `Date`:
///
///   - Stable across DST transitions (no clock-shift effect on the encoded
///     key).
///   - Stable across timezone changes for the typical case where the user
///     re-views an entry on the same calendar day she logged it.
///   - Compatible with the existing SwiftData `Date` schema — no migration
///     needed beyond a one-off re-key of pre-fix data (dev-only at this
///     pre-release stage).
///
/// **Known limitation:** if a user logs at e.g. 02:00 Tokyo, then travels
/// to a timezone where the same absolute instant falls on the previous
/// calendar day, the entry still maps to the day the user *thought* she
/// was logging (May 21 in Tokyo) — which is the desired semantic.
extension Date {
    /// Returns a `Date` representing the calendar-day identity of `self`,
    /// frozen as UTC midnight of the (year, month, day) extracted in the
    /// supplied `calendar`. Use this everywhere a `dayStart` value is
    /// stored or used as a predicate key.
    func civilDay(in calendar: Calendar = .current) -> Date {
        // If this date is already at UTC midnight, it is already a normalized civilDay key.
        // Re-extracting it in a local calendar would shift the day by -1 or +1 day depending
        // on the timezone offset relative to UTC, which breaks database retrieval.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let utcComps = utcCal.dateComponents([.hour, .minute, .second, .nanosecond], from: self)
        if utcComps.hour == 0 && utcComps.minute == 0 && utcComps.second == 0 && (utcComps.nanosecond ?? 0) == 0 {
            return self
        }

        let components = calendar.dateComponents([.year, .month, .day], from: self)
        return utcCal.date(from: components) ?? self
    }

    /// Adds a fractional number of days to `self` using calendar arithmetic
    /// for the integer-day component, so DST transitions inside the
    /// horizon don't bleed into the predicted calendar day.
    ///
    /// **Why this exists (task #99):** `addingTimeInterval(N * 86_400)`
    /// silently produces the wrong calendar day when the prediction window
    /// crosses a DST boundary — by one hour, but enough to flip the
    /// surface day at moments close to midnight. Especially visible in
    /// cycle-length predictions and credible-interval endpoints, where the
    /// user sees the wall-clock date.
    ///
    /// Algorithm: split `days` into `intDays + frac`; use `Calendar`'s
    /// `byAdding: .day` for the integer part (correctly absorbs the
    /// 23h or 25h DST day), then a plain `addingTimeInterval` for the
    /// sub-day remainder where no DST flip can occur within the window.
    func addingDays(_ days: Double, in calendar: Calendar = .current) -> Date {
        let intDays = Int(days.rounded(.towardZero))
        let frac = days - Double(intDays)
        guard let dayShifted = calendar.date(byAdding: .day, value: intDays, to: self) else {
            return self.addingTimeInterval(days * 86_400)
        }
        return dayShifted.addingTimeInterval(frac * 86_400)
    }

    /// Number of calendar days from `self` to `other`, using the supplied
    /// `calendar`. Stable across DST. Returns 0 if either date is invalid
    /// for the calendar.
    func daysUntil(_ other: Date, in calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: self, to: other).day ?? 0
    }
}
