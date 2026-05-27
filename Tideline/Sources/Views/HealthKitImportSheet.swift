import SwiftUI
import HealthKit

/// HealthKit menstrual-flow import sheet (task #71). Walks the user through
/// permission → load → review → commit → success. Review screen lets the
/// user opt out of individual cycles before commit; conflicts with existing
/// Tideline `DayEntry` rows are silently skipped.
///
/// See `docs/roadmap/2026-05-22-consolidated-roadmap.md` Phase 1 for the
/// rationale (HealthKit import unblocks Mein Zyklus patterns + Doctor PDF
/// for new users with existing history).
struct HealthKitImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.healthKitService) private var healthKit
    @Environment(\.cycleStore) private var store

    @State private var step: ImportStep = .permissionAsk
    @State private var skippedGroupIDs: Set<UUID> = []
    @State private var lastPlan: HKImportPlan?
    @State private var errorMessage: String?

    /// Lookback window for the read query. Two years covers most users'
    /// usable history; older entries are clinically less informative for
    /// the current predictor anyway (cycle characteristics drift with age).
    private static let lookbackDays: TimeInterval = 730 * 86_400

    enum ImportStep: Equatable {
        case permissionAsk
        case loading
        case review
        case importing
        case success(ImportResult)
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
                    case .importing: importingStep
                    case .success(let result): successStep(result: result)
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

    // MARK: - Permission ask

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Aus Apple Health importieren")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)

            Text("Tideline kann deine bisherigen Periodendaten aus Apple Health übernehmen — damit deine Vorhersagen vom ersten Tag an aussagekräftig sind.")
                .font(.body)
                .foregroundStyle(.secondary)

            Label("Deine Daten bleiben auf deinem Gerät. Tideline schickt nichts in die Cloud.", systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 12)

            primaryButton("Erlauben") {
                Task { await requestAndLoad() }
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
            ProgressView()
                .scaleEffect(1.2)
            Text("Lese Apple Health …")
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
                    if plan.totalConflictingDays > 0 {
                        conflictNotice(plan: plan)
                    }
                }
                Spacer(minLength: 12)
                if let selectedCount = selectedDayCount, selectedCount > 0 {
                    let label = selectedCount == 1
                        ? "1 Tag importieren"
                        : "\(selectedCount) Tage importieren"
                    primaryButton(label) {
                        Task { await commitImport() }
                    }
                } else if !plan.groups.isEmpty {
                    Text("Keine Zyklen ausgewählt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private func reviewHeader(plan: HKImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.groups.isEmpty
                 ? "Keine Zyklus-Daten in Apple Health gefunden."
                 : "Wir haben \(plan.groups.count) Zyklen gefunden. Welche möchtest du importieren?")
                .tidelineSerifHeadline(size: 22, relativeTo: .title2)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
        }
    }

    private var emptyReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Du kannst Tideline trotzdem nutzen — logge deine erste Periode, sobald sie beginnt, und der Rest wird automatisch.")
                .font(.body)
                .foregroundStyle(.secondary)
            primaryButton("Schließen") { dismiss() }
        }
    }

    private func reviewRow(group: HKImportCycleGroup) -> some View {
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
                    Text("\(group.bleedingDayCount) Bluttage")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if group.hasConflicts {
                    Text("\(group.conflictingCount) Tage bereits geloggt")
                        .font(.caption2)
                        // Task #133 — was .tertiary; bumped to .secondary
                        // (WCAG AA on body text).
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
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
        }
        .padding(12)
        .background(
            Color.primary.opacity(isSkipped ? 0.02 : 0.05),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .opacity(isSkipped ? 0.6 : 1.0)
    }

    private func conflictNotice(plan: HKImportPlan) -> some View {
        Label("\(plan.totalConflictingDays) Tage sind bereits in Tideline geloggt — sie werden übersprungen.", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    // MARK: - Importing

    private var importingStep: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Importiere …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Success

    private func successStep(result: ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)

            Text("Import abgeschlossen")
                .tidelineSerifHeadline(size: 24, relativeTo: .title2)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(result.importedDays) Tage importiert")
                if result.skippedExistingDays > 0 {
                    Text("\(result.skippedExistingDays) Tage übersprungen (bereits geloggt)")
                        .foregroundStyle(.secondary)
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

            Text("Import nicht möglich")
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

            // Wave-B fix (4.5): retry path. After the user fixes the
            // permission in iOS Settings and returns, they previously
            // landed back on this error screen with no obvious way to
            // re-attempt the import — they had to close and reopen the
            // sheet. The "Erneut versuchen" button calls back into the
            // same `requestAndLoad()` entry point so the re-attempt
            // shares the original code path (no divergent flow).
            Button {
                Task { await requestAndLoad() }
            } label: {
                Text("Erneut versuchen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Versucht den Apple-Health-Import erneut. Nutze diesen Knopf, nachdem du die Berechtigung in den iPhone-Einstellungen erlaubt hast.")

            Button("Schließen") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Buttons / shared

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
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private var selectedDayCount: Int? {
        lastPlan?.selectedDays(skipping: skippedGroupIDs).count
    }

    // MARK: - Actions

    private func requestAndLoad() async {
        guard let healthKit, HealthKitService.isHealthDataAvailable else {
            errorMessage = "Apple Health ist auf diesem Gerät nicht verfügbar."
            step = .error
            return
        }
        step = .loading
        do {
            try await healthKit.requestAuthorization()
            let since = Date.now.addingTimeInterval(-Self.lookbackDays)
            let samples = try await healthKit.readMenstrualFlow(since: since)
            let existingDates: Set<Date>
            if let store {
                existingDates = Set(await store.loggedDays().map(\.date))
            } else {
                existingDates = []
            }
            let plan = HKImportPlanner.plan(
                samples: samples,
                existingEntryDates: existingDates
            )
            lastPlan = plan
            // Default: all groups selected (skip set empty).
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

    private func commitImport() async {
        guard let store, let plan = lastPlan else { return }
        let selected = plan.selectedDays(skipping: skippedGroupIDs)
        let payload = selected.map { (date: $0.date, flow: $0.flow) }
        step = .importing
        let result = await store.importHealthKitSamples(payload, skipExisting: true)
        step = .success(result)
    }

    private func humanReadable(_ error: HealthKitError) -> String {
        switch error {
        case .unavailable:
            return "Apple Health ist auf diesem Gerät nicht verfügbar."
        case .authorizationDenied:
            return "Apple Health hat den Zugriff verweigert. Du kannst ihn in den Einstellungen erlauben."
        case .query(let underlying):
            return "Fehler beim Lesen aus Apple Health: \(underlying.localizedDescription)"
        }
    }
}

#Preview {
    HealthKitImportSheet()
}
