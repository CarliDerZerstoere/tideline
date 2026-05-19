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
    // Defaults are calibrated from population data (Grieger et al. 2019,
    // >600K cycles): mean ~29 days, SD ~3.7 days. We start with a weak prior
    // so observations dominate quickly while still preventing pathological
    // estimates from 1–2 cycles of data.

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
}

// MARK: - Standard normal quantile

enum Normal {
    /// Two-sided quantile of the standard normal: z such that P(|Z| <= z) = p.
    /// Uses Beasley-Springer-Moro approximation (one-sided), good to ~1e-7.
    static func quantile(twoSided p: Double) -> Double {
        let alpha = 0.5 * (1.0 + p) // one-sided upper tail target
        return inverseStandardNormalCDF(alpha)
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
