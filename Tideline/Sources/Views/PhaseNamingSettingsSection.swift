import SwiftUI

/// Settings toggle for the phase-naming convention (task #93).
///
/// Two flavours of phase labels exist in the codebase:
///   - **Clinical** (default): Menstruation / Follikelphase / Ovulation
///     / Lutealphase. The AWHS-aligned medical convention.
///   - **Tide metaphor**: Stille / Aufgang / Hochwasser / Rückzug. The
///     poetic naming that matches Tideline's visual language.
///
/// The `phaseNamingClinical_v2` AppStorage key has existed since the
/// home view was built (`TidelineHomeView` reads it) but had no user-
/// facing UI to flip it — users were stuck on whichever default the
/// app shipped with. This section exposes the choice.
///
/// Same presentational pattern as the other `*SettingsSection` files;
/// no actor calls, no async state, no unit tests (matches established
/// pattern — `AppLockSettingsSection` and `CycleIrregularitySection`
/// have none either).
struct PhaseNamingSettingsSection: View {
    /// AppStorage key — single source of truth shared with
    /// `TidelineHomeView`. Reviewer-flagged risk: a typo in either
    /// site would silently desync the toggle from the consumer.
    static let storageKey = "phaseNamingClinical_v2"

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PhaseNamingSettingsSection.storageKey) private var useClinicalNaming: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phasennamen")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $useClinicalNaming) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(useClinicalNaming ? "Klinische Namen" : "Gezeiten-Namen")
                            .font(.system(size: 15, weight: .semibold))
                        Text(useClinicalNaming
                             ? "Menstruation · Follikelphase · Ovulation · Lutealphase"
                             : "Stille · Aufgang · Hochwasser · Rückzug")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                // A11y sweep (audit fix #131): the toggle's label has TWO
                // Text children which VoiceOver would otherwise read as two
                // separate utterances. Give it a single descriptive label.
                .accessibilityLabel(
                    useClinicalNaming
                    ? "Phasennamen: Klinisch. Menstruation, Follikelphase, Ovulation, Lutealphase."
                    : "Phasennamen: Gezeiten. Stille, Aufgang, Hochwasser, Rückzug."
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
        }
    }
}
