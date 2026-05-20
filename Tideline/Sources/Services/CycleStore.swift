import Foundation
import SwiftData

/// The single bridge between SwiftData persistence and `PredictorService`.
///
/// Declared `@ModelActor` so the actor owns its own `ModelContext` and is safe
/// to call across concurrency domains under Swift 6 strict concurrency.
/// `ModelContext` is non-Sendable; `@ModelActor` is the documented way to
/// access it from a background actor in iOS 18+.
///
/// Responsibilities:
///   - Insert `Cycle` and `CycleEvent` records.
///   - Derive cycle length from consecutive period-start dates and feed it to
///     the predictor.
///   - On cold start, replay the full history (cycles + events in
///     chronological order) into a fresh `PredictorService` so the posterior
///     and mode survive app launches without separate persistence.
@ModelActor
actor CycleStore {
    private var predictor = PredictorService()
    private var didReplay = false

    /// Fetch all cycles and events in chronological order and replay them into
    /// a fresh predictor. Idempotent — repeat calls are no-ops.
    func loadAndReplay() async {
        guard !didReplay else { return }
        predictor = PredictorService()

        let cycleDescriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let eventDescriptor = FetchDescriptor<CycleEvent>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        let cycles = (try? modelContext.fetch(cycleDescriptor)) ?? []
        let events = (try? modelContext.fetch(eventDescriptor)) ?? []

        // Merge by date so disruption events land in the right place between
        // cycles. Cycle length = next start - this start; an event that lands
        // between cycle N and N+1 fires before cycle N+1 is observed.
        var cycleIndex = 0
        var eventIndex = 0
        while cycleIndex < cycles.count - 1 || eventIndex < events.count {
            let cycleDate = cycleIndex < cycles.count - 1
                ? cycles[cycleIndex + 1].startDate
                : Date.distantFuture
            let eventDate = eventIndex < events.count
                ? events[eventIndex].date
                : Date.distantFuture

            if eventDate <= cycleDate {
                let ev = events[eventIndex]
                if let kind = ev.kind {
                    await predictor.apply(eventKind: kind, on: ev.date)
                }
                eventIndex += 1
            } else {
                let length = cycles[cycleIndex + 1].startDate
                    .timeIntervalSince(cycles[cycleIndex].startDate) / 86_400
                await predictor.observe(cycleLength: length)
                cycleIndex += 1
            }
        }

        didReplay = true
    }

    // MARK: - Mutations

    /// Record the start of a new period. Closes the previous open cycle by
    /// setting its `endDate` and feeding the derived length to the predictor.
    ///
    /// Debounces against starts within 5 days of the most recent one. Five
    /// days covers typical menses duration (median 5 days, range 2–8 per
    /// AWHS 2023): bleeding logged on day 3 of an ongoing period must not
    /// be treated as a new cycle. Shorter than the shortest plausible cycle
    /// (~21 days), so genuine very-short cycles are still recognised.
    func startPeriod(on date: Date) async {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if let last = existing.first {
            let gap = date.timeIntervalSince(last.startDate)
            if gap < 5 * 86_400 { return }   // debounce
            last.endDate = date
            let length = gap / 86_400
            if length > 0 {
                await predictor.observe(cycleLength: length)
            }
        }

        let newCycle = Cycle(startDate: date)
        modelContext.insert(newCycle)
        try? modelContext.save()
    }

    /// Upsert a `DayEntry` for the given date with the user's logged flow,
    /// symptoms, mood, and free-text note. If `flow >= .light` and the
    /// previous day was not a bleeding day, this is treated as the first
    /// day of a new period and `startPeriod` is called.
    ///
    /// Spotting alone does NOT trigger a cycle start — clinical convention
    /// is that cycle day 1 is the first day of menses-quality flow.
    /// Symptoms and mood are never fed to the predictor (per the verified
    /// research note: no published study demonstrates symptom features
    /// improve cycle-length prediction accuracy).
    func logDay(
        date: Date,
        flow: FlowLevel,
        symptoms: [String] = [],
        mood: Int? = nil,
        note: String = ""
    ) async {
        let dayStart = Calendar.current.startOfDay(for: date)

        // Upsert DayEntry.
        let allEntries = (try? modelContext.fetch(
            FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []
        if let existing = allEntries.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: dayStart)
        }) {
            existing.flow = flow
            existing.symptoms = symptoms
            existing.moodRaw = mood
            existing.note = note
        } else {
            modelContext.insert(DayEntry(
                date: dayStart,
                flow: flow,
                moodRaw: mood,
                symptoms: symptoms,
                note: note
            ))
        }
        try? modelContext.save()

        // Decide whether this is a new cycle start.
        guard flow.rawValue >= FlowLevel.light.rawValue else { return }

        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let yesterdayWasBleeding = allEntries.contains { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: yesterdayStart)
                && entry.flow.rawValue >= FlowLevel.light.rawValue
        }
        if !yesterdayWasBleeding {
            await startPeriod(on: dayStart)
        }
    }

    /// Delete the `DayEntry` for the given date if it exists.
    /// Does NOT remove the corresponding `Cycle` row — that's a separate
    /// action because removing a cycle invalidates downstream observations
    /// and requires a replay.
    func deleteDay(date: Date) async {
        let dayStart = Calendar.current.startOfDay(for: date)
        let allEntries = (try? modelContext.fetch(
            FetchDescriptor<DayEntry>()
        )) ?? []
        for entry in allEntries where Calendar.current.isDate(entry.date, inSameDayAs: dayStart) {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    /// Record a life-event (Category A–E per `docs/design/disrupted-cycles.md`).
    /// Routes through `PredictorService.apply(eventKind:on:)` to perform the
    /// retire / pause / soft-reset / widen action.
    func addEvent(kind: EventKind, on date: Date, note: String = "") async {
        let event = CycleEvent(date: date, kind: kind, note: note)
        modelContext.insert(event)
        try? modelContext.save()
        await predictor.apply(eventKind: kind, on: date)
    }

    // MARK: - Reads

    func currentMode() async -> PredictorMode {
        await predictor.currentMode()
    }

    /// Returns the next-period prediction, or nil if paused / retired.
    /// The returned interval is the predictor's native (uncalibrated) one.
    /// Use `nextCalibratedPrediction` for the conformal-wrapped interval.
    func nextPrediction(confidence: Double = 0.90) async -> Prediction? {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let cycles = (try? modelContext.fetch(descriptor)) ?? []
        guard let last = cycles.first else { return nil }
        return await predictor.nextPrediction(after: last.startDate, confidence: confidence)
    }

    /// Like `nextPrediction`, but wraps the interval with the conformal
    /// calibrator so the 90% interval is empirically calibrated to ~90%.
    func nextCalibratedPrediction(confidence: Double = 0.90) async -> CalibratedPrediction? {
        guard let base = await nextPrediction(confidence: confidence) else { return nil }
        let pointDays = base.estimate.timeIntervalSince(.now) / 86_400
        let calibrated = ConformalCalibrator.shared.wrap(
            point: pointDays,
            confidence: confidence
        )
        let low = Date(timeIntervalSinceNow: calibrated.lowerBound * 86_400)
        let high = Date(timeIntervalSinceNow: calibrated.upperBound * 86_400)
        return CalibratedPrediction(
            estimate: base.estimate,
            interval: low...high,
            isWidenedRecovery: base.isWidenedRecovery
        )
    }

    /// Summary of past cycles for the home-view sparkline. Returns each
    /// closed cycle's start date and derived length in days, ordered
    /// oldest → newest.
    func pastCycleSummaries(limit: Int = 6) -> [CycleSummary] {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        let cycles = (try? modelContext.fetch(descriptor)) ?? []
        guard cycles.count >= 2 else { return [] }
        var out: [CycleSummary] = []
        for i in 0..<(cycles.count - 1) {
            let length = Int(round(
                cycles[i + 1].startDate.timeIntervalSince(cycles[i].startDate) / 86_400
            ))
            guard length > 0 else { continue }
            out.append(CycleSummary(startDate: cycles[i].startDate, lengthDays: length))
        }
        return Array(out.suffix(limit))
    }

    /// Start date of the most recent (current) cycle, or nil if none.
    func currentCycleStart() -> Date? {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let cycles = (try? modelContext.fetch(descriptor)) ?? []
        return cycles.first?.startDate
    }

    /// Bleeding days within the current cycle, returned as 1-indexed cycle days
    /// (day 1 = start of current cycle).
    func bleedingDaysInCurrentCycle() -> Set<Int> {
        guard let start = currentCycleStart() else { return [] }
        let dayStart = Calendar.current.startOfDay(for: start)
        let entries = (try? modelContext.fetch(
            FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []
        var out: Set<Int> = []
        for entry in entries where entry.flow.rawValue >= FlowLevel.light.rawValue {
            let entryDay = Calendar.current.startOfDay(for: entry.date)
            let days = Calendar.current.dateComponents([.day], from: dayStart, to: entryDay).day ?? -1
            if days >= 0 { out.insert(days + 1) }
        }
        return out
    }

    /// Conditional credible interval given the current cycle has run
    /// `daysSinceLastPeriod` without a new period yet (the late-period UI).
    func conditionalIntervalForLatePeriod(
        daysSinceLastPeriod D: Double,
        confidence: Double = 0.90
    ) async -> ClosedRange<Double>? {
        await predictor.conditionalInterval(daysSinceLastPeriod: D, confidence: confidence)
    }
}

/// Same shape as `Prediction` but explicitly carries the conformal interval.
/// Kept as a separate type so the caller knows it was calibrated.
public struct CalibratedPrediction: Sendable, Equatable {
    public let estimate: Date
    public let interval: ClosedRange<Date>
    public let isWidenedRecovery: Bool
}
