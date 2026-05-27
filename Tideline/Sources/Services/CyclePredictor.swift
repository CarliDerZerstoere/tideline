import Foundation

/// Bayesian predictor for menstrual cycle length.
///
/// Models cycle length as Normal(mu, sigma^2) with a Normal-inverse-gamma
/// conjugate prior over (mu, sigma^2). The posterior is updated in closed form
/// with each observed cycle length. The posterior predictive distribution for
/// the next cycle length is a non-standardized Student's t distribution.
///
/// Reference: Murphy, "Conjugate Bayesian analysis of the Gaussian distribution" (2007).
///
/// This is a pure-math type. No iOS dependencies. Deterministic and Sendable.
public struct CyclePredictor: Sendable, Equatable {

    // MARK: - Hyperparameters (Normal-inverse-gamma)
    //
    //   mu_0:     prior mean of cycle length (days)
    //   kappa_0:  prior "pseudo-observations" weight on mu
    //   alpha_0:  prior shape for sigma^2
    //   beta_0:   prior scale for sigma^2
    //
    // Defaults are calibrated to the verified primary source:
    //   Mahalingaiah et al. 2023 (Apple Women's Health Study,
    //   npj Digital Medicine, PMC10226714, n=165,668 cycles):
    //     population mean 28.7 days, population SD 6.1
    //     within-person SD: 5.33 (under 20), 3.79 (ages 35-39, lowest),
    //                       5.42 (45-49), 11.19 (50+)
    //
    // We use μ₀ = 28.7 as the canonical population mean — this matches
    // CLAUDE.md ("Population prior: μ=28.7 verified from AWHS 2023") and
    // the verified research note. AWHS is preferred over Bull et al. 2019
    // (~29.3) because AWHS includes anovulatory cycles and is closer to
    // the European general-population estimate (~28 days, Scandinavian
    // cohorts). The 0.6-day spread between the two studies washes out
    // after ~3 logged cycles with our κ₀=2 weak prior — see task #94.
    //
    // v2 of the predictor (docs/design/mixture-predictor.md) replaces
    // this point prior with an age-stratified prior + two-component
    // mixture.
    //
    // We start with a weak prior so observations dominate quickly while
    // still preventing pathological estimates from 1-2 cycles of data.

    public var mu: Double         // posterior mean of mu
    public var kappa: Double      // posterior precision weight
    public var alpha: Double      // posterior shape
    public var beta: Double       // posterior scale
    public var observedCount: Int // number of observed cycles
    public var isOngoingIrregularity: Bool // Category E (PCOS etc.) flag
    /// Number of post-soft-reset observations still inside the "recovery"
    /// window. Set to `Self.recoveryWindowLength` in `softReset(...)` and
    /// decremented per `observe(...)`. Distinguishes "low data because
    /// the user just started" (observedCount < 3, recoveryRemaining = 0)
    /// from "low data because we just reset after a Category C/F event"
    /// (observedCount < 3, recoveryRemaining > 0) — the latter is the
    /// user-visible "the estimate will sharpen with new cycles" suffix
    /// in `HeroStateBuilder`. Audit fix #101.
    public var recoveryRemaining: Int

    /// Canonical population prior, age-agnostic. Calibrated to AWHS 2023
    /// lowest-variability within-person SD (35–39 band, σ = 3.79 days).
    ///
    /// Task #158 — math correctness pass: previously used β = α·σ² = 41.07
    /// (= 3 · 3.7²) with a doc-comment claiming "beta/alpha ≈ sigma²" as
    /// if that represented the prior mean of σ². That's wrong for
    /// standard NIG, which has E[σ²] = β/(α−1), not β/α. The corrected
    /// formula is β = (α−1)·σ² so the prior mean of σ² exactly matches
    /// the target σ. With α=3, σ=3.79: β = 2 · 14.36 = 28.72.
    ///
    /// Effect: the prior's predictive 90% CI at N=0 narrows from ~17.6 d
    /// to ~14.4 d. Closer to within-person variability than to total
    /// population-marginal variability — appropriate, since each user is
    /// one person, not a mixture of all users.
    /// Number of post-soft-reset observations during which the predictor is
    /// in the user-visible "recovery window". After this many fresh
    /// observations the posterior is again data-dominated and the
    /// recovery-suffix disappears from the home view. 5 chosen to match
    /// the "first 3–5 logged cycles dominate the posterior post-reset"
    /// language in `docs/design/disrupted-cycles.md`.
    public static let recoveryWindowLength: Int = 5

