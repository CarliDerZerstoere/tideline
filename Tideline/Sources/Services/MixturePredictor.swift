import Foundation

/// 2-component Bayesian mixture predictor for menstrual cycle length.
///
/// Implements the design in `docs/design/mixture-predictor.md`:
///
///   L ~ π · Normal(μ₁, σ₁²)              (ovulatory)
///     + (1−π) · LogNormal(μ₂, σ₂²; δ=14) (anovulatory, shifted)
///
/// Component 2 is parameterised in log-space: `y = log(L − δ) ~ Normal(μ₂, σ₂²)`.
/// The original-scale density of component 2 carries the Jacobian factor
/// `1/(L − δ)`, equivalently `−log(L − δ)` in log-space — **omitting this
/// biases the assignment step** and is the subtle math bug the design doc
/// flags.
///
/// Inference: Gibbs sampling (200 iterations, 100 burn-in). Each iteration:
///   1. Sample latent assignment S_t ∈ {1,2} per observation from the
///      posterior conditional (log-space softmax for numerical stability).
///   2. NIG conjugate update on observations assigned to each component.
///   3. Sample new (μ_k, σ_k²) from the resulting NIG posterior.
///   4. Beta-Binomial update on π given the assignment counts.
///
/// Label switching is mitigated via assignment initialisation (short cycles
/// → component 1, long → component 2) plus strong well-separated priors.
/// The design doc's per-iteration swap is not implemented because the two
/// components live in different parameterisations (days vs. log-days);
/// instead we rely on prior separation and verify empirically via tests.
///
/// References:
///   - Diebolt & Robert (1994), JRSS-B 56(2): Bayesian sampling for mixtures
///   - Geman & Geman (1984), IEEE PAMI 6(6): Gibbs sampling
///   - Frühwirth-Schnatter (2006), "Finite Mixture and Markov Switching Models"
///
/// This is a pure-math type. No iOS dependencies. Deterministic given the
/// `seed:` argument.
///
/// **Empty-posterior return contract (Session 5 / #215):** all methods that
/// derive values from `posteriorSamples` return `Optional` (`Double?` or
/// `ClosedRange<Double>?`) and yield `nil` when the chain hasn't produced
/// samples yet. Pillar-3 aligned — explicit empty signalling rather than
/// silent NaN propagation or degenerate `0...0` ranges.
public struct MixturePredictor: Sendable, Equatable {

    // MARK: - Shift parameter

    /// Lower-bound offset for the shifted log-normal component, in days.
    /// Set to 14 (not 15) so legitimate ~15-day spotting-to-bleed
    /// intervals don't produce log(0) if accidentally routed to
    /// component 2. Component 1's effective floor stays at 15 via the
    /// truncation in the original design.
    public static let delta: Double = 14.0

    /// Hard threshold above which cycles are definitionally nonstandard
    /// (Harlow & Zeger 1991, PMID 1940994). In the Gibbs sampler,
    /// observations at or above this value are deterministically routed
    /// to component 2 instead of being soft-assigned. This both reflects
    /// the literature definition and prevents a stable label-switched
    /// bad mode where a wide σ²₁ draw lets component 1 absorb long
    /// cycles. 43 days is the Harlow-Zeger boundary cited verbatim in
    /// the design doc's References section.
    public static let nonstandardThreshold: Double = 43.0

    // MARK: - Prior hyperparameters

    /// Component 1 (ovulatory, Normal in days) prior.
    public var mu1Prior: Double
    public var kappa1Prior: Double
    public var alpha1Prior: Double
    public var beta1Prior: Double

    /// Component 2 (anovulatory, Normal in log(L−δ)) prior.
    public var mu2Prior: Double
    public var kappa2Prior: Double
    public var alpha2Prior: Double
    public var beta2Prior: Double

    /// Beta prior for the mixing weight π = P(next cycle ovulatory).
    /// Baseline `Beta(8, 2)` → E[π] = 0.80 from AWHS proportions.
    public var piAlphaPrior: Double
    public var piBetaPrior: Double

    // MARK: - Observed data

    /// Observed cycle lengths in days. Order doesn't matter (mixture model
    /// is exchangeable in v1; HMM extension to v1.5 will need order).
    public var observations: [Double]

    /// Posterior samples collected after the most recent Gibbs run.
    /// Empty until `runGibbs()` has been called with non-zero observations.
    public var posteriorSamples: [PosteriorSample]

