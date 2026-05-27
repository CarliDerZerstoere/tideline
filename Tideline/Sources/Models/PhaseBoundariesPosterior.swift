import Foundation

/// A scalar quantity with Bayesian uncertainty (mean + variance).
///
/// Used by `PhaseBoundariesPosterior` to carry predicted ovulation day and
/// cycle length as posterior distributions instead of crisp Ints. The
/// underlying distribution is Student-t under the predictor's NIG posterior;
/// `df` is supplied separately by `PhaseBoundariesPosterior`.
public struct GaussianPosterior: Sendable, Equatable {
    public let mean: Double
    public let variance: Double

    public init(mean: Double, variance: Double) {
        precondition(variance >= 0, "variance must be non-negative")
        self.mean = mean
        self.variance = variance
    }

    public var sd: Double { variance.squareRoot() }
}

/// Phase boundaries as a posterior distribution — uncertainty-aware
/// replacement for the crisp `PhaseBoundaries` Ints.
///
/// **Why this exists (NEW-176):** the legacy `PhaseBoundaries.from(...)`
/// collapses the Bayesian posterior on cycle length to a crisp ovulation
/// Int. UI surfaces consuming `bounds.ovulation` thus pretend we know the
/// ovulation day with certainty. The empirical validation against the
/// Fehring NFP dataset (1,508 cycles) shows the predicted ovulation has
/// non-trivial uncertainty even with the corrected constant: cycle-length
/// posterior variance plus population luteal variance gives a 90% CI of
/// roughly ±5 d for typical users.
///
/// **Architecture (Facade + Posterior-First):** `.crisp` projects this
/// posterior to a legacy `PhaseBoundaries` for existing callers (doctor
/// PDF, current phase strip, etc.). New consumers (graduated-opacity
/// calendar #164, hero text band) read `ovulationDay` / `cycleLength`
/// directly and render uncertainty.
///
/// **Math (post-fact-check):**
///   - `mensesEnd` is observed (Belsey-derived per #156 + personal floor
///     per NEW-171) — crisp.
///   - `ovulationDay.mean = μ_NIG − defaultLutealDuration` (12).
///   - `ovulationDay.variance = NIG_predictive_var + σ²_within + σ²_between`
///     where the population luteal variance is σ²_within (literature anchor
///     1.15²) + σ²_between (1.87²), reflecting both within-person variability
///     AND the uncertainty about THIS user's luteal mean (we don't observe
///     it). Fact-check correction I4: not σ²_within alone.
///   - `df = 2·α_post` from the NIG posterior; use Student-t for CI.
///
/// See `docs/research/2026-05-25-empirical-validation-results.md` for the
/// validation that justifies these specific constants and the documented
/// ~9pp overcoverage (Pillar-3-compatible honest conservatism). Tightening
/// path: NEW-E / #124 conformal calibration.
public struct PhaseBoundariesPosterior: Sendable, Equatable {
    /// Menses-end day. **Semantics depend on the builder:**
    ///   - `homeSnapshot()` builder: observed end of the CURRENT cycle's
    ///     menses (#156 Belsey + NEW-171 personal floor) — crisp.
    ///   - `phaseBoundariesPosteriorForCalendar()` builder: assumed
    ///     duration of the NEXT cycle's menses (personal median or
    ///     population default) — used by `nextMensesProbability(...)`.
    ///
    /// The two semantics are numerically similar (both reflect the user's
    /// typical menses duration) but conceptually different. Callers
    /// reading this field for current-cycle observation MUST use the
    /// homeSnapshot-built instance.
    public let mensesEnd: Int

    /// Predicted ovulation day with posterior uncertainty.
    public let ovulationDay: GaussianPosterior

    /// Predicted total cycle length with posterior uncertainty (from NIG).
    public let cycleLength: GaussianPosterior

    /// Student-t df for credible interval computation. = 2·α_post.
    public let df: Double

    /// Whether the user's cycle is in a recovery window (post-Category-C).
    /// Mirrors `Prediction.isWidenedRecovery`.
    public let isWidenedRecovery: Bool

    /// Whether the user has declared an ongoing irregularity (PCOS).
    /// Mirrors `Prediction.isOngoingIrregularity`.
    public let isOngoingIrregularity: Bool

    /// Population-mean luteal variance, decomposed (Fehring V2 + Berglund
    /// Scherwitzl 2015 anchors). Within-person σ² ≈ 1.15² (cycle-to-cycle
    /// luteal variation for one woman). Between-person σ² ≈ 1.87²
    /// (uncertainty about her luteal mean since we don't observe it).
    /// Total = within + between. Documented as marginalized prior for
    /// fact-check correction I4. Constants are rounded to 2 dp; the test
    /// pins the same rounding.
    public static let populationLutealVarianceWithin: Double = 1.32
    public static let populationLutealVarianceBetween: Double = 3.50
    /// Derived: within + between (avoids drift if one part is tuned).
    public static let populationLutealVarianceTotal: Double =
        populationLutealVarianceWithin + populationLutealVarianceBetween

    public init(
        mensesEnd: Int,
        ovulationDay: GaussianPosterior,
        cycleLength: GaussianPosterior,
        df: Double,
        isWidenedRecovery: Bool = false,
        isOngoingIrregularity: Bool = false
    ) {
        precondition(df > 0, "df must be positive")
        self.mensesEnd = mensesEnd
        self.ovulationDay = ovulationDay
        self.cycleLength = cycleLength
        self.df = df
        self.isWidenedRecovery = isWidenedRecovery
        self.isOngoingIrregularity = isOngoingIrregularity
    }

