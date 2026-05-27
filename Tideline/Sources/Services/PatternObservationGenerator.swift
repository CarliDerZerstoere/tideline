import Foundation

/// Direction of a detected cycle-length trend.
enum TrendDirection: Sendable, Equatable {
    case longer
    case shorter
}

/// A single observation about the user's recent cycle history, surfaced
/// on the Mein Zyklus tab's Layer 2 (task #120). German sentence is
/// pre-formatted so the view layer just renders the string.
///
/// `nil` is returned by the generator when no pattern is strong enough
/// to surface — the view layer renders a "Noch zu wenig Daten" fallback
/// instead of forcing a pattern that isn't there.
struct PatternObservation: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case cycleLengthStable(meanDays: Int)
        case cycleLengthTrending(direction: TrendDirection, deltaDays: Int)
    }

    let kind: Kind
    let germanSentence: String
    /// Inline visual data: the raw cycle lengths of the last N cycles,
    /// oldest first. Suitable for a small dot/sparkline next to the
    /// sentence.
    let sparklineValues: [Double]

    init(kind: Kind, germanSentence: String, sparklineValues: [Double]) {
        self.kind = kind
        self.germanSentence = germanSentence
        self.sparklineValues = sparklineValues
    }
}

/// Pure pattern detector for Mein Zyklus Layer 2 (task #120). Given a
/// list of recent past cycles (oldest first), picks the strongest
/// observation from a fixed priority order and returns it with a
/// pre-formatted German sentence. Returns `nil` when data is too sparse
/// or no pattern qualifies — the caller renders a low-data line.
///
/// **Priority order** (first match wins):
/// 1. **Cycle-length stability** — last 3–6 cycles' stdev ≤ 2 days →
///    *"Deine Zyklen sind konstant bei N Tagen."*
/// 2. **Cycle-length trend** — last 3 cycles all > mean+2 OR all < mean-2
///    → *"Deine Zyklen wurden in den letzten 3 Monaten länger/kürzer."*
///
/// **Out of scope for v1** (deferred to v1.1):
/// - Bleeding-day-count vs. average — needs per-cycle bleeding day counts
///   which aren't in `CycleSummary`. Wire when there's a reason to.
/// - Phase-specific pattern detection (e.g. "deine Lutealphase war
///   konstant 13 Tage") — needs phase boundaries per cycle, which we
///   don't store; PhaseBoundaries is derived from cycle length at render
///   time. Same constraint as above.
enum PatternObservationGenerator {

    /// Minimum cycles required before any pattern is surfaced. Below
    /// this, the view layer shows the low-data fallback message.
    static let minCyclesForPattern = 3

    /// Stability tolerance — last 3–6 cycles with stdev ≤ this many days
    /// counts as "stable". Tightened over time as confidence grows.
    static let stabilityToleranceDays: Double = 2.0

    /// Trend trigger — every cycle in the last 3 must differ from the
    /// overall mean by at least this much (in the same direction) to
    /// count as trending.
    static let trendTriggerDeltaDays: Double = 2.0

    static func generate(cycles: [CycleSummary]) -> PatternObservation? {
        guard cycles.count >= minCyclesForPattern else { return nil }

        // Look at the last 6 cycles (or fewer if the user has fewer).
        let recent = Array(cycles.suffix(6))
        let lengths = recent.map { Double($0.lengthDays) }
        let mean = lengths.reduce(0, +) / Double(lengths.count)

        // 1. Stability
        let stdev = standardDeviation(values: lengths, mean: mean)
        if stdev <= stabilityToleranceDays {
            let meanInt = Int(mean.rounded())
            return PatternObservation(
                kind: .cycleLengthStable(meanDays: meanInt),
                germanSentence: "Deine Zyklen sind konstant bei \(meanInt) Tagen.",
                sparklineValues: lengths
            )
        }

        // 2. Trend — last 3 cycles all on the same side of mean ± trigger
        if recent.count >= 3 {
            let last3 = lengths.suffix(3)
            let priorMean: Double = {
                let prior = Array(lengths.dropLast(3))
                guard !prior.isEmpty else { return mean }
                return prior.reduce(0, +) / Double(prior.count)
            }()
            let allLonger  = last3.allSatisfy { $0 > priorMean + trendTriggerDeltaDays }
            let allShorter = last3.allSatisfy { $0 < priorMean - trendTriggerDeltaDays }
            if allLonger || allShorter {
                let direction: TrendDirection = allLonger ? .longer : .shorter
                let last3Mean = last3.reduce(0, +) / Double(last3.count)
                let delta = Int(abs(last3Mean - priorMean).rounded())
                let germanDirection = direction == .longer ? "länger" : "kürzer"
                // Audit Wave-A fix (4.3): interpolate the computed
                // `delta` int into the user-facing sentence. Previously
                // the value was computed but never displayed — the
                // sentence said "länger" without the magnitude. "Um 3
                // Tage länger" is actionable; "länger" is not.
                //
                // German grammar: "um 1 Tag" vs "um N Tage" (plural).
                let germanDeltaPhrase = delta == 1 ? "1 Tag" : "\(delta) Tage"
                return PatternObservation(
                    kind: .cycleLengthTrending(direction: direction, deltaDays: delta),
                    germanSentence: "Deine Zyklen wurden in den letzten 3 Monaten um \(germanDeltaPhrase) \(germanDirection).",
                    sparklineValues: lengths
                )
            }
        }

        // No pattern strong enough to surface.
        return nil
    }

    // MARK: - Internal

    static func standardDeviation(values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let squaredDeltas = values.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDeltas.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }
}