    /// Assignment-stability diagnostic from the last Gibbs run: fraction of
    /// observations whose assignment was identical between consecutive
    /// post-burn-in iterations, averaged over those iterations. A value
    /// `< 0.9` flags convergence concerns per the design doc.
    public var assignmentStability: Double

    public var observedCount: Int { observations.count }

    // MARK: - Single posterior draw

    public struct PosteriorSample: Sendable, Equatable {
        /// Component 1 mean (days).
        public let mu1: Double
        /// Component 1 variance (days²).
        public let sigma1Sq: Double
        /// Component 2 location parameter (log-space, i.e. mean of log(L−δ)).
        public let mu2: Double
        /// Component 2 spread parameter (log-space variance of log(L−δ)).
        public let sigma2Sq: Double
        /// Mixing weight: probability the next cycle is from component 1.
        public let pi: Double

        public init(mu1: Double, sigma1Sq: Double, mu2: Double, sigma2Sq: Double, pi: Double) {
            self.mu1 = mu1
            self.sigma1Sq = sigma1Sq
            self.mu2 = mu2
            self.sigma2Sq = sigma2Sq
            self.pi = pi
        }

        /// Expected cycle length under this single posterior draw, in days.
        /// Jensen-corrected mean of the shifted log-normal: `exp(μ + σ²/2) + δ`.
        public var expectedCycleLength: Double {
            let comp2Mean = exp(mu2 + 0.5 * sigma2Sq) + MixturePredictor.delta
            return pi * mu1 + (1 - pi) * comp2Mean
        }
    }

    // MARK: - Init

    public init(
        mu1Prior: Double,
        kappa1Prior: Double,
        alpha1Prior: Double,
        beta1Prior: Double,
        mu2Prior: Double,
        kappa2Prior: Double,
        alpha2Prior: Double,
        beta2Prior: Double,
        piAlphaPrior: Double,
        piBetaPrior: Double,
        observations: [Double] = [],
        posteriorSamples: [PosteriorSample] = [],
        assignmentStability: Double = 1.0
    ) {
        self.mu1Prior = mu1Prior
        self.kappa1Prior = kappa1Prior
        self.alpha1Prior = alpha1Prior
        self.beta1Prior = beta1Prior
        self.mu2Prior = mu2Prior
        self.kappa2Prior = kappa2Prior
        self.alpha2Prior = alpha2Prior
        self.beta2Prior = beta2Prior
        self.piAlphaPrior = piAlphaPrior
        self.piBetaPrior = piBetaPrior
        self.observations = observations
        self.posteriorSamples = posteriorSamples
        self.assignmentStability = assignmentStability
    }

    // MARK: - Canonical priors

    /// Baseline population prior, age-agnostic.
    ///
    /// Component 1: μ₁=28.7, σ₁=3.79 (AWHS 35–39 within-person SD), α=3.
    ///   β = (α−1)·σ² = 2 · 3.79² = 28.7282.
    /// Component 2: μ₂=log(25)≈3.22, σ₂=0.45, α=3.
    ///   β = (α−1)·σ² = 2 · 0.45² = 0.405.
    /// Mixing weight: Beta(8, 2) → E[π]=0.80 from AWHS proportions
    /// (86% in 24–38, 5% >38, 9% <24 — the >38 portion seeds component 2).
    public static let populationPrior = MixturePredictor(
        mu1Prior: 28.7,
        kappa1Prior: 2.0,
        alpha1Prior: 3.0,
        beta1Prior: 2.0 * 3.79 * 3.79,
        mu2Prior: log(25.0),
        kappa2Prior: 2.0,
        alpha2Prior: 3.0,
        beta2Prior: 2.0 * 0.45 * 0.45,
        piAlphaPrior: 8.0,
        piBetaPrior: 2.0
    )

    /// Age-stratified prior. Only component 1's σ₁ shifts per band; the
    /// anovulatory component-2 prior stays at the population baseline
    /// because anovulatory cycles' tail behaviour is governed more by
    /// hormonal-irregularity prevalence than by age within reproductive
    /// years.
    public static func populationPrior(for band: AgeBand) -> MixturePredictor {
        let sigma1 = band.withinPersonSDDays
        var prior = populationPrior
        prior.beta1Prior = 2.0 * sigma1 * sigma1
        return prior
    }