    /// Legacy crisp projection. Existing callers (doctor PDF, current phase
    /// strip, sparkline, etc.) consume this and see no behavioural change
    /// vs the old `PhaseBoundaries.from(cycleLength:mensesEnd:)`.
    ///
    /// **Invariant:** for any `(L, m)`, `from(L, m) == fromCrisp(L, m).crisp`.
    /// Pinned by `PhaseBoundariesPosteriorTests.crispEquivalence`.
    public var crisp: PhaseBoundaries {
        PhaseBoundaries.from(
            cycleLength: Int(cycleLength.mean.rounded()),
            mensesEnd: mensesEnd
        )
    }

    /// Probability that a calendar day at offset `daysFromCurrentStart`
    /// from the current cycle's start falls inside the **next cycle's
    /// menses window**. Used by the calendar to render the predicted
    /// next-period bleeding days with opacity proportional to per-day
    /// probability instead of crisp rings (Tracker #164).
    ///
    /// **Model:**
    ///   - L = next cycle's start = current_start + cycleLength
    ///   - cycleLength ~ location-scale Student-t with location
    ///     `cycleLength.mean`, **scale** s (≠ SD; see math note), and
    ///     df = self.df = 2·α_post per the NIG posterior
    ///   - Next cycle's menses runs `[L, L + mensesEndAssumed)` for
    ///     `mensesEndAssumed` days (NEW-171 personal floor or population
    ///     default — caller provides via `nextCycleMensesEnd`)
    ///
    /// **Math note (location-scale Student-t):** the SD and scale of a
    /// Student-t with df ν differ by `sqrt(ν/(ν−2))`. We carry `variance`
    /// (= SD²) on `GaussianPosterior` but the t-CDF transformation needs
    /// the scale parameter: `scale² = variance · (ν−2)/ν` (for ν > 2).
    /// We derive scale on the fly here. Matches `CyclePredictor.predictiveCDF`
    /// (Services/CyclePredictor.swift:218) which uses the canonical
    /// scale-not-SD denominator.
    ///
    /// **Closed-form:**
    ///   - P(day d ∈ next menses)
    ///   - = P(L ≤ d ≤ L + m_end)
    ///   - = P(L ∈ [d − m_end, d])
    ///   - = F_t((d − μ)/s) − F_t((d − m_end − μ)/s)
    ///   where F_t is the standardised Student-t CDF.
    ///
    /// Returns a value in [0, 1]. Always 0 when `daysFromCurrentStart < 1`
    /// or when the posterior's df ≤ 2 (predictive scale undefined).
    public func nextMensesProbability(
        forDayOffset daysFromCurrentStart: Int,
        nextCycleMensesEnd m: Int
    ) -> Double {
        precondition(m > 0, "nextCycleMensesEnd must be positive")
        guard daysFromCurrentStart >= 1 else { return 0.0 }
        guard df > 2.0 else { return 0.0 }   // scale undefined for ν ≤ 2

        // Convert SD² (variance) → scale² for the location-scale t.
        // Var(t) = scale² · ν/(ν−2)  ⇒  scale² = variance · (ν−2)/ν.
        let scaleSquared = cycleLength.variance * (df - 2.0) / df
        let scale = scaleSquared.squareRoot()
        guard scale > 0 else {
            // Degenerate posterior — collapse to deterministic indicator.
            let L = Int(cycleLength.mean.rounded())
            return (L <= daysFromCurrentStart && daysFromCurrentStart < L + m) ? 1.0 : 0.0
        }

        let upperT = (Double(daysFromCurrentStart) - cycleLength.mean) / scale
        let lowerT = (Double(daysFromCurrentStart - m) - cycleLength.mean) / scale
        let p = StudentT.cdf(t: upperT, degreesOfFreedom: df)
            - StudentT.cdf(t: lowerT, degreesOfFreedom: df)
        return max(0.0, min(1.0, p))
    }

    /// Build a posterior from the NIG predictor's posterior parameters.
    ///
    /// - Parameters:
    ///   - mensesEnd: observed (Belsey-derived + personal floor).
    ///   - cycleLengthMean: NIG posterior mean (μ_post).
    ///   - cycleLengthPredictiveVariance: NIG posterior predictive variance
    ///     for the next observation, = β(κ+1)/((α−1)κ). Computed by the
    ///     caller from the predictor's current posterior parameters.
    ///   - alphaPost: NIG posterior α (controls Student-t df = 2·α_post).
    ///   - isWidenedRecovery / isOngoingIrregularity: mirror predictor flags.
    public static func from(
        mensesEnd: Int,
        cycleLengthMean: Double,
        cycleLengthPredictiveVariance: Double,
        alphaPost: Double,
        isWidenedRecovery: Bool = false,
        isOngoingIrregularity: Bool = false
    ) -> PhaseBoundariesPosterior {
        let ovMean = cycleLengthMean - Double(PhaseBoundaries.defaultLutealDuration)
        let ovVar = cycleLengthPredictiveVariance + populationLutealVarianceTotal
        return PhaseBoundariesPosterior(
            mensesEnd: mensesEnd,
            ovulationDay: GaussianPosterior(mean: ovMean, variance: ovVar),
            cycleLength: GaussianPosterior(mean: cycleLengthMean,
                                           variance: cycleLengthPredictiveVariance),
            df: 2.0 * alphaPost,
            isWidenedRecovery: isWidenedRecovery,
            isOngoingIrregularity: isOngoingIrregularity
        )
    }
}
