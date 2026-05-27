import Testing
import Foundation
@testable import Tideline

/// Unit tests for the Resume-After-Pause sheet eligibility gate (task #74).
/// The gate is a pure function over (PredictorMode, mostRecentBleedingDay,
/// dismissedAt, now), so all branches are exercisable without spinning up
/// SwiftUI or SwiftData.
@Suite("ResumeSheetGate — eligibility rules")
struct ResumeSheetGateTests {

    /// Convenience: build a `.paused` mode whose `since` is `daysAgo` days
    /// before `now`. The archived predictor is the population prior — we
    /// don't read it in the gate.
    private func pausedMode(reason: PauseReason, daysAgoFrom now: Date, days: Double) -> PredictorMode {
        let since = now.addingTimeInterval(-days * 86_400)
        return .paused(archived: .populationPrior, since: since, reason: reason)
    }

    // MARK: - Happy path

    @Test("paused 90d + fresh bleed + no dismiss → show")
    func happyPath() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 90)
        let recentBleed = now.addingTimeInterval(-1 * 86_400)  // bled yesterday
        #expect(ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: recentBleed,
            dismissedAt: nil,
            now: now
        ))
    }

    // MARK: - Rule 1 (mode is .paused)

    @Test(".active mode never triggers")
    func activeModeDoesNotTrigger() {
        let now = Date()
        #expect(!ResumeSheetGate.shouldShow(
            mode: .active(.populationPrior),
            mostRecentBleedingDay: now.addingTimeInterval(-86_400),
            dismissedAt: nil,
            now: now
        ))
    }

    @Test(".retired mode never triggers")
    func retiredModeDoesNotTrigger() {
        let now = Date()
        #expect(!ResumeSheetGate.shouldShow(
            mode: .retired(since: now.addingTimeInterval(-200 * 86_400), reason: .hysterectomy),
            mostRecentBleedingDay: now.addingTimeInterval(-86_400),
            dismissedAt: nil,
            now: now
        ))
    }

    // MARK: - Rule 2 (fresh bleed, post-pause)

    @Test("nil bleeding day → no sheet")
    func nilBleedingNoSheet() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 90)
        #expect(!ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: nil,
            dismissedAt: nil,
            now: now
        ))
    }

    @Test("stale bleed (logged BEFORE the pause started) → no sheet")
    func staleBleedBeforePauseNoSheet() {
        // Reviewer rec #3: a paused user with a bleeding day logged from
        // before the pause must not trigger the sheet. Otherwise a user
        // who had a regular period right before starting hormonal
        // contraception would see this sheet pop on every cooldown
        // rollover for months.
        let now = Date()
        let mode = pausedMode(reason: .hormonalContraception, daysAgoFrom: now, days: 90)
        // Bleed was 100 days ago (= 10 days BEFORE the pause started).
        let staleBleed = now.addingTimeInterval(-100 * 86_400)
        #expect(!ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: staleBleed,
            dismissedAt: nil,
            now: now
        ))
    }

    @Test("bleed exactly equal to pause.since (boundary) → no sheet")
    func bleedAtPauseStartBoundaryNoSheet() {
        // Strictly-after, not at-or-after. A bleed on the same day the
        // pause was declared belongs to the cycle that immediately
        // preceded the pause; it's not a "your period came back" signal.
        let now = Date()
        let pauseStart = now.addingTimeInterval(-90 * 86_400)
        let mode = PredictorMode.paused(
            archived: .populationPrior,
            since: pauseStart,
            reason: .breastfeeding
        )
        #expect(!ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: pauseStart,
            dismissedAt: nil,
            now: now
        ))
    }

    // MARK: - Rule 3 (pause is old enough)

    @Test("pause <60d (postpartum lochia window) → no sheet")
    func shortPauseNoSheet() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 30)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        #expect(!ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: nil,
            now: now
        ))
    }

    @Test("pause exactly at 60d boundary → show")
    func pauseAtBoundary() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 60)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        #expect(ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: nil,
            now: now
        ))
    }

    // MARK: - Rule 4 (dismiss cooldown)

    @Test("dismissed yesterday → no sheet (within 7d cooldown)")
    func recentDismissBlocks() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 90)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        let dismissedAt = now.addingTimeInterval(-1 * 86_400)
        #expect(!ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: dismissedAt,
            now: now
        ))
    }

    @Test("dismissed 10d ago + fresh bleed → show again")
    func staleDismissAllowsRetrigger() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 90)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        let dismissedAt = now.addingTimeInterval(-10 * 86_400)
        #expect(ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: dismissedAt,
            now: now
        ))
    }

    @Test("dismissed exactly at 7d boundary → show")
    func dismissAtBoundary() {
        let now = Date()
        let mode = pausedMode(reason: .breastfeeding, daysAgoFrom: now, days: 90)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        let dismissedAt = now.addingTimeInterval(-7 * 86_400)
        #expect(ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: dismissedAt,
            now: now
        ))
    }

    // MARK: - Interaction (rules 3 + 4 together)

    @Test("custom thresholds: short pause + short cooldown — both apply")
    func customThresholdsBothApply() {
        // Use 7-day pause threshold and 1-day cooldown — verify both
        // boundaries are checked, not just one.
        let now = Date()
        let mode = pausedMode(reason: .userInitiated, daysAgoFrom: now, days: 8)
        let bleed = now.addingTimeInterval(-1 * 3600)
        // Dismissed 12 hours ago → still within 1-day cooldown → no sheet.
        let dismissed = now.addingTimeInterval(-12 * 3600)
        #expect(!ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: dismissed,
            now: now,
            minPauseDuration: 7 * 86_400,
            dismissCooldown: 1 * 86_400
        ))
    }

    // MARK: - All pause reasons trigger uniformly

    @Test("hormonal contraception pause triggers identically")
    func hbcPauseTriggers() {
        let now = Date()
        let mode = pausedMode(reason: .hormonalContraception, daysAgoFrom: now, days: 90)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        #expect(ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: nil,
            now: now
        ))
    }

    @Test("hypothalamic amenorrhea pause triggers identically")
    func haPauseTriggers() {
        let now = Date()
        let mode = pausedMode(reason: .hypothalamicAmenorrhea, daysAgoFrom: now, days: 90)
        let bleed = now.addingTimeInterval(-1 * 86_400)
        #expect(ResumeSheetGate.shouldShow(
            mode: mode,
            mostRecentBleedingDay: bleed,
            dismissedAt: nil,
            now: now
        ))
    }

    // MARK: - Genitive label helper

    @Test("pauseReasonGenitive produces conjugated German")
    func genitiveLabels() {
        #expect(ResumeAfterPauseSheet.pauseReasonGenitive(.breastfeeding) == "der Stillzeit")
        #expect(ResumeAfterPauseSheet.pauseReasonGenitive(.hormonalContraception) == "der hormonellen Verhütung")
        #expect(ResumeAfterPauseSheet.pauseReasonGenitive(.hypothalamicAmenorrhea) == "der hypothalamischen Amenorrhoe")
        #expect(ResumeAfterPauseSheet.pauseReasonGenitive(.userInitiated) == "deiner Pause")
    }
}
