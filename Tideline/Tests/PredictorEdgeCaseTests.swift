import Testing
import Foundation
@testable import Tideline

/// Edge-case behaviour tests for `CyclePredictor` and related math
/// surfaces. The peer-reviewed validation against Fehring + mcPHASES
/// covers normal-population accuracy; this suite pins the OTHER behaviours
/// we rely on: soft reset, conditional interval widening, posterior μ vs
/// arithmetic mean divergence, and the boundary cases of the Bayesian
/// update.
@Suite("CyclePredictor — edge cases beyond standard validation")
struct PredictorEdgeCaseTests {

    // MARK: - Soft reset

    @Test("softReset preserves μ but resets κ, α, β to population values")
    func softResetParameters() {
        var p = CyclePredictor.populationPrior
        // Observe some cycles to move the posterior away from the prior.
        p.observe(cycleLength: 31)
        p.observe(cycleLength: 32)
        p.observe(cycleLength: 33)
        let muBefore = p.mu
        #expect(muBefore != PhaseBoundaries.populationDefault.cycleLength.toDouble)
        #expect(p.kappa > 2.0)
        #expect(p.alpha > 3.0)

        p.softReset()

        // μ preserved, but κ, α, β back to fresh prior values.
        #expect(p.mu == muBefore)
        #expect(p.kappa == 2.0)
        #expect(p.alpha == 3.0)
        // Task #158 — was 41.07 (β=α·σ² wrong formula); corrected to
        // (α−1)·σ² with σ=3.79 → β = 2·14.3641 = 28.7282.
        // Task #162 — no-arg softReset() defaults to .unspecified band
        // (σ=5.0, β=50.0). The test below covers explicit band routing.
        #expect(abs(p.beta - 50.0) < 1e-9)
        // observedCount also resets — predictor treats subsequent
        // observations as fresh data for the variance estimate.
        #expect(p.observedCount == 0)
    }

    @Test("softReset widens the predictive interval substantially")
    func softResetWidensInterval() {
        var p = CyclePredictor.populationPrior
        // Tight posterior from many similar observations.
        for _ in 0..<10 { p.observe(cycleLength: 29.0) }
        let intervalBefore = p.nextCycleLengthInterval(confidence: 0.90)
        let widthBefore = intervalBefore.upperBound - intervalBefore.lowerBound

        p.softReset()
        let intervalAfter = p.nextCycleLengthInterval(confidence: 0.90)
        let widthAfter = intervalAfter.upperBound - intervalAfter.lowerBound

        // The CI width must grow after a soft reset — the user lost the
        // tight confidence she'd built up.
        #expect(widthAfter > widthBefore * 1.5)
    }

    // MARK: - Posterior μ vs arithmetic mean (bug #100)

    @Test("Posterior μ ≠ arithmetic mean for small N (the bug)")
    func posteriorVsArithmeticMeanDiverge() {
        var p = CyclePredictor.populationPrior  // μ₀ = 28.7, κ₀ = 2 (AWHS, task #94)
        p.observe(cycleLength: 35)

        // Posterior μ = (κ₀·μ₀ + N·x̄) / (κ₀ + N) = (2·28.7 + 1·35) / 3 = 30.8
        // Arithmetic mean of past = 35
        // Divergence ≈ 4.2 days — clinically meaningful for a UI.
        let posteriorMu = p.mu
        let arithmeticMean = 35.0
        #expect(abs(posteriorMu - 30.8) < 0.01)
        #expect(abs(posteriorMu - arithmeticMean) > 3.5)
    }

    @Test("After 10 cycles at 35, posterior μ stays well below 35 due to prior weight")
    func posteriorShrinkagePersists() {
        var p = CyclePredictor.populationPrior  // μ₀ = 28.7, κ₀ = 2
        for _ in 0..<10 { p.observe(cycleLength: 35.0) }

        // Formula: μ_N = (κ₀·μ₀ + N·x̄) / (κ₀+N) = (2·28.7 + 10·35) / 12 = 33.95
        // The κ₀ = 2 prior weight ensures μ never fully reaches 35.
        #expect(abs(p.mu - 33.95) < 0.01)
        #expect(p.mu < 35.0)  // shrinkage toward prior
    }

    // MARK: - Conditional interval (overdue scenarios)

    @Test("conditionalInterval respects lowerBound ≥ currentDay across overdue range")
    func conditionalIntervalLowerBoundCorrect() {
        var p = CyclePredictor.populationPrior
        for _ in 0..<5 { p.observe(cycleLength: 29.0) }

        // The conditional CDF truncates at currentDay: the lower bound of
        // the 90% interval must never claim the period would happen in
        // the past. Note: the interval does NOT monotonically widen with
        // currentDay — once we condition past the mean, the remaining
        // probability mass concentrates in the tail and the interval can
        // narrow. That's mathematically correct truncation behaviour.
        //
        // Sweep extended through D=80 (audit task #108): the original
        // truncation bug only manifested at D ≥ μ+30 (≈59 here). Below
        // that, the legacy code happened to produce reasonable results
        // by accident. Now the loop covers the pathological regime too.
        for d in stride(from: 25.0, through: 80.0, by: 5.0) {
            let interval = p.conditionalInterval(currentDay: d, confidence: 0.90)
            #expect(interval.lowerBound >= d, "lower bound \(interval.lowerBound) must be ≥ currentDay \(d)")
            #expect(interval.upperBound > interval.lowerBound)
        }
    }

