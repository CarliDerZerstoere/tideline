import Testing
import Foundation
@testable import Tideline

/// Real-data validation against the mcPHASES dataset (PhysioNet v1.0.0).
/// 42 women across two short observation intervals; cycle lengths derived
/// from menstrual-phase onsets per (subject, study_interval).
///
/// **License:** PhysioNet Restricted Health Data License 1.5.0.
/// Research/validation only. Not redistributed. Not bundled in shipping app.
/// Raw data lives in `data/raw/mcphases/` (gitignored).
///
/// Source: https://physionet.org/content/mcphases/1.0.0/
///
/// Because the observation window is short, most subjects yield only 2–3
/// cycles. We use `minTrain = 1` here — predict cycle k+1 from cycles 1..k
/// starting at k=1. This is the "early user" regime: prior-dominated for the
/// first prediction, data starting to take over from k=2.
@Suite("mcPHASES real-data validation")
struct McPhasesValidationTests {

    @Test("Predictor on mcPHASES (early-user regime, min train = 1)")
    func mcphasesPredictionError() throws {
        let cycles = try loadMcPhases()
        let bySubject = Dictionary(grouping: cycles, by: \.subjectId)
            .mapValues { $0.sorted(by: { $0.cycleIndex < $1.cycleIndex }) }

        struct Row {
            let absError: Double
            let halfWidth: Double
            let covered: Bool
            let trainSize: Int
        }
        var rows: [Row] = []

        let minTrain = 1
        for (_, seq) in bySubject {
            guard seq.count >= minTrain + 1 else { continue }
            for splitIndex in minTrain..<seq.count {
                var predictor = CyclePredictor.populationPrior
                for i in 0..<splitIndex { predictor.observe(cycleLength: seq[i].lengthDays) }
                let actual = seq[splitIndex].lengthDays
                let predicted = predictor.nextCycleLengthEstimate
                let ci = predictor.nextCycleLengthInterval(confidence: 0.90)
                rows.append(Row(
                    absError: abs(actual - predicted),
                    halfWidth: (ci.upperBound - ci.lowerBound) / 2.0,
                    covered: ci.contains(actual),
                    trainSize: splitIndex
                ))
            }
        }

        guard !rows.isEmpty else {
            Issue.record("No predictions possible from mcPHASES")
            return
        }

        let n = rows.count
        let mae = rows.map(\.absError).reduce(0, +) / Double(n)
        let medianAbs = rows.map(\.absError).sorted()[n / 2]
        let meanHalfWidth = rows.map(\.halfWidth).reduce(0, +) / Double(n)
        let coverage = Double(rows.filter(\.covered).count) / Double(n)
        let evalSubjects = bySubject.values.filter { $0.count >= minTrain + 1 }.count
        let totalCycles = cycles.count

        print("""

        ── mcPHASES validation ─────────────────────────────────
          Subject-intervals total: \(bySubject.count)
          Subject-intervals eval:  \(evalSubjects)
          Cycles total:            \(totalCycles)
          Predictions made:        \(n)

          Point accuracy:
            MAE:                \(String(format: "%.2f", mae)) days
            Median absolute:    \(String(format: "%.2f", medianAbs)) days

          Interval (90% PI):
            Mean half-width:    ±\(String(format: "%.2f", meanHalfWidth)) days
            Coverage:           \(String(format: "%.1f", coverage * 100))%
        ────────────────────────────────────────────────────────
        """)

        #expect(mae < 7.0, "MAE should be under 7 days for early-user predictions")
        #expect(coverage > 0.70, "90% interval should cover at least 70% in practice")
    }

    @Test("mcPHASES population mean roughly matches AWHS/Bull range")
    func mcphasesMean() throws {
        let cycles = try loadMcPhases()
        let lengths = cycles.map(\.lengthDays)
        let mean = lengths.reduce(0, +) / Double(lengths.count)
        // AWHS=28.7, Bull=29.3, Fehring≈29.3 — mcPHASES should sit in same range
        #expect(mean > 26 && mean < 32, "mcPHASES mean = \(mean)")
    }

    // MARK: - Loading

    struct McPhasesCycle {
        let subjectId: String
        let cycleIndex: Int
        let lengthDays: Double
    }

    private func loadMcPhases() throws -> [McPhasesCycle] {
        let bundle = Bundle(for: McPhasesBundleMarker.self)
        guard let url = bundle.url(forResource: "mcphases_cycles", withExtension: "csv") else {
            Issue.record("mcphases_cycles.csv not found in test bundle (path: \(bundle.bundlePath))")
            return []
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard lines.count > 1 else { return [] }
        var out: [McPhasesCycle] = []
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            let id = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty,
                  let cyc = Int(fields[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let len = Double(fields[2].trimmingCharacters(in: .whitespacesAndNewlines)),
                  len > 0 else { continue }
            out.append(McPhasesCycle(subjectId: id, cycleIndex: cyc, lengthDays: len))
        }
        return out
    }
}

private final class McPhasesBundleMarker {}
