import SwiftUI

/// The single logging surface — used both as Quick-Log (today) and as the
/// day editor (any past date, reached from a calendar tap in Block 2).
///
/// Required: flow level + date. Everything else is optional and lives in
/// the "Weitere Details" disclosure to keep the Quick-Log path to two taps.
struct LogDaySheet: View {
    let initialDate: Date
    let initialFlow: FlowLevel
    let initialSymptoms: Set<String>
    let initialMood: Int?
    let initialNote: String

    @Environment(\.cycleStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var flow: FlowLevel
    @State private var symptoms: Set<String>
    @State private var mood: Int?
    @State private var note: String
    @State private var detailsExpanded: Bool = false
    @State private var isSaving: Bool = false

    init(
        date: Date = .now,
        flow: FlowLevel = .none,
        symptoms: Set<String> = [],
        mood: Int? = nil,
        note: String = ""
    ) {
        self.initialDate = date
        self.initialFlow = flow
        self.initialSymptoms = symptoms
        self.initialMood = mood
        self.initialNote = note
        _date = State(initialValue: date)
        _flow = State(initialValue: flow)
        _symptoms = State(initialValue: symptoms)
        _mood = State(initialValue: mood)
        _note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datum") {
                    DatePicker(
                        "Tag",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }

                Section("Blutung") {
                    FlowLevelPicker(selection: $flow)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section {
                    DisclosureGroup("Weitere Details", isExpanded: $detailsExpanded) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Symptome")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                SymptomGrid(selected: $symptoms)
                            }

                            MoodPicker(selection: $mood)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notiz")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField("Optional", text: $note, axis: .vertical)
                                    .lineLimit(2...5)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Tag erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Speichern").bold()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let store else { dismiss(); return }
        isSaving = true
        await store.logDay(
            date: date,
            flow: flow,
            symptoms: Array(symptoms),
            mood: mood,
            note: note
        )
        isSaving = false
        dismiss()
    }
}

#Preview {
    LogDaySheet()
}
