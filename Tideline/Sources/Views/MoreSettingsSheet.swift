import SwiftUI

/// "Mehr"-Tab settings sheet. Hosts the app-lock section, cycle
/// irregularity self-declare, age-band picker, notification opt-in,
/// data import/export rows, and the privacy disclosure.
struct MoreSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showHealthKitImport: Bool = false
    @State private var showHealthKitExport: Bool = false
    @State private var showDoctorPDF: Bool = false
    @State private var showSupport: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                // Audit Wave-A fix (4.4): sections reordered by
                // frequency-of-use. The previous order put set-and-forget
                // controls (AppLock, AgeBand) above the daily-touch
                // surfaces (Data import/export, Doctor PDF) which buried
                // the actionable items. New order:
                //   1. Data — frequently revisited (HK sync, Doctor PDF)
                //   2. Notifications — toggle + per-category gates
                //   3. PhaseNaming — visible-on-home preference (clinical/tide)
                //   4. CycleIrregularity — declarative health state
                //   5. AgeBand — calibration value, rarely changed
                //   6. AppLock — first-time setup; rarely revisited
                //   7. Privacy — reference material, anchors the bottom
                VStack(alignment: .leading, spacing: 24) {
                    dataSection

                    NotificationSettingsSection()

                    PhaseNamingSettingsSection()

                    CycleIrregularitySection()

                    AgeBandSettingsSection()

                    AppLockSettingsSection()

                    supportSection

                    PrivacyDisclosureSection()

                    // Future settings sections land here.

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(PageBackground.color(scheme: colorScheme).ignoresSafeArea())
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showHealthKitImport) {
                HealthKitImportSheet()
            }
            .sheet(isPresented: $showHealthKitExport) {
                HealthKitExportSheet()
            }
            .sheet(isPresented: $showDoctorPDF) {
                DoctorPDFSheet()
            }
            .sheet(isPresented: $showSupport) {
                SupportSheet()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "Daten" section — sources Tideline data can pull from. Task #71
    /// adds Apple Health import here; future entries (CSV import, doctor
    /// PDF export — see #46) will follow.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daten")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            dataRow(
                systemImage: "heart.text.square",
                tint: .pink,
                title: "Aus Apple Health importieren",
                subtitle: "Bisherige Periodendaten übernehmen"
            ) {
                showHealthKitImport = true
            }

            dataRow(
                systemImage: "arrow.up.heart",
                tint: Color(red: 0.95, green: 0.55, blue: 0.60),
                title: "Daten in Apple Health speichern",
                subtitle: "Periodendaten zurück nach Apple Health schreiben"
            ) {
                showHealthKitExport = true
            }

            dataRow(
                systemImage: "doc.text",
                tint: Color(red: 0.93, green: 0.48, blue: 0.48),
                title: "Bericht für meinen Frauenarzt-Termin",
                subtitle: "PDF auf deinem Gerät erstellen — privat, ohne Cloud"
            ) {
                showDoctorPDF = true
            }
        }
    }

    /// "Tideline unterstützen" section — single row that opens the
    /// SupportSheet. Generous-free model (R31): the row is framed as
    /// optional support, never as an upsell. No "Pro" or "Premium"
    /// language. Heart icon doubles as the post-purchase state cue.
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tideline unterstützen")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            dataRow(
                systemImage: "heart",
                tint: .pink,
                title: "Einmaliger Beitrag",
                subtitle: "Optional — Tideline funktioniert ohne Kauf gleich"
            ) {
                showSupport = true
            }
        }
    }

    @ViewBuilder
    private func dataRow(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        // Task #132 — semantic style scales with Dynamic Type.
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        // A11y sweep (audit fix #131): collapse icon + title + subtitle +
        // chevron into one accessible button so VoiceOver users navigate
        // by row rather than getting four separate utterances per item.
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