    public static let populationPrior = CyclePredictor(
        mu: 28.7,
        kappa: 2.0,
        alpha: 3.0,
        // β = (α−1) · σ² with σ = 3.79 (AWHS 35–39 within-person SD).
        // Gives E[σ²] = β/(α−1) = 3.79² = 14.36. Standard NIG conjugate
        // prior derivation per Murphy 2007.
        beta: 2.0 * 3.79 * 3.79,  // = 28.7282
        observedCount: 0,
        recoveryRemaining: 0
    )

    /// Age-stratified population prior (task #97). Same μ across all
    /// bands (AWHS shows population mean is age-invariant) — only β
    /// changes, scaling with the band's within-person SD per the AWHS
    /// table. See `AgeBand.withinPersonSDDays` for sources.
    ///
    /// Formula: β = (α−1) · σ² so that E[σ²] = σ_band². Standard NIG
    /// prior-mean convention (Murphy 2007). Task #158 corrected this
    /// from the previously-wrong β = α · σ² (which had implied E[σ²]
    /// 50% larger than the documented σ).
    public static func populationPrior(for band: AgeBand) -> CyclePredictor {
        let sigma = band.withinPersonSDDays
        return CyclePredictor(
            mu: 28.7,
            kappa: 2.0,
            alpha: 3.0,
            beta: 2.0 * sigma * sigma,
            observedCount: 0,
            recoveryRemaining: 0
        )
    }

    public init(
        mu: Double,
        kappa: Double,
        alpha: Double,
        beta: Double,
        observedCount: Int = 0,
        isOngoingIrregularity: Bool = false,
        recoveryRemaining: Int = 0
    ) {
        self.mu = mu
        self.kappa = kappa
        self.alpha = alpha
        self.beta = beta
        self.observedCount = observedCount
        self.isOngoingIrregularity = isOngoingIrregularity
        self.recoveryRemaining = recoveryRemaining
    }

    // MARK: - Updates

    /// Bayesian update with a single observed cycle length (in days).
    ///
    /// Closed-form Normal-inverse-gamma update for n=1:
    ///   kappa' = kappa + 1
    ///   mu'    = (kappa * mu + x) / kappa'
    ///   alpha' = alpha + 0.5
    ///   beta'  = beta + 0.5 * (kappa / kappa') * (x - mu)^2
    public mutating func observe(cycleLength x: Double) {
        let kappaNew = kappa + 1.0
        let muNew = (kappa * mu + x) / kappaNew
        let alphaNew = alpha + 0.5
        let betaNew = beta + 0.5 * (kappa / kappaNew) * (x - mu) * (x - mu)

        self.mu = muNew
        self.kappa = kappaNew
        self.alpha = alphaNew
        self.beta = betaNew
        self.observedCount += 1
        // Recovery counter — decrement per observation so the
        // "estimate will sharpen with new cycles" suffix disappears
        // automatically once data dominates the prior again. Saturates
        // at zero. Audit fix #101.
        if recoveryRemaining > 0 { recoveryRemaining -= 1 }
    }

    /// Apply a sequence of observed cycle lengths in order.
    public mutating func observe(cycleLengths: [Double]) {
        for x in cycleLengths { observe(cycleLength: x) }
    }

    // MARK: - Posterior predictive

    /// The posterior predictive distribution for the next cycle length is:
    ///   X | data ~ t_{2 alpha} ( mu, beta * (kappa + 1) / (alpha * kappa) )
    /// i.e. a non-standardized Student's t with 2 alpha degrees of freedom,
    /// location mu, and scale sqrt(beta (kappa+1) / (alpha kappa)).
    public var predictiveLocation: Double { mu }

    public var predictiveScale: Double {
        sqrt(beta * (kappa + 1.0) / (alpha * kappa))
    }

    public var predictiveDegreesOfFreedom: Double { 2.0 * alpha }

