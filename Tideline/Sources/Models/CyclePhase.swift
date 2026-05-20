import Foundation
import SwiftUI

/// The four+1 visible cycle phases. Naming defaults to the tide metaphor per
/// `docs/design/tideline-visual-language.md`; clinical names available via
/// `clinicalName` for the settings toggle.
public enum CyclePhase: String, CaseIterable, Sendable {
    case menses             // Blutung — coral/peach (sunrise)
    case follicular         // aufsteigende Flut — turquoise (morning)
    case ovulation          // Hochwasser — gold (midday)
    case lutealEarly        // fallende Flut — amber (afternoon)
    case lutealLate         // Dämmerung — dusky purple (sunset)

    public var tideName: String {
        switch self {
        case .menses: return "Periode"
        case .follicular: return "aufsteigende Flut"
        case .ovulation: return "Hochwasser"
        case .lutealEarly: return "fallende Flut"
        case .lutealLate: return "Dämmerung"
        }
    }

    public var clinicalName: String {
        switch self {
        case .menses: return "Menstruation"
        case .follicular: return "Follikelphase"
        case .ovulation: return "Ovulationsfenster"
        case .lutealEarly: return "Lutealphase"
        case .lutealLate: return "späte Lutealphase"
        }
    }
}

/// Computed phase boundaries for one cycle.
/// See `docs/design/tideline-visual-language.md` § Phase boundary computation.
/// Day numbers are 1-indexed (cycle day 1 = first day of menses).
public struct PhaseBoundaries: Sendable, Equatable {
    public let mensesEnd: Int           // last bleeding day (inclusive)
    public let ovulation: Int           // estimated ovulation day
    public let cycleLength: Int         // predicted length of this cycle

    public var follicularStart: Int { mensesEnd + 1 }
    public var follicularEnd: Int { ovulation - 3 }
    public var ovulationWindowStart: Int { ovulation - 2 }
    public var ovulationWindowEnd: Int { ovulation + 2 }
    public var lutealEarlyStart: Int { ovulation + 3 }
    public var lutealEarlyEnd: Int { min(cycleLength - 4, lutealEarlyStart + 7) }
    public var lutealLateStart: Int { lutealEarlyEnd + 1 }
    public var lutealLateEnd: Int { cycleLength }

    /// Map a cycle day → phase. Days before menses end (inclusive) = .menses.
    public func phase(forDay day: Int) -> CyclePhase {
        if day <= mensesEnd { return .menses }
        if day < ovulationWindowStart { return .follicular }
        if day <= ovulationWindowEnd { return .ovulation }
        if day <= lutealEarlyEnd { return .lutealEarly }
        return .lutealLate
    }

    /// Default boundaries when we have no per-user data yet — uses the
    /// population-prior cycle length (29) and median menses (5).
    /// Ovulation = cycleLength − 14 per the clinical folk rule
    /// (Bull 2019 empirical luteal ≈ 12.4 days; the 14 is a heuristic the
    /// soft phase-band gradient is wide enough to absorb).
    public static let populationDefault = PhaseBoundaries(
        mensesEnd: 5,
        ovulation: 15,
        cycleLength: 29
    )

    /// Build from a predicted cycle length and observed menses end.
    public static func from(cycleLength: Int, mensesEnd: Int) -> PhaseBoundaries {
        PhaseBoundaries(
            mensesEnd: max(1, mensesEnd),
            ovulation: max(mensesEnd + 2, cycleLength - 14),
            cycleLength: max(cycleLength, mensesEnd + 7)
        )
    }
}

/// Phase colors. Each phase has a day-mode and dark-mode anchor.
/// Soft transitions between adjacent phases are handled at render time
/// via gradient stops, not as separate enum cases.
public struct PhasePalette {
    public static func color(for phase: CyclePhase, scheme: ColorScheme) -> Color {
        switch (phase, scheme) {
        // Day mode — sunrise → midday → sunset palette
        case (.menses, .light):       return Color(red: 0.93, green: 0.46, blue: 0.45)  // deep coral
        case (.follicular, .light):   return Color(red: 0.56, green: 0.82, blue: 0.88)  // pale turquoise
        case (.ovulation, .light):    return Color(red: 0.98, green: 0.78, blue: 0.36)  // bright gold
        case (.lutealEarly, .light):  return Color(red: 0.93, green: 0.65, blue: 0.45)  // amber
        case (.lutealLate, .light):   return Color(red: 0.55, green: 0.42, blue: 0.62)  // dusky purple

        // Dark mode — night palette
        case (.menses, .dark):        return Color(red: 0.62, green: 0.18, blue: 0.22)  // deep ember
        case (.follicular, .dark):    return Color(red: 0.18, green: 0.42, blue: 0.58)  // phosphor turquoise
        case (.ovulation, .dark):     return Color(red: 0.72, green: 0.55, blue: 0.20)  // moonlit gold
        case (.lutealEarly, .dark):   return Color(red: 0.58, green: 0.35, blue: 0.30)  // aurora amber
        case (.lutealLate, .dark):    return Color(red: 0.28, green: 0.20, blue: 0.42)  // twilight violet

        @unknown default:
            return Color.gray
        }
    }

    /// Neutral palette for paused / retired modes — "ruhige See".
    public static func neutralColor(scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color(red: 0.20, green: 0.28, blue: 0.34)
        case .light: return Color(red: 0.72, green: 0.80, blue: 0.82)
        @unknown default: return Color.gray
        }
    }
}
