import Foundation

/// AppStorage key constants for tracking preferences set in the first-
/// launch onboarding (task #76). Persists which optional `LogDaySheet`
/// fields (mood, symptoms, notes) the user opted into. Future LogDaySheet
/// integration reads these to hide/show those fields by default.
///
/// Defaults are all `false` (off) per CLAUDE.md Pillar 6 — minimum
/// viable logging. Periode + Tage are always on and not represented as
/// a key here (the toggle in onboarding is purely informational).
///
/// Single source of truth for the key strings so future views read them
/// via `@AppStorage(TrackingPreferences.moodEnabledKey)` instead of
/// drifting string literals.
public enum TrackingPreferences {
    public static let moodEnabledKey     = "trackMoodEnabled"
    public static let symptomsEnabledKey = "trackSymptomsEnabled"
    public static let notesEnabledKey    = "trackNotesEnabled"

    /// Convenience snapshot. Reads from the given defaults store
    /// (defaults to `.standard`). Useful for tests + non-View readers
    /// that don't want to instantiate `@AppStorage`.
    public static func snapshot(defaults: UserDefaults = .standard) -> Snapshot {
        Snapshot(
            moodEnabled:     defaults.bool(forKey: moodEnabledKey),
            symptomsEnabled: defaults.bool(forKey: symptomsEnabledKey),
            notesEnabled:    defaults.bool(forKey: notesEnabledKey)
        )
    }

    public struct Snapshot: Sendable, Equatable {
        public let moodEnabled: Bool
        public let symptomsEnabled: Bool
        public let notesEnabled: Bool

        public init(moodEnabled: Bool, symptomsEnabled: Bool, notesEnabled: Bool) {
            self.moodEnabled = moodEnabled
            self.symptomsEnabled = symptomsEnabled
            self.notesEnabled = notesEnabled
        }
    }
}

/// User's choice on the onboarding "Wann hat deine letzte Periode
/// begonnen?" screen. Lives at module scope (not nested in OnboardingFlow)
/// so tests + future re-entry surfaces can construct it.
public enum LastPeriodChoice: Equatable, Sendable {
    case specificDate(Date)
    case recently   // "Vor kurzem — ich logge ab heute"
    case unsure     // "Weiß ich nicht genau"
}
