import SwiftUI

/// "Mein Zyklus" tab — three-layer recognition surface (task #120):
///   - **Layer 1**: today's recognition card (German template per phase + zone)
///   - **Layer 2**: one pattern observation from recent cycles, or
///                  low-data fallback line
///   - **Layer 3**: collapsed cycle-history list
///
/// Bottom CTAs route to the Doctor PDF (#46) and the standalone event
/// list (extracted to `EventListSheet`). The "+" toolbar (added in #75)
/// stays — it presents `LogEventSheet` to add disruption events.
///
/// **Mode handling**:
/// - `.active`: full three-layer experience.
/// - `.paused`: Layer 1 shows pause copy. Layer 2 hidden (no current
///   cycle to surface patterns against). Layer 3 keeps retrospection.
/// - `.retired`: Layer 1 shows retirement copy. Layer 2 hidden. Layer 3
///   keeps retrospection.
struct MyCycleSheet: View {
    @Environment(\.cycleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Task #110 — TZ change / midnight rollover signal.
    @Environment(\.refreshClock) private var clock

    @State private var template: RecognitionTemplate?
    @State private var paused: PauseReason? = nil
    @State private var retired: RetirementReason? = nil
    @State private var pattern: PatternObservation?
    @State private var pastCycles: [CycleSummary] = []
    @State private var eventCount: Int = 0
    @State private var hasLoaded: Bool = false
    /// Task #193 / #83 Session 1 — v2 mixture-derived cycle pattern.
    /// Nil when N < 12 cycles, mode != active, or mixture chain is
    /// fresh (e.g. just after a Category C event).
    @State private var cyclePattern: CyclePattern?
    /// Task #194 (Phase 3) — active recovery-profile state. When
    /// non-nil, replaces the `cyclePattern` badge with recovery-mode
    /// copy ("Im Erholungsprozess nach <event> (Zyklus N von M)").
    @State private var recoveryState: PredictorService.ActiveRecovery?

    @State private var showLogEvent: Bool = false
    @State private var showEventList: Bool = false
    @State private var showDoctorPDF: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground.color(scheme: colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        if hasLoaded {
                            layer1Card
                            if shouldShowLayer2 {
                                layer2Card
                                // Task #193 — surface the v2 mixture-
                                // derived cycle-pattern badge below the
                                // existing pattern card. The badge view
                                // itself returns an empty view when
                                // `cyclePattern` is nil, so the slot
                                // takes no vertical space pre-graduation.
                                cyclePatternBadge
                            }
                            if !pastCycles.isEmpty {
                                layer3CycleHistory
                            }
                            ctaSection
                            Spacer(minLength: 16)
                        } else {
                            ProgressView()
                                .padding(.top, 80)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Mein Zyklus")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogEvent, onDismiss: { Task { await reload() } }) {
                LogEventSheet()
            }
            .sheet(isPresented: $showEventList, onDismiss: { Task { await reload() } }) {
                EventListSheet()
            }
            .sheet(isPresented: $showDoctorPDF) {
                DoctorPDFSheet()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await reload() }
        .onChange(of: clock?.tick) { oldValue, newValue in
            // Task #110 — TZ change / midnight rollover. Cycle-day math
            // depends on Date.now.civilDay() (line ~407 in this file),
            // which is stale until we reload. Guarded against the
            // env-injection nil→0 fire that would double-load on cold open.
            guard let oldValue, let newValue, newValue != oldValue else { return }
            Task { await reload() }
        }
    }

    // MARK: - Layer 1 (recognition)

    @ViewBuilder
    private var layer1Card: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                if let r = retired {
                    Text("Beendet")
                        .tidelineSerifHeadline(size: 22, relativeTo: .title3)
                        .fontDesign(.serif).italic().fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Tideline ist auf \(germanRetirement(r)) eingestellt. Deine bisherigen Daten bleiben hier.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                } else if let p = paused {
                    Text("Pausiert")
                        .tidelineSerifHeadline(size: 22, relativeTo: .title3)
                        .fontDesign(.serif).italic().fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Deine Vorhersage ist pausiert wegen \(germanPause(p)). Hier siehst du wieder Statistiken, sobald dein Zyklus zurückkehrt.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                } else if let t = template {
                    Text(t.headline)
                        .tidelineSerifHeadline(size: 22, relativeTo: .title3)
                        .fontDesign(.serif).italic().fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    Text(t.body)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                } else {
                    Text("Willkommen")
                        .tidelineSerifHeadline(size: 22, relativeTo: .title3)
                        .fontDesign(.serif).italic().fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Logge deine erste Periode, um Tideline kennen zu lernen.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Layer 2 (pattern)

    /// Hide Layer 2 entirely in paused/retired modes (no current cycle to
    /// frame patterns against). Active mode: show pattern card or
    /// low-data fallback line.
    private var shouldShowLayer2: Bool {
        paused == nil && retired == nil
    }

    @ViewBuilder
    private var layer2Card: some View {
        if let p = pattern {
            cardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Muster aus den letzten \(p.sparklineValues.count) Zyklen")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(p.germanSentence)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    sparklineRow(values: p.sparklineValues)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
            }
        } else {
            Text("Noch zu wenig Daten — Tideline sieht Muster ab dem 3. Zyklus.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    /// Minimal inline visual — equal-height dots with intensity scaled to
    /// cycle length normalised against the local range.
    @ViewBuilder
    private func sparklineRow(values: [Double]) -> some View {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(0.0001, maxV - minV)
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                let intensity = (v - minV) / span
                Circle()
                    .fill(Color.accentColor.opacity(0.4 + 0.6 * intensity))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Cycle-pattern / recovery badge (Tasks #193, #194)

    /// Descriptive cycle-pattern badge powered by the v2 mixture
    /// predictor's posterior mixing weight, OR — when a Category C
    /// recovery window is active — a recovery-mode badge that takes
    /// precedence and describes the post-event tracking phase.
    ///
    /// Both surfaces are strictly descriptive of *what was logged or
    /// what event the user declared*. Never diagnostic per the CLAUDE.md
    /// hard rule "Never display diagnostic interpretations."
    @ViewBuilder
    private var cyclePatternBadge: some View {
        if let recovery = recoveryState {
            // Recovery state takes precedence: during the post-event
            // window the cycle-pattern read isn't a meaningful summary
            // of the user's long-run pattern, since the data is
            // dominated by the recovery trajectory.
            cardContainer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Erholungsprozess")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(recoveryBadgeHeadline(recovery))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(recoveryBadgeSubtitle(recovery))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        } else if let pattern = cyclePattern {
            cardContainer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dein Muster")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(pattern.germanLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(pattern.basisLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recoveryBadgeHeadline(_ recovery: PredictorService.ActiveRecovery) -> String {
        "Tideline begleitet dich \(recovery.germanRecoveryPhrase)"
    }

    private func recoveryBadgeSubtitle(_ recovery: PredictorService.ActiveRecovery) -> String {
        if recovery.ashermanFlag {
            // D&C events stay flagged indefinitely (HRU 2024 — 17% of
            // first-trimester D&C cases develop intrauterine adhesions).
            // We don't show a graduation count for these.
            return "Zyklus \(recovery.currentCycle) — wir bleiben aufmerksam"
        }
        return "Zyklus \(recovery.currentCycle) von \(recovery.totalCycles)"
    }

    // MARK: - Layer 3 (cycle history)

    @ViewBuilder
    private var layer3CycleHistory: some View {
        cardContainer {
            DisclosureGroup {
                VStack(spacing: 6) {
                    // `pastCycleSummaries(limit:)` returns oldest-first;
                    // reverse for newest-first display in the list.
                    ForEach(pastCycles.reversed()) { c in
                        cycleHistoryRow(c)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("Verlauf (letzte \(pastCycles.count) Zyklen)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
    }

    private func cycleHistoryRow(_ cycle: CycleSummary) -> some View {
        HStack {
            // Task #130 — no explicit locale: follow device locale.
            // DACH user sees "24. Mai 2026", EN user sees "May 24, 2026".
            Text(cycle.startDate.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(cycle.lengthDays) Tage")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - CTA section

    @ViewBuilder
    private var ctaSection: some View {
        VStack(spacing: 10) {
            ctaButton("Für meinen Frauenarzt-Termin", systemImage: "doc.text") {
                showDoctorPDF = true
            }
            ctaButton("Ereignisse anzeigen (\(eventCount))", systemImage: "list.bullet") {
                showEventList = true
            }
        }
        .padding(.top, 8)
    }

    private func ctaButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card container

    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 14)
            )
    }

    // MARK: - German labels for mode display

    private func germanPause(_ reason: PauseReason) -> String {
        switch reason {
        case .breastfeeding: return "Stillzeit"
        case .hormonalContraception: return "hormoneller Verhütung"
        case .hypothalamicAmenorrhea: return "hypothalamischer Amenorrhoe"
        case .userInitiated: return "manueller Pause"
        }
    }

    private func germanRetirement(_ reason: RetirementReason) -> String {
        switch reason {
        case .hysterectomy: return "Hysterektomie"
        case .oophorectomy: return "Oophorektomie"
        case .userInitiated: return "manuell beendet"
        }
    }

    // MARK: - Reload

    private func reload() async {
        guard let store else {
            hasLoaded = true
            return
        }

        // Single atomic snapshot — eliminates the multi-await vintage
        // drift the #120 reviewer flagged. All fields come from one
        // actor hop, so we never render Layer 1 against `.active` mode
        // alongside Layer 2 against post-retire cycles.
        let snap = await store.myCycleSnapshot(pastCyclesLimit: 6)
        let predictedLength = Int(round(snap.predictedCycleLength))

        // Reset mode bindings.
        paused = nil
        retired = nil
        template = nil
        pattern = nil
        cyclePattern = snap.cyclePattern
        recoveryState = snap.recoveryState

        switch snap.mode {
        case .paused(_, _, let reason):
            paused = reason
        case .retired(_, let reason):
            retired = reason
        case .active:
            // Layer 1 template — derive phase + day-in-cycle + boundaries.
            if let currentStart = snap.currentCycleStart {
                let dayInCycle = max(1, Calendar.current.dateComponents(
                    [.day], from: currentStart.civilDay(), to: Date.now.civilDay()
                ).day.map { $0 + 1 } ?? 1)
                let mensesEnd = PhaseBoundaries.mensesEnd(
                    bleedingDays: snap.bleedingDaysInCurrentCycle,
                    todayDayInCycle: dayInCycle,
                    personalMedianMenses: snap.personalMedianMenses
                )
                let boundaries = PhaseBoundaries.from(
                    cycleLength: predictedLength,
                    mensesEnd: mensesEnd
                )
                let clampedDay = min(dayInCycle, boundaries.cycleLength)
                let phase = boundaries.phase(forDay: clampedDay)
                // Seed rotation from the current cycle's start so the
                // template stays stable across re-renders within the
                // cycle but rotates day-by-day.
                let seed = Int(currentStart.timeIntervalSinceReferenceDate / 86_400)
                template = RecognitionTemplates.pick(
                    phase: phase,
                    dayInCycle: clampedDay,
                    boundaries: boundaries,
                    cycleStartHash: seed
                )
            }
            // Layer 2 pattern — needs past cycles.
            pattern = PatternObservationGenerator.generate(cycles: snap.pastCycles)
        }

        pastCycles = snap.pastCycles
        eventCount = snap.events.count
        hasLoaded = true
    }
}

#Preview {
    MyCycleSheet()
}
