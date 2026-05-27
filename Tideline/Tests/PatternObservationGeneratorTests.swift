import Testing
import Foundation
@testable import Tideline

/// Tests for `PatternObservationGenerator` (task #120). Pure-function
/// tests, no SwiftData/UI required.
@Suite("PatternObservationGenerator — Layer 2 pattern detection")
struct PatternObservationGeneratorTests {

    private func cycle(start daysAgo: Int, length: Int) -> CycleSummary {
        CycleSummary(
            startDate: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400),
            lengthDays: length
        )
    }

    // MARK: - Low-data threshold

    @Test("Empty cycles → nil")
    func emptyReturnsNil() {
        #expect(PatternObservationGenerator.generate(cycles: []) == nil)
    }

    @Test("1 cycle → nil")
    func singleCycleReturnsNil() {
        let cycles = [cycle(start: 30, length: 28)]
        #expect(PatternObservationGenerator.generate(cycles: cycles) == nil)
    }

    @Test("2 cycles → nil (below threshold)")
    func twoCyclesReturnsNil() {
        let cycles = [cycle(start: 60, length: 28), cycle(start: 30, length: 29)]
        #expect(PatternObservationGenerator.generate(cycles: cycles) == nil)
    }

    // MARK: - Stability

    @Test("3 cycles all same length → cycleLengthStable")
    func stableThreeIdentical() {
        let cycles = (0..<3).map { cycle(start: (3 - $0) * 28, length: 28) }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        #expect(obs?.kind == .cycleLengthStable(meanDays: 28))
        #expect(obs?.germanSentence.contains("28 Tagen") == true)
    }

    @Test("6 cycles within ±1 day → cycleLengthStable")
    func stableSixWithinTolerance() {
        // 27, 28, 28, 29, 28, 28 — stdev ≈ 0.6, well under 2.
        let lengths = [27, 28, 28, 29, 28, 28]
        let cycles = lengths.enumerated().map { (i, len) in
            cycle(start: (6 - i) * 28, length: len)
        }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        if case .cycleLengthStable(let mean) = obs?.kind {
            #expect(mean == 28)
        } else {
            Issue.record("Expected .cycleLengthStable, got \(String(describing: obs?.kind))")
        }
    }

    @Test("Highly variable cycles (stdev > 2) → not stable")
    func volatileNotStable() {
        // 22, 32, 24, 30, 26, 33 — stdev > 2.
        let lengths = [22, 32, 24, 30, 26, 33]
        let cycles = lengths.enumerated().map { (i, len) in
            cycle(start: (6 - i) * 28, length: len)
        }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        // Should NOT be stable. Could be trending or nil.
        if case .cycleLengthStable = obs?.kind {
            Issue.record("Volatile cycles shouldn't be classified as stable")
        }
    }

    // MARK: - Trend

    @Test("6 cycles trending longer → cycleLengthTrending(.longer)")
    func trendingLonger() {
        // 24, 25, 26, 30, 32, 34 — prior mean of [24,25,26] = 25; last 3 [30,32,34]
        // all > 25 + 2 = 27. Should trigger.
        let lengths = [24, 25, 26, 30, 32, 34]
        let cycles = lengths.enumerated().map { (i, len) in
            cycle(start: (6 - i) * 28, length: len)
        }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        if case .cycleLengthTrending(let dir, _) = obs?.kind {
            #expect(dir == .longer)
            #expect(obs?.germanSentence.contains("länger") == true)
        } else {
            Issue.record("Expected .cycleLengthTrending(.longer), got \(String(describing: obs?.kind))")
        }
    }

    @Test("6 cycles trending shorter → cycleLengthTrending(.shorter)")
    func trendingShorter() {
        // 34, 32, 30, 26, 25, 24 — prior mean of first 3 = 32; last 3 [26,25,24]
        // all < 32 - 2 = 30. Should trigger.
        let lengths = [34, 32, 30, 26, 25, 24]
        let cycles = lengths.enumerated().map { (i, len) in
            cycle(start: (6 - i) * 28, length: len)
        }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        if case .cycleLengthTrending(let dir, _) = obs?.kind {
            #expect(dir == .shorter)
            #expect(obs?.germanSentence.contains("kürzer") == true)
        } else {
            Issue.record("Expected .cycleLengthTrending(.shorter), got \(String(describing: obs?.kind))")
        }
    }

    @Test("Stable trumps trend in priority order")
    func stabilityWinsOverTrend() {
        // All same length — stable should match before trend logic even
        // gets a chance.
        let cycles = (0..<6).map { cycle(start: (6 - $0) * 28, length: 28) }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        if case .cycleLengthStable = obs?.kind {
            // pass
        } else {
            Issue.record("Expected .cycleLengthStable to win priority, got \(String(describing: obs?.kind))")
        }
    }

    // MARK: - Sparkline data

    @Test("Sparkline values are last-N cycle lengths, oldest first")
    func sparklineValuesPreserveOrder() {
        let lengths = [28, 28, 28, 28, 28, 28]
        let cycles = lengths.enumerated().map { (i, len) in
            cycle(start: (6 - i) * 28, length: len)
        }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        #expect(obs?.sparklineValues == lengths.map { Double($0) })
    }

    @Test("Sparkline values capped at 6 even with longer history")
    func sparklineCappedAtSix() {
        let lengths = Array(repeating: 28, count: 12)
        let cycles = lengths.enumerated().map { (i, len) in
            cycle(start: (12 - i) * 28, length: len)
        }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        #expect(obs?.sparklineValues.count == 6)
    }

    // MARK: - German formatting

    @Test("Stable sentence uses German singular/plural correctly")
    func germanSentenceFormatting() {
        // We only ever say "Tagen" (plural dative) here — never 1 day.
        // But verify the sentence reads naturally for typical values.
        let cycles = (0..<3).map { cycle(start: (3 - $0) * 29, length: 29) }
        let obs = PatternObservationGenerator.generate(cycles: cycles)
        #expect(obs?.germanSentence == "Deine Zyklen sind konstant bei 29 Tagen.")
    }
}
