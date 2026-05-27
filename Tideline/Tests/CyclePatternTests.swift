import Testing
import Foundation
@testable import Tideline

@Suite("CyclePattern — type + labels")
struct CyclePatternTests {

    // MARK: - Threshold mapping

    @Test("π ≥ 0.85 → mostlyOvulatory")
    func mostlyOvulatoryHigh() {
        #expect(CyclePattern(mixingWeight: 1.0, observedCount: 24).category == .mostlyOvulatory)
        #expect(CyclePattern(mixingWeight: 0.85, observedCount: 24).category == .mostlyOvulatory)
        #expect(CyclePattern(mixingWeight: 0.90, observedCount: 12).category == .mostlyOvulatory)
    }

    @Test("0.50 ≤ π < 0.85 → occasionallyAnovulatory")
    func occasionallyAnovulatoryMid() {
        #expect(CyclePattern(mixingWeight: 0.84, observedCount: 18).category == .occasionallyAnovulatory)
        #expect(CyclePattern(mixingWeight: 0.65, observedCount: 18).category == .occasionallyAnovulatory)
        #expect(CyclePattern(mixingWeight: 0.50, observedCount: 18).category == .occasionallyAnovulatory)
    }

    @Test("π < 0.50 → oftenAnovulatory")
    func oftenAnovulatoryLow() {
        #expect(CyclePattern(mixingWeight: 0.49, observedCount: 30).category == .oftenAnovulatory)
        #expect(CyclePattern(mixingWeight: 0.25, observedCount: 30).category == .oftenAnovulatory)
        #expect(CyclePattern(mixingWeight: 0.0, observedCount: 30).category == .oftenAnovulatory)
    }

    @Test("boundary exactness: 0.85 stays in mostlyOvulatory, 0.50 stays in occasionally")
    func boundaryExactness() {
        // The thresholds are inclusive on the upper category boundary
        // by design (≥ 0.85, ≥ 0.50). Test the exact values to prevent
        // off-by-one drift if anyone tweaks the comparisons.
        #expect(CyclePattern(mixingWeight: 0.85, observedCount: 12).category == .mostlyOvulatory)
        #expect(CyclePattern(mixingWeight: 0.5, observedCount: 12).category == .occasionallyAnovulatory)
    }

    // MARK: - German labels

    @Test("German labels match the user-approved copy")
    func germanLabels() {
        #expect(CyclePattern(category: .mostlyOvulatory, observedCount: 24).germanLabel
                == "Meist ovulatorisch")
        #expect(CyclePattern(category: .occasionallyAnovulatory, observedCount: 24).germanLabel
                == "Gelegentlich anovulatorisch")
        #expect(CyclePattern(category: .oftenAnovulatory, observedCount: 24).germanLabel
                == "Häufig anovulatorisch")
    }

    @Test("basisLabel pluralises German correctly")
    func basisLabelPlural() {
        #expect(CyclePattern(category: .mostlyOvulatory, observedCount: 1).basisLabel
                == "basiert auf 1 Zyklus")
        #expect(CyclePattern(category: .mostlyOvulatory, observedCount: 12).basisLabel
                == "basiert auf 12 Zyklen")
        #expect(CyclePattern(category: .mostlyOvulatory, observedCount: 100).basisLabel
                == "basiert auf 100 Zyklen")
    }

    @Test("Equatable: same category + count = equal")
    func equatable() {
        let a = CyclePattern(category: .mostlyOvulatory, observedCount: 12)
        let b = CyclePattern(category: .mostlyOvulatory, observedCount: 12)
        let c = CyclePattern(category: .mostlyOvulatory, observedCount: 13)
        let d = CyclePattern(category: .occasionallyAnovulatory, observedCount: 12)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}

@Suite("PredictorService — cycle-pattern sidecar (#193)")
struct PredictorServiceCyclePatternTests {

    @Test("cyclePattern is nil with zero observed cycles")
    func nilOnEmpty() async {
        let service = PredictorService()
        let pattern = await service.cyclePattern()
        #expect(pattern == nil)
    }