    // MARK: - Recovery profile (Phase 3 / #194)

    /// Re-prime priors for the next cycle's predictions given an
    /// event-specific recovery profile. Implements the design doc's
    /// "Per-event recovery profiles" semantics:
    ///   - Component 1 μ₁ prior shifts by `profile.mu1Offset`
    ///   - Component 1 σ₁ prior widens so `E[σ₁²] = sigma1Cycle1²`
    ///   - Mixing weight π prior shifts toward `profile.piPriorMean`
    ///     (keeping total prior weight ≈ 10)
    ///
    /// **Observations are preserved.** Mirrors Session 1's H1 decision:
    /// a single Category C event doesn't erase the user's accumulated
    /// long-run cycle history. The profile shapes the *prior* for the
    /// next cycle's predictions; existing observations still inform the
    /// posterior. Posterior samples are cleared so the next pattern /
    /// interval read re-runs Gibbs against the new prior.
    ///
    /// **`profile.sigma1Cycle2` is read but NOT yet applied here.** The
    /// design doc's per-cycle tapering trajectory (cycle 1 wide, cycle
    /// 2 narrower, cycles 3+ approaching baseline) would require
    /// re-applying a tapered profile on each `observe()` inside the
    /// recovery window. That's a Phase 3.1 follow-up. For v1, σ₁ stays
    /// at `sigma1Cycle1` for the full recovery window; data dominates
    /// the prior after cycle 1 in practice for high-N users, mitigating
    /// the deferred tapering's impact.
    ///
    /// **κ₁_prior is NOT inflated.** The recovery profile's effective
    /// prior weight stays at κ₁=2 (Session 1 default). For users with
    /// 24+ observations, this means the prior shift is largely swamped
    /// by data — the profile is most impactful for users in the 12–18
    /// cycle range. Deliberate: see design doc § "Per-event recovery
    /// profiles (implementation)" for the trade-off rationale.
    ///
    /// PCOS-Beta(3,5) and ongoing-irregularity priors are NOT recovery
    /// profiles — those are persistent state set elsewhere. Recovery
    /// profiles are transient (cleared by `PredictorService` after
    /// `cyclesToBaseline` observations).
    public mutating func applyRecoveryProfile(_ profile: RecoveryProfile) {
        mu1Prior += profile.mu1Offset
        // β = (α−1)·σ² so that E[σ²] = σ² under NIG. Matches the
        // Murphy 2007 convention used in `CyclePredictor` and the
        // canonical priors above.
        beta1Prior = (alpha1Prior - 1.0) * profile.sigma1Cycle1 * profile.sigma1Cycle1
        // π prior with effective total weight 10: a Beta(π·10, (1−π)·10)
        // has E[π] = piPriorMean and concentrates similarly to the
        // baseline Beta(8, 2).
        let totalWeight = 10.0
        piAlphaPrior = profile.piPriorMean * totalWeight
        piBetaPrior = (1.0 - profile.piPriorMean) * totalWeight
        // Invalidate cached posterior — next read will re-run Gibbs
        // with the new prior shaping the chain initialisation.
        posteriorSamples = []
        assignmentStability = 1.0
    }

    // MARK: - Observations

    /// Append a new observed cycle length and invalidate cached samples.
    /// Caller must invoke `runGibbs(...)` to refit before reading posterior.
    public mutating func observe(cycleLength x: Double) {
        observations.append(x)
        posteriorSamples = []
    }

    public mutating func observe(cycleLengths xs: [Double]) {
        observations.append(contentsOf: xs)
        posteriorSamples = []
    }

    // MARK: - Gibbs sampler

