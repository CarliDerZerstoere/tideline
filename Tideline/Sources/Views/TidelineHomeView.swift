import SwiftUI
import SwiftData

/// The home view. Four vertical layers per `docs/design/tideline-visual-language.md`:
///   1. TidelineHero — atmospheric beach scene
///   2. CyclePhaseStrip — data anchor (day numbers, bleeding overlays, phase bands)
///   3. TideSparkline — last 6 cycles
///   4. Actions card — quick log, mood, life-event
struct TidelineHomeView: View {
    @Environment(\.cycleStore) private var store
    @AppStorage("useTideNaming") private var useTideNaming: Bool = true

    @State private var heroState: HeroState = .empty
    @State private var pastCycles: [CycleSummary] = []
    @State private var currentCycleStart: Date?
    @State private var currentCycleBoundaries: PhaseBoundaries = .populationDefault
    @State private var todayDayInCycle: Int = 1
    @State private var bleedingDays: Set<Int> = []
    @State private var showLogSheet: Bool = false
    @State private var moodSelection: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TidelineHero(state: heroState, useTideNaming: useTideNaming)
                    .padding(.horizontal)

                if let start = currentCycleStart {
                    CyclePhaseStrip(
                        cycleStartDate: start,
                        boundaries: currentCycleBoundaries,
                        bleedingDays: bleedingDays,
                        today: todayDayInCycle,
                        useTideNaming: useTideNaming
                    )
                    .padding(.horizontal)
                }

                TideSparkline(
                    cycles: pastCycles,
                    onCycleTap: { _ in /* TODO: detail view */ }
                )
                .padding(.horizontal)

                actionsCard
                    .padding(.horizontal)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    showLogSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityLabel("Tag erfassen")
                .disabled(store == nil)
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $showLogSheet, onDismiss: { Task { await refresh() } }) {
            LogDaySheet()
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            // Mood emojis only — no label.
            MoodPicker(selection: $moodSelection)
                .onChange(of: moodSelection) { _, new in
                    Task { await logMoodToday(new) }
                }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Data refresh

    private func refresh() async {
        guard let store else { return }
        let mode = await store.currentMode()
        let past = await store.pastCycleSummaries(limit: 6)
        pastCycles = past

        let lastStart = await store.currentCycleStart()
        currentCycleStart = lastStart
        let bleed = await store.bleedingDaysInCurrentCycle()
        bleedingDays = bleed

        if let lastStart {
            let dayCount = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastStart), to: Calendar.current.startOfDay(for: .now)).day ?? 0
            todayDayInCycle = max(1, dayCount + 1)
            let mensesEnd = bleed.max() ?? 5
            // Predicted cycle length: from past cycles if available, else 29.
            let predLen: Int = past.isEmpty ? 29 : Int(round(Double(past.map(\.lengthDays).reduce(0, +)) / Double(past.count)))
            currentCycleBoundaries = PhaseBoundaries.from(cycleLength: predLen, mensesEnd: mensesEnd)
        }

        // Build hero state.
        switch mode {
        case .active where lastStart != nil:
            let calibrated = await store.nextCalibratedPrediction(confidence: 0.90)
            let predLower = predictedDay(from: calibrated?.interval.lowerBound, baseline: currentCycleStart)
            let predUpper = predictedDay(from: calibrated?.interval.upperBound, baseline: currentCycleStart)
            let intervalText = predictionIntervalText(from: calibrated?.interval)
            let phase = currentCycleBoundaries.phase(forDay: todayDayInCycle)
            heroState = .active(ActiveHeroModel(
                todayDay: todayDayInCycle,
                cycleLength: currentCycleBoundaries.cycleLength,
                phase: phase,
                predictedLowerDay: predLower,
                predictedUpperDay: predUpper,
                predictionIntervalText: intervalText
            ))

        case .active:
            heroState = .empty

        case .paused(_, _, let reason):
            heroState = .paused(reasonLabel: germanLabel(for: reason))

        case .retired(_, let reason):
            heroState = .retired(reasonLabel: germanLabel(for: reason))
        }
    }

    private func predictedDay(from date: Date?, baseline: Date?) -> Int {
        guard let date, let baseline else { return currentCycleBoundaries.cycleLength }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: baseline), to: Calendar.current.startOfDay(for: date)).day ?? currentCycleBoundaries.cycleLength
        return max(1, days + 1)
    }

    private func predictionIntervalText(from interval: ClosedRange<Date>?) -> String? {
        guard let interval else { return nil }
        let lower = interval.lowerBound.formatted(.dateTime.day().month())
        let upper = interval.upperBound.formatted(.dateTime.day().month())
        return "Periode zwischen \(lower) und \(upper) erwartet"
    }

    private func germanLabel(for reason: PauseReason) -> String {
        switch reason {
        case .breastfeeding: return "Stillzeit"
        case .hormonalContraception: return "hormonelle Verhütung"
        case .hypothalamicAmenorrhea: return "hypothalamische Amenorrhoe"
        case .userInitiated: return "manuell pausiert"
        }
    }

    private func germanLabel(for reason: RetirementReason) -> String {
        switch reason {
        case .hysterectomy: return "Hysterektomie"
        case .oophorectomy: return "Oophorektomie"
        case .userInitiated: return "manuell beendet"
        }
    }

    private func logMoodToday(_ mood: Int?) async {
        guard let store, let mood else { return }
        await store.logDay(date: .now, flow: .none, symptoms: [], mood: mood)
    }
}