    @Test("Highly-late period (D ≥ μ+30) produces a non-truncated interval")
    func highlyLatePeriodDoesNotTruncate() {
        // Regression test for audit #108. Before the fix, at D = 60-80
        // the marginal predictiveCDF(hi) was already ≈ 1.0, causing the
        // expansion loop to exit immediately and the bisection to return
        // an interval of width ~1 day at the upper bound. Now the loop
        // expands until the CONDITIONAL CDF crosses the target.
        var p = CyclePredictor.populationPrior
        p.observe(cycleLengths: [28.0, 29.0, 30.0, 28.0])

        // D = μ+45 ≈ 74 days: deeply into the previous regime's pathological zone.
        let interval = p.conditionalInterval(currentDay: 74.0, confidence: 0.90)

        // The upper bound must be meaningfully greater than D+1 (the
        // buggy truncation result). A width below 2 days at D=74 would
        // indicate the bug has regressed.
        #expect(interval.upperBound > interval.lowerBound + 2.0,
                "interval width \(interval.upperBound - interval.lowerBound) suggests truncation regression")
        // And the absolute upper bound shouldn't claim the period is
        // overdue by 6 months either (sanity ceiling).
        #expect(interval.upperBound < 74.0 + 90.0)
    }

    @Test("Degeneracy guard: D so late that F(D) ≈ 1 returns a meaningful 30-day fallback")
    func degeneracyGuardOnExtremeOverdue() {
        // When the marginal CDF saturates against float precision, the
        // conditional distribution loses resolution. The fallback gives
        // lower=D (could be now) and upper=D+30 (could be ~month out),
        // which is honest: "we genuinely don't know inside [D, D+30]".
        var p = CyclePredictor.populationPrior
        p.observe(cycleLengths: [28.0, 29.0, 28.0, 29.0, 28.0])

        // D = 200 days: F(D) is essentially indistinguishable from 1.0.
        let interval = p.conditionalInterval(currentDay: 200.0, confidence: 0.90)
        #expect(interval.lowerBound >= 200.0)
        #expect(interval.upperBound.isFinite)
        // Fallback range width = 30 days (D to D+30).
        let width = interval.upperBound - interval.lowerBound
        #expect(width > 0)
        #expect(width <= 30.001)
    }

    @Test("conditionalInterval lower bound is never less than currentDay")
    func conditionalIntervalShiftsFuture() {
        var p = CyclePredictor.populationPrior
        for _ in 0..<5 { p.observe(cycleLength: 29.0) }

        // Even when overdue past the expected length, the prediction
        // cannot say "it'll happen in the past" — the lower bound must
        // be ≥ currentDay (the truncation respects observed history).
        let d = 35.0
        let interval = p.conditionalInterval(currentDay: d, confidence: 0.90)
        #expect(interval.lowerBound >= d)
    }

    // MARK: - PCOS widening

    @Test("declareOngoingIrregularity multiplies β by 2.5")
    func pcosWidensBeta() {
        var p = CyclePredictor.populationPrior
        let betaBefore = p.beta
        p.declareOngoingIrregularity()
        #expect(abs(p.beta - betaBefore * 2.5) < 0.001)
    }

    @Test("After irregularity declaration, predictive interval widens")
    func pcosWidensInterval() {
        var p = CyclePredictor.populationPrior
        for _ in 0..<5 { p.observe(cycleLength: 29.0) }
        let intervalBefore = p.nextCycleLengthInterval(confidence: 0.90)
        let widthBefore = intervalBefore.upperBound - intervalBefore.lowerBound

        p.declareOngoingIrregularity()
        let intervalAfter = p.nextCycleLengthInterval(confidence: 0.90)
        let widthAfter = intervalAfter.upperBound - intervalAfter.lowerBound

        #expect(widthAfter > widthBefore)
    }

    // MARK: - Boundary cases

    @Test("observe accepts a single observation without breaking")
    func singleObservationStable() {
        var p = CyclePredictor.populationPrior
        p.observe(cycleLength: 28.0)
        #expect(p.observedCount == 1)
        #expect(p.mu.isFinite)
        #expect(p.beta > 0)
        #expect(p.alpha > 0)
    }

    @Test("Posterior μ converges to sample mean over many observations")
    func convergenceToSampleMean() {
        var p = CyclePredictor.populationPrior
        // 100 observations at 30 days — prior weight κ₀=2 becomes
        // negligible compared to data weight N=100.
        for _ in 0..<100 { p.observe(cycleLength: 30.0) }

        // Posterior μ = (2·29 + 100·30) / 102 = 29.98 → essentially 30.
        #expect(abs(p.mu - 30.0) < 0.05)
    }
}

private extension Int {
    var toDouble: Double { Double(self) }
}
