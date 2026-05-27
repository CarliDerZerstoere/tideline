import Foundation

/// Coarse age stratification for the predictor's population prior (task #97).
/// Five buckets + an explicit "no answer" case so the user can decline to
/// share without the app silently substituting a value.
///
/// Values for `withinPersonSDDays` come from Mahalingaiah et al. 2023 (AWHS,
/// PMC10226714, n=165,668 cycles), Table 2 within-person SD by age. The
/// paper publishes four bands directly; the mid-bands (20–34, 40–44) are
/// snapped to the nearest published band using a step function (NOT
/// linear interpolation — that would manufacture precision the source
/// doesn't have).
///
/// `RawValue: String` so `@AppStorage("userAgeBand")` can round-trip the
/// case directly without a separate codec.
///
/// v2 mixture predictor (#83) will absorb this enum into its prior — the
/// type itself is forward-compatible and survives that refactor.
public enum AgeBand: String, CaseIterable, Sendable, Equatable {
    case unspecified         = "unspecified"
    case adolescent          = "adolescent"          // <20
    case reproductive        = "reproductive"        // 20–39
    case perimenopausalEarly = "perimenopausalEarly" // 40–44
    case perimenopausal      = "perimenopausal"      // 45–49
    case menopausal          = "menopausal"          // 50+

    /// Within-person standard deviation of cycle length, in days.
    ///
    /// AWHS-published values (direct quotes from the paper):
    ///   - Under 20:   5.33  → `.adolescent`
    ///   - Ages 35–39: 3.79  → `.reproductive` (the band's lowest)
    ///   - Ages 45–49: 5.42  → `.perimenopausal`
    ///   - Age 50+:   11.19  → `.menopausal`
    ///
    /// Step-extrapolated bands:
    ///   - `.reproductive` (20–39) uses the 35–39 figure 3.79; the AWHS
    ///     J-curve has its trough at 35–39 but variance is comparable
    ///     across 20–39 (paper's text describes it as the "low and
    ///     relatively flat" portion).
    ///   - `.perimenopausalEarly` (40–44) snaps to the 45–49 value
    ///     5.42; conservative-by-a-modest-amount given the J-curve
    ///     climbs through the 40s. Honest about the data gap.
    ///
    /// `.unspecified` uses 5.0 as a modeling-choice fallback — roughly
    /// midway between the published bands, chosen so a no-answer user
    /// gets a prior that's neither over-precise (3.79) nor wildly wide
    /// (11.19). Flagged in code as a modeling decision rather than a
    /// verbatim AWHS figure.
    public var withinPersonSDDays: Double {
        switch self {
        case .unspecified:         return 5.0
        case .adolescent:          return 5.33
        case .reproductive:        return 3.79
        case .perimenopausalEarly: return 5.42
        case .perimenopausal:      return 5.42
        case .menopausal:          return 11.19
        }
    }

    /// Auto-localizing label for SwiftUI `Text(_:)` (task #129). See
    /// `EventKind.localizedLabel` for the rationale on why both
    /// `localizedLabel` and `germanLabel` coexist.
    public var localizedLabel: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: germanLabel)
    }

    /// German display label for the onboarding picker + settings row.
    public var germanLabel: String {
        switch self {
        case .unspecified:         return "Lieber nicht angeben"
        case .adolescent:          return "Unter 20"
        case .reproductive:        return "20 – 39"
        case .perimenopausalEarly: return "40 – 44"
        case .perimenopausal:      return "45 – 49"
        case .menopausal:          return "50 oder älter"
        }
    }

    /// Order used for both the onboarding radio list and the settings
    /// picker. `.unspecified` ships last as the "decline" option — the
    /// real bands are listed first so the user sees them as the
    /// primary choices rather than as alternatives to "decline."
    public static let displayOrder: [AgeBand] = [
        .adolescent,
        .reproductive,
        .perimenopausalEarly,
        .perimenopausal,
        .menopausal,
        .unspecified,
    ]
}
