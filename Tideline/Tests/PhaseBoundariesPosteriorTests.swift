import Testing
import Foundation
@testable import Tideline

/// Pins the NEW-176 posterior types: GaussianPosterior, PhaseBoundariesPosterior,
/// and the .crisp equivalence with the legacy `PhaseBoundaries.from(...)`.
///
/// The most load-bearing test is `crispEquivalence` — it guarantees existing
/// callers see no behavioural change when this new type lands. Without that,
/// the dual-path architecture would silently drift over time.
@Suite("NEW-176 — PhaseBoundariesPosterior types and crisp equivalence")
struct PhaseBoundariesPosteriorTests {

    // MARK: - GaussianPosterior basics

    @Test("GaussianPosterior holds mean + variance; SD = sqrt(variance)")
    func gaussianPosteriorSDFromVariance() {
        let g = GaussianPosterior(mean: 28.7, variance: 9.0)
        #expect(g.mean == 28.7)
        #expect(g.variance == 9.0)
        #expect(abs(g.sd - 3.0) < 1e-9)
    }

    @Test("GaussianPosterior allows zero variance (sd = 0)")
    func gaussianPosteriorZeroVariance() {
        let g = GaussianPosterior(mean: 12.0, variance: 0.0)
        #expect(g.sd == 0.0)
    }

    // MARK: - Population variance constants (post fact-check correction I4)

