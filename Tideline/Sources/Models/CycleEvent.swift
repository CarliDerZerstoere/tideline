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
    /// Task #136 NEW-J — neutral catchall for users who don't want to
    /// medically sub-categorize their loss. Same algorithmic effect as
    /// the specific loss kinds (Category C soft-reset + isPregnancyLoss
    /// flag → #122 suppression). Covers pre-clinical losses, losses the
    /// user prefers not to label, or losses where the medical category
    /// isn't clear.
    case pregnancyLoss
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
    /// Task #135 NEW-I. Distinct from `.acuteIllnessSevere` (Category C
    /// soft-reset class): this is the cold / mild-fever / short-duration
    /// case where AWHS-type literature shows a small effect (+0.34–0.62
    /// days, PMC12083795 / PMC12168487 for the vaccine subset). Formal
    /// soft-reset would over-react; Category D outlier-rejection via #96
    /// drops the affected cycle's observation without touching the
    /// posterior's location estimate.
    case mildIllness
    case vaccination

    // Category E — Ongoing irregularity (widen β)
    case pcosDeclared
    case perimenopauseDeclared
    case ongoingIrregularityOther

    // Category F — Resume after pause (un-pause + soft reset)
    case resumeAfterPause
}

public enum EventCategory: String, Sendable {
    case complete    // A: retire
    case pause       // B: pause + archive
    case recoverable // C: outlier-reject + soft reset (active mode only)
    case anomaly     // D: outlier-reject only
    case ongoing     // E: widen β
    case resume      // F: un-pause + soft-reset the archived predictor (paused mode only)
}

extension EventKind {
    /// Only Category-B (`.pause`) events have a meaningful `pauseReason`.
    /// All other categories fall through to `.userInitiated` as a
    /// defensive default, but callers should never read this property
    /// for a non-pause event — `apply(eventKind:on:)` only consults it
    /// inside the `case .pause` arm. The default is here to keep the
    /// switch exhaustive without forcing every category to invent a
    /// fictional reason. If a future feature reads this for an
    /// arbitrary event, it will silently see `.userInitiated` for
    /// e.g. resume / anomaly / ongoing events — flagging here so the
    /// next reader doesn't introduce that drift.
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

    /// Same caveat as `pauseReason`: only Category-A (`.complete`) events
    /// should be read via this property. Other categories fall through
    /// to `.userInitiated` to keep the switch exhaustive.
    public var retirementReason: RetirementReason {
        switch self {
        case .hysterectomy: return .hysterectomy
        case .oophorectomy: return .oophorectomy
        default: return .userInitiated
        }
    }

    /// True for the specific subset of Category C events that represent
    /// a pregnancy loss (task #122). Used by `NotificationGate` to
    /// suppress cycle-prediction notifications for 28 days after such
    /// an event — CLAUDE.md hard rule, Pillar 4.
    ///
    /// Distinct from the broader `EventCategory.recoverable`: many
    /// recoverable events (acute illness, extreme stress, weight change,
    /// stopping contraception) are NOT losses and don't warrant
    /// outbound-notification silence. Birth without breastfeeding is
    /// also Category C but is a birth, not a loss.
    public var isPregnancyLoss: Bool {
        switch self {
        case .miscarriageEarly,
             .miscarriageLate,
             .medicalAbortion,
             .surgicalAbortion,
             .pregnancyLoss:
            return true
        default:
            return false
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
             .pregnancyLoss,
             .birthNoBreastfeeding,
             .stoppedHormonalContraception, .stoppedIUDHormonal,
             .acuteIllnessSevere, .majorSurgery,
             .significantWeightChange, .extremeStress:
            return .recoverable
        case .singleAnomaly,
             .emergencyContraceptionFollicular,
             .emergencyContraceptionPeriOrLuteal,
             .mildIllness,
             .vaccination:
            return .anomaly
        case .pcosDeclared, .perimenopauseDeclared, .ongoingIrregularityOther:
            return .ongoing
        case .resumeAfterPause:
            return .resume
        }
    }

    /// Auto-localizing label for SwiftUI `Text(_:)` (task #129). Looks
    /// up `germanLabel` as the key in `Localizable.strings` — when the
    /// device locale is EN, returns the translated string from
    /// `en.lproj`; falls back to the literal German source for any
    /// missing key.
    ///
    /// Prefer this over `germanLabel` for UI display. PDF + tests
    /// keep using `germanLabel` directly (the Doctor PDF must always
    /// render in German regardless of device locale — clinical doc
    /// going to a DACH practitioner).
    public var localizedLabel: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: germanLabel)
    }

    /// Literal German source string. Used as:
    ///   1. The lookup key in `Localizable.strings` for
    ///      `localizedLabel`.
    ///   2. The Doctor PDF rendering (always-DE per clinical-doc
    ///      convention).
    ///   3. Test assertions (stable across locales).
    ///
    /// Phrased neutrally — never says "abortion" / "miscarriage" in a
    /// way that adds emotional weight beyond what the user themselves
    /// chose by logging the event. Keep close to the user's framing.
    public var germanLabel: String {
        switch self {
        // Category A
        case .hysterectomy: return "Hysterektomie"
        case .oophorectomy: return "Oophorektomie"
        // Category B
        case .birthBreastfeeding: return "Geburt, mit Stillzeit"
        case .startedCombinedContraception: return "Hormonelle Verhütung gestartet"
        case .startedProgestinOnlyContraception: return "Gestagen-Verhütung gestartet"
        case .startedIUDHormonal: return "Hormonspirale gestartet"
        case .startedInjectableContraception: return "Verhütungsspritze gestartet"
        case .hypothalamicAmenorrhea: return "Hypothalamische Amenorrhoe"
        // Category C
        case .medicalAbortion: return "Medikamentöser Abbruch"
        case .surgicalAbortion: return "Chirurgischer Abbruch"
        case .miscarriageEarly: return "Fehlgeburt (früh)"
        case .miscarriageLate: return "Fehlgeburt (spät)"
        case .pregnancyLoss: return "Schwangerschaftsverlust"
        case .birthNoBreastfeeding: return "Geburt, ohne Stillzeit"
        case .stoppedHormonalContraception: return "Hormonelle Verhütung beendet"
        case .stoppedIUDHormonal: return "Hormonspirale entfernt"
        case .acuteIllnessSevere: return "Schwere Erkrankung"
        case .majorSurgery: return "Größere Operation"
        case .significantWeightChange: return "Deutliche Gewichtsveränderung"
        case .extremeStress: return "Starker Stress"
        // Category D
        case .singleAnomaly: return "Einmalige Abweichung"
        case .emergencyContraceptionFollicular: return "Notfallverhütung (Follikelphase)"
        case .emergencyContraceptionPeriOrLuteal: return "Notfallverhütung (peri/luteal)"
        case .mildIllness: return "Leichte Krankheit (z. B. Erkältung)"
        case .vaccination: return "Impfung"
        // Category E
        case .pcosDeclared: return "Unregelmäßige Zyklen (deklariert)"
        case .perimenopauseDeclared: return "Perimenopause (deklariert)"
        case .ongoingIrregularityOther: return "Andere Zyklus-Besonderheit"
        // Category F
        case .resumeAfterPause: return "Zyklus wieder aufgenommen"
        }
    }
}