    @Test("cyclePattern is nil below graduation threshold (N=11)")
    func nilBelowThreshold() async {
        let service = PredictorService()
        // 11 plausible cycles, all close to 28 days.
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28] {
            _ = await service.observe(cycleLength: length)
        }
        let pattern = await service.cyclePattern()
        #expect(pattern == nil)
    }

    @Test("cyclePattern emerges at graduation threshold (N=12)")
    func emergesAtThreshold() async {
        let service = PredictorService()
        // 12 cycles all ~28 → mixture should land at "Meist ovulatorisch".
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let pattern = await service.cyclePattern()
        #expect(pattern != nil)
        #expect(pattern?.observedCount == 12)
        #expect(pattern?.category == .mostlyOvulatory)
    }

    @Test("cyclePattern reflects mixture composition with long cycles mixed in")
    func reflectsMixture() async {
        let service = PredictorService()
        // 12 cycles, 4 of which are long (~44 days, above the H-Z hard
        // threshold). This is exactly the PCOS-ish pattern v2 is built
        // for. Expect π to drop materially — landing in either
        // `.occasionallyAnovulatory` (typical) or `.oftenAnovulatory`
        // (if Gibbs noise pushes it lower).
        let cycles: [Double] = [
            28, 29, 28, 44,
            27, 29, 30, 44,
            28, 28, 30, 44,
        ]
        // Add a fourth long cycle to make sure π drops well below 0.85.
        // 4/12 = 33% anovulatory by construction → posterior π ≈ 0.67
        // (with Beta(8,2) prior tugging back toward 0.8).
        var lengths = cycles
        lengths[10] = 44.0  // make 5/12 long → π posterior likely <0.85
        for length in lengths {
            _ = await service.observe(cycleLength: length)
        }
        let pattern = await service.cyclePattern()
        #expect(pattern != nil)
        // The exact category depends on Gibbs noise but it must NOT be
        // `.mostlyOvulatory` given that 5/12 cycles are above the H-Z
        // hard threshold (deterministically routed to comp 2).
        #expect(pattern?.category != .mostlyOvulatory,
                "5/12 anovulatory cycles should pull pattern out of 'mostly ovulatory'")
    }

    @Test("softReset (Category C) keeps cyclePattern — long-run pattern survives single disruption")
    func softResetKeepsPattern() async {
        // Reviewer H1 (#193 Session 1): a single Category C event
        // (miscarriage, medical abortion, illness) should NOT wipe 24
        // cycles of accumulated long-run pattern. The single disrupted
        // cycle gets handled by the CyclePredictor's softReset (β
        // widens, recovery window starts) but the mixture sidecar
        // keeps its history — pattern badge stays visible.
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let beforePattern = await service.cyclePattern()
        #expect(beforePattern != nil)

        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        let afterPattern = await service.cyclePattern()
        #expect(afterPattern != nil,
                "Category C should preserve the cyclePattern badge — long-run trait is stable")
        #expect(afterPattern?.observedCount == beforePattern?.observedCount,
                "observedCount should match the original (CyclePredictor.softReset zeros it, but the mixture sidecar tracks its own count)")
    }

    @Test("retire clears cyclePattern (Category A event)")
    func retireClears() async {
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        await service.apply(eventKind: .hysterectomy, on: Date.now)
        let pattern = await service.cyclePattern()
        #expect(pattern == nil)
    }

    @Test("pause clears cyclePattern (Category B event)")
    func pauseClears() async {
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        await service.apply(eventKind: .birthBreastfeeding, on: Date.now)
        let pattern = await service.cyclePattern()
        #expect(pattern == nil)
    }

    @Test("cyclePattern is cached: identical when called twice without new observation")
    func cachedBetweenCalls() async {
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let first = await service.cyclePattern()
        let second = await service.cyclePattern()
        #expect(first == second,
                "cyclePattern should be deterministic / cached across calls without new observe()")
    }

    // MARK: - Session 2 — mixtureConditionalInterval

    @Test("mixtureConditionalInterval returns nil below graduation threshold")
    func mixtureIntervalNilBelowThreshold() async {
        let service = PredictorService()
        // 8 observations, well below the 12-cycle graduation threshold.
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let interval = await service.mixtureConditionalInterval(
            daysSinceLastPeriod: 30.0, confidence: 0.90
        )
        #expect(interval == nil)
    }

    @Test("mixtureConditionalInterval emerges at N=12")
    func mixtureIntervalEmergesAtThreshold() async {
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let interval = await service.mixtureConditionalInterval(
            daysSinceLastPeriod: 30.0, confidence: 0.90
        )
        #expect(interval != nil)
        #expect((interval?.lowerBound ?? 0) >= 30.0,
                "Lower bound must respect the conditioning day")
        #expect((interval?.upperBound ?? 0) > (interval?.lowerBound ?? 0))
    }

    @Test("mixtureConditionalInterval is nil after retire (Category A)")
    func mixtureIntervalNilAfterRetire() async {
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        await service.apply(eventKind: .hysterectomy, on: Date.now)
        let interval = await service.mixtureConditionalInterval(
            daysSinceLastPeriod: 30.0, confidence: 0.90
        )
        #expect(interval == nil)
    }

    @Test("mixtureConditionalInterval survives Category C event (mirrors cyclePattern behavior)")
    func mixtureIntervalSurvivesCategoryC() async {
        let service = PredictorService()
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        let interval = await service.mixtureConditionalInterval(
            daysSinceLastPeriod: 30.0, confidence: 0.90
        )
        #expect(interval != nil,
                "Category C must keep mixture intact (long-run pattern is stable across single disruptions)")
    }

    // NOTE: reviewer L3 (end-to-end snapshot binding test) is deferred —
    // `CycleStore` is `@ModelActor` with an inline `private var predictor
    // = PredictorService()` and no constructor seam for injection. The
    // alternative — driving 12 cycles through the public `logDay` API
    // — requires multi-month date arithmetic in the test and inflates
    // the test substantially. The service-level + snapshot-shape tests
    // here cover the same code paths via simpler scaffolding. Tracker
    // item for future: refactor `CycleStore` to allow predictor
    // injection (would also help several other integration tests).

    @Test("setAgeBand on empty mixture re-primes the prior")
    func ageBandRePrimes() async {
        let service = PredictorService()
        await service.setAgeBand(.menopausal)
        // Add 12 cycles. Pattern should be derivable — the menopausal-
        // prior mixture is still functional.
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let pattern = await service.cyclePattern()
        #expect(pattern != nil,
                "Setting age band before observing should still allow pattern to emerge at N=12")
    }
}
