import Testing
import Foundation
@testable import Tideline

/// Tests for `RecognitionTemplates` (task #121). Pins:
///   - every reachable (phase, zone) cell has at least one template
///   - no template contains banned instructional verbs (regex-driven)
///   - selection is deterministic for fixed input
///   - selection rotates across days within a cycle
///   - `zone(forDay:)` correctly classifies edge cases
@Suite("RecognitionTemplates — German recognition copy")
struct RecognitionTemplatesTests {

    private let standardBoundaries = PhaseBoundaries.populationDefault

    // MARK: - Coverage

    /// Every (phase, zone) combination that the `zone(forDay:)` classifier
    /// can actually produce for a 29-day cycle has at least one template.
    /// If someone adds a new zone enum case without populating templates,
    /// this fails loudly.
    @Test("Every reachable (phase, zone) cell has at least one template")
    func everyReachableCellNonEmpty() {
        let boundaries = standardBoundaries
        var reachableCells: Set<String> = []
        for day in 1...boundaries.cycleLength {
            let phase = boundaries.phase(forDay: day)
            let zone = RecognitionTemplates.zone(forDay: day, boundaries: boundaries)
            let cellKey = "\(phase.rawValue)|\(zone.rawValue)"
            if reachableCells.contains(cellKey) { continue }
            reachableCells.insert(cellKey)
            let templates = RecognitionTemplates.templates(for: phase, zone: zone)
            #expect(!templates.isEmpty,
                    "Cell (\(phase), \(zone)) is reachable on day \(day) but has no templates")
        }
    }

    /// Every reachable cell has a non-empty headline + body.
    @Test("Every reachable template has non-empty headline + body")
    func everyTemplateNonEmpty() {
        let boundaries = standardBoundaries
        var seen: Set<String> = []
        for day in 1...boundaries.cycleLength {
            let phase = boundaries.phase(forDay: day)
            let zone = RecognitionTemplates.zone(forDay: day, boundaries: boundaries)
            let cellKey = "\(phase.rawValue)|\(zone.rawValue)"
            if seen.contains(cellKey) { continue }
            seen.insert(cellKey)
            for template in RecognitionTemplates.templates(for: phase, zone: zone) {
                #expect(!template.headline.isEmpty)
                #expect(!template.body.isEmpty)
            }
        }
    }

    // MARK: - Recognition-framing rule

    /// No template body or headline contains banned instructional/diagnostic
    /// verbs. Per UI plan §5 + CLAUDE.md Pillar 7 (no MDR drift).
    @Test("No template contains banned instructional / diagnostic verbs")
    func noBannedVerbs() {
        // Match case-insensitive; german umlauts handled by Foundation.
        let banned: [String] = [
            "du solltest",
            "du musst",
            "du sollst",
            "wahrscheinlich hast du",
            "du leidest",
            "diagnose",
            "krankheit",
            // Imperative + infinitive constructions (reviewer rec):
            "tracke ",
            "tracking",
            "nimm ",
            "ruh dich",
            "trinke ",
            "ernähre dich",
            // English fallback safety nets:
            "you should",
            "you must"
        ]
        let boundaries = standardBoundaries
        var seen: Set<String> = []
        for day in 1...boundaries.cycleLength {
            let phase = boundaries.phase(forDay: day)
            let zone = RecognitionTemplates.zone(forDay: day, boundaries: boundaries)
            let cellKey = "\(phase.rawValue)|\(zone.rawValue)"
            if seen.contains(cellKey) { continue }
            seen.insert(cellKey)
            for template in RecognitionTemplates.templates(for: phase, zone: zone) {
                let combined = (template.headline + " " + template.body).lowercased()
                for verb in banned {
                    #expect(!combined.contains(verb),
                            "Template '\(template.headline)' contains banned verb '\(verb)'")
                }
            }
        }
    }

    // MARK: - Selection determinism

    @Test("pick is deterministic for fixed input")
    func pickDeterministic() {
        let boundaries = standardBoundaries
        for day in 1...boundaries.cycleLength {
            let phase = boundaries.phase(forDay: day)
            let a = RecognitionTemplates.pick(
                phase: phase, dayInCycle: day, boundaries: boundaries, cycleStartHash: 42
            )
            let b = RecognitionTemplates.pick(
                phase: phase, dayInCycle: day, boundaries: boundaries, cycleStartHash: 42
            )
            #expect(a == b, "pick must be deterministic for day \(day)")
        }
    }

    @Test("pick varies across days (rotation works)")
    func pickRotatesAcrossDays() {
        // Within a phase that has 2+ days, consecutive days should not
        // always return the same template (assumes at least 2 templates
        // per cell — which the coverage test pins).
        let boundaries = standardBoundaries
        // Look at follicular days, which always span ≥3 days.
        var seenTemplates: Set<String> = []
        for day in boundaries.follicularStart...(boundaries.ovulationWindowStart - 1) {
            let template = RecognitionTemplates.pick(
                phase: .follicular, dayInCycle: day, boundaries: boundaries, cycleStartHash: 0
            )
            seenTemplates.insert(template.headline)
        }
        // Across 5–7 follicular days we should see at least 2 distinct
        // templates (with 2+ templates per zone × 2 zones in follicular).
        #expect(seenTemplates.count >= 2,
                "Rotation should produce at least 2 distinct templates across follicular days")
    }

    @Test("pick varies across cycleStartHash (rotation by cycle)")
    func pickRotatesAcrossCycles() {
        let boundaries = standardBoundaries
        let day = 5  // mensesMid for a default cycle
        let phase = boundaries.phase(forDay: day)
        var seenTemplates: Set<String> = []
        for hash in 0..<20 {
            let template = RecognitionTemplates.pick(
                phase: phase, dayInCycle: day, boundaries: boundaries, cycleStartHash: hash
            )
            seenTemplates.insert(template.headline)
        }
        // Across 20 cycle-start hashes we should see most of the
        // mensesMid templates (currently 4).
        #expect(seenTemplates.count >= 2,
                "Rotation across cycles should produce variety; got only \(seenTemplates.count)")
    }

    // MARK: - Zone classifier edge cases

    @Test("Day 1 is mensesEarly")
    func day1IsMensesEarly() {
        #expect(RecognitionTemplates.zone(forDay: 1, boundaries: standardBoundaries) == .mensesEarly)
    }

    @Test("Day 2 is mensesEarly, day 3 is mensesMid (for default 5-day menses)")
    func mensesBoundary() {
        let b = standardBoundaries  // mensesEnd = 5
        #expect(RecognitionTemplates.zone(forDay: 2, boundaries: b) == .mensesEarly)
        #expect(RecognitionTemplates.zone(forDay: 3, boundaries: b) == .mensesMid)
        #expect(RecognitionTemplates.zone(forDay: 5, boundaries: b) == .mensesMid)
    }

    @Test("Day equal to ovulationWindowStart is ovulationPeak")
    func ovulationStartBoundary() {
        let b = standardBoundaries
        #expect(RecognitionTemplates.zone(forDay: b.ovulationWindowStart, boundaries: b) == .ovulationPeak)
    }

    @Test("Day equal to ovulationWindowEnd is ovulationPeak")
    func ovulationEndBoundary() {
        let b = standardBoundaries
        #expect(RecognitionTemplates.zone(forDay: b.ovulationWindowEnd, boundaries: b) == .ovulationPeak)
    }

    @Test("Day after ovulationWindowEnd is lutealEarly")
    func lutealStartBoundary() {
        let b = standardBoundaries
        #expect(RecognitionTemplates.zone(forDay: b.ovulationWindowEnd + 1, boundaries: b) == .lutealEarly)
    }

    @Test("Day equal to cycleLength is lutealLate")
    func cycleEndBoundary() {
        let b = standardBoundaries
        #expect(RecognitionTemplates.zone(forDay: b.cycleLength, boundaries: b) == .lutealLate)
    }

    // MARK: - Walk-the-cycle coverage

    @Test("Walking every day 1...30 through pick returns non-nil templates")
    func walkEveryDayReturnsTemplate() {
        let boundaries = standardBoundaries
        for day in 1...30 {
            let phase = boundaries.phase(forDay: min(day, boundaries.cycleLength))
            let template = RecognitionTemplates.pick(
                phase: phase, dayInCycle: day, boundaries: boundaries, cycleStartHash: 0
            )
            #expect(!template.headline.isEmpty)
            #expect(!template.body.isEmpty)
        }
    }
}
