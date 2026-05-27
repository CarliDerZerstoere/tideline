import Testing
import Foundation
@testable import Tideline

@Suite("ConformalCalibrator — split-conformal wrapper")
struct ConformalCalibratorTests {

    @Test("quantile matches the textbook split-conformal formula on toy data")
    func quantileFormula() {
        // n=10 residuals 0..9. For α=0.1, the conformal rank is
        // ceil((n+1)(1-α)) = ceil(11·0.9) = 10 → 1-indexed 10th, 0-indexed 9.
        let c = ConformalCalibrator(populationResiduals: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(c.quantile(confidence: 0.90) == 9.0)
    }

    @Test("quantile at 50% confidence picks the median-ish residual")
    func quantileMedian() {
        let c = ConformalCalibrator(populationResiduals: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let q50 = c.quantile(confidence: 0.50)
        // ceil(11·0.5) - 1 = 5 → residuals[5] = 5
        #expect(q50 == 5.0)
    }

    @Test("wrap centers symmetrically around the point")
    func wrapSymmetric() {
        let c = ConformalCalibrator(populationResiduals: [1, 2, 3, 4])
        let interval = c.wrap(point: 28.0, confidence: 0.90)
        // n=4, ceil(5·0.9)-1 = 4 → clamped to 3 → residuals[3] = 4
        #expect(interval == 24.0...32.0)
    }

    @Test("Fehring 90% quantile is 4.543 days (post-#163 re-extraction)")
    func fehringQuantile() {
        // Documents that the population residuals file is correctly loaded.
        // Task #163 (2026-05-26) re-extracted the residuals against the
        // corrected post-#158 NIG prior (β=28.7282 instead of 41.07). The
        // 90th-percentile dropped from 4.571 → 4.543 (~0.6% interval-width
        // change). Pin the new value so a future regen against an
        // unintended prior is caught here. The pin tracks the value
        // `quantile(_:)` actually returns (textbook ceil rank), not the
        // floor-ranked value Python's :.3f display historically printed.
        let q = ConformalCalibrator.shared.quantile(confidence: 0.90)
        #expect(abs(q - 4.543) < 0.01)
    }

    @Test("Quantile is monotonic non-decreasing in confidence (#163 invariant)")
    func quantileMonotonic() {
        // A higher confidence level can never select a smaller residual
        // than a lower one. Pinning this protects against a future
        // refactor that accidentally truncates or shuffles the residual
        // array. Cheap structural check.
        let c = ConformalCalibrator.shared
        let q50 = c.quantile(confidence: 0.50)
        let q80 = c.quantile(confidence: 0.80)
        let q90 = c.quantile(confidence: 0.90)
        let q95 = c.quantile(confidence: 0.95)
        #expect(q50 <= q80)
        #expect(q80 <= q90)
        #expect(q90 <= q95)
    }

    @Test("Conformal-width baseline sentinel (post-#163, ±1%)")
    func widthBaselineSentinel() {
        // Documents the v1.0 → v1.1 calibration shift. Before #163, the
        // 90th-percentile residual was 4.571 → interval width 9.142d.
        // After #163, 4.543 → width 9.086d. Delta: −0.056d (−0.6%).
        // The test fails if a future regen produces >1% delta from the
        // post-#163 baseline. Tightened from the original 2% per reviewer
        // feedback — narrower band makes the sentinel catch real shifts
        // earlier (e.g. someone swapping the cohort or changing the
        // extractor algorithm) while staying generous enough not to
        // trip on micro-changes in the data pipeline.
        let widthNew = ConformalCalibrator.shared.wrap(
            point: 29.0,
            confidence: 0.90
        )
        let widthDays = widthNew.upperBound - widthNew.lowerBound
        let post163Baseline = 4.543 * 2.0  // 9.086
        let deltaFraction = abs(widthDays - post163Baseline) / post163Baseline
        #expect(deltaFraction < 0.01,
                "Interval width drifted >1% from post-#163 baseline (was \(post163Baseline), now \(widthDays))")
    }

    @Test("empty residuals returns infinite interval (degenerate but safe)")
    func emptyResiduals() {
        let c = ConformalCalibrator(populationResiduals: [])
        let q = c.quantile(confidence: 0.90)
        #expect(q.isInfinite)
    }

    @Test("coverage simulation: empirical coverage ≥ 1-α on calibration distribution")
    func empiricalCoverage() {
        // Sample 1000 actual values from the same population the residuals
        // describe. We expect ~90% coverage by construction.
        let c = ConformalCalibrator.shared
        let q = c.quantile(confidence: 0.90)
        var rng = SeededRNG(seed: 12345)
        var covered = 0
        let n = 1000
        for _ in 0..<n {
            // Draw a residual by sampling uniformly from the population set.
            let idx = Int(rng.nextUniform() * Double(c.populationResiduals.count))
            let drawn = c.populationResiduals[min(idx, c.populationResiduals.count - 1)]
            if drawn <= q { covered += 1 }
        }
        let coverage = Double(covered) / Double(n)
        // Conformal guarantees ≥ 90%; allow slack for finite sampling.
        #expect(coverage > 0.87)
    }
}