    /// Point estimate of the next cycle length in days.
    public var nextCycleLengthEstimate: Double { mu }

    /// Symmetric central credible interval for the next cycle length.
    /// Width is +/- `zScore` * predictive scale, with `zScore` derived from
    /// a Student's t quantile; we approximate with a simple table.
    public func nextCycleLengthInterval(confidence: Double = 0.90) -> ClosedRange<Double> {
        let t = StudentT.quantile(confidence: confidence, degreesOfFreedom: predictiveDegreesOfFreedom)
        let half = t * predictiveScale
        return (mu - half)...(mu + half)
    }

    /// Predict the next period start date, given the last known period start.
    ///
    /// Uses `Date.addingDays(_:)` (calendar arithmetic for the integer-day
    /// component) so a DST transition inside the prediction horizon does
    /// not silently shift the predicted calendar day by an hour — which,
    /// at moments near midnight, would surface as a wrong wall-clock date
    /// in the UI. Audit task #99.
    public func nextPeriodDate(after lastPeriodStart: Date) -> Date {
        lastPeriodStart.addingDays(nextCycleLengthEstimate)
    }

    /// Predict the next period start as a confidence band of dates.
    public func nextPeriodDateInterval(
        after lastPeriodStart: Date,
        confidence: Double = 0.90
    ) -> ClosedRange<Date> {
        let range = nextCycleLengthInterval(confidence: confidence)
        let low = lastPeriodStart.addingDays(range.lowerBound)
        let high = lastPeriodStart.addingDays(range.upperBound)
        return low...high
    }

    // MARK: - CDF and conditional prediction

    /// Cumulative posterior predictive probability: P(next cycle length ≤ x).
    /// Uses the location-scale Student's-t with df = 2α, location = μ, scale = predictiveScale.
    public func predictiveCDF(cycleLength x: Double) -> Double {
        let t = (x - predictiveLocation) / predictiveScale
        return StudentT.cdf(t: t, degreesOfFreedom: predictiveDegreesOfFreedom)
    }

    /// Conditional probability that the next period starts on or before day `x`,
    /// given that no period has occurred yet at `currentDay`.
    ///
    /// This is the core late-period math: as `currentDay` advances past μ, the
    /// conditional distribution shifts right and stretches, correctly representing
    /// the growing uncertainty.
    public func conditionalCDF(cycleLength x: Double, currentDay D: Double) -> Double {
        let FD = predictiveCDF(cycleLength: D)
        // Guard aligned with `inverseConditionalCDF`'s degeneracy threshold
        // (audit task #108). Before, this returned 1.0 at FD > 0.9999 while
        // the inverse function only bailed out at FD > 0.99999 — that
        // 0.9999 < FD < 0.99999 band caused bisection to collapse to a
        // zero-width interval at moderate-late D (e.g. D=45 with μ=29).
        guard FD < 0.99999 else { return 1.0 }
        let Fx = predictiveCDF(cycleLength: x)
        return max(0, min(1, (Fx - FD) / (1 - FD)))
    }

    /// Conditional credible interval given the cycle has already reached `currentDay`
    /// without a period starting. Returns a range of days-from-last-period.
    ///
    /// Numerically inverts the conditional CDF via binary search.
    public func conditionalInterval(
        currentDay D: Double,
        confidence: Double = 0.90
    ) -> ClosedRange<Double> {
        let lowerTarget = (1 - confidence) / 2
        let upperTarget = 1 - lowerTarget
        let lower = inverseConditionalCDF(target: lowerTarget, currentDay: D)
        let upper = inverseConditionalCDF(target: upperTarget, currentDay: D)
        return lower...upper
    }

