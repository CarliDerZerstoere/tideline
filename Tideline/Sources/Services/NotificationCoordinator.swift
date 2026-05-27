import Foundation
import UserNotifications

/// Owns the lifecycle of Tideline's scheduled local notifications.
///
/// Bridges three pure pieces that were previously unconnected:
///   - `NotificationGate.shouldDeliver(...)` — pure rule predicate (task #122).
///   - `NotificationService.schedule(...)` — UNUserNotificationCenter wrapper
///     (task #85).
///   - `CycleStore.homeSnapshot(...)` — live cycle/mode state.
///
/// Before this type existed the gate and service both shipped but had ZERO
/// production callers. The audit (`docs/memory/2026-05-24-done-audit.md`)
/// flagged this as the biggest user-visible gap: the CLAUDE.md hard rule
/// "no cycle notifications within 28 days of a logged loss" was vacuously
/// satisfied because nothing scheduled anything at all.
///
/// **Idempotent reschedule**: callers can invoke `reschedule(...)` after
/// every `refresh()` cycle. Each call cancels Tideline's prior pending
/// requests (by stable identifier) and re-schedules from current state.
/// That keeps the scheduled set in sync with the moving prediction without
/// requiring delta logic at the call site.
///
/// **Scheduling policy** (matches `docs/design/late-and-missed-periods.md`):
///   - **Day 3 late** (cycleStart + predictedLen + 3) — quiet check-in.
///     Fires at 10:00 user local time. Suppressed entirely during
///     loss-suppression window.
///   - **Day 10 late** — pregnancy-test population-framed milestone (only
///     when no recent loss; identical gating to the in-app card #73).
///   - Cancelled when: master toggle off, predictor paused/retired, recent
///     loss logged, or new period start observed.
///
/// **Pillar 1**: zero exfiltration. Notification content uses the privacy
/// builder (`makePrivacyContent`) so lockscreen-visible fields never reveal
/// cycle state. The detail routing only resolves when the user opens the
/// app and the secured layer reads `userInfo["category"]`.
@MainActor
final class NotificationCoordinator {

    /// Stable identifiers so a `reschedule()` can deterministically replace
    /// the previously-issued requests. iOS keys pending notifications by
    /// these strings; reusing them is the documented overwrite pattern.
    enum NotificationID {
        static let lateCheckIn = "com.tideline.notif.late-check-in"
        static let pregnancyTest = "com.tideline.notif.pregnancy-test-milestone"

        /// All identifiers Tideline schedules. Used by `cancelAllTideline()`
        /// so a future categories addition only needs to grow this set.
        static let all: [String] = [lateCheckIn, pregnancyTest]
    }

    /// Hour-of-day (local timezone) at which scheduled notifications fire.
    /// 10:00 chosen as a friendly mid-morning timepoint — late enough that
    /// the user is awake, early enough that the prompt isn't competing with
    /// evening fatigue. Matches the same convention Clue/Flo use for
    /// "your period may start today" reminders.
    static let scheduledHourOfDay = 10

    private let service: NotificationService

    init(service: NotificationService = NotificationService()) {
        self.service = service
    }

    /// Cancel + reschedule based on current state. Safe to call repeatedly
    /// from `TidelineHomeView.refresh()` — each invocation produces a
    /// consistent scheduled set for the inputs.
    ///
    /// All time inputs are passed explicitly so the function is testable
    /// without `Date.now` and so the caller can pin a snapshot timestamp
    /// (avoids `now` drift between cancel + schedule).
    func reschedule(
        currentCycleStart: Date?,
        predictedCycleLength: Double,
        masterEnabled: Bool,
        hasRecentLoss: Bool,
        isActive: Bool,
        now: Date = .now
    ) async {
        // Always cancel pending Tideline requests first. This is the
        // "single source of truth" pattern — current state in this call
        // becomes the canonical scheduled set on return.
        await cancelAllTideline()

        // Master gate. If the user disabled notifications, leave the
        // pending set empty.
        guard masterEnabled else { return }

        // Need an active cycle + active predictor. Paused (breastfeeding,
        // contraception, HA) and retired (hysterectomy, oophorectomy) modes
        // explicitly suppress predictions — no notifications either.
        guard isActive, let start = currentCycleStart else { return }

        // Defensive guard against a degenerate posterior (cycleBoundaries
        // derived from empty data could produce a 0-day cycle in pathological
        // states). The future-only `> now` check below would absorb this,
        // but explicit > 0 is clearer about intent and avoids scheduling
        // a notification for "right now" if the posterior collapses.
        guard predictedCycleLength > 0 else { return }

        // Compute trigger dates. The 10:00 local-time anchor lives in
        // `makeTrigger` so both notifications share the convention.
        // `predictedCycleLength` is the posterior μ — its day-axis is
        // calendar arithmetic, so we use `addingDays` (DST-safe, task #99).
        let lateCheckInDate = start.addingDays(predictedCycleLength + 3)
        let pregTestDate = start.addingDays(predictedCycleLength + 10)

        // Late check-in: gated by NotificationGate + future-only.
        if lateCheckInDate > now,
           NotificationGate.shouldDeliver(
            category: .latePeriodCheckIn,
            masterEnabled: masterEnabled,
            hasRecentLoss: hasRecentLoss
           ) {
            let trigger = makeTrigger(at: lateCheckInDate)
            let content = service.makePrivacyContent(category: .latePeriodCheckIn)
            _ = await service.schedule(
                identifier: NotificationID.lateCheckIn,
                content: content,
                trigger: trigger
            )
        }

        // Pregnancy-test milestone: same gate + future-only. Note the gate
        // is checked TWICE: once for late-check-in above and once here.
        // Both are subject to loss-suppression so they evaluate to the
        // same `false` during the 28-day window — but writing it out
        // keeps the categories independent so a future change to one
        // category's rule doesn't accidentally affect the other.
        if pregTestDate > now,
           NotificationGate.shouldDeliver(
            category: .pregnancyTestMilestone,
            masterEnabled: masterEnabled,
            hasRecentLoss: hasRecentLoss
           ) {
            let trigger = makeTrigger(at: pregTestDate)
            let content = service.makePrivacyContent(category: .pregnancyTestMilestone)
            _ = await service.schedule(
                identifier: NotificationID.pregnancyTest,
                content: content,
                trigger: trigger
            )
        }
    }

    /// Cancel every Tideline-owned pending notification. Used on master-
    /// toggle-off, before each reschedule, and on hard state changes
    /// (e.g. event logged that retires the predictor).
    func cancelAllTideline() async {
        for id in NotificationID.all {
            await service.cancel(identifier: id)
        }
    }

    /// Build a calendar trigger anchored to `date`'s civil day at the
    /// configured `scheduledHourOfDay` in the user's current timezone.
    /// `.matchingNextTime` semantics aren't needed here — the trigger
    /// fires once at the absolute moment and then expires.
    private func makeTrigger(at date: Date) -> UNCalendarNotificationTrigger {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        components.hour = Self.scheduledHourOfDay
        components.minute = 0
        return UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
    }
}
