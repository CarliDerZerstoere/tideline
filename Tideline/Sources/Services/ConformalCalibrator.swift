import Foundation

/// Split-conformal prediction interval wrapper.
///
/// Given a sorted population calibration set of past prediction residuals
/// (|actual − predicted|), constructs an interval `point ± q_α` where q_α is
/// the empirical (1−α)-quantile of the residuals. The interval comes with a
/// distribution-free finite-sample coverage guarantee:
///
///   P(actual ∈ [point − q, point + q]) ≥ 1 − α
///
/// under exchangeability of calibration and test residuals (Vovk et al. 2005;
/// Angelopoulos & Bates 2023, arXiv:2107.07511).
///
/// `populationResiduals` is generated offline from leave-one-out validation
/// on the Fehring NFP dataset (see `data/extract_conformal_residuals.py`).
/// As users accumulate their own history, we could swap to a personal
/// calibration set — but the population residuals are a safe starting point.
public struct ConformalCalibrator: Sendable {
    /// Sorted ascending. Each value is |actual cycle length − predicted| in days.
    public let populationResiduals: [Double]

    public init(populationResiduals: [Double] = Self.defaultPopulationResiduals) {
        self.populationResiduals = populationResiduals.sorted()
    }

    /// Wrap a point prediction with a symmetric conformal interval.
    /// Returns `point ± q` where q is the empirical (1−α)-quantile.
    public func wrap(point: Double, confidence: Double = 0.90) -> ClosedRange<Double> {
        let q = quantile(confidence: confidence)
        return (point - q)...(point + q)
    }

    /// Compute q_α = the ⌈(n+1)(1−α)⌉/n-th order statistic of the residuals.
    /// This is the standard split-conformal quantile formula.
    public func quantile(confidence: Double) -> Double {
        let n = populationResiduals.count
        guard n > 0 else { return .infinity }
        let alpha = 1.0 - confidence
        let rank = Int((Double(n + 1) * (1 - alpha)).rounded(.up)) - 1
        let clamped = min(max(rank, 0), n - 1)
        return populationResiduals[clamped]
    }

    public static let shared = ConformalCalibrator()

    /// Population residuals derived from leave-one-out validation against the
    /// Fehring NFP dataset (1223 predictions, MAE 2.115 days, median 1.500,
    /// 90th-percentile residual 4.571 days). See `ConformalResiduals.swift`
    /// for the full sorted array and regeneration command.
    public static let defaultPopulationResiduals: [Double] = ConformalResiduals.fehringPopulation
}