    /// Run the Gibbs sampler over the currently observed cycles.
    ///
    /// - Parameters:
    ///   - iterations: Total Gibbs iterations including burn-in.
    ///   - burnIn: Iterations discarded before collecting samples.
    ///   - seed: Deterministic random seed.
    ///
    /// Post-condition: `posteriorSamples` populated with `iterations −
    /// burnIn` samples, `assignmentStability` recorded.
    public mutating func runGibbs(iterations: Int = 200, burnIn: Int = 100, seed: UInt64 = 42) {
        guard !observations.isEmpty else {
            posteriorSamples = []
            assignmentStability = 1.0
            return
        }

        var rng = MixtureRNG(seed: seed)
        let n = observations.count

        // Initialise assignments heuristically — shorter cycles to
        // component 1, longer to component 2 (Harlow & Zeger 1991
        // threshold). Stabilises the chain so strong priors aren't
        // fighting an adversarial initial labelling.
        var s = [Int](repeating: 1, count: n)
        for t in 0..<n {
            s[t] = observations[t] >= 43.0 ? 2 : 1
        }

        // Initialise (s1, s2, π) by running one NIG update + Beta-Binomial
        // update GIVEN the heuristic assignments — *not* from raw priors.
        //
        // Why this matters: an unlucky prior sample of σ²₁ can occasionally
        // draw very wide (Gamma right-tail), letting component 1 look like
        // a broad Gaussian that explains both ovulatory and anovulatory
        // cycles. The first assignment step then mis-routes anovulatory
        // cycles to component 1, the comp-1 NIG absorbs them, and Gibbs
        // gets stuck in a bad mode (label-switched fixed point).
        //
        // Anchoring on the heuristic assignments forces the initial
        // comp-1 posterior to be tight around short cycles and comp-2
        // tight around long cycles, before any assignment-resampling
        // happens.
        var s1 = nigUpdateAndSample(
            comp: 1,
            assignments: s,
            observations: observations,
            muPrior: mu1Prior, kappaPrior: kappa1Prior,
            alphaPrior: alpha1Prior, betaPrior: beta1Prior,
            rng: &rng
        )
        var s2 = nigUpdateAndSample(
            comp: 2,
            assignments: s,
            observations: observations,
            muPrior: mu2Prior, kappaPrior: kappa2Prior,
            alphaPrior: alpha2Prior, betaPrior: beta2Prior,
            rng: &rng
        )
        var n1Init = 0
        for t in 0..<n where s[t] == 1 { n1Init += 1 }
        var piCur = sampleBeta(
            alpha: piAlphaPrior + Double(n1Init),
            beta: piBetaPrior + Double(n - n1Init),
            rng: &rng
        )

        var samples: [PosteriorSample] = []
        samples.reserveCapacity(max(0, iterations - burnIn))

        var stabilityHits = 0
        var stabilityTotal = 0
        var prevAssignmentsForStability: [Int]? = nil

        for iter in 0..<iterations {
            // 1. Sample assignments per observation.
            //
            // Cycles ≥ `nonstandardThreshold` (43 days) are deterministically
            // routed to component 2 — they are definitionally nonstandard
            // per Harlow & Zeger 1991 (PMID 1940994). This also prevents
            // label switching: without the hard cap, a wide σ²₁ draw can
            // let component 1 absorb long cycles, creating a stable bad
            // fixed-point. The cap pins component 1 to the ovulatory
            // regime as the design doc intends.
            for t in 0..<n {
                let L = observations[t]
                if L >= Self.nonstandardThreshold {
                    s[t] = 2
                    continue
                }
                let logP1 = log(piCur) + normalLogPdf(x: L, mu: s1.mu, sigmaSq: s1.sigmaSq)
                let logP2: Double
                if L > Self.delta {
                    let y = log(L - Self.delta)
                    let yLogPdf = normalLogPdf(x: y, mu: s2.mu, sigmaSq: s2.sigmaSq)
                    // Jacobian: shifted-log-normal density in original
                    // scale is (1/(L−δ)) · φ(log(L−δ); μ₂, σ₂²). In
                    // log-space that's `yLogPdf − log(L − δ)`.
                    logP2 = log(1 - piCur) + yLogPdf - log(L - Self.delta)
                } else {
                    logP2 = -.infinity
                }
                let m = max(logP1, logP2)
                let p1Norm: Double
                if m.isFinite {
                    let e1 = exp(logP1 - m)
                    let e2 = exp(logP2 - m)
                    p1Norm = e1 / (e1 + e2)
                } else {
                    p1Norm = 0.5
                }
                s[t] = rng.nextUniform() < p1Norm ? 1 : 2
            }

            // 2-3. NIG posterior on component 1 then sample. (Same
            // helper as the chain-init call above — keeping a single
            // source of the per-component update math.)
            s1 = nigUpdateAndSample(
                comp: 1,
                assignments: s,
                observations: observations,
                muPrior: mu1Prior, kappaPrior: kappa1Prior,
                alphaPrior: alpha1Prior, betaPrior: beta1Prior,
                rng: &rng
            )

            // 2-3. NIG posterior on component 2 (log-space) then sample.
            s2 = nigUpdateAndSample(
                comp: 2,
                assignments: s,
                observations: observations,
                muPrior: mu2Prior, kappaPrior: kappa2Prior,
                alphaPrior: alpha2Prior, betaPrior: beta2Prior,
                rng: &rng
            )

            // 4. Beta-Binomial update on π.
            var n1 = 0
            for t in 0..<n where s[t] == 1 { n1 += 1 }
            let n2 = n - n1
            piCur = sampleBeta(
                alpha: piAlphaPrior + Double(n1),
                beta: piBetaPrior + Double(n2),
                rng: &rng
            )

            // Diagnostics + collection (only after burn-in).
            if iter >= burnIn {
                samples.append(PosteriorSample(
                    mu1: s1.mu, sigma1Sq: s1.sigmaSq,
                    mu2: s2.mu, sigma2Sq: s2.sigmaSq,
                    pi: piCur
                ))
                if let prev = prevAssignmentsForStability {
                    for t in 0..<n {
                        if prev[t] == s[t] { stabilityHits += 1 }
                        stabilityTotal += 1
                    }
                }
                prevAssignmentsForStability = s
            }
        }

        self.posteriorSamples = samples
        self.assignmentStability = stabilityTotal > 0
            ? Double(stabilityHits) / Double(stabilityTotal)
            : 1.0
    }