    /// Binary-search inverse of `conditionalCDF`. Tolerance: 0.01 days.
    ///
    /// Bug fix (audit task #108): the old loop guarded on
    /// `predictiveCDF(hi) < 0.999`, which is the WRONG criterion — it's
    /// about the unconditional marginal CDF, not the conditional one we
    /// actually need to cross. At very late `D` (say D ≥ μ+30), the
    /// marginal `predictiveCDF(hi)` is already saturated near 1.0 for
    /// any `hi ≥ D`, so the expansion loop exited immediately and `hi`
    /// stayed pinned at `max(D+1, μ+30)`. Bisection then produced a
    /// laughably narrow interval (often [D, D+1]). The correct stopping
    /// criterion is `conditionalCDF(hi, D) >= target` — we expand `hi`
    /// until the conditional density we care about has crossed it.
    ///
    /// We also add an explicit degeneracy guard for the case where
    /// `predictiveCDF(D)` is so close to 1.0 that the conditional CDF
    /// loses numerical resolution — return a safe ~30-day fallback.
    private func inverseConditionalCDF(target: Double, currentDay D: Double) -> Double {
        // Degeneracy guard: if (1 - F(D)) underflows float resolution,
        // the conditional distribution is no longer expressible. Return
        // a meaningful fallback that still produces a non-zero interval:
        // low-target (lower bound of CI) → D, high-target (upper bound) →
        // D+30. This degenerate case shouldn't normally surface — the
        // late-mode UI is expected to suppress the date display at that
        // point — but if it does, a 30-day fallback range is honest
        // ("we genuinely don't know").
        let FD = predictiveCDF(cycleLength: D)
        guard FD < 0.99999 else {
            return target < 0.5 ? D : D + 30.0
        }

        var lo = D                          // can't be earlier than today
        var hi = max(D + 1, mu + 30)        // generous initial upper bound

        // Expand hi until the CONDITIONAL CDF (not the marginal) reaches
        // the target. 15-day steps with a 180-day safety cap — plenty of
        // room for the upper percentile of any plausible cycle, and we
        // never return something pretending to predict more than 6 months
        // out (at which point we'd be in late-period "no clear estimate"
        // territory anyway).
        while conditionalCDF(cycleLength: hi, currentDay: D) < target {
            hi += 15.0
            if hi > D + 180.0 { return hi }
        }

        // Bisection. 30 iterations give ~1e-9 day precision — overkill,
        // but cheap.
        for _ in 0..<30 {
            let mid = 0.5 * (lo + hi)
            if hi - lo < 0.01 { return mid }
            if conditionalCDF(cycleLength: mid, currentDay: D) < target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return 0.5 * (lo + hi)
    }

    // MARK: - State resets

    /// True while the predictor is still in the high-uncertainty window after
    /// a soft reset (Category C or F event). The window is set to
    /// `Self.recoveryWindowLength` (= 5) observations on softReset and
    /// decrements per `observe(...)`. Callers (`HeroStateBuilder`) use this
    /// to show the "estimate will sharpen with new cycles" suffix.
    ///
    /// **Distinct from low-data fallback**: a brand-new predictor has
    /// `observedCount == 0` AND `recoveryRemaining == 0`. The hero shows
    /// the "Wir lernen deinen Rhythmus kennen" message. A post-soft-reset
    /// predictor has `observedCount == 0` AND `recoveryRemaining > 0` —
    /// the hero shows the calibrated interval PLUS the recovery suffix
    /// because the user previously had history; we're just rebuilding
    /// confidence from a known μ. Audit fix #101.
    public var isInRecoveryWindow: Bool { recoveryRemaining > 0 }

    /// Soft reset after a recoverable disruption event (Category C in
    /// docs/design/disrupted-cycles.md).
    ///
    /// Preserves μ as a "location hint" — the user's body probably still has
    /// roughly their pre-event mean cycle. Resets confidence (κ → 2) and
    /// variance estimate (α, β → prior values) so the first 3-5 cycles
    /// post-event dominate the posterior quickly.
    public mutating func softReset() {
        softReset(forBand: .unspecified)
    }

    /// Age-band-aware soft reset (task #162). Routes through the band's
    /// AWHS σ so a Category C event for a menopausal user (σ=11.19)
    /// resets to that band's prior (β≈250) instead of collapsing to the
    /// reproductive band's β=28.7282.
    ///
    /// Default-arg `softReset()` resolves to `.unspecified` band (σ=5.0,
    /// β=50.0) — backward-compatible widened-fallback.
    public mutating func softReset(forBand band: AgeBand) {
        // mu: keep — pre-event mean is still our best location hint
        self.kappa = 2.0
        self.alpha = 3.0
        // β = (α−1) · σ² with σ from the user's declared age band.
        // Standard NIG conjugate-prior derivation per Murphy 2007 (task
        // #158 math correction).
        //
        // Pillar-3 tension (explicitly accepted, task #158): a tighter
        // band-appropriate β still makes the first 1–3 cycles post-event
        // publish a narrower CI than a maximally-diffuse prior would.
        // For users in vulnerable states (post-miscarriage) this trades
        // "Pillar 3 honesty about uncertainty" for "math + clinical
        // honesty about the user's actual within-person variability."
        // The clinical case dominates: a menopausal user's high σ
        // should NOT be reset to reproductive-band σ just because she
        // logged a Category C event.
        let sigma = band.withinPersonSDDays
        self.beta = 2.0 * sigma * sigma
        self.observedCount = 0
        // Audit fix #101 — enter the recovery window so the UI can
        // surface the "estimate will sharpen with new cycles" suffix.
        // Distinct from cold-start low-data (observedCount=0 + recovery=0).
        self.recoveryRemaining = Self.recoveryWindowLength
    }

    /// Widen the variance prior for users who have declared ongoing irregularity
    /// (Category E: PCOS, recovering eating disorder, etc.). Multiplies β by 2.5,
    /// which corresponds to ~1.58x wider posterior SD.
    public mutating func declareOngoingIrregularity() {
        self.beta *= 2.5
        self.isOngoingIrregularity = true
    }
}

// MARK: - Student's t quantile (lightweight approximation)

enum StudentT {
    /// Two-sided quantile: the value t such that P(|T| <= t) = confidence,
    /// where T ~ Student t with the given degrees of freedom.
    ///
    /// Uses a small table for common confidences and the standard normal
    /// approximation for large df. Sufficient for cycle-prediction UX where
    /// df grows quickly (df = 2 * alpha = 6 + observedCount with default prior).
    static func quantile(confidence: Double, degreesOfFreedom df: Double) -> Double {
        let p = max(0.5, min(0.999, confidence))

        // Normal approximation: for df > 30 the t distribution is close to normal.
        if df >= 30 {
            return Normal.quantile(twoSided: p)
        }

        // Snap to nearest tabulated confidence.
        let nearest = tableConfidences.min(by: { abs($0 - p) < abs($1 - p) }) ?? 0.90
        let row = quantileTable[nearest]!
        return interpolate(x: df, xs: row.df, ys: row.t)
    }

