import SwiftUI
import HealthKit

/// HealthKit menstrual-flow export sheet (task #91). Mirror of
/// `HealthKitImportSheet`, but data flows Tideline → Apple Health.
///
/// Walks the user through: permission → load (compute plan) → review
/// (per-cycle opt-out toggles) → writing → success. Silently skips days
/// already in HK; never overwrites HK values.
struct HealthKitExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.healthKitService) private var healthKit
    @Environment(\.cycleStore) private var store

    @State private var step: ExportStep = .permissionAsk
    @State private var skippedGroupIDs: Set<UUID> = []
    @State private var lastPlan: HKExportPlan?
    @State private var errorMessage: String?
    @State private var lastResult: (written: Int, skipped: Int) = (0, 0)
    /// Number of samples Apple Health rejected during the batch write.
    /// Non-zero → success step surfaces a partial-failure line.
    @State private var partialFailureCount: Int = 0

    /// Lookback for the HK "what's already there" query. Match the import
    /// sheet's window so the conflict check is symmetric.
    private static let lookbackDays: TimeInterval = 730 * 86_400

    enum ExportStep: Equatable {
        case permissionAsk
        case loading
        case review
        case writing
        case success
        case error
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .permissionAsk: permissionStep
                    case .loading: loadingStep
                    case .review: reviewStep
                    case .writing: writingStep
                    case .success: successStep
                    case .error: errorStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PageBackground.color(scheme: colorScheme).ignoresSafeArea())
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Permission

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("In Apple Health speichern")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)

            Text("Tideline kann deine geloggten Periodendaten in Apple Health schreiben — damit andere Health-Apps deinen Zyklus sehen können. Es bleibt alles auf deinem Gerät.")
                .font(.body)
                .foregroundStyle(.secondary)

            Label("Tideline überschreibt nichts in Apple Health — bestehende Einträge bleiben unverändert.", systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 12)

            primaryButton("Erlauben") {
                Task { await requestAndPlan() }
            }

            if !HealthKitService.isHealthDataAvailable {
                Text("Apple Health ist auf diesem Gerät nicht verfügbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Loading

    private var loadingStep: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("Daten werden geprüft …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let plan = lastPlan {
                reviewHeader(plan: plan)
                if plan.groups.isEmpty {
                    emptyReview
                } else {
                    ForEach(plan.groups) { group in
                        reviewRow(group: group)
                    }
                    if plan.skippedAlreadyInHK > 0 {
                        Label("\(plan.skippedAlreadyInHK) Tage sind bereits in Apple Health — sie werden übersprungen.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 12)
                if let selectedCount = selectedDayCount, selectedCount > 0 {
                    let label = selectedCount == 1
                        ? "1 Tag übertragen"
                        : "\(selectedCount) Tage übertragen"
                    primaryButton(label) {
                        Task { await commitWrite() }
                    }
                } else if !plan.groups.isEmpty, plan.totalWritableDays > 0 {
                    Text("Keine Zyklen ausgewählt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private func reviewHeader(plan: HKExportPlan) -> some View {
        // Wave-B fix (4.5): leading state-icon for the review header so
        // the user scans the OUTCOME state (done / nothing-to-do / has-
        // work) before reading the words. Previously all three states
        // rendered as the same serif italic with only the prose
        // distinguishing them, which slow EN-locale or quick-skim users
        // missed. `checkmark.circle.fill` (green) = synced;
        // `info.circle` = empty; no icon = normal "review me" state.
        HStack(alignment: .top, spacing: 12) {
            if plan.totalWritableDays == 0 && plan.skippedAlreadyInHK > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color(red: 0.30, green: 0.70, blue: 0.45))
                    .accessibilityHidden(true)
            } else if plan.groups.isEmpty {
                Image(systemName: "info.circle")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if plan.totalWritableDays == 0 && plan.skippedAlreadyInHK > 0 {
                    Text("Apple Health ist bereits auf dem aktuellsten Stand.")
                        .tidelineSerifHeadline(size: 22, relativeTo: .title2)
                        .fontDesign(.serif)
                        .italic()
                        .fontWeight(.bold)
                } else if plan.groups.isEmpty {
                    Text("Nichts zu exportieren.")
                        .tidelineSerifHeadline(size: 22, relativeTo: .title2)
                        .fontDesign(.serif)
                        .italic()
                        .fontWeight(.bold)
                } else {
                    Text("\(plan.totalWritableDays) Tage werden nach Apple Health übertragen — welche möchtest du synchronisieren?")
                        .tidelineSerifHeadline(size: 22, relativeTo: .title2)
                        .fontDesign(.serif)
                        .italic()
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var emptyReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logge deine erste Periode in Tideline — dann kannst du sie hierher zurück synchronisieren.")
                .font(.body)
                .foregroundStyle(.secondary)
            primaryButton("Schließen") { dismiss() }
        }
    }

    private func reviewRow(group: HKExportCycleGroup) -> some View {
        let isSkipped = skippedGroupIDs.contains(group.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedCycleStart(group.cycleStart))
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 10) {
                    if let len = group.lengthDays {
                        Text("\(len) Tage Zyklus")
                    } else {
                        Text("Aktueller Zyklus")
                    }
                    Text("·")
                    Text("\(group.writableDays.count) zu übertragen")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if group.hasConflicts {
                    Text("\(group.alreadyInHKCount) Tage bereits in Apple Health")
                        .font(.caption2)
                        // Task #133 — was .tertiary; bumped to .secondary
                        // (WCAG AA on body text).
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !group.writableDays.isEmpty {
                Toggle("", isOn: Binding(
                    get: { !isSkipped },
                    set: { wantsInclude in
                        if wantsInclude {
                            skippedGroupIDs.remove(group.id)
                        } else {
                            skippedGroupIDs.insert(group.id)
                        }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Zyklus startend \(formattedCycleStart(group.cycleStart))")
            } else {
                // Inert row — nothing to write for this cycle. Neutral
                // marker instead of a green checkmark (reviewer rec —
                // green ✓ next to "5 zu übertragen" reads as
                // "selected/done", which it isn't).
                Text("Bereits synchron")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            Color.primary.opacity(isSkipped ? 0.02 : 0.05),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .opacity(isSkipped ? 0.6 : 1.0)
    }

    // MARK: - Writing

    private var writingStep: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("Übertrage nach Apple Health …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Success

    private var successStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)

            Text("Übertragung abgeschlossen")
                .tidelineSerifHeadline(size: 24, relativeTo: .title2)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(lastResult.written) Tage übertragen")
                if lastResult.skipped > 0 {
                    Text("\(lastResult.skipped) Tage übersprungen (bereits in Apple Health)")
                        .foregroundStyle(.secondary)
                }
                if partialFailureCount > 0 {
                    Text("\(partialFailureCount) Tage konnten nicht geschrieben werden")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 12)
            primaryButton("Fertig") { dismiss() }
        }
    }

    // MARK: - Error

    private var errorStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)

            Text("Übertragung nicht möglich")
                .tidelineSerifHeadline(size: 22, relativeTo: .title2)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(errorMessage ?? "Apple Health hat den Zugriff verweigert. Du kannst ihn in den Einstellungen erlauben.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Einstellungen öffnen")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Wave-B fix (4.5): retry path. Symmetric with the import
            // sheet's "Erneut versuchen" button. After permission is
            // granted in iOS Settings the user can re-attempt without
            // closing and reopening the sheet.
            Button {
                Task { await requestAndPlan() }
            } label: {
                Text("Erneut versuchen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Versucht die Übertragung erneut. Nutze diesen Knopf, nachdem du die Berechtigung in den iPhone-Einstellungen erlaubt hast.")

            Button("Schließen") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Shared

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private static let coralGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.48, blue: 0.48), Color(red: 0.88, green: 0.38, blue: 0.38)],
        startPoint: .top,
        endPoint: .bottom
    )

    private func formattedCycleStart(_ date: Date) -> String {
        // Task #130 — drop explicit de_DE locale, follow device locale.
        // The review sheet's user is the device owner, not a clinical
        // reader — locale matching their iOS Settings is the right call.
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private var selectedDayCount: Int? {
        lastPlan?.selectedDays(skipping: skippedGroupIDs).count
    }

    // MARK: - Actions

    private func requestAndPlan() async {
        guard let healthKit, HealthKitService.isHealthDataAvailable else {
            errorMessage = "Apple Health ist auf diesem Gerät nicht verfügbar."
            step = .error
            return
        }
        step = .loading
        do {
            try await healthKit.requestAuthorization()
            // Fetch existing HK days within the same lookback window the
            // import uses, so the symmetry holds (a day we just imported
            // from HK won't get re-written back).
            let since = Date.now.addingTimeInterval(-Self.lookbackDays)
            let hkSamples = try await healthKit.readMenstrualFlow(since: since)
            let hkDates = Set(hkSamples.map { $0.date.civilDay() })

            // Pull all Tideline-logged days.
            let entries: [(date: Date, flow: FlowLevel)]
            if let store {
                entries = await store.loggedDays().map { (date: $0.date, flow: $0.flow) }
            } else {
                entries = []
            }

            let plan = HKExportPlanner.plan(
                tidelineEntries: entries,
                existingHKDates: hkDates
            )
            lastPlan = plan
            skippedGroupIDs = []
            step = .review
        } catch let error as HealthKitError {
            errorMessage = humanReadable(error)
            step = .error
        } catch {
            errorMessage = error.localizedDescription
            step = .error
        }
    }

    private func commitWrite() async {
        guard let healthKit, let plan = lastPlan else { return }
        let selected = plan.selectedDays(skipping: skippedGroupIDs)
        // Forward isCycleStart so HK metadata correctly marks day-1 of
        // each cycle (per Apple's HKMetadataKeyMenstrualCycleStart spec).
        let payload = selected.map { (date: $0.date, flow: $0.flow, isCycleStart: $0.isCycleStart) }
        let requested = payload.count
        step = .writing
        let result = await healthKit.writeMenstrualFlowBatch(payload)
        lastResult = (written: result.written, skipped: plan.skippedAlreadyInHK)
        // Show success when everything went through. Show error step ONLY
        // when zero succeeded — otherwise the user sees a partial-success
        // success step (Reviewer rec: never lose the written count to a
        // thrown error; Apple Health doesn't dedupe on retry).
        if result.written == 0, let err = result.firstError {
            errorMessage = (err as? HealthKitError).map(humanReadable) ?? err.localizedDescription
            step = .error
        } else {
            partialFailureCount = requested - result.written
            step = .success
        }
    }

    private func humanReadable(_ error: HealthKitError) -> String {
        switch error {
        case .unavailable:
            return "Apple Health ist auf diesem Gerät nicht verfügbar."
        case .authorizationDenied:
            return "Apple Health hat den Zugriff verweigert. Du kannst ihn in den Einstellungen erlauben."
        case .query(let underlying):
            return "Fehler beim Schreiben in Apple Health: \(underlying.localizedDescription)"
        }
    }
}

#Preview {
    HealthKitExportSheet()
}
