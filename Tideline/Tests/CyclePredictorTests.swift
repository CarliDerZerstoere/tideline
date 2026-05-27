import Testing
import Foundation
@testable import Tideline

@Suite("CyclePredictor — math")
struct CyclePredictorTests {

    @Test("populationPrior point estimate equals μ₀")
    func priorEstimate() {
        let p = CyclePredictor.populationPrior
        #expect(p.nextCycleLengthEstimate == 28.7)
    }

    @Test("worked example: observe [28, 30, 27] from prior")
    func workedExample() {
        var p = CyclePredictor.populationPrior  // μ₀=28.7, κ₀=2 (AWHS, task #94)
        p.observe(cycleLengths: [28, 30, 27])
        // κ: 2 → 3 → 4 → 5
        #expect(p.kappa == 5.0)
        // μ': (2·28.7 + 28)/3 = 28.467
        //   → (3·28.467 + 30)/4 = 28.85
        //   → (4·28.85 + 27)/5 = 28.48
        #expect(abs(p.mu - 28.48) < 0.01)
        #expect(p.observedCount == 3)
        // α: 3 → 4.5
        #expect(p.alpha == 4.5)
    }

    @Test("posterior μ converges to true mean with N=200")
    func convergence() {
        var p = CyclePredictor.populationPrior
        let truth = 27.5
        var rng = SeededRNG(seed: 42)
        for _ in 0..<200 {
            let x = truth + rng.nextGaussian() * 3.0
            p.observe(cycleLength: x)
        }
        #expect(abs(p.mu - truth) < 0.5)
    }

    @Test("predictive scale shrinks as data accumulates")
    func scaleShrinks() {
        var p = CyclePredictor.populationPrior
        let s0 = p.predictiveScale
        for _ in 0..<50 { p.observe(cycleLength: 29.0) }
        let s1 = p.predictiveScale
        #expect(s1 < s0)
    }

    @Test("90% interval contains μ")
    func intervalContainsMean() {
        let p = CyclePredictor.populationPrior
        let ci = p.nextCycleLengthInterval(confidence: 0.90)
        #expect(ci.contains(p.mu))
    }

    @Test("conditional interval's lower bound moves rightward as currentDay grows")
    func conditionalShiftsRight() {
        var p = CyclePredictor.populationPrior
        p.observe(cycleLengths: [28, 30, 29, 28, 30])
        let early = p.conditionalInterval(currentDay: p.mu + 2, confidence: 0.90)
        let late = p.conditionalInterval(currentDay: p.mu + 10, confidence: 0.90)
        // The model correctly says "the period is not before now" as the cycle
        // gets later — the lower bound tracks D upward.
        #expect(late.lowerBound > early.lowerBound)
        #expect(late.lowerBound >= p.mu + 10 - 0.01)
    }

    @Test("conditional interval lower bound ≥ currentDay")
    func conditionalLowerBound() {
        let p = CyclePredictor.populationPrior
        let D = p.mu + 3
        let ci = p.conditionalInterval(currentDay: D, confidence: 0.90)
        #expect(ci.lowerBound >= D - 0.01)
    }

    @Test("softReset preserves μ, resets κ/α/β")
    func softResetPreservesMu() {
        var p = CyclePredictor.populationPrior
        p.observe(cycleLengths: [28, 30, 27, 29, 30])
        let muBefore = p.mu
        p.softReset()
        #expect(p.mu == muBefore)
        #expect(p.kappa == 2.0)
        #expect(p.alpha == 3.0)
        #expect(p.observedCount == 0)
    }

    @Test("declareOngoingIrregularity widens β")
    func widenBeta() {
        var p = CyclePredictor.populationPrior
        let b0 = p.beta
        p.declareOngoingIrregularity()
        #expect(p.beta > b0)
        #expect(abs(p.beta - 2.5 * b0) < 1e-9)
    }

    @Test("predictive CDF is monotonic and in [0,1]")
    func cdfMonotonic() {
        let p = CyclePredictor.populationPrior
        var last = -1.0
        for d in stride(from: 10.0, to: 60.0, by: 2.0) {
            let f = p.predictiveCDF(cycleLength: d)
            #expect(f >= 0 && f <= 1)
            #expect(f >= last)
            last = f
        }
    }

    @Test("predictive CDF at μ ≈ 0.5")
    func cdfAtMean() {
        let p = CyclePredictor.populationPrior
        let f = p.predictiveCDF(cycleLength: p.mu)
        #expect(abs(f - 0.5) < 1e-6)
    }
}

// Deterministic RNG for reproducible tests.
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUniform() -> Double {
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }

    /// Box-Muller standard normal sample.
    mutating func nextGaussian() -> Double {
        let u1 = max(nextUniform(), 1e-12)
        let u2 = nextUniform()
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}
