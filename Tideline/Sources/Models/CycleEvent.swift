import Foundation
import SwiftData

/// Life events that affect the cycle predictor's behavior.
/// See docs/design/disrupted-cycles.md for the full taxonomy.
@Model
public final class CycleEvent {
    public var date: Date
    public var kindRaw: String
    public var note: String

    public init(date: Date, kind: EventKind, note: String = "") {
        self.date = date
        self.kindRaw = kind.rawValue
        self.note = note
    }

    /// Decoded event kind, or nil if the stored raw string is unrecognized
    /// (e.g., written by a newer app version). Callers must handle nil safely —
    /// silently treating unknowns as a default category would risk skipping a
    /// retirement or pause that the user explicitly logged.
    public var kind: EventKind? {
        EventKind(rawValue: kindRaw)
    }
}

public enum EventKind: String, Codable, CaseIterable, Sendable {
    // Category A — Complete disruption (retire predictor)
    case hysterectomy
    case oophorectomy

    // Category B — Extended pause (pause + archive)
    case birthBreastfeeding
    case startedCombinedContraception
    case startedProgestinOnlyContraception
    case startedIUDHormonal
    case startedInjectableContraception
    case hypothalamicAmenorrhea

    // Category C — Recoverable disruption (outlier-reject + soft reset)
    case medicalAbortion
    case surgicalAbortion
    case miscarriageEarly
    case miscarriageLate
    case birthNoBreastfeeding
    case stoppedHormonalContraception
    case stoppedIUDHormonal
    case acuteIllnessSevere
    case majorSurgery
    case significantWeightChange
    case extremeStress

    // Category D — Single anomaly (outlier-reject only)
    case singleAnomaly
    case emergencyContraceptionFollicular
    case emergencyContraceptionPeriOrLuteal

    // Category E — Ongoing irregularity (widen β)
    case pcosDeclared
    case perimenopauseDeclared
    case ongoingIrregularityOther
}

public enum EventCategory: String, Sendable {
    case complete    // A: retire
    case pause       // B: pause + archive
    case recoverable // C: outlier-reject + soft reset
    case anomaly     // D: outlier-reject only
    case ongoing     // E: widen β
}

extension EventKind {
    public var pauseReason: PauseReason {
        switch self {
        case .birthBreastfeeding: return .breastfeeding
        case .startedCombinedContraception,
             .startedProgestinOnlyContraception,
             .startedIUDHormonal,
             .startedInjectableContraception:
            return .hormonalContraception
        case .hypothalamicAmenorrhea: return .hypothalamicAmenorrhea
        default: return .userInitiated
        }
    }

    public var retirementReason: RetirementReason {
        switch self {
        case .hysterectomy: return .hysterectomy
        case .oophorectomy: return .oophorectomy
        default: return .userInitiated
        }
    }

    public var category: EventCategory {
        switch self {
        case .hysterectomy, .oophorectomy:
            return .complete
        case .birthBreastfeeding,
             .startedCombinedContraception,
             .startedProgestinOnlyContraception,
             .startedIUDHormonal,
             .startedInjectableContraception,
             .hypothalamicAmenorrhea:
            return .pause
        case .medicalAbortion, .surgicalAbortion,
             .miscarriageEarly, .miscarriageLate,
             .birthNoBreastfeeding,
             .stoppedHormonalContraception, .stoppedIUDHormonal,
             .acuteIllnessSevere, .majorSurgery,
             .significantWeightChange, .extremeStress:
            return .recoverable
        case .singleAnomaly,
             .emergencyContraceptionFollicular,
             .emergencyContraceptionPeriOrLuteal:
            return .anomaly
        case .pcosDeclared, .perimenopauseDeclared, .ongoingIrregularityOther:
            return .ongoing
        }
    }
}