    // MARK: - Predictive distribution

    /// Mean of the posterior predictive distribution for the next cycle
    /// length, in days. Averages over collected posterior samples and over
    /// the mixture components via Jensen-corrected shifted-log-normal mean.
    /// Returns nil if `posteriorSamples` is empty.
    ///
    /// #190 (2026-05-26) — changed from `Double` (NaN on empty) to
    /// `Double?`. Silent NaN propagation through arithmetic and SwiftUI
    /// `Text(_:format:)` produced literal "nan" strings on screen
    /// during chain-fresh windows; Optional forces explicit handling.
    /// Pillar 3 ("honest uncertainty") alignment.
    public var nextCycleLengthEstimate: Double? {
        guard !posteriorSamples.isEmpty else { return nil }
        var sum = 0.0
        for sample in posteriorSamples {
            sum += sample.expectedCycleLength
        }
        return sum / Double(posteriorSamples.count)
    }

    /// Posterior mean of the mixing weight π (probability next cycle is
    /// ovulatory). Returns nil if `posteriorSamples` is empty. See
    /// `nextCycleLengthEstimate` doc for the #190 nil-vs-NaN rationale.
    public var mixingWeightEstimate: Double? {
        guard !posteriorSamples.isEmpty else { return nil }
        var sum = 0.0
        for sample in posteriorSamples { sum += sample.pi }
        return sum / Double(posteriorSamples.count)
    }

    // MARK: - Predictive CDF + late-period conditional (Session 2)

    /// Posterior predictive CDF of the mixture: `P(next cycle length ≤ x)`.
    ///
    /// Averages the analytical mixture CDF over posterior samples:
    /// ```
    /// P(L ≤ x) = E_posterior[ π · Φ((x − μ₁)/σ₁) + (1−π) · Φ((log(x−δ) − μ₂)/σ₂) ]
    /// ```
    /// where the component-2 term is `0` for `x ≤ δ`. Component 1's L ≥ 15
    /// truncation is omitted per the documented design deviation
    /// (numerically irrelevant at the population prior).
    ///
    /// Worst-case bias from the omitted truncation: under an unusually
    /// wide σ₁ posterior (Gibbs draw with σ₁ ≈ 8), the unnormalised CDF
    /// runs ~5% high. That regime only manifests for observation-poor
    /// users below the N≥12 graduation threshold, where this method is
    /// not called by any production code path. Safe.
    ///
    /// Returns nil when `posteriorSamples` is empty (#215 migration
    /// from NaN-on-empty for design coherence with the Optional return
    /// of `nextCycleLengthEstimate` / `mixingWeightEstimate`).
    public func predictiveCDF(cycleLength x: Double) -> Double? {
        guard !posteriorSamples.isEmpty else { return nil }
        var sum = 0.0
        for s in posteriorSamples {
            let sigma1 = sqrt(max(s.sigma1Sq, 1e-12))
            let z1 = (x - s.mu1) / sigma1
            let c1cdf = Normal.cdf(z1)
            let c2cdf: Double
            if x > Self.delta {
                let y = log(x - Self.delta)
                let sigma2 = sqrt(max(s.sigma2Sq, 1e-12))
                let z2 = (y - s.mu2) / sigma2
                c2cdf = Normal.cdf(z2)
            } else {
                c2cdf = 0.0
            }
            sum += s.pi * c1cdf + (1.0 - s.pi) * c2cdf
        }
        return sum / Double(posteriorSamples.count)
    }

