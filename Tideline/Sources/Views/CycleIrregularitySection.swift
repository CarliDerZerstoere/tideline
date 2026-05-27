import SwiftUI

/// Settings section for self-declaring an ongoing cycle irregularity
/// (task #77 / Category E from `disrupted-cycles.md`).
///
/// **Why the label is "Meine Zyklen sind unregelmäßig" and NOT "PCOS":**
/// CLAUDE.md is explicit — the app must stay in EU MDR wellness/lifestyle
/// territory. A user observing "my cycles are irregular" is a personal
/// observation; "I have PCOS" would be a diagnosis. Different
/// regulatory worlds. The internal `EventKind.pcosDeclared` is just an
/// implementation handle; the user-facing label intentionally avoids
/// the clinical term.
///
/// **Toggle pattern:** Custom `Binding` setter — direct write fires the
/// async store mutation, no `.onChange`. Same pattern we used to fix the
/// LogDaySheet disclosure detent race: a deferred `.onChange` couldn't
/// distinguish user-tap from programmatic `.task` init, leading to a
/// double-fire of the side effect. Routing only the user's deliberate
/// flip through the setter sidesteps that race.
///
/// **Disabled until loaded:** The `.task` reads the current state from
/// the store via `hasPCOSDeclared()`. Until that returns, the toggle is
/// `.disabled` to prevent a user-tap-before-load from going to the
/// wrong base value.
struct CycleIrregularitySection: View {
    @Environment(\.cycleStore) private var store

    @State private var isIrregular: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var inFlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zyklus-Besonderheiten")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: irregularBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meine Zyklen sind unregelmäßig")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Tideline weitet die Vorhersage und zeigt einen Hinweis, dass deine Zyklen natürlich variabel sind.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!hasLoaded || inFlight || store == nil)
                .padding(.vertical, 4)
                // A11y sweep (audit fix #131): give VoiceOver a single
                // descriptive label that joins the two label rows.
                .accessibilityLabel("Meine Zyklen sind unregelmäßig")
                .accessibilityHint("Wenn aktiviert, weitet Tideline die Vorhersage und blendet einen Variabilitätshinweis ein.")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .task {
            // Initial load — only updates the visible state, no side
            // effects on the store. Toggle stays disabled until this
            // returns so a fast user-tap can't race the fetch.
            guard let store else {
                hasLoaded = true  // still allow interaction; binding guards on nil store
                return
            }
            isIrregular = await store.hasPCOSDeclared()
            hasLoaded = true
        }
    }

    /// Custom binding so only deliberate user taps trigger the store
    /// mutation. Programmatic writes (`isIrregular = ...` inside .task)
    /// bypass this setter and don't fire the side effect — same race-
    /// avoidance pattern used in LogDaySheet.disclosureBinding.
    ///
    /// The store mutation runs inside `Task { @MainActor in ... }` so the
    /// final `inFlight = false` write reaches `@State` on the MainActor
    /// (Swift 6 strict-concurrency requirement — a bare `Task` would
    /// hop off the MainActor and the `@State` write would race). The
    /// `defer { inFlight = false }` guards against a future refactor
    /// that makes `addEvent` / `deletePCOSDeclared` throwing — without
    /// it the toggle would stay permanently disabled after a thrown
    /// error.
    private var irregularBinding: Binding<Bool> {
        Binding(
            get: { isIrregular },
            set: { newValue in
                isIrregular = newValue
                guard let store, !inFlight else { return }
                inFlight = true
                Task { @MainActor in
                    defer { inFlight = false }
                    if newValue {
                        await store.addEvent(kind: .pcosDeclared, on: .now)
                    } else {
                        await store.deletePCOSDeclared()
                    }
                }
            }
        )
    }
}

#Preview {
    CycleIrregularitySection()
        .padding()
        .background(Color(red: 0.96, green: 0.93, blue: 0.85))
}
