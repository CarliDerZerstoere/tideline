import Foundation

/// Late-period milestone classification — five buckets sized to the
/// research-supported breakpoints for "how late is late" perception.
///
/// **Copy was derived from `docs/design/late-mode-implementation.md`**
/// but tightened on 2026-05-21 after a fact-check pass found four
/// claims that were either unsupported or more directive than the
/// EU MDR wellness posture allows. The design doc still carries the
/// pre-fact-check wording and should be updated alongside any further
/// changes here. Deviations from the doc (each cited inline):
///
///   - **1–4 day bucket:** "±5 Tage" was directionally right for
///     adults (AWHS 2023 SD ≈ 3.79–5.33 days) but wrong for the
///     adolescent and perimenopausal extremes. Replaced with the
///     non-numeric "ein paar Tage in jede Richtung".
///
///   - **5–9 day bucket:** "Schlafmangel" was unsupported as a discrete
///     cause of cycle delay — published evidence is on shift work and
///     circadian disruption, not acute sleep loss. Dropped from the
///     list. Stress + travel + illness all have at least plausible
///     published support and stay.
///
///   - **10–14 day bucket:** "Viele Personen machen um diese Zeit
///     einen Schwangerschaftstest" was an uncited population-behaviour
///     claim. Reworded to anchor in test *reliability* (Cole 2004,
///     PMID 14749643: >97% sensitive a week past expected period) per
///     standard NHS/ACOG patient-information framing.
///
///   - **30+ day bucket:** ACOG/ASRM define secondary amenorrhea at
///     ≥90 days; 30+ days is well below that clinical threshold.
///     "ist sinnvoll" tone was softened to non-directive
///     ("jederzeit möglich") so the app surfaces the option without
///     recommending it. CLAUDE.md prohibits diagnostic interpretation;
///     this softening keeps us on the wellness side at the 30-day
///     mark while still helping users who are worried find their way
///     to a professional.
///
/// `LateMilestoneCopyTests` pins the current strings; any future change
/// must update both the bodies and the pin tests in the same commit.
public enum LateMilestoneBucket: String, Sendable, CaseIterable {
    case slightlyLate           // 1–4 days
    case noticeablyLate         // 5–9 days
    case pregnancyTestWindow    // 10–14 days
    case persistentlyLate       // 15–29 days
    case longOverdue            // 30+ days

    public var headline: String {
        switch self {
        case .slightlyLate: return "Etwas später als erwartet"
        case .noticeablyLate: return "Spürbar später"
        case .pregnancyTestWindow: return "Information zum Zeitpunkt"
        case .persistentlyLate: return "Weiterhin später als erwartet"
        case .longOverdue: return "Lange überfällig"
        }
    }

    /// Body string with `{N}` interpolated as the days-late count.
    public func body(daysLate: Int) -> String {
        let n = "\(daysLate)"
        // Deviation from the design doc table: "1 Tag" instead of
        // "1 Tage". The doc uses `{N} Tage` as a placeholder; rendering
        // "1 Tage" is grammatically wrong in German. The 1-day case
        // only affects `.slightlyLate`; other buckets start at N≥5.
        let tagWord = daysLate == 1 ? "Tag" : "Tage"
        switch self {
        case .slightlyLate:
            return "Deine Periode liegt \(n) \(tagWord) über der erwarteten Zeit. Bei den meisten Personen schwankt ein Zyklus um ein paar Tage in jede Richtung. Beobachte ruhig weiter."
        case .noticeablyLate:
            return "\(n) Tage über der Erwartung. Stress, Reise oder Krankheit können einen Zyklus verschieben. Du kannst ein Ereignis loggen, falls dir eines davon einfällt."
        case .pregnancyTestWindow:
            return "Tag \(n) über der Erwartung. Ein Schwangerschaftstest ist ab jetzt zuverlässig — als Orientierung, nicht als Empfehlung."
        case .persistentlyLate:
            return "Tag \(n) über der Erwartung. Wenn du dir Sorgen machst, ist eine ärztliche Einschätzung der nächste Schritt — die App diagnostiziert nicht."
        case .longOverdue:
            return "Tag \(n) über der Erwartung. Wenn du dir unsicher bist, ist eine ärztliche Einschätzung jederzeit möglich — Tideline diagnostiziert nicht. Du kannst die Vorhersage zurücksetzen, wenn dein Rhythmus sich neu sortiert."
        }
    }
}

public enum LateMilestone {
    /// Map an integer day count past the expected period date to a
    /// milestone bucket. Day boundaries are inclusive at both ends per
    /// the design doc table.
    public static func bucket(daysLate: Int) -> LateMilestoneBucket? {
        guard daysLate >= 1 else { return nil }
        switch daysLate {
        case 1...4: return .slightlyLate
        case 5...9: return .noticeablyLate
        case 10...14: return .pregnancyTestWindow
        case 15...29: return .persistentlyLate
        default: return .longOverdue   // 30+
        }
    }
}
