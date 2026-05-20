import Foundation

/// The state machine that governs what the predictor is allowed to do.
/// See docs/design/disrupted-cycles.md § Algorithm Reactions.
public enum PredictorMode: Sendable, Equatable {
    case active(CyclePredictor)
    case paused(archived: CyclePredictor, since: Date, reason: PauseReason)
    case retired(since: Date, reason: RetirementReason)
}

public enum PauseReason: String, Codable, Sendable {
    case breastfeeding
    case hormonalContraception
    case hypothalamicAmenorrhea
    case userInitiated
}

public enum RetirementReason: String, Codable, Sendable {
    case hysterectomy
    case oophorectomy
    case userInitiated
}

extension PredictorMode {
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
    public var isRetired: Bool {
        if case .retired = self { return true }
        return false
    }

    /// The predictor you can act on right now. Nil if paused or retired.
    public var activePredictor: CyclePredictor? {
        guard case .active(let p) = self else { return nil }
        return p
    }

    /// Read-only access to whichever predictor state is on record (active or archived).
    /// Use for displaying historical μ, not for issuing new predictions.
    public var archivedPredictor: CyclePredictor? {
        switch self {
        case .active(let p): return p
        case .paused(let archived, _, _): return archived
        case .retired: return nil
        }
    }
}
