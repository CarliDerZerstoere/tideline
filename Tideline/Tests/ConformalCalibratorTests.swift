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

    @Test("Fehring 90% quantile is 4.571 days")
    func fehringQuantile() {
        // This is the headline number from the validation note —
        // documents that the population residuals file is correctly loaded.
        let q = ConformalCalibrator.shared.quantile(confidence: 0.90)
        #expect(abs(q - 4.571) < 0.01)
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