    @Test("Population luteal variance: within + between sums correctly")
    func populationLutealVarianceDecomposition() {
        // Fact-check I4 — when we don't observe per-user luteal mean, the
        // propagation variance is σ²_within + σ²_between, not σ²_within alone.
        // Constants documented in PhaseBoundariesPosterior.
        #expect(abs(PhaseBoundariesPosterior.populationLutealVarianceWithin - 1.32) < 1e-9)
        #expect(abs(PhaseBoundariesPosterior.populationLutealVarianceBetween - 3.50) < 1e-9)
        #expect(abs(PhaseBoundariesPosterior.populationLutealVarianceTotal - 4.82) < 1e-9)
        // Algebraic invariant
        #expect(abs(
            PhaseBoundariesPosterior.populationLutealVarianceWithin
            + PhaseBoundariesPosterior.populationLutealVarianceBetween
            - PhaseBoundariesPosterior.populationLutealVarianceTotal
        ) < 1e-9)
    }

    // MARK: - from(...) factory: ovulation mean / variance propagation

    @Test("from(...) propagates ov.mean = cycle.mean − defaultLutealDuration")
    func factoryOvulationMean() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        // ov.mean = 29.0 - 12 (NEW-169 default luteal) = 17.0
        #expect(abs(p.ovulationDay.mean - 17.0) < 1e-9)
    }

    @Test("from(...) propagates ov.variance = NIG_pred_var + populationLutealVarianceTotal")
    func factoryOvulationVariance() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        // Expect: 4.0 + 4.82 = 8.82
        #expect(abs(p.ovulationDay.variance - 8.82) < 1e-9)
    }

    @Test("from(...) sets df = 2·alphaPost (Student-t under NIG posterior)")
    func factoryDF() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        #expect(abs(p.df - 12.0) < 1e-9)
    }

    @Test("from(...) preserves recovery + irregularity flags from caller")
    func factoryPreservesFlags() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 30.0,
            cycleLengthPredictiveVariance: 5.0,
            alphaPost: 5.0,
            isWidenedRecovery: true,
            isOngoingIrregularity: true
        )
        #expect(p.isWidenedRecovery == true)
        #expect(p.isOngoingIrregularity == true)
    }

    // MARK: - .crisp equivalence (the load-bearing invariant)

    @Test("crisp.cycleLength matches from(L, m).cycleLength for L=29, m=5")
    func crispEquivalenceTypical() {
        let posterior = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        let legacy = PhaseBoundaries.from(cycleLength: 29, mensesEnd: 5)
        let projected = posterior.crisp
        #expect(projected.cycleLength == legacy.cycleLength)
        #expect(projected.mensesEnd == legacy.mensesEnd)
        #expect(projected.ovulation == legacy.ovulation)
    }

    @Test("crisp ovulation matches legacy for several (L, m) pairs")
    func crispEquivalenceSweep() {
        let cases: [(Int, Int)] = [
            (26, 4), (28, 5), (29, 5), (30, 5), (32, 6), (35, 7), (40, 5)
        ]
        for (L, m) in cases {
            let posterior = PhaseBoundariesPosterior.from(
                mensesEnd: m,
                cycleLengthMean: Double(L),
                cycleLengthPredictiveVariance: 4.0,
                alphaPost: 6.0
            )
            let legacy = PhaseBoundaries.from(cycleLength: L, mensesEnd: m)
            #expect(posterior.crisp.ovulation == legacy.ovulation,
                   "Mismatch at L=\(L), m=\(m): posterior=\(posterior.crisp.ovulation), legacy=\(legacy.ovulation)")
        }
    }

    @Test("crisp rounds posterior mean correctly (28.7 → 29)")
    func crispRoundsCycleMean() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 28.7,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        // 28.7 rounds to 29 → ovulation = 29 - 12 = 17
        #expect(p.crisp.cycleLength == 29)
        #expect(p.crisp.ovulation == 17)
    }

    // MARK: - NEW-Wave B — nextMensesProbability for graduated calendar opacity

    @Test("nextMensesProbability: pre-cycle (day 1) → 0")
    func nextMensesProbDay1IsZero() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,  // SD = 2.0
            alphaPost: 6.0
        )
        // Day 1 of current cycle — way before any plausible next-cycle start.
        // P should be ~0.
        let prob = p.nextMensesProbability(forDayOffset: 1, nextCycleMensesEnd: 5)
        #expect(prob < 0.01)
    }

    @Test("nextMensesProbability: at posterior mean cycle end → ~50% (entering menses)")
    func nextMensesProbAtMean() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        // Day 29 = posterior mean L → half the cycle-length probability mass
        // is at or before, half after. Day 29 falls in [L, L+5] only if
        // L ≤ 29 (50%). So P(day 29 in menses) ≈ 0.5.
        let prob = p.nextMensesProbability(forDayOffset: 29, nextCycleMensesEnd: 5)
        #expect(prob > 0.40 && prob < 0.60)
    }

    @Test("nextMensesProbability: well past upper bound → ~0")
    func nextMensesProbPastUpperBound() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,  // SD = 2.0
            alphaPost: 6.0
        )
        // Day 50 is way past mean + many SDs → both CDF terms ≈ 1.0 → diff ≈ 0
        let prob = p.nextMensesProbability(forDayOffset: 50, nextCycleMensesEnd: 5)
        #expect(prob < 0.05)
    }

    @Test("nextMensesProbability: profile is bell-shaped around mean")
    func nextMensesProbBellShape() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        let m = 5
        let probAt27 = p.nextMensesProbability(forDayOffset: 27, nextCycleMensesEnd: m)
        let probAt29 = p.nextMensesProbability(forDayOffset: 29, nextCycleMensesEnd: m)
        let probAt31 = p.nextMensesProbability(forDayOffset: 31, nextCycleMensesEnd: m)
        let probAt33 = p.nextMensesProbability(forDayOffset: 33, nextCycleMensesEnd: m)
        let probAt35 = p.nextMensesProbability(forDayOffset: 35, nextCycleMensesEnd: m)
        // Peak should be near 29-31 (middle of [L, L+m]).
        let peak = max(probAt29, probAt31)
        #expect(probAt27 < peak, "left tail below peak")
        #expect(probAt35 < peak, "right tail below peak")
        // All probs in [0, 1]
        for prob in [probAt27, probAt29, probAt31, probAt33, probAt35] {
            #expect(prob >= 0.0 && prob <= 1.0)
        }
    }

    @Test("nextMensesProbability: clamps to [0,1]")
    func nextMensesProbClamps() {
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 4.0,
            alphaPost: 6.0
        )
        // Even pathological offsets stay in [0, 1].
        for d in [0, -5, 100, 1000] {
            let prob = p.nextMensesProbability(forDayOffset: d, nextCycleMensesEnd: 5)
            #expect(prob >= 0.0 && prob <= 1.0)
        }
    }

    @Test("nextMensesProbability: agrees with CyclePredictor.predictiveCDF (anchor)")
    func nextMensesProbMatchesCanonical() {
        // The Wave-A scale-vs-SD distinction is load-bearing: SD ≠ scale
        // for a Student-t with finite df. Anchor against CyclePredictor's
        // own predictiveCDF (which uses the canonical scale denominator
        // β(κ+1)/(ακ)) to make sure our posterior agrees numerically.
        var predictor = CyclePredictor.populationPrior
        predictor.observe(cycleLengths: [28, 30, 29, 31, 28])
        let predVar = predictor.beta * (predictor.kappa + 1.0)
            / ((predictor.alpha - 1.0) * predictor.kappa)
        let posterior = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: predictor.mu,
            cycleLengthPredictiveVariance: predVar,
            alphaPost: predictor.alpha
        )
        // For m=1 (single-day window), P(day d ∈ menses) should equal
        // F_X(d) − F_X(d-1) where F_X is the predictor's predictive CDF.
        let day = Int(predictor.mu.rounded())
        let pPosterior = posterior.nextMensesProbability(forDayOffset: day, nextCycleMensesEnd: 1)
        let pCanonical = predictor.predictiveCDF(cycleLength: Double(day))
            - predictor.predictiveCDF(cycleLength: Double(day - 1))
        #expect(abs(pPosterior - pCanonical) < 0.001,
               "posterior P=\(pPosterior) vs canonical P=\(pCanonical) — scale-vs-SD regression?")
    }

    @Test("nextMensesProbability: wider variance → wider bell")
    func nextMensesProbWidthScalesWithVariance() {
        // High-variance user: posterior is much wider.
        let pNarrow = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 1.0,  // SD = 1.0
            alphaPost: 10.0
        )
        let pWide = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 16.0,  // SD = 4.0
            alphaPost: 10.0
        )
        // At the centre, narrow user has higher density per day → higher
        // single-day P (mass more concentrated). At the tails (far from
        // peak), narrow user has lower P (less mass there). Test the tail
        // case at day 25, far from cycle-mean 29 + menses 5.
        let narrowTail = pNarrow.nextMensesProbability(forDayOffset: 22, nextCycleMensesEnd: 5)
        let wideTail = pWide.nextMensesProbability(forDayOffset: 22, nextCycleMensesEnd: 5)
        #expect(wideTail > narrowTail,
               "wider posterior should have higher P in the tails")
    }

    @Test("Ovulation SD reflects propagated variance")
    func ovulationSDPropagation() {
        // NIG predictive var = 9.0 → cycle SD 3.0
        // Adding population luteal 4.82: total = 13.82 → SD ≈ 3.72
        let p = PhaseBoundariesPosterior.from(
            mensesEnd: 5,
            cycleLengthMean: 29.0,
            cycleLengthPredictiveVariance: 9.0,
            alphaPost: 6.0
        )
        #expect(abs(p.ovulationDay.sd - (13.82.squareRoot())) < 1e-9)
    }
}
