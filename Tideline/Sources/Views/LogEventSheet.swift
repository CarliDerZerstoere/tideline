import SwiftUI

/// Sheet for logging a disruption event (task #75). Two-state flow:
///   selecting → (commit) → acknowledging (sensitive events only) → dismiss
///
/// User-intent groupings live in `EventCategoryGrouping` — distinct from
/// the algorithm-internal `EventCategory`. Sensitive events (Cat A
/// complete-disruption + Cat C losses) get a quiet warm acknowledgment
/// screen per `docs/design/disrupted-cycles.md` § UX Rules.
struct LogEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cycleStore) private var store

    @State private var step: LogEventStep = .selecting
    @State private var selectedKind: EventKind?
    @State private var eventDate: Date = .now
    @State private var note: String = ""
    @State private var expandedGroup: EventUserGroup?
    @State private var isSaving: Bool = false

    private var dateRange: ClosedRange<Date> {
        Date.now.addingDays(-365) ... Date.now
    }

    enum LogEventStep: Equatable {
        case selecting
        case acknowledging(EventKind)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground.color(scheme: colorScheme).ignoresSafeArea()
                switch step {
                case .selecting:
                    selectingView
                case .acknowledging(let kind):
                    acknowledgingView(kind: kind)
                }
            }
            .navigationTitle("Ereignis hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .selecting = step {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            Task { await commit() }
                        }
                        .disabled(selectedKind == nil || isSaving)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Selecting step

    private var selectingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welches Ereignis?")
                    .tidelineSerifHeadline(size: 26, relativeTo: .title)
                    .fontDesign(.serif)
                    .italic()
                    .fontWeight(.bold)
                    .padding(.top, 4)

                VStack(spacing: 10) {
                    ForEach(EventUserGroup.allCases, id: \.self) { group in
                        groupSection(group)
                    }
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Wann?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "",
                        selection: $eventDate,
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notiz (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("z. B. Anlass, Arzt-Empfehlung", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func groupSection(_ group: EventUserGroup) -> some View {
        let isExpanded = expandedGroup == group
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { newValue in
                    // Single-expanded mode: tapping a collapsed group
                    // collapses all others. Keeps the picker scannable.
                    expandedGroup = newValue ? group : nil
                }
            )
        ) {
            VStack(spacing: 6) {
                ForEach(EventCategoryGrouping.userVisibleEvents(in: group), id: \.self) { kind in
                    eventRow(kind)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(group.localizedLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(EventCategoryGrouping.userVisibleEvents(in: group).count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            // Combine label + count into a single VoiceOver utterance —
            // otherwise users hear "Schwangerschaft & Geburt", then "6"
            // as separate elements. (Reviewer rec #8.)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.germanLabel), \(EventCategoryGrouping.userVisibleEvents(in: group).count) Ereignisse")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func eventRow(_ kind: EventKind) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            selectedKind = kind
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(kind.localizedLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Acknowledging step (sensitive events)

    @ViewBuilder
    private func acknowledgingView(kind: EventKind) -> some View {
        let tone = EventCategoryGrouping.sensitivityTone(kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "heart.circle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color(red: 0.78, green: 0.55, blue: 0.62))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)

                Text(acknowledgmentHeadline(tone: tone))
                    .tidelineSerifHeadline(size: 28, relativeTo: .title)
                    .fontDesign(.serif)
                    .italic()
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(acknowledgmentBody(tone: tone))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Spacer(minLength: 16)

                Button {
                    dismiss()
                } label: {
                    Text("Schließen")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.35), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    /// German acknowledgment headline, specialised by tone so a user
    /// who just logged a hysterectomy doesn't see "loslegen" copy.
    /// Reviewer rec #1.
    private func acknowledgmentHeadline(tone: EventCategoryGrouping.SensitivityTone) -> String {
        switch tone {
        case .retirement: return "Notiert."
        case .loss:       return "Es tut uns leid."
        case .none:       return ""
        }
    }

    private func acknowledgmentBody(tone: EventCategoryGrouping.SensitivityTone) -> String {
        switch tone {
        case .retirement:
            // Permanent — no "wieder loslegen" phrasing.
            return "Tideline schaltet die Zyklus-Vorhersage ab. Deine bisherigen Daten bleiben hier."
        case .loss:
            // Recoverable — warmth + open invitation.
            return "Es ist nichts vorherzusagen — und das ist okay. Deine bisherigen Daten bleiben hier. Wenn du irgendwann wieder loslegen möchtest, sind wir da."
        case .none:
            return ""
        }
    }

    private static let coralGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.48, blue: 0.48), Color(red: 0.88, green: 0.38, blue: 0.38)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Actions

    private func commit() async {
        guard let kind = selectedKind, let store, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await store.addEvent(kind: kind, on: eventDate, note: note)
        if EventCategoryGrouping.isSensitive(kind) {
            step = .acknowledging(kind)
        } else {
            dismiss()
        }
    }
}

#Preview {
    LogEventSheet()
}