    /// Conditional posterior predictive: `P(L ≤ x | L > D)`.
    ///
    /// Mirrors `CyclePredictor.conditionalCDF`. Used to drive the
    /// late-period UI when the user's cycle has reached day `D` without
    /// bleeding starting — the conditional distribution shifts right and
    /// stretches, correctly representing the growing uncertainty.
    /// For irregular users, the mixture's right tail (component 2)
    /// gives a *materially wider* interval than the single-component
    /// model would — which is exactly what v2 was built for.
    ///
    /// Returns nil when posterior is empty (#215).
    public func conditionalCDF(cycleLength x: Double, currentDay D: Double) -> Double? {
        guard let FD = predictiveCDF(cycleLength: D) else { return nil }
        guard FD < 0.99999 else { return 1.0 }
        guard let Fx = predictiveCDF(cycleLength: x) else { return nil }
        return max(0, min(1, (Fx - FD) / (1 - FD)))
    }

    /// Conditional credible interval given the cycle has reached day `D`
    /// without bleeding. Bisection inverse of `conditionalCDF`.
    /// Matches the algorithm in `CyclePredictor.inverseConditionalCDF` —
    /// expand the upper bound until the conditional CDF crosses the
    /// target percentile, then bisect.
    ///
    /// Returns nil when posterior is empty (#215). Previously returned
    /// `0...0` — silent-degenerate-range was confusing to downstream
    /// callers since `lowerBound == upperBound == 0` is a valid-looking
    /// range that produces nonsense in arithmetic.
    public func conditionalInterval(
        currentDay D: Double,
        confidence: Double = 0.90
    ) -> ClosedRange<Double>? {
        guard !posteriorSamples.isEmpty else { return nil }
        let lowerTarget = (1.0 - confidence) / 2.0
        let upperTarget = 1.0 - lowerTarget
        let lower = inverseConditionalCDF(target: lowerTarget, currentDay: D)
        let upper = inverseConditionalCDF(target: upperTarget, currentDay: D)
        return lower...upper
    }