    private static let quantileTable: [Double: (df: [Double], t: [Double])] = [
        0.80: (df: [1, 2, 3, 5, 10, 20, 30], t: [3.078, 1.886, 1.638, 1.476, 1.372, 1.325, 1.310]),
        0.90: (df: [1, 2, 3, 5, 10, 20, 30], t: [6.314, 2.920, 2.353, 2.015, 1.812, 1.725, 1.697]),
        0.95: (df: [1, 2, 3, 5, 10, 20, 30], t: [12.706, 4.303, 3.182, 2.571, 2.228, 2.086, 2.042]),
        0.99: (df: [1, 2, 3, 5, 10, 20, 30], t: [63.657, 9.925, 5.841, 4.032, 3.169, 2.845, 2.750]),
    ]
    private static let tableConfidences: [Double] = [0.80, 0.90, 0.95, 0.99]

    private static func interpolate(x: Double, xs: [Double], ys: [Double]) -> Double {
        if x <= xs.first! { return ys.first! }
        if x >= xs.last! { return ys.last! }
        for i in 0..<(xs.count - 1) {
            let x0 = xs[i], x1 = xs[i + 1]
            if x >= x0 && x <= x1 {
                let frac = (x - x0) / (x1 - x0)
                return ys[i] + frac * (ys[i + 1] - ys[i])
            }
        }
        return ys.last!
    }

