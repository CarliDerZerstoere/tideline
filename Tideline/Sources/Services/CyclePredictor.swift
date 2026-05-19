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
    // Defaults are calibrated from primary-source population data:
    //   Mahalingaiah et al. 2023 (Apple Women's Health Study,
    //   npj Digital Medicine, PMC10226714, n=165,668 cycles):
    //     population mean 28.7 days, population SD 6.1
    //     within-person SD: 5.33 (under 20), 3.79 (ages 35-39, lowest),
    //                       5.42 (45-49), 11.19 (50+)
    //   Bull et al. 2019 (Natural Cycles, npj Digital Medicine,
    //   ~600K cycles): mean 29.3 days.
    //
    // The default prior here uses μ=29 (intermediate between the two)
    // and β tuned for ~3.7-day SD as a default. v2 of the predictor
    // (see docs/design/mixture-predictor.md) replaces this with an
    // age-stratified prior + two-component mixture.
    //
    // We start with a weak prior so observations dominate quickly while
    // still preventing pathological estimates from 1-2 cycles of data.

    public var mu: Double         // posterior mean of mu
    public var kappa: Double      // posterior precision weight
    public var alpha: Double      // posterior shape
    public var beta: Double       // posterior scale
    public var observedCount: Int // number of observed cycles

    public static let populationPrior = CyclePredictor(
        mu: 29.0,
        kappa: 2.0,
        alpha: 3.0,
        beta: 3.0 * 13.69, // beta/alpha ≈ sigma^2 ≈ 3.7^2
        observedCount: 0
    )

    public init(
        mu: Double,
        kappa: Double,
        alpha: Double,
        beta: Double,
        observedCount: Int = 0
    ) {
        self.mu = mu
        self.kappa = kappa
        self.alpha = alpha
        self.beta = beta
        self.observedCount = observedCount
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
    public func nextPeriodDate(after lastPeriodStart: Date) -> Date {
        lastPeriodStart.addingTimeInterval(nextCycleLengthEstimate * 86_400)
    }

    /// Predict the next period start as a confidence band of dates.
    public func nextPeriodDateInterval(
        after lastPeriodStart: Date,
        confidence: Double = 0.90
    ) -> ClosedRange<Date> {
        let range = nextCycleLengthInterval(confidence: confidence)
        let low = lastPeriodStart.addingTimeInterval(range.lowerBound * 86_400)
        let high = lastPeriodStart.addingTimeInterval(range.upperBound * 86_400)
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
        guard FD < 0.9999 else { return 1.0 }
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
    private func inverseConditionalCDF(target: Double, currentDay D: Double) -> Double {
        var lo = D                          // can't be earlier than today
        var hi = max(D + 1, mu + 30)        // generous upper bound
        // Expand hi until the conditional CDF reaches the target
        while predictiveCDF(cycleLength: hi) < 0.999 && conditionalCDF(cycleLength: hi, currentDay: D) < target {
            hi += 30
            if hi > D + 365 { return hi }   // hard ceiling: 1 year out
        }
        for _ in 0..<60 {                   // ~10^-18 precision in 60 bisections; plenty
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

    /// Soft reset after a recoverable disruption event (Category C in
    /// docs/design/disrupted-cycles.md).
    ///
    /// Preserves μ as a "location hint" — the user's body probably still has
    /// roughly their pre-event mean cycle. Resets confidence (κ → 2) and
    /// variance estimate (α, β → prior values) so the first 3-5 cycles
    /// post-event dominate the posterior quickly.
    public mutating func softReset() {
        // mu: keep — pre-event mean is still our best location hint
        self.kappa = 2.0
        self.alpha = 3.0
        self.beta = 41.07            // matches within-person SD ~3.7 days
        self.observedCount = 0
    }

    /// Widen the variance prior for users who have declared ongoing irregularity
    /// (Category E: PCOS, recovering eating disorder, etc.). Multiplies β by 2.5,
    /// which corresponds to ~1.58x wider posterior SD.
    public mutating func declareOngoingIrregularity() {
        self.beta *= 2.5
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

        // Table for common confidences and small df, linearly interpolated.
        let key: [Double: (df: [Double], t: [Double])] = [
            0.80: (df: [1, 2, 3, 5, 10, 20, 30], t: [3.078, 1.886, 1.638, 1.476, 1.372, 1.325, 1.310]),
            0.90: (df: [1, 2, 3, 5, 10, 20, 30], t: [6.314, 2.920, 2.353, 2.015, 1.812, 1.725, 1.697]),
            0.95: (df: [1, 2, 3, 5, 10, 20, 30], t: [12.706, 4.303, 3.182, 2.571, 2.228, 2.086, 2.042]),
            0.99: (df: [1, 2, 3, 5, 10, 20, 30], t: [63.657, 9.925, 5.841, 4.032, 3.169, 2.845, 2.750]),
        ]

        // Snap to nearest tabulated confidence.
        let confs = Array(key.keys).sorted()
        let nearest = confs.min(by: { abs($0 - p) < abs($1 - p) }) ?? 0.90
        let row = key[nearest]!
        return interpolate(x: df, xs: row.df, ys: row.t)
    }

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
        let bt = exp(
            lgamma(a + b) - lgamma(a) - lgamma(b)
            + a * log(x) + b * log(1.0 - x)
        )
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
