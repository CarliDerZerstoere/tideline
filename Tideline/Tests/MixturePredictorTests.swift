import Testing
import Foundation
@testable import Tideline

// MARK: - Synthetic data generator (#11)

/// Deterministic synthetic cycle generator for testing the mixture
/// predictor against ground truth. Produces cycle-length sequences drawn
/// from a known 2-component mixture so tests can assert recovery within
/// tolerance.
///
/// Component 1: `L ~ Normal(mu1, sigma1²)`.
/// Component 2: `log(L − delta) ~ Normal(mu2, sigma2²)`, equivalently
/// `L = exp(Normal(mu2, sigma2²)) + delta`.
///
/// Mixing weight `pi` = probability the draw comes from component 1.
struct SyntheticMixture {
    let mu1: Double
    let sigma1: Double
    let mu2: Double          // log-space
    let sigma2: Double       // log-space
    let delta: Double
    let pi: Double

    /// Returns the lengths and the ground-truth labels (1 = component 1,
    /// 2 = component 2). Both arrays have length `n`.
    func generate(n: Int, seed: UInt64) -> (lengths: [Double], labels: [Int]) {
        var rng = TestRNG(seed: seed)
        var lengths = [Double](); lengths.reserveCapacity(n)
        var labels = [Int](); labels.reserveCapacity(n)
        for _ in 0..<n {
            let useComp1 = rng.nextUniform() < pi
            if useComp1 {
                let z = rng.nextGaussian()
                lengths.append(mu1 + sigma1 * z)
                labels.append(1)
            } else {
                let z = rng.nextGaussian()
                let y = mu2 + sigma2 * z
                lengths.append(exp(y) + delta)
                labels.append(2)
            }
        }
        return (lengths, labels)
    }
}

/// Test-only RNG. Separate from `SeededRNG` in `CyclePredictorTests` to
/// avoid cross-file Sendable / test-ordering concerns. Algorithm and
/// Box-Muller logic mirror the production `MixtureRNG`.
struct TestRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUniform() -> Double {
        max(1e-12, min(1.0 - 1e-12, Double(nextUInt64() >> 11) / Double(1 << 53)))
    }

    mutating func nextGaussian() -> Double {
        let u1 = nextUniform()
        let u2 = nextUniform()
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}

// MARK: - Suite

@Suite("MixturePredictor — Gibbs sampler")
struct MixturePredictorTests {

    // MARK: Prior + API contract

    @Test("populationPrior has the documented anchor values")
    func priorAnchors() {
        let p = MixturePredictor.populationPrior
        #expect(p.mu1Prior == 28.7)
        #expect(p.kappa1Prior == 2.0)
        #expect(p.alpha1Prior == 3.0)
        #expect(abs(p.beta1Prior - 2.0 * 3.79 * 3.79) < 1e-9)
        #expect(abs(p.mu2Prior - log(25.0)) < 1e-9)
        #expect(p.observedCount == 0)
        #expect(p.posteriorSamples.isEmpty)
    }

    @Test("empty observations: runGibbs is a no-op, predictive is nil (#190)")
    func emptyObservationsNoop() {
        var p = MixturePredictor.populationPrior
        p.runGibbs(iterations: 50, burnIn: 20, seed: 1)
        #expect(p.posteriorSamples.isEmpty)
        #expect(p.nextCycleLengthEstimate == nil)
        #expect(p.mixingWeightEstimate == nil)
    }

