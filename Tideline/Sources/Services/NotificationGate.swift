import Foundation

/// Categories of notifications Tideline may schedule. Each one has
/// independent eligibility rules — e.g. cycle-prediction notifications
/// must be suppressed for 28 days after a logged pregnancy loss
/// (#122), but the loss-aware suppression doesn't apply to App-Lock-
/// related notifications (if those ever ship).
public enum NotificationCategory: String, Sendable, Equatable {
    /// Quiet check-in when the user's cycle has gone past the expected
    /// window. Pillar 4 — "silence is valid, but never the *only*
    /// response". Subject to loss-aware suppression.
    case latePeriodCheckIn

    /// Population-framed pregnancy-test reminder at the 10–14 days
    /// late window. Subject to loss-aware suppression.
    case pregnancyTestMilestone

    /// Catch-all for non-cycle notifications (currently unused).
    /// Not subject to loss-aware suppression.
    case general
}

/// Pure decision function: given the current app state, may a
/// notification of this category be delivered?
///
/// Lives outside `NotificationService` so the load-bearing decisions
/// can be unit-tested without UNUserNotificationCenter.
///
/// Callers are responsible for fetching the inputs:
///   - `masterEnabled`: read `@AppStorage("notificationsMasterEnabled")`
///   - `hasRecentLoss`: `await store.hasRecentPregnancyLoss(within: 28*86_400)`
public enum NotificationGate {

    public static func shouldDeliver(
        category: NotificationCategory,
        masterEnabled: Bool,
        hasRecentLoss: Bool = false
    ) -> Bool {
        guard masterEnabled else { return false }
        switch category {
        case .latePeriodCheckIn, .pregnancyTestMilestone:
            // CLAUDE.md hard rule (task #122) — cycle-prediction
            // notifications MUST NOT fire within 28 days of a logged
            // pregnancy loss. Pillar 4: silence is valid; an upbeat
            // "your period is due!" ping after a miscarriage compounds
            // grief with mistimed reminders.
            return !hasRecentLoss
        case .general:
            // Not subject to loss-aware suppression. Reserved for
            // non-cycle notifications (e.g. future app-lock alerts).
            // If a future caller uses `.general` for cycle content,
            // re-classify it here.
            return true
        }
    }
}
