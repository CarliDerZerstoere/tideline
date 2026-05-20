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
}
