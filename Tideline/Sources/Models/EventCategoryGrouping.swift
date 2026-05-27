import Foundation

/// User-intent groupings of `EventKind` for the LogEventSheet picker
/// (task #75). Distinct from the algorithm-internal `EventCategory`
/// (which classifies events by their predictor reaction: retire / pause
/// / soft-reset / etc.). Users think in life-event domains — pregnancy,
/// contraception, surgery — not in math-driven categories.
///
/// The mapping is a total function: every `EventKind` belongs to
/// exactly one `EventUserGroup`. Pinned by `EventCategoryGroupingTests`
/// so adding a new `EventKind` without grouping it fails loudly at
/// test time.
public enum EventUserGroup: String, CaseIterable, Sendable {
    case pregnancy
    case contraception
    case surgery
    case health
    case irregularity
    case misc

    public var germanLabel: String {
        switch self {
        case .pregnancy:     return "Schwangerschaft & Geburt"
        case .contraception: return "Verhütung"
        case .surgery:       return "Operation"
        case .health:        return "Gesundheit"
        case .irregularity:  return "Zyklus-Besonderheiten"
        case .misc:          return "Sonstiges"
        }
    }

    /// Auto-localizing label for SwiftUI `Text(_:)` (task #129). See
    /// `EventKind.localizedLabel` for the rationale.
    public var localizedLabel: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: germanLabel)
    }
}

public enum EventCategoryGrouping {

    /// User-intent group for a given `EventKind`. Total function — every
    /// `EventKind` belongs to exactly one group.
    public static func userGroup(for kind: EventKind) -> EventUserGroup {
        switch kind {
        // Pregnancy
        case .birthBreastfeeding, .birthNoBreastfeeding,
             .miscarriageEarly, .miscarriageLate,
             .medicalAbortion, .surgicalAbortion,
             .pregnancyLoss:
            return .pregnancy

        // Contraception
        case .startedCombinedContraception,
             .startedProgestinOnlyContraception,
             .startedIUDHormonal,
             .startedInjectableContraception,
             .stoppedHormonalContraception,
             .stoppedIUDHormonal,
             .emergencyContraceptionFollicular,
             .emergencyContraceptionPeriOrLuteal:
            return .contraception

        // Surgery
        case .hysterectomy, .oophorectomy, .majorSurgery:
            return .surgery

        // Health
        case .acuteIllnessSevere, .hypothalamicAmenorrhea,
             .significantWeightChange, .extremeStress,
             .mildIllness, .vaccination:
            return .health

        // Irregularity (user-declared)
        case .pcosDeclared, .perimenopauseDeclared, .ongoingIrregularityOther:
            return .irregularity

        // Misc
        case .singleAnomaly, .resumeAfterPause:
            return .misc
        }
    }

    /// All `EventKind`s in a given user group, in stable display order
    /// (declaration order of `EventKind.allCases` filtered to the group).
    public static func events(in group: EventUserGroup) -> [EventKind] {
        EventKind.allCases.filter { userGroup(for: $0) == group }
    }

    /// User-visible events for the manual picker — excludes events the
    /// app fires automatically and that don't make sense to log
    /// manually. Currently filters out `.resumeAfterPause` (auto-fired
    /// by `ResumeAfterPauseSheet`; manual logging from .active mode is
    /// a no-op per `PredictorService.swift:74`). Reviewer rec #5.
    public static func userVisibleEvents(in group: EventUserGroup) -> [EventKind] {
        events(in: group).filter { kind in
            kind != .resumeAfterPause
        }
    }

    /// Tone of the post-log acknowledgment screen. `.none` skips the
    /// screen entirely. Splits Cat A (permanent retirement) from Cat C
    /// losses so the German copy can avoid the off-key
    /// "Wenn du wieder loslegen möchtest" suggestion for a user whose
    /// fertility-tracking has ended. Reviewer rec #1+#9.
    public enum SensitivityTone: Equatable {
        case none
        case retirement   // Cat A — permanent (hysterectomy, oophorectomy)
        case loss         // Cat C losses — recoverable
    }

    public static func sensitivityTone(_ kind: EventKind) -> SensitivityTone {
        switch kind {
        case .hysterectomy, .oophorectomy:
            return .retirement
        case .medicalAbortion, .surgicalAbortion,
             .miscarriageEarly, .miscarriageLate,
             .pregnancyLoss:
            return .loss
        default:
            return .none
        }
    }

    /// All groups in display order.
    public static var allGroupsInOrder: [EventUserGroup] {
        EventUserGroup.allCases
    }

    /// Convenience wrapper: any tone other than `.none` warrants the
    /// warm acknowledgment screen.
    public static func isSensitive(_ kind: EventKind) -> Bool {
        sensitivityTone(kind) != .none
    }
}