    /// Cumulative distribution function of the standard Student's-t.
    /// For df ≥ 30 falls back to the standard normal CDF (negligible error).
    /// For smaller df uses the regularized incomplete beta function via a
    /// simple continued-fraction expansion — accurate to ~1e-6, more than
    /// enough for cycle-prediction UX.
    static func cdf(t: Double, degreesOfFreedom df: Double) -> Double {
        if df >= 30 {
            return Normal.cdf(t)
        }
        // Use the relationship: P(T ≤ t) = 1 - 0.5 * I_x(df/2, 1/2) where x = df/(df+t²), for t ≥ 0
        // Symmetry: for t < 0, P(T ≤ t) = 0.5 * I_x(df/2, 1/2)
        let x = df / (df + t * t)
        let halfIncomplete = 0.5 * regularizedIncompleteBeta(a: df / 2.0, b: 0.5, x: x)
        return t >= 0 ? 1.0 - halfIncomplete : halfIncomplete
    }

    /// Regularized incomplete beta function I_x(a, b) via continued fraction.
    /// Numerical Recipes-style implementation; converges in <100 iters for
    /// reasonable inputs.
    private static func regularizedIncompleteBeta(a: Double, b: Double, x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let logBt = lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1.0 - x)
        let bt = exp(logBt)
        if x < (a + 1) / (a + b + 2) {
            return bt * betacf(a: a, b: b, x: x) / a
        } else {
            return 1.0 - bt * betacf(a: b, b: a, x: 1.0 - x) / b
        }
    }

    private static func betacf(a: Double, b: Double, x: Double) -> Double {
        let eps = 3.0e-7
        let fpmin = 1.0e-30
        let qab = a + b
        let qap = a + 1
        let qam = a - 1
        var c = 1.0
        var d = 1.0 - qab * x / qap
        if abs(d) < fpmin { d = fpmin }
        d = 1.0 / d
        var h = d
        for m in 1...100 {
            let m2 = 2 * m
            var aa = Double(m) * (b - Double(m)) * x / ((qam + Double(m2)) * (a + Double(m2)))
            d = 1.0 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1.0 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1.0 / d
            h *= d * c
            aa = -(a + Double(m)) * (qab + Double(m)) * x / ((a + Double(m2)) * (qap + Double(m2)))
            d = 1.0 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1.0 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1.0 / d
            let del = d * c
            h *= del
            if abs(del - 1.0) < eps { return h }
        }
        return h
    }
}

// MARK: - Standard normal quantile

enum Normal {
    /// Two-sided quantile of the standard normal: z such that P(|Z| <= z) = p.
    /// Uses Beasley-Springer-Moro approximation (one-sided), good to ~1e-7.
    static func quantile(twoSided p: Double) -> Double {
        let alpha = 0.5 * (1.0 + p) // one-sided upper tail target
        return inverseStandardNormalCDF(alpha)
    }

    /// Standard normal CDF using the error function.
    static func cdf(_ z: Double) -> Double {
        return 0.5 * (1.0 + erf(z / sqrt(2.0)))
    }

    private static func inverseStandardNormalCDF(_ p: Double) -> Double {
        // Beasley-Springer-Moro.
        let a: [Double] = [
            -3.969683028665376e+01,
             2.209460984245205e+02,
            -2.759285104469687e+02,
             1.383577518672690e+02,
            -3.066479806614716e+01,
             2.506628277459239e+00,
        ]
        let b: [Double] = [
            -5.447609879822406e+01,
             1.615858368580409e+02,
            -1.556989798598866e+02,
             6.680131188771972e+01,
            -1.328068155288572e+01,
        ]
        let c: [Double] = [
            -7.784894002430293e-03,
            -3.223964580411365e-01,
            -2.400758277161838e+00,
            -2.549732539343734e+00,
             4.374664141464968e+00,
             2.938163982698783e+00,
        ]
        let d: [Double] = [
             7.784695709041462e-03,
             3.224671290700398e-01,
             2.445134137142996e+00,
             3.754408661907416e+00,
        ]
        let plow = 0.02425
        let phigh = 1.0 - plow

        if p < plow {
            let q = sqrt(-2.0 * log(p))
            return (((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]) /
                   ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1.0)
        } else if p <= phigh {
            let q = p - 0.5
            let r = q * q
            return (((((a[0]*r + a[1])*r + a[2])*r + a[3])*r + a[4])*r + a[5]) * q /
                   (((((b[0]*r + b[1])*r + b[2])*r + b[3])*r + b[4])*r + 1.0)
        } else {
            let q = sqrt(-2.0 * log(1.0 - p))
            return -(((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]) /
                    ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1.0)
        }
    }
}