    /// Bisection inverse — invoked only after the outer `conditionalInterval`
    /// has guarded for non-empty posterior. Safe to assume
    /// `predictiveCDF` returns non-nil throughout.
    private func inverseConditionalCDF(target: Double, currentDay D: Double) -> Double {
        // Degeneracy guard matches CyclePredictor's: when the marginal
        // CDF at D is essentially 1 (we're so deep into the tail that
        // the conditional distribution loses numerical resolution),
        // return a 30-day fallback range. In practice this shouldn't
        // surface for the mixture even at large D, because the
        // shifted-log-normal tail keeps F(D) < 1 for any finite D.
        let FD = predictiveCDF(cycleLength: D) ?? 0.0
        guard FD < 0.99999 else {
            return target < 0.5 ? D : D + 30.0
        }

        var lo = D
        // Generous initial upper bound — for the mixture, the
        // anovulatory tail can be long, so start at D + 60 (vs
        // CyclePredictor's D + 30) to reduce the expansion loop.
        var hi = max(D + 1.0, D + 60.0)
        while (conditionalCDF(cycleLength: hi, currentDay: D) ?? 1.0) < target {
            hi += 15.0
            if hi > D + 180.0 { return hi }
        }
        for _ in 0..<30 {
            let mid = 0.5 * (lo + hi)
            if hi - lo < 0.01 { return mid }
            if (conditionalCDF(cycleLength: mid, currentDay: D) ?? 1.0) < target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return 0.5 * (lo + hi)
    }

    /// Empirical credible interval for the next cycle length, derived by
    /// Monte Carlo over the posterior + mixture predictive.
    ///
    /// Returns nil on empty posterior (#215 migration; previously
    /// returned silent-degenerate `0...0`).
    ///
    /// - Parameters:
    ///   - confidence: Width of the symmetric central interval (e.g. 0.90).
    ///   - mixtureDrawsPerPosteriorSample: Number of forward simulations
    ///     per posterior sample. Default 10 × 100 samples = 1000-sample
    ///     predictive — sufficient for sub-day quantile resolution.
    ///   - seed: Deterministic random seed for the forward simulation.
    public func nextCycleLengthInterval(
        confidence: Double = 0.90,
        mixtureDrawsPerPosteriorSample: Int = 10,
        seed: UInt64 = 7
    ) -> ClosedRange<Double>? {
        guard !posteriorSamples.isEmpty else { return nil }

        var rng = MixtureRNG(seed: seed)
        var pool: [Double] = []
        pool.reserveCapacity(posteriorSamples.count * mixtureDrawsPerPosteriorSample)

        for sample in posteriorSamples {
            for _ in 0..<mixtureDrawsPerPosteriorSample {
                let useComp1 = rng.nextUniform() < sample.pi
                if useComp1 {
                    let z = rng.nextGaussian()
                    pool.append(sample.mu1 + sqrt(sample.sigma1Sq) * z)
                } else {
                    let z = rng.nextGaussian()
                    let y = sample.mu2 + sqrt(sample.sigma2Sq) * z
                    pool.append(exp(y) + Self.delta)
                }
            }
        }

        pool.sort()
        let alpha = (1.0 - confidence) / 2.0
        let loIdx = Int((alpha * Double(pool.count)).rounded())
        let hiIdx = Int(((1.0 - alpha) * Double(pool.count)).rounded()) - 1
        let lo = pool[max(0, min(pool.count - 1, loIdx))]
        let hi = pool[max(0, min(pool.count - 1, hiIdx))]
        return lo...hi
    }
}

// MARK: - Sampling primitives (private to this file)

/// State for an NIG sample: (μ, σ²) drawn from Normal-Inverse-Gamma.
fileprivate struct NIGSample {
    let mu: Double
    let sigmaSq: Double
}

/// Sequential NIG conjugate update over the observations assigned to
/// `comp` (1 = Normal in original days; 2 = Normal in log(L − δ)), then
/// sample (μ, σ²) from the posterior. Used both at chain initialisation
/// and inside the main Gibbs loop.
fileprivate func nigUpdateAndSample(
    comp: Int,
    assignments: [Int],
    observations: [Double],
    muPrior: Double,
    kappaPrior: Double,
    alphaPrior: Double,
    betaPrior: Double,
    rng: inout MixtureRNG
) -> NIGSample {
    var muP = muPrior
    var kP = kappaPrior
    var aP = alphaPrior
    var bP = betaPrior
    for t in 0..<observations.count where assignments[t] == comp {
        let v: Double
        if comp == 1 {
            v = observations[t]
        } else {
            guard observations[t] > MixturePredictor.delta else { continue }
            v = log(observations[t] - MixturePredictor.delta)
        }
        let newK = kP + 1.0
        let newMu = (kP * muP + v) / newK
        let newA = aP + 0.5
        let newB = bP + 0.5 * (kP / newK) * (v - muP) * (v - muP)
        muP = newMu; kP = newK; aP = newA; bP = newB
    }
    return sampleNIG(mu: muP, kappa: kP, alpha: aP, beta: bP, rng: &rng)
}

/// Sample (μ, σ²) from Normal-Inverse-Gamma(μ₀, κ₀, α, β).
///
/// Algorithm:
///   σ² ~ InverseGamma(α, β); equivalently 1/σ² ~ Gamma(α, rate=β).
///   μ | σ² ~ Normal(μ₀, σ²/κ₀)
fileprivate func sampleNIG(
    mu: Double, kappa: Double, alpha: Double, beta: Double,
    rng: inout MixtureRNG
) -> NIGSample {
    // We want σ² ~ InverseGamma(α, β). Equivalently 1/σ² ~ Gamma(α,
    // rate=β), which in scale parameterisation is Gamma(α, scale=1/β).
    // Marsaglia-Tsang's `nextGamma(shape:scale:)` takes the scale form,
    // so pass `scale = 1.0 / beta`.
    let invSigmaSq = rng.nextGamma(shape: alpha, scale: 1.0 / beta)
    let sigmaSq = 1.0 / max(invSigmaSq, 1e-300)
    let z = rng.nextGaussian()
    let muSample = mu + sqrt(sigmaSq / kappa) * z
    return NIGSample(mu: muSample, sigmaSq: sigmaSq)
}

/// Sample from Beta(α, β) via two Gamma samples.
fileprivate func sampleBeta(alpha: Double, beta: Double, rng: inout MixtureRNG) -> Double {
    let x = rng.nextGamma(shape: alpha, scale: 1.0)
    let y = rng.nextGamma(shape: beta, scale: 1.0)
    let sum = x + y
    if sum <= 0 { return 0.5 } // degenerate fallback
    let v = x / sum
    // Clamp to (0, 1) open interval — log(0) and log(1) downstream both blow up.
    return max(1e-12, min(1.0 - 1e-12, v))
}

/// log-PDF of Normal(μ, σ²) evaluated at x. No truncation; the design's
/// L ≥ 15 truncation has negligible mass for plausible component-1 priors
/// and is omitted for simplicity (documented trade-off).
fileprivate func normalLogPdf(x: Double, mu: Double, sigmaSq: Double) -> Double {
    let v = max(sigmaSq, 1e-12)
    let diff = x - mu
    return -0.5 * log(2.0 * .pi * v) - (diff * diff) / (2.0 * v)
}

// MARK: - RNG

/// Seeded xorshift64 PRNG with Box-Muller Gaussian + Marsaglia-Tsang
/// Gamma. Sendable for use inside the MixturePredictor (Sendable struct
/// itself: the RNG is taken `inout` by callers and never escapes).
///
/// **Visibility note (Session 4 / #192):** `MixtureRNG` is `internal`
/// (not `fileprivate`) specifically so cross-language parity tests can
/// assert bit-exact equivalence with the Python port in
/// `data/validate_phase_predictor.py`. Without this seam, the V6
/// validation report's RNG-parity claim would be untestable in CI.
/// No production code outside this file consumes `MixtureRNG`; the
/// `internal` exposure is test-infrastructure only.
internal struct MixtureRNG: Sendable {
    private var state: UInt64
    private var cachedGaussian: Double? = nil

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform on (0, 1). Strictly open — never returns 0 or 1.
    mutating func nextUniform() -> Double {
        let raw = Double(nextUInt64() >> 11) / Double(1 << 53)
        return max(1e-12, min(1.0 - 1e-12, raw))
    }

