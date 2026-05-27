import SwiftUI

/// Settings section for changing the user's declared age band (task #97).
/// Changing the band triggers `store.reprimeForAgeBand`, which rebuilds
/// the predictor's posterior from scratch against the new prior. For
/// users with N≥6 logged cycles the visible change is small (posterior
/// is data-dominated); low-data users see a noticeable shift, which is
/// the right behaviour — the band change is intentional.
struct AgeBandSettingsSection: View {
    @Environment(\.cycleStore) private var store
    @AppStorage("userAgeBand") private var persistedAgeBand: String = AgeBand.unspecified.rawValue

    @State private var pickerOpen: Bool = false
    @State private var inFlight: Bool = false

    private var currentBand: AgeBand {
        AgeBand(rawValue: persistedAgeBand) ?? .unspecified
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Persönliche Daten")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Button {
                pickerOpen = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Altersbereich")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(currentBand.germanLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .disabled(inFlight || store == nil)
            // A11y sweep (audit fix #131): collapse the two Text lines and
            // the chevron into a single accessible button with a label
            // describing both the action ("change age band") and the
            // current value, so VoiceOver users get the same context
            // sighted users get from the chevron.
            .accessibilityLabel("Altersbereich, aktuell \(currentBand.germanLabel)")
            .accessibilityHint("Tippen um den Altersbereich zu ändern.")
        }
        .sheet(isPresented: $pickerOpen) {
            AgeBandPickerSheet(
                initialSelection: currentBand,
                onCommit: { newBand in
                    Task { await applyChange(to: newBand) }
                }
            )
        }
    }

    private func applyChange(to band: AgeBand) async {
        guard !inFlight, let store else { return }
        inFlight = true
        defer { inFlight = false }
        persistedAgeBand = band.rawValue
        await store.reprimeForAgeBand(band)
    }
}

/// Small picker sheet listing every `AgeBand` with German labels.
/// Mirrors the onboarding step's UI so the user encounters the same
/// affordances in both contexts.
private struct AgeBandPickerSheet: View {
    let initialSelection: AgeBand
    let onCommit: (AgeBand) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: AgeBand

    init(initialSelection: AgeBand, onCommit: @escaping (AgeBand) -> Void) {
        self.initialSelection = initialSelection
        self.onCommit = onCommit
        self._selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ZStack {
            PageBackground.color(scheme: colorScheme).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Altersbereich")
                    .font(.system(size: 22, weight: .bold, design: .serif).italic())
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                Text("Diese Anpassung kann deine Schätzung leicht verändern, vor allem in den ersten Zyklen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                VStack(spacing: 8) {
                    ForEach(AgeBand.displayOrder, id: \.rawValue) { band in
                        Button {
                            selection = band
                        } label: {
                            HStack {
                                Text(band.localizedLabel)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selection == band {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                selection == band
                                    ? Color(red: 0.93, green: 0.48, blue: 0.48).opacity(0.10)
                                    : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                        // A11y: report the selection state with the standard
                        // `.isSelected` trait so VoiceOver announces it the
                        // same way it does for native pickers / segmented
                        // controls.
                        .accessibilityLabel(band.localizedLabel)
                        .accessibilityAddTraits(selection == band ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                Button {
                    onCommit(selection)
                    dismiss()
                } label: {
                    Text("Übernehmen")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            Color(red: 0.93, green: 0.48, blue: 0.48),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selection == initialSelection)
                .opacity(selection == initialSelection ? 0.55 : 1.0)
                .padding(.horizontal, 8)
            }
            .padding(16)
        }
        .presentationDetents([.medium])
    }
}
