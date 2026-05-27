import Testing
import Foundation
@testable import Tideline

/// Real-data validation against the Fehring NFP / Marquette cycle dataset
/// (1665 cycles from 159 women using natural family planning).
///
/// **License note:** Fehring data has no OSI license — only a consent-based
/// reuse statement. Used here for offline validation in dev only. Not bundled
/// into the shipping app, not redistributed via any public channel.
///
/// Source: https://epublications.marquette.edu/data_nfp/7/
@Suite("Fehring real-data validation")
struct FehringValidationTests {

    @Test("Predictor achieves reasonable error on Fehring cycles")
    func fehringPredictionError() throws {
        let raw = try loadFehringUnfiltered()
        let totalRaw = raw.count
        let filtered = raw.filter { $0.lengthDays >= 15 && $0.lengthDays <= 90 }
        let exclusionRate = 1.0 - Double(filtered.count) / Double(totalRaw)

        let bySubject = Dictionary(grouping: filtered, by: \.subjectId)
            .mapValues { $0.sorted(by: { $0.cycleIndex < $1.cycleIndex }) }

        struct Row {
            let absError: Double
            let halfWidth: Double
            let covered: Bool
            let trainSize: Int
        }
        var rows: [Row] = []

        for (_, seq) in bySubject {
            guard seq.count >= 4 else { continue }
            for splitIndex in 3..<seq.count {
                var predictor = CyclePredictor.populationPrior
                for i in 0..<splitIndex { predictor.observe(cycleLength: seq[i].lengthDays) }
                let actual = seq[splitIndex].lengthDays
                let predicted = predictor.nextCycleLengthEstimate
                let ci = predictor.nextCycleLengthInterval(confidence: 0.90)
                let halfWidth = (ci.upperBound - ci.lowerBound) / 2.0
                rows.append(Row(
                    absError: abs(actual - predicted),
                    halfWidth: halfWidth,
                    covered: ci.contains(actual),
                    trainSize: splitIndex
                ))
            }
        }

        guard !rows.isEmpty else {
            Issue.record("No predictions possible — Fehring CSV was empty or failed to load")
            return
        }

        let n = rows.count
        let mae = rows.map(\.absError).reduce(0, +) / Double(n)
        let medianAbs = rows.map(\.absError).sorted()[n / 2]
        let meanHalfWidth = rows.map(\.halfWidth).reduce(0, +) / Double(n)
        let medianHalfWidth = rows.map(\.halfWidth).sorted()[n / 2]
        let coverage = Double(rows.filter(\.covered).count) / Double(n)

        // Stratify MAE by training-set size, to expose whether the prior is
        // doing the work (early k) vs. the data (later k).
        let early = rows.filter { $0.trainSize <= 5 }
        let mid = rows.filter { $0.trainSize > 5 && $0.trainSize <= 12 }
        let late = rows.filter { $0.trainSize > 12 }
        func maeOf(_ rs: [Row]) -> Double { rs.isEmpty ? 0 : rs.map(\.absError).reduce(0, +) / Double(rs.count) }

        // Clustered (per-subject) coverage to avoid pretending 1223 predictions
        // are independent across 129 women.
        let coveragePerSubject = bySubject.values.compactMap { seq -> Double? in
            guard seq.count >= 4 else { return nil }
            let subjectRows = (3..<seq.count).map { idx -> Bool in
                var p = CyclePredictor.populationPrior
                for i in 0..<idx { p.observe(cycleLength: seq[i].lengthDays) }
                return p.nextCycleLengthInterval(confidence: 0.90).contains(seq[idx].lengthDays)
            }
            return Double(subjectRows.filter { $0 }.count) / Double(subjectRows.count)
        }
        // Audit task #115: a CSV that has rows but no subject with ≥4
        // cycles leaves `coveragePerSubject` empty — division by zero (NaN)
        // and a same-index subscript trap. The outer `rows.isEmpty` guard
        // doesn't catch this because the per-subject filter is independent.
        guard !coveragePerSubject.isEmpty else {
            Issue.record("No subject had ≥4 cycles — Fehring CSV malformed or filtered to nothing")
            return
        }
        let clusteredMean = coveragePerSubject.reduce(0, +) / Double(coveragePerSubject.count)
        let clusteredSorted = coveragePerSubject.sorted()
        let clusteredMedian = clusteredSorted[clusteredSorted.count / 2]

        print("""

        ── Fehring validation ──────────────────────────────────
          Raw cycles:           \(totalRaw)
          After 15–90d filter:  \(filtered.count)  (excluded \(String(format: "%.1f", exclusionRate * 100))%)
          Subjects evaluated:   \(bySubject.values.filter { $0.count >= 4 }.count)
          Predictions made:     \(n)

          Point accuracy:
            MAE:                \(String(format: "%.2f", mae)) days
            Median absolute:    \(String(format: "%.2f", medianAbs)) days
            MAE | train ≤5:     \(String(format: "%.2f", maeOf(early))) days  (n=\(early.count))
            MAE | 5<train≤12:   \(String(format: "%.2f", maeOf(mid))) days  (n=\(mid.count))
            MAE | train >12:    \(String(format: "%.2f", maeOf(late))) days  (n=\(late.count))

          Interval (90% PI):
            Mean half-width:    ±\(String(format: "%.2f", meanHalfWidth)) days
            Median half-width:  ±\(String(format: "%.2f", medianHalfWidth)) days
            Coverage (pooled):  \(String(format: "%.1f", coverage * 100))%
            Coverage (per-subj mean):   \(String(format: "%.1f", clusteredMean * 100))%
            Coverage (per-subj median): \(String(format: "%.1f", clusteredMedian * 100))%
        ────────────────────────────────────────────────────────
        """)

        #expect(mae < 5.0, "MAE should be under 5 days for a healthy NFP population")
        #expect(coverage > 0.70, "90% interval should cover at least 70% in practice")
    }