    /// Standard normal via Box-Muller. The cache is intentionally
    /// shared across all callers of this RNG (Gamma rejection loops,
    /// NIG sample, etc.). Box-Muller produces independent pairs; the
    /// cached half is the second component of the pair generated by
    /// the previous call. Consuming the cached half before generating
    /// a new pair preserves the statistical contract: every call
    /// returns a marginal standard-normal draw, and the cross-call
    /// sequence is i.i.d. modulo the deterministic pairing inside
    /// each Box-Muller invocation. Reviewer N3 (Session 2) + Session
    /// 4 wording refinement.
    mutating func nextGaussian() -> Double {
        if let g = cachedGaussian {
            cachedGaussian = nil
            return g
        }
        let u1 = nextUniform()
        let u2 = nextUniform()
        let r = sqrt(-2.0 * log(u1))
        let theta = 2.0 * .pi * u2
        cachedGaussian = r * sin(theta)
        return r * cos(theta)
    }

    /// Gamma(shape, scale) — Marsaglia & Tsang 2000 algorithm.
    /// For shape ≥ 1 directly; for shape < 1 uses the boost trick
    /// `Gamma(shape) = Gamma(shape+1) · U^(1/shape)`.
    mutating func nextGamma(shape: Double, scale: Double) -> Double {
        guard shape > 0 else { return 0 }
        if shape < 1.0 {
            let g = nextGamma(shape: shape + 1.0, scale: 1.0)
            let u = nextUniform()
            return scale * g * pow(u, 1.0 / shape)
        }
        let d = shape - 1.0 / 3.0
        let c = 1.0 / sqrt(9.0 * d)
        while true {
            var x = nextGaussian()
            var v = 1.0 + c * x
            while v <= 0 {
                x = nextGaussian()
                v = 1.0 + c * x
            }
            v = v * v * v
            let u = nextUniform()
            if u < 1.0 - 0.0331 * x * x * x * x {
                return scale * d * v
            }
            if log(u) < 0.5 * x * x + d * (1.0 - v + log(v)) {
                return scale * d * v
            }
        }
    }
}
