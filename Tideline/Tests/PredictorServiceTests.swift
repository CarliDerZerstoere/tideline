import Testing
import Foundation
@testable import Tideline

@Suite("PredictorService — category-to-action routing")
struct PredictorServiceTests {

    @Test("Category A (hysterectomy) retires the predictor")
    func categoryARetires() async {
        let svc = PredictorService()
        await svc.apply(eventKind: .hysterectomy, on: .now)
        #expect(await svc.currentMode().isRetired)
        let applied = await svc.observe(cycleLength: 29)
        #expect(applied == false)
        let pred = await svc.nextPrediction(after: .now)
        #expect(pred == nil)
    }

    @Test("Category B (breastfeeding) pauses and archives the posterior")
    func categoryBPauses() async {
        let svc = PredictorService()
        await svc.observe(cycleLength: 28)
        await svc.observe(cycleLength: 30)
        let muBefore = await svc.currentMode().archivedPredictor?.mu
        await svc.apply(eventKind: .birthBreastfeeding, on: .now)
        let mode = await svc.currentMode()
        #expect(mode.isPaused)
        #expect(mode.archivedPredictor?.mu == muBefore)
        let applied = await svc.observe(cycleLength: 29)
        #expect(applied == false)
    }

    @Test("resume() from paused performs soft-reset, preserves μ")
    func resumeSoftResets() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27, 29, 30])
        let muBefore = await svc.currentMode().archivedPredictor?.mu
        await svc.apply(eventKind: .birthBreastfeeding, on: .now)
        await svc.resume()
        let mode = await svc.currentMode()
        #expect(mode.isActive)
        #expect(mode.archivedPredictor?.mu == muBefore)
        #expect(mode.archivedPredictor?.kappa == 2.0)
        #expect(mode.archivedPredictor?.observedCount == 0)
    }

    @Test("Category F (resumeAfterPause) un-pauses with soft-reset semantics")
    func resumeAfterPauseEventUnPauses() async {
        // Build μ ≈ 28.7 (default with no observations), then add a few
        // observations so we have a non-trivial archived posterior.
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27, 29, 30])
        let muBefore = await svc.currentMode().activePredictor?.mu
        await svc.apply(eventKind: .birthBreastfeeding, on: .now)
        #expect(await svc.currentMode().isPaused)

        // Months later — user starts cycling again.
        await svc.apply(eventKind: .resumeAfterPause, on: .now.addingTimeInterval(180 * 86_400))

        let mode = await svc.currentMode()
        #expect(mode.isActive)
        // μ survives as location hint; κ/α/β reset to defaults.
        #expect(mode.activePredictor?.mu == muBefore)
        #expect(mode.activePredictor?.kappa == 2.0)
        #expect(mode.activePredictor?.alpha == 3.0)
        #expect(mode.activePredictor?.observedCount == 0)
    }

    @Test("Category F is a no-op when applied to active mode")
    func resumeAfterPauseNoOpOnActive() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27, 29, 30])
        let observedBefore = await svc.currentMode().activePredictor?.observedCount

        await svc.apply(eventKind: .resumeAfterPause, on: .now)

        // Still active, posterior untouched.
        let mode = await svc.currentMode()
        #expect(mode.isActive)
        #expect(mode.activePredictor?.observedCount == observedBefore)
    }

    @Test("Category F is a no-op when applied to retired mode")
    func resumeAfterPauseNoOpOnRetired() async {
        let svc = PredictorService()
        await svc.apply(eventKind: .hysterectomy, on: .now)
        #expect(await svc.currentMode().isRetired)
        await svc.apply(eventKind: .resumeAfterPause, on: .now)
        #expect(await svc.currentMode().isRetired)  // still retired
    }

    /// Doctrine pin (disrupted-cycles.md §F): an ongoing-irregularity
    /// declaration (PCOS / perimenopause / other) is a chronic-condition
    /// flag — it does NOT clear when a Category-B pause event archives
    /// the predictor, nor when a `.resumeAfterPause` un-pauses it. PCOS
    /// doesn't vanish during breastfeeding. The user can still toggle
    /// it off via Settings if they want to re-evaluate after recovery.
    /// This test pins the persistence so a future `softReset()` refactor
    /// can't silently start clearing the flag.
    @Test("isOngoingIrregularity persists across pause → resumeAfterPause")
    func irregularityFlagSurvivesPauseResume() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27, 29, 30])
        await svc.apply(eventKind: .pcosDeclared, on: .now)
        #expect(await svc.currentMode().activePredictor?.isOngoingIrregularity == true)

        await svc.apply(eventKind: .birthBreastfeeding, on: .now)
        #expect(await svc.currentMode().isPaused)
        // Flag survives in the archived posterior.
        #expect(await svc.currentMode().archivedPredictor?.isOngoingIrregularity == true)

        await svc.apply(eventKind: .resumeAfterPause, on: .now.addingTimeInterval(180 * 86_400))
        #expect(await svc.currentMode().isActive)
        // Flag survives the soft-reset in resume().
        #expect(await svc.currentMode().activePredictor?.isOngoingIrregularity == true)
    }

    @Test("Category C (miscarriage) soft-resets in place")
    func categoryCSoftReset() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27])
        let muBefore = await svc.currentMode().archivedPredictor?.mu
        await svc.apply(eventKind: .miscarriageEarly, on: .now)
        let mode = await svc.currentMode()
        #expect(mode.isActive)
        #expect(mode.archivedPredictor?.mu == muBefore)
        #expect(mode.archivedPredictor?.kappa == 2.0)
        #expect(mode.archivedPredictor?.observedCount == 0)
    }

    @Test("Category C: a long disrupted cycle after the event does not corrupt μ")
    func categoryCRejectsOutlier() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27, 29, 30])
        let muBefore = await svc.currentMode().archivedPredictor?.mu ?? 0
        await svc.apply(eventKind: .miscarriageEarly, on: .now)
        await svc.observe(cycleLength: 31)
        let muAfter = await svc.currentMode().archivedPredictor?.mu ?? 0
        #expect(abs(muAfter - muBefore) < 2.0)
    }

    @Test("Category E (PCOS) widens β, observe still works")
    func categoryEWidensBeta() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27])
        let bBefore = await svc.currentMode().archivedPredictor?.beta ?? 0
        await svc.apply(eventKind: .pcosDeclared, on: .now)
        let bAfter = await svc.currentMode().archivedPredictor?.beta ?? 0
        #expect(bAfter > bBefore)
        let applied = await svc.observe(cycleLength: 45)
        #expect(applied == true)
    }

    @Test("Category D (single anomaly) does not change posterior")
    func categoryDNoChange() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 30, 27])
        let before = await svc.currentMode().archivedPredictor
        await svc.apply(eventKind: .singleAnomaly, on: .now)
        let after = await svc.currentMode().archivedPredictor
        #expect(before == after)
    }

    @Test("apply after retirement is a no-op")
    func retiredIsTerminal() async {
        let svc = PredictorService()
        await svc.apply(eventKind: .hysterectomy, on: .now)
        await svc.apply(eventKind: .miscarriageEarly, on: .now)
        #expect(await svc.currentMode().isRetired)
    }

    // MARK: - #95 Clinical-plausibility clamp on observe()

    @Test("observe(12) is rejected as clinically implausible")
    func clampRejectsTooShort() async {
        let svc = PredictorService()
        let observedBefore = await svc.currentMode().activePredictor?.observedCount
        let applied = await svc.observe(cycleLength: 12)
        #expect(applied == false)
        #expect(await svc.currentMode().activePredictor?.observedCount == observedBefore)
    }

    @Test("observe(70) is rejected as clinically implausible")
    func clampRejectsTooLong() async {
        let svc = PredictorService()
        let observedBefore = await svc.currentMode().activePredictor?.observedCount
        let applied = await svc.observe(cycleLength: 70)
        #expect(applied == false)
        #expect(await svc.currentMode().activePredictor?.observedCount == observedBefore)
    }

    @Test("observe(21) is accepted (boundary inclusive)")
    func clampAcceptsLowerBoundary() async {
        let svc = PredictorService()
        let applied = await svc.observe(cycleLength: 21)
        #expect(applied == true)
    }

    @Test("observe(45) is accepted (boundary inclusive)")
    func clampAcceptsUpperBoundary() async {
        let svc = PredictorService()
        let applied = await svc.observe(cycleLength: 45)
        #expect(applied == true)
    }

    @Test("clinicallyPlausible static matches the band [21, 45]")
    func clinicallyPlausibleStatic() {
        #expect(PredictorService.clinicallyPlausible(20.999) == false)
        #expect(PredictorService.clinicallyPlausible(21.0) == true)
        #expect(PredictorService.clinicallyPlausible(28.0) == true)
        #expect(PredictorService.clinicallyPlausible(45.0) == true)
        #expect(PredictorService.clinicallyPlausible(45.001) == false)
    }

    // MARK: - #96 Category D single-anomaly outlier rejection

    @Test("singleAnomaly suppresses the very next observe")
    func anomalySuppressesNextObserve() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        let observedBefore = await svc.currentMode().activePredictor?.observedCount

        await svc.apply(eventKind: .singleAnomaly, on: .now)
        let suppressed = await svc.observe(cycleLength: 28)
        #expect(suppressed == false)
        #expect(await svc.currentMode().activePredictor?.observedCount == observedBefore)
    }

    @Test("Observe after the suppressed one applies normally")
    func observeAfterAnomalyApplies() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        await svc.apply(eventKind: .singleAnomaly, on: .now)
        let suppressed = await svc.observe(cycleLength: 28)
        #expect(suppressed == false)

        let applied = await svc.observe(cycleLength: 29)
        #expect(applied == true)
    }

    @Test("Two singleAnomaly events suppress exactly one observe (idempotent flag)")
    func doubleAnomalyIsIdempotent() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        await svc.apply(eventKind: .singleAnomaly, on: .now)
        await svc.apply(eventKind: .singleAnomaly, on: .now)

        // Only the next observe is suppressed; the second is applied.
        let first = await svc.observe(cycleLength: 28)
        let second = await svc.observe(cycleLength: 29)
        #expect(first == false)
        #expect(second == true)
    }

    @Test("Category C event clears the anomaly flag (soft-reset terminates the cycle)")
    func recoverableClearsAnomalyFlag() async {
        // Reviewer B1: a singleAnomaly followed by a Category C event
        // (miscarriage etc.) must NOT silently suppress the first
        // post-recovery cycle. The soft-reset already widens β; the
        // anomaly flag is redundant once the tracking phase restarts.
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        await svc.apply(eventKind: .singleAnomaly, on: .now)
        await svc.apply(eventKind: .miscarriageEarly, on: .now)

        let applied = await svc.observe(cycleLength: 28)
        #expect(applied == true)
    }

    @Test("Pause clears the anomaly flag (cycle terminated)")
    func pauseClearsAnomalyFlag() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        await svc.apply(eventKind: .singleAnomaly, on: .now)
        await svc.apply(eventKind: .birthBreastfeeding, on: .now)
        await svc.apply(eventKind: .resumeAfterPause, on: .now.addingTimeInterval(180 * 86_400))

        // The post-resume observe must apply — pause cleared the flag.
        let applied = await svc.observe(cycleLength: 28)
        #expect(applied == true)
    }

    @Test("Retirement clears the anomaly flag (terminal mode)")
    func retireClearsAnomalyFlag() async {
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        await svc.apply(eventKind: .singleAnomaly, on: .now)
        await svc.apply(eventKind: .hysterectomy, on: .now)
        // Mode is retired so observe is a no-op anyway; the flag state
        // is no longer observable from outside. This test pins the
        // apply-time clearing intent — see PredictorService.swift:50.
        #expect(await svc.currentMode().isRetired)
    }

    /// Task #135 NEW-I — the two new event types route to Category D
    /// (anomaly = outlier-reject only), same machinery as singleAnomaly.
    /// Pin the category mapping so a future "promote to Category C
    /// soft-reset" refactor would visibly require this test to change.
    @Test("mildIllness routes to Category D anomaly + suppresses next observe")
    func mildIllnessSuppressesObservation() async {
        #expect(EventKind.mildIllness.category == .anomaly)
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        let observedBefore = await svc.currentMode().activePredictor?.observedCount
        await svc.apply(eventKind: .mildIllness, on: .now)
        let suppressed = await svc.observe(cycleLength: 31)
        #expect(suppressed == false)
        #expect(await svc.currentMode().activePredictor?.observedCount == observedBefore)
        // Next cycle observes normally.
        let applied = await svc.observe(cycleLength: 28)
        #expect(applied == true)
    }

    @Test("vaccination routes to Category D anomaly + suppresses next observe")
    func vaccinationSuppressesObservation() async {
        #expect(EventKind.vaccination.category == .anomaly)
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        let observedBefore = await svc.currentMode().activePredictor?.observedCount
        await svc.apply(eventKind: .vaccination, on: .now)
        let suppressed = await svc.observe(cycleLength: 30)
        #expect(suppressed == false)
        #expect(await svc.currentMode().activePredictor?.observedCount == observedBefore)
    }

    @Test("Out-of-range observe does not consume the anomaly flag")
    func clampDoesNotConsumeAnomalyFlag() async {
        // The clamp returns false BEFORE the flag check, so a rejected-by-clamp
        // observation must not also burn the anomaly flag. This pins the
        // ordering in PredictorService.observe(cycleLength:).
        let svc = PredictorService()
        await svc.observe(cycleLengths: [28, 29, 30])
        await svc.apply(eventKind: .singleAnomaly, on: .now)

        let rejectedByClamp = await svc.observe(cycleLength: 12)
        #expect(rejectedByClamp == false)

        // Flag should still be armed: the next plausible observe is suppressed.
        let suppressed = await svc.observe(cycleLength: 28)
        #expect(suppressed == false)

        // And the one after that applies normally.
        let applied = await svc.observe(cycleLength: 29)
        #expect(applied == true)
    }
}