    @Test("Posterior μ across all Fehring cycles approaches population mean")
    func fehringPosteriorMean() throws {
        let cycles = try loadFehring()
        var predictor = CyclePredictor.populationPrior
        for c in cycles { predictor.observe(cycleLength: c.lengthDays) }
        // Truth from the dataset itself: mean ≈ 29.3 days
        #expect(abs(predictor.mu - 29.3) < 0.5)
        #expect(predictor.observedCount == cycles.count)
    }

    // MARK: - Loading

    struct FehringCycle {
        let subjectId: String
        let cycleIndex: Int
        let lengthDays: Double
    }

    private func loadFehring() throws -> [FehringCycle] {
        try loadFehringUnfiltered().filter { $0.lengthDays >= 15 && $0.lengthDays <= 90 }
    }

    private func loadFehringUnfiltered() throws -> [FehringCycle] {
        let bundle = Bundle(for: BundleMarker.self)
        guard let url = bundle.url(forResource: "fehring_cycles", withExtension: "csv") else {
            Issue.record("fehring_cycles.csv not found in test bundle")
            return []
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard lines.count > 1 else { return [] }
        let header = lines[0].split(separator: ",").map(String.init)
        guard let idIdx = header.firstIndex(of: "ClientID"),
              let cycleIdx = header.firstIndex(of: "CycleNumber"),
              let lenIdx = header.firstIndex(of: "LengthofCycle") else {
            Issue.record("Unexpected Fehring CSV header: \(header)")
            return []
        }
        var out: [FehringCycle] = []
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count > max(idIdx, cycleIdx, lenIdx) else { continue }
            let id = fields[idIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty,
                  let cycDouble = Double(fields[cycleIdx].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let len = Double(fields[lenIdx].trimmingCharacters(in: .whitespacesAndNewlines)),
                  len > 0 else { continue }
            out.append(FehringCycle(subjectId: id, cycleIndex: Int(cycDouble), lengthDays: len))
        }
        return out
    }
}

/// Marker class so Bundle(for:) finds the test bundle.
private final class BundleMarker {}