    @Test("observe + observe(cycleLengths:) invalidates posterior samples")
    func observeInvalidates() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: Array(repeating: 28.0, count: 10))
        p.runGibbs(iterations: 30, burnIn: 10, seed: 1)
        #expect(!p.posteriorSamples.isEmpty)
        p.observe(cycleLength: 29.0)
        #expect(p.posteriorSamples.isEmpty)  // invalidated
        #expect(p.observedCount == 11)
    }

    @Test("determinism: same seed produces identical posterior samples")
    func determinism() {
        let cycles: [Double] = [27, 28, 29, 30, 26, 29, 28, 32, 27, 30, 28, 29]
        var p1 = MixturePredictor.populationPrior
        p1.observe(cycleLengths: cycles)
        p1.runGibbs(iterations: 80, burnIn: 30, seed: 99)

        var p2 = MixturePredictor.populationPrior
        p2.observe(cycleLengths: cycles)
        p2.runGibbs(iterations: 80, burnIn: 30, seed: 99)

        #expect(p1.posteriorSamples.count == p2.posteriorSamples.count)
        for (a, b) in zip(p1.posteriorSamples, p2.posteriorSamples) {
            #expect(a.mu1 == b.mu1)
            #expect(a.sigma1Sq == b.sigma1Sq)
            #expect(a.mu2 == b.mu2)
            #expect(a.sigma2Sq == b.sigma2Sq)
            #expect(a.pi == b.pi)
        }
    }

    @Test("different seed → different (but plausible) chain")
    func seedSensitivity() {
        let cycles: [Double] = (0..<30).map { _ in 28.0 }
        var p1 = MixturePredictor.populationPrior
        p1.observe(cycleLengths: cycles)
        p1.runGibbs(iterations: 80, burnIn: 30, seed: 1)

        var p2 = MixturePredictor.populationPrior
        p2.observe(cycleLengths: cycles)
        p2.runGibbs(iterations: 80, burnIn: 30, seed: 2)

        // Different seeds → different samples, but both should be in the
        // same neighbourhood (data is degenerate at L=28 for all obs).
        let differ = zip(p1.posteriorSamples, p2.posteriorSamples)
            .contains { abs($0.mu1 - $1.mu1) > 1e-6 }
        #expect(differ)
        #expect(abs((p1.nextCycleLengthEstimate ?? .nan) - (p2.nextCycleLengthEstimate ?? .nan)) < 1.0)
    }

    // MARK: Recovery on synthetic mixtures

    @Test("pure ovulatory data: posterior π → 1.0, μ₁ near truth")
    func recoverPureOvulatory() {
        let synth = SyntheticMixture(
            mu1: 28.0, sigma1: 3.0,
            mu2: log(36.0 - 14.0), sigma2: 0.4,   // unused (pi=1)
            delta: MixturePredictor.delta,
            pi: 1.0
        )
        let (cycles, _) = synth.generate(n: 80, seed: 42)
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 250, burnIn: 100, seed: 11)

        // With all observations from component 1, the assignment-step
        // posterior should drive π → 1.0 (saturating with the Beta(8,2)
        // prior, ~ (8 + 80) / (8 + 80 + 2) = 0.978).
        #expect((p.mixingWeightEstimate ?? .nan) > 0.90,
                "π posterior \(p.mixingWeightEstimate ?? .nan) should be ≥ 0.90 for pure ovulatory data")
        // μ₁ posterior should land near the true 28.
        let muSum = p.posteriorSamples.reduce(0.0) { $0 + $1.mu1 }
        let mu1Mean = muSum / Double(p.posteriorSamples.count)
        #expect(abs(mu1Mean - 28.0) < 1.5,
                "μ₁ posterior mean \(mu1Mean) should be within ±1.5 of truth 28.0")
    }

    @Test("80/20 mixture: posterior π near 0.8, both component means recovered")
    func recoverMixture80_20() {
        // Truth: 80% ovulatory at μ₁=28, 20% anovulatory at original-mean
        // exp(log(36)+0.4²/2)+14 = 22·exp(0.08)+14 ≈ 36 (Jensen).
        let trueMu2InLog = log(22.0)   // → component 2 original-mean ≈ 36
        let synth = SyntheticMixture(
            mu1: 28.0, sigma1: 2.5,
            mu2: trueMu2InLog, sigma2: 0.4,
            delta: MixturePredictor.delta,
            pi: 0.8
        )
        let (cycles, _) = synth.generate(n: 200, seed: 7)
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 300, burnIn: 150, seed: 13)

        #expect(abs((p.mixingWeightEstimate ?? .nan) - 0.8) < 0.10,
                "π posterior \(p.mixingWeightEstimate ?? .nan) should be within ±0.10 of truth 0.80")

        let mu1Mean = p.posteriorSamples.reduce(0.0) { $0 + $1.mu1 }
            / Double(p.posteriorSamples.count)
        #expect(abs(mu1Mean - 28.0) < 1.5,
                "μ₁ posterior mean \(mu1Mean) should be within ±1.5 of truth 28.0")

        let mu2Mean = p.posteriorSamples.reduce(0.0) { $0 + $1.mu2 }
            / Double(p.posteriorSamples.count)
        #expect(abs(mu2Mean - trueMu2InLog) < 0.30,
                "μ₂ posterior mean \(mu2Mean) (log-space) should be within ±0.30 of truth \(trueMu2InLog)")
    }

    @Test("nextCycleLengthEstimate near data mean for unimodal data")
    func predictiveMeanForUnimodal() {
        let cycles = [27.0, 28.0, 28.0, 29.0, 28.0, 27.0, 29.0, 28.0,
                      27.0, 28.0, 29.0, 28.0, 27.0, 28.0, 30.0, 28.0]
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 200, burnIn: 100, seed: 5)
        // Predictive mean should track the data mean (28.0 ± 0.5).
        let dataMean = cycles.reduce(0.0, +) / Double(cycles.count)
        #expect(abs((p.nextCycleLengthEstimate ?? .nan) - dataMean) < 1.5,
                "Predictive mean \(p.nextCycleLengthEstimate ?? .nan) should be near data mean \(dataMean)")
    }

    // MARK: Identifiability + chain health

    @Test("identifiability: comp 1 mean < comp 2 original-scale mean on average")
    func identifiabilityHolds() {
        // 70/30 mixture with well-separated components — exactly the case
        // the design assumes will not need a per-iteration swap.
        let synth = SyntheticMixture(
            mu1: 28.0, sigma1: 3.0,
            mu2: log(40.0 - 14.0), sigma2: 0.35,
            delta: MixturePredictor.delta,
            pi: 0.7
        )
        let (cycles, _) = synth.generate(n: 150, seed: 21)
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 250, burnIn: 100, seed: 23)

        var violations = 0
        for s in p.posteriorSamples {
            let comp2Original = exp(s.mu2 + 0.5 * s.sigma2Sq) + MixturePredictor.delta
            if s.mu1 >= comp2Original { violations += 1 }
        }
        // Strong priors should keep label switching rare; allow up to 10%
        // violations as a soft check.
        let frac = Double(violations) / Double(p.posteriorSamples.count)
        #expect(frac < 0.10,
                "Label switching violations \(frac) should be <10% on well-separated mixture")
    }

    @Test("assignment stability ≥ 0.9 on well-separated mixture (#191)")
    func assignmentStability() {
        let synth = SyntheticMixture(
            mu1: 28.0, sigma1: 2.5,
            mu2: log(45.0 - 14.0), sigma2: 0.3,
            delta: MixturePredictor.delta,
            pi: 0.7
        )
        let (cycles, _) = synth.generate(n: 100, seed: 31)
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 250, burnIn: 100, seed: 41)
        // #191 — tightened from > 0.7 to > 0.9. Design doc § "Gibbs
        // sampler structure" specifies ≥ 0.9 as the convergence target.
        // For well-separated synthetic data (μ₁=28 vs comp-2 mean ≈45)
        // with the H-Z hard threshold, stability should comfortably
        // clear 0.9.
        #expect(p.assignmentStability > 0.9,
                "Assignment stability \(p.assignmentStability) below design doc's convergence target")
    }

    // MARK: Predictive interval

    @Test("90% credible interval brackets the predictive mean")
    func intervalBracketsMean() {
        let cycles: [Double] = (0..<40).map { i in
            // 90% ~ 28d, 10% ~ 60d (anovulatory)
            (i % 10 == 0) ? 60.0 : 28.0
        }
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 200, burnIn: 100, seed: 53)
        let interval = p.nextCycleLengthInterval(confidence: 0.90, seed: 71) ?? (.nan...(.nan))
        let mean = p.nextCycleLengthEstimate ?? .nan
        #expect(interval.lowerBound <= mean)
        #expect(mean <= interval.upperBound)
        #expect(interval.upperBound > interval.lowerBound)
    }

    @Test("predictive interval widens with mixture variance vs pure data")
    func intervalWidensWithMixture() {
        // Pure 28d data: tight interval. Mixed 28d + 60d: wider.
        var pPure = MixturePredictor.populationPrior
        pPure.observe(cycleLengths: Array(repeating: 28.0, count: 30))
        pPure.runGibbs(iterations: 200, burnIn: 100, seed: 61)
        let pureInterval = pPure.nextCycleLengthInterval(confidence: 0.90, seed: 81) ?? (.nan...(.nan))
        let pureWidth = pureInterval.upperBound - pureInterval.lowerBound

        var pMix = MixturePredictor.populationPrior
        let mixed: [Double] = (0..<30).map { i in (i % 3 == 0) ? 55.0 : 28.0 }
        pMix.observe(cycleLengths: mixed)
        pMix.runGibbs(iterations: 200, burnIn: 100, seed: 61)
        let mixInterval = pMix.nextCycleLengthInterval(confidence: 0.90, seed: 81) ?? (.nan...(.nan))
        let mixWidth = mixInterval.upperBound - mixInterval.lowerBound

        #expect(mixWidth > pureWidth,
                "Mixture-data 90% CI width \(mixWidth) should exceed pure-data width \(pureWidth)")
    }

    @Test("predictive mean reflects component 2 when π posterior is near zero")
    func meanReflectsComponentWeights() {
        // Pure anovulatory cycles (L=55±) — Gibbs posterior π ≈ 0 (per
        // jacobianTermActuallyApplied). The predictive MEAN should
        // therefore be dominated by component 2 (centered ~55 days).
        // Using the mean (not the lower-tail quantile) is robust to the
        // residual ~5% comp-1 weight that still leaks through the
        // posterior — the lower 5% quantile can land in the boundary
        // band, but the mean is firmly in the comp-2 range.
        let synth = SyntheticMixture(
            mu1: 28.0, sigma1: 3.0,
            mu2: log(55.0 - 14.0), sigma2: 0.15,
            delta: MixturePredictor.delta,
            pi: 0.0
        )
        let (cycles, _) = synth.generate(n: 120, seed: 211)
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 250, burnIn: 100, seed: 213)
        #expect((p.nextCycleLengthEstimate ?? .nan) > 45.0,
                "Predictive mean \(p.nextCycleLengthEstimate ?? .nan) should sit in the long-cycle range, reflecting low π posterior")
        let interval = p.nextCycleLengthInterval(confidence: 0.90, seed: 401) ?? (.nan...(.nan))
        #expect(interval.upperBound > 60.0,
                "90% interval upper bound \(interval.upperBound) should extend into the right tail")
    }

    // MARK: Cold start

    @Test("N=1 observation: Gibbs doesn't crash, samples populated")
    func singleObservationDoesNotCrash() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLength: 28.0)
        p.runGibbs(iterations: 60, burnIn: 20, seed: 91)
        #expect(p.posteriorSamples.count == 40)
        #expect(p.posteriorSamples.allSatisfy { $0.sigma1Sq.isFinite && $0.sigma2Sq.isFinite })
    }

    @Test("N=3 short observations: posterior μ₁ pulled toward data")
    func shortObservationsPullPosterior() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: [25, 26, 27])
        p.runGibbs(iterations: 150, burnIn: 50, seed: 101)
        let mu1Mean = p.posteriorSamples.reduce(0.0) { $0 + $1.mu1 } / Double(p.posteriorSamples.count)
        // Posterior should sit somewhere between prior (28.7) and data
        // mean (26), with the weak κ=2 prior partially conceding.
        #expect(mu1Mean < 28.7, "μ₁ posterior \(mu1Mean) should be pulled below prior toward data")
        #expect(mu1Mean > 25.0, "μ₁ posterior \(mu1Mean) shouldn't overshoot data minimum")
    }

    // MARK: Jacobian smoke test

    @Test("expectedCycleLength uses Jensen-corrected log-normal mean")
    func jensenCorrectionInSampleMean() {
        let s = MixturePredictor.PosteriorSample(
            mu1: 28.0, sigma1Sq: 9.0,
            mu2: log(25.0), sigma2Sq: 0.16,  // log-space SD = 0.4
            pi: 0.8
        )
        // Component 2 original-scale mean = exp(log(25) + 0.16/2) + 14
        //                                = 25 · exp(0.08) + 14
        //                                ≈ 25 · 1.0833 + 14
        //                                ≈ 41.08
        let expectedComp2Mean = 25.0 * exp(0.08) + 14.0
        let expected = 0.8 * 28.0 + 0.2 * expectedComp2Mean
        #expect(abs(s.expectedCycleLength - expected) < 1e-6)
    }

    // NOTE: a "soft-regime Jacobian test" was attempted but removed —
    // the L<43 borderline case is dominated by prior-strength
    // interactions rather than the Jacobian term in isolation, and the
    // hand-computed direction depended on which side of the prior
    // boundary the borderline cycles fall on. The Jacobian math itself
    // was independently fact-checker-verified (see code-review report
    // 2026-05-25). The `jacobianTermActuallyApplied` test below exercises
    // the end-to-end correctness via the L≥43 path; for additional
    // confidence the Jacobian could be unit-tested by exposing the
    // `normalLogPdf` helper, but that's a follow-up tracker item.

    @Test("Jacobian: unambiguously long cycles get assigned to comp 2, not comp 1")
    func jacobianTermActuallyApplied() {
        // Generate cycles that are *unambiguously* anovulatory:
        // mu2=log(41), sigma2=0.15 → original-scale cycle range
        // approximately [44, 69] days. These cannot plausibly come from
        // component 1's prior at μ₁=28.7, σ₁≈3.79 (probability of L≥44
        // is below 4e-5). If Gibbs nonetheless assigns them to
        // component 1, the assignment likelihood is being miscomputed —
        // and the most-likely culprit is the Jacobian term `−log(L−δ)`
        // being dropped (its absence would shift component-2 log density
        // up by ~−log(30)≈−3.4 for these L values, making comp 1 look
        // unfairly competitive).
        let synth = SyntheticMixture(
            mu1: 28.0, sigma1: 3.0,         // unused (pi=0)
            mu2: log(55.0 - 14.0), sigma2: 0.15,
            delta: MixturePredictor.delta,
            pi: 0.0
        )
        let (cycles, _) = synth.generate(n: 120, seed: 211)
        #expect(cycles.allSatisfy { $0 > 38.0 },
                "Synthetic generator should produce only long cycles; got min \(cycles.min() ?? 0)")
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 250, burnIn: 100, seed: 213)
        // Beta(8, 2) prior tugs π toward 0.8 from below; with 120
        // unambiguously-anovulatory cycles, posterior π should drop
        // below 0.20. Without the Jacobian + Harlow-Zeger hard threshold,
        // π would stay much higher.
        #expect((p.mixingWeightEstimate ?? .nan) < 0.20,
                "π posterior \(p.mixingWeightEstimate ?? .nan) should drop on pure-anovulatory data")
    }

    // MARK: Predictive CDF + conditional (Session 2)

    @Test("predictiveCDF returns nil with no posterior samples (#215)")
    func predictiveCDFEmpty() {
        let p = MixturePredictor.populationPrior
        #expect(p.predictiveCDF(cycleLength: 28.0) == nil)
    }

    @Test("predictiveCDF is monotone increasing in x")
    func predictiveCDFMonotone() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: Array(repeating: 28.0, count: 20))
        p.runGibbs(iterations: 200, burnIn: 100, seed: 51)
        let f10 = p.predictiveCDF(cycleLength: 10.0) ?? .nan
        let f28 = p.predictiveCDF(cycleLength: 28.0) ?? .nan
        let f50 = p.predictiveCDF(cycleLength: 50.0) ?? .nan
        let f100 = p.predictiveCDF(cycleLength: 100.0) ?? .nan
        #expect(f10 < f28)
        #expect(f28 < f50)
        #expect(f50 < f100)
        #expect(f10 >= 0.0 && f100 <= 1.0)
    }

    @Test("conditionalCDF: at the conditioning day → 0, far right → 1")
    func conditionalCDFEndpoints() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: Array(repeating: 28.0, count: 20))
        p.runGibbs(iterations: 200, burnIn: 100, seed: 53)
        let atD = p.conditionalCDF(cycleLength: 30.0, currentDay: 30.0) ?? .nan
        #expect(atD < 0.01,
                "conditionalCDF at the conditioning day should be ~0; got \(atD)")
        let farRight = p.conditionalCDF(cycleLength: 200.0, currentDay: 30.0) ?? .nan
        #expect(farRight > 0.99,
                "conditionalCDF far right should saturate to ~1; got \(farRight)")
    }

    @Test("conditionalCDF returns nil with no posterior samples (#215)")
    func conditionalCDFEmpty() {
        let p = MixturePredictor.populationPrior
        #expect(p.conditionalCDF(cycleLength: 30.0, currentDay: 28.0) == nil)
    }

    @Test("conditionalInterval returns nil with no posterior samples (#215)")
    func conditionalIntervalEmpty() {
        let p = MixturePredictor.populationPrior
        #expect(p.conditionalInterval(currentDay: 28.0, confidence: 0.90) == nil)
    }

    @Test("conditionalInterval lower bound ≥ D, upper bound finite")
    func conditionalIntervalShape() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: Array(repeating: 28.0, count: 20))
        p.runGibbs(iterations: 200, burnIn: 100, seed: 57)
        let interval = p.conditionalInterval(currentDay: 30.0, confidence: 0.90) ?? (.nan...(.nan))
        #expect(interval.lowerBound >= 30.0,
                "Lower bound \(interval.lowerBound) must be ≥ conditioning day 30")
        #expect(interval.upperBound > interval.lowerBound)
        #expect(interval.upperBound < 250.0,
                "Upper bound should be finite and within plausible range; got \(interval.upperBound)")
    }

    @Test("conditional interval widens for mixed (anovulatory) data vs pure ovulatory")
    func conditionalWidensWithAnovulatory() {
        var pPure = MixturePredictor.populationPrior
        pPure.observe(cycleLengths: Array(repeating: 28.0, count: 20))
        pPure.runGibbs(iterations: 200, burnIn: 100, seed: 61)
        let pureInterval = pPure.conditionalInterval(currentDay: 32.0, confidence: 0.90) ?? (.nan...(.nan))
        let pureWidth = pureInterval.upperBound - pureInterval.lowerBound

        var pMix = MixturePredictor.populationPrior
        var mixed = Array(repeating: 28.0, count: 14)
        mixed.append(contentsOf: Array(repeating: 55.0, count: 6))
        pMix.observe(cycleLengths: mixed)
        pMix.runGibbs(iterations: 200, burnIn: 100, seed: 61)
        let mixInterval = pMix.conditionalInterval(currentDay: 32.0, confidence: 0.90) ?? (.nan...(.nan))
        let mixWidth = mixInterval.upperBound - mixInterval.lowerBound

        #expect(mixWidth > pureWidth,
                "Mixed-data conditional width \(mixWidth) should exceed pure-ovulatory \(pureWidth) — the v2 mixture's whole point")
    }

    @Test("conditional interval for ovulatory data: lower bound parity with single-component")
    func conditionalLowerBoundParity() {
        // Even with pure-ovulatory data the mixture is *intentionally
        // different* from single-component on the upper bound: the
        // Beta(8,2) prior on π keeps ~5–10% posterior mass on
        // component 2 even when no observations support it, and that
        // small anovulatory tail dominates the conditional upper
        // quantile when D > μ₁ (the conditional posterior is mostly
        // shaped by component-2 mass above D). This is by design —
        // honest acknowledgement that an "occasional anovulatory cycle"
        // is always possible.
        //
        // What we *can* test for parity: the **lower bound**. The
        // bottom of the conditional CI is set by where the bulk of
        // mass starts after D, which for ovulatory data is dominated
        // by component 1. The two models should agree within a few
        // days here.
        var mix = MixturePredictor.populationPrior
        mix.observe(cycleLengths: Array(repeating: 28.0, count: 30))
        mix.runGibbs(iterations: 200, burnIn: 100, seed: 71)
        let mixInterval = mix.conditionalInterval(currentDay: 30.0, confidence: 0.90) ?? (.nan...(.nan))

        var single = CyclePredictor.populationPrior
        single.observe(cycleLengths: Array(repeating: 28.0, count: 30))
        let singleInterval = single.conditionalInterval(currentDay: 30.0, confidence: 0.90)

        #expect(abs(mixInterval.lowerBound - singleInterval.lowerBound) < 3.0,
                "Lower-bound parity: mixture \(mixInterval.lowerBound) vs single \(singleInterval.lowerBound)")
        // Upper bound: mixture is allowed to extend further into the
        // anovulatory tail. Just check it's not blown up beyond ~75d.
        #expect(mixInterval.upperBound < 75.0,
                "Mixture upper bound \(mixInterval.upperBound) shouldn't blow up for ovulatory data")
    }

    @Test("conditionalInterval stays finite at very late D")
    func conditionalAtLateD() {
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: Array(repeating: 28.0, count: 20))
        p.runGibbs(iterations: 200, burnIn: 100, seed: 73)
        let interval = p.conditionalInterval(currentDay: 90.0, confidence: 0.90) ?? (.nan...(.nan))
        #expect(interval.upperBound < 360.0,
                "Late-D conditional upper bound \(interval.upperBound) must stay finite")
    }

    // MARK: Harlow-Zeger threshold bias regression (#192)

    @Test("H-Z hard threshold introduces small downward π bias near boundary")
    func hzThresholdBiasRegression() {
        // #192 — pin the small downward bias on π that the Harlow-Zeger
        // hard threshold introduces. Construct data with 5 of 100 cycles
        // in [43, 50] (forced to comp 2) and 95 in [25, 32] (soft
        // assignment). The "true" π if both cohorts were freely
        // identified would be 0.95 — but with the hard threshold,
        // posterior π gets capped slightly lower because comp 2 absorbs
        // some borderline-43 cycles that might otherwise be ovulatory.
        //
        // We don't enforce a specific bias magnitude (it depends on the
        // π prior weight); we just pin "still high but below 0.95" so
        // a future change that accidentally removes the H-Z threshold
        // (and lets comp 1 absorb all cycles, returning π → 1.0) is
        // detected as a behaviour regression.
        var cycles: [Double] = Array(repeating: 28.0, count: 95)
        cycles.append(contentsOf: [43, 45, 47, 48, 50])
        var p = MixturePredictor.populationPrior
        p.observe(cycleLengths: cycles)
        p.runGibbs(iterations: 250, burnIn: 100, seed: 197)
        let pi = p.mixingWeightEstimate ?? .nan
        #expect(pi >= 0.80,
                "π posterior \(pi) should stay high — 95/100 cycles are ovulatory")
        #expect(pi <= 0.97,
                "π posterior \(pi) should NOT saturate to ~1.0 — the H-Z threshold forces 5/100 to comp 2 by construction, giving a small downward bias. If this test pops above 0.97, the hard threshold may have been removed.")
    }

    // MARK: RNG parity (#192)

    @Test("MixtureRNG (production) and TestRNG (synthetic generator) produce bit-identical uniform streams (#192)")
    func rngParity() {
        // #192 — pin bit-exact parity between the production MixtureRNG
        // (used by MixturePredictor in production code paths) and the
        // TestRNG (used by the SyntheticMixture generator). Both
        // implement xorshift64 with seed != 0 sentinel-replaced to 1.
        // Without parity, synthetic-data tests would silently drift
        // from production behaviour as the two RNGs evolve.
        //
        // MixtureRNG was promoted from `fileprivate` to `internal`
        // specifically for this test (Session 4 reviewer flagged the
        // prior test as a no-op). No production code outside
        // MixturePredictor.swift consumes MixtureRNG; the visibility
        // is test-infrastructure only.
        var prod = MixtureRNG(seed: 42)
        var test = TestRNG(seed: 42)
        // First: bit-exact UInt64 stream (the underlying xorshift).
        for i in 0..<20 {
            let p = prod.nextUInt64()
            let t = test.nextUInt64()
            #expect(p == t,
                    "RNG divergence at draw \(i): MixtureRNG \(p) vs TestRNG \(t)")
        }
        // Second: clamped-uniform stream — verifies the mantissa shift
        // and [1e-12, 1-1e-12] clamp match.
        var prod2 = MixtureRNG(seed: 17)
        var test2 = TestRNG(seed: 17)
        for i in 0..<20 {
            let p = prod2.nextUniform()
            let t = test2.nextUniform()
            #expect(p == t,
                    "Uniform divergence at draw \(i): MixtureRNG \(p) vs TestRNG \(t)")
        }
        // Third: seed-0 sentinel parity — both must treat seed 0 as 1.
        var prodZero = MixtureRNG(seed: 0)
        var testOne = TestRNG(seed: 1)
        for _ in 0..<5 {
            #expect(prodZero.nextUInt64() == testOne.nextUInt64(),
                    "Seed-0 sentinel must match seed-1 for both RNGs")
        }
    }

    @Test("Cross-language RNG parity: Python port matches Swift MixtureRNG bit-exactly (#192 audit)")
    func crossLanguageRNGParityVsPythonReference() {
        // These literal values were dumped from
        // `data/raw/.venv/bin/python3 -c "..."` using the Python port in
        // data/validate_phase_predictor.py § MixtureRNG. If a future
        // change to the Swift xorshift / Box-Muller / Marsaglia-Tsang
        // diverges from the Python port, the Fehring/MCPhases validation
        // numbers in docs/research/2026-05-26-*.md become unreliable.
        // This test guards against silent drift.
        var rng = MixtureRNG(seed: 42)
        let expectedUniforms: [Double] = [
            2.4641099161115676e-09,
            0.62516277981195145,
            0.54326210096934802,
            0.15715843401255802,
            0.306905739834477,
        ]
        for expected in expectedUniforms {
            let actual = rng.nextUniform()
            #expect(actual == expected,
                    "Uniform divergence: Swift \(actual) vs Python reference \(expected)")
        }
        let expectedGaussians: [Double] = [
            -0.79968119205366139,
            -0.75249192268324594,
            -0.6357983586236331,
            -0.83621517241914811,
            1.1226488822410428,
        ]
        for expected in expectedGaussians {
            let actual = rng.nextGaussian()
            #expect(actual == expected,
                    "Gaussian divergence: Swift \(actual) vs Python reference \(expected)")
        }
        let expectedGammas: [Double] = [
            1.5725200242991944,
            0.51176072241430826,
            1.8027368441457561,
            0.8621131863588164,
            2.2126237918879914,
        ]
        for expected in expectedGammas {
            let actual = rng.nextGamma(shape: 3.0, scale: 0.348)
            #expect(actual == expected,
                    "Gamma divergence: Swift \(actual) vs Python reference \(expected)")
        }
    }

    // MARK: Age-stratified prior

    @Test("populationPrior(for: .menopausal) widens component 1 β")
    func menopausalPriorWiderBeta() {
        let baseline = MixturePredictor.populationPrior
        let meno = MixturePredictor.populationPrior(for: .menopausal)
        // Menopausal AWHS within-person SD = 11.19; expect a much larger β₁.
        #expect(meno.beta1Prior > baseline.beta1Prior * 5,
                "Menopausal β₁ \(meno.beta1Prior) should be ≥5× baseline \(baseline.beta1Prior)")
        // Component 2 + π priors should be unchanged.
        #expect(meno.mu2Prior == baseline.mu2Prior)
        #expect(meno.piAlphaPrior == baseline.piAlphaPrior)
    }
}
