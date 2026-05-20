import Foundation

/// A point prediction with a credible interval.
public struct Prediction: Sendable, Equatable {
    public let estimate: Date
    public let interval: ClosedRange<Date>
    public let isWidenedRecovery: Bool
}

/// Owns the predictor's mode and routes life-events to the right action.
/// See docs/design/disrupted-cycles.md § Category-to-action lookup table.
///
/// **No-op contract:** `apply(event:)` silently returns without effect when
/// the mode is incompatible with the event's category (e.g., Category C event
/// during `.paused` or `.retired`). Callers driving UI must check
/// `currentMode()` before presenting options. An unrecognized `EventKind`
/// raw value (future app version writing to older schema) is also a no-op.
public actor PredictorService {
    private var mode: PredictorMode

    public init(mode: PredictorMode = .active(.populationPrior)) {
        self.mode = mode
    }

    public func currentMode() -> PredictorMode { mode }

    /// Apply a life-event by kind + date. Routes to retire / pause / softReset
    /// / widen / no-op. Takes primitives (not the SwiftData `@Model` class)
    /// so it can be called safely across actor boundaries.
    public func apply(eventKind kind: EventKind, on date: Date) {
        switch kind.category {
        case .complete:
            mode = .retired(since: date, reason: kind.retirementReason)

        case .pause:
            let archived = mode.archivedPredictor ?? .populationPrior
            mode = .paused(archived: archived, since: date, reason: kind.pauseReason)

        case .recoverable:
            if case .active(var p) = mode {
                p.softReset()
                mode = .active(p)
            }
            // Paused/retired: no-op — caller must resume() first.

        case .anomaly:
            // Outlier-reject only — the disrupted cycle is suppressed at the
            // observe() boundary, not here.
            break

        case .ongoing:
            if case .active(var p) = mode {
                p.declareOngoingIrregularity()
                mode = .active(p)
            }
        }
    }

    /// Observe a completed cycle length (days). Returns true if applied,
    /// false if suppressed by mode.
    @discardableResult
    public func observe(cycleLength days: Double) -> Bool {
        guard case .active(var p) = mode else { return false }
        p.observe(cycleLength: days)
        mode = .active(p)
        return true
    }

    /// Observe a sequence of cycle lengths. Returns how many were applied.
    @discardableResult
    public func observe(cycleLengths: [Double]) -> Int {
        var applied = 0
        for x in cycleLengths where observe(cycleLength: x) { applied += 1 }
        return applied
    }

    /// Next-period prediction. Returns nil if paused or retired.
    public func nextPrediction(
        after lastPeriodStart: Date,
        confidence: Double = 0.90
    ) -> Prediction? {
        guard let p = mode.activePredictor else { return nil }
        let estimate = p.nextPeriodDate(after: lastPeriodStart)
        let interval = p.nextPeriodDateInterval(after: lastPeriodStart, confidence: confidence)
        return Prediction(
            estimate: estimate,
            interval: interval,
            isWidenedRecovery: p.isInRecoveryWindow
        )
    }

    /// Conditional credible interval given the cycle has run `daysSinceLastPeriod`
    /// without a new period starting yet. Returns nil if paused/retired.
    public func conditionalInterval(
        daysSinceLastPeriod D: Double,
        confidence: Double = 0.90
    ) -> ClosedRange<Double>? {
        guard let p = mode.activePredictor else { return nil }
        return p.conditionalInterval(currentDay: D, confidence: confidence)
    }

    /// Resume from `.paused`. Performs a soft-reset on the archived posterior.
    public func resume() {
        if case .paused(var archived, _, _) = mode {
            archived.softReset()
            mode = .active(archived)
        }
    }
}
