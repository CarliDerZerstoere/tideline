import SwiftUI

/// Chronological event list (task #120 — extracted from the original
/// `MyCycleSheet` when that view was rewritten into the three-layer
/// recognition surface). Behaves identically to the pre-rewrite list:
/// reverse-chronological events with swipe-to-delete, plus a "+"
/// toolbar that presents `LogEventSheet` (#75 add path).
struct EventListSheet: View {
    @Environment(\.cycleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var events: [CycleEventSnapshot] = []
    @State private var hasLoaded: Bool = false
    /// Debounce flag so rapid back-to-back swipe-deletes can't enqueue
    /// against a stale `events` snapshot. Same rationale as in the
    /// pre-rewrite `MyCycleSheet`.
    @State private var isMutating: Bool = false
    @State private var showLogEvent: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground.color(scheme: colorScheme).ignoresSafeArea()
                content
            }
            .navigationTitle("Ereignisse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showLogEvent = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Ereignis hinzufügen")
                    }
                }
                // Audit Wave-A fix (4.3): the `.onDelete` swipe gesture
                // is undiscoverable. An `EditButton` puts deletion on
                // the rotor + visible primary toolbar so VoiceOver
                // users and sighted-but-non-power users both find it.
                // Hidden when there are no events to act on.
                if !events.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .accessibilityHint("Aktiviert den Bearbeitungsmodus, um Ereignisse zu löschen.")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogEvent, onDismiss: { Task { await reload() } }) {
                LogEventSheet()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            ProgressView()
        } else if events.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Noch keine Ereignisse")
                .font(.system(size: 18, weight: .semibold))
            Text("Tippe auf + oben rechts, um ein Ereignis hinzuzufügen.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var list: some View {
        List {
            Section("Ereignisse") {
                ForEach(events) { event in
                    eventRow(event)
                }
                .onDelete { indices in
                    Task { await deleteEvents(at: indices) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func eventRow(_ event: CycleEventSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.kind.localizedLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if !event.note.isEmpty {
                Text(event.note)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func reload() async {
        guard let store else {
            hasLoaded = true
            return
        }
        events = await store.allEvents()
        hasLoaded = true
    }

    private func deleteEvents(at indices: IndexSet) async {
        guard let store, !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let toDelete = indices.map { events[$0] }
        for snapshot in toDelete {
            await store.deleteEvent(persistentID: snapshot.persistentID)
        }
        await reload()
    }
}

#Preview {
    EventListSheet()
}
