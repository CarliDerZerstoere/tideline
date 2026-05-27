import Foundation
import SwiftData
import os.log

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

    /// On-device persistence logger. Audit fix — the 9 `modelContext.save()`
    /// call sites previously used `try?` which silently swallowed write
    /// failures. Now they route through `persist()` which logs the error
    /// to OSLog. No exfiltration risk: OSLog is on-device only (Pillar 1).
    private static let persistenceLog = Logger(
        subsystem: "com.carliderzerstoere.tideline",
        category: "persistence"
    )

    /// Save the model context, logging any error to OSLog. Replaces the
    /// previous bare `try? modelContext.save()` pattern at 9 sites in
    /// this file. Silent write failures previously surfaced as confusing
    /// "where did my data go" reports; now they're recoverable via
    /// `log show --predicate 'subsystem == "com.carliderzerstoere.tideline"'`.
    private func persist() {
        do {
            try modelContext.save()
        } catch {
            Self.persistenceLog.error("modelContext.save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    /// Current age band used to construct the predictor's prior (task #97).
    /// Set by `AppContainer` at composition time via `setAgeBand(_:)`; can
    /// be changed at runtime via `reprimeForAgeBand(_:)`. Defaults to
    /// `.unspecified` so a store constructed without an explicit band
    /// uses the safe widened fallback prior, not the (too-tight) static
    /// `populationPrior` alias.
    private var ageBand: AgeBand = .unspecified

    /// Set the initial age band BEFORE `loadAndReplay()`. AppContainer
    /// calls this at composition time after reading
    /// `@AppStorage("userAgeBand")` from `UserDefaults.standard`. Has no
    /// effect on the predictor's posterior until the next replay — call
    /// this before observations are applied.
    ///
    /// Idempotent: a no-op when the band is unchanged. Reviewer N5 —
    /// without the guard, calling `setAgeBand` twice (e.g. onboarding's
    /// `finish()` then RootView's `.task` reading the same persisted
    /// value) would rebuild the predictor twice, discarding any
    /// observations landed between the two calls. Cold-launch in
    /// particular triggers this path.
    func setAgeBand(_ band: AgeBand) async {
        guard band != ageBand || !didReplay else {
            ageBand = band
            // Task #162 — even on the idempotent path, ensure the
            // predictor knows the band so a future softReset routes
            // through the right prior. Cheap; mirrors actor state.
            await predictor.setAgeBand(band)
            return
        }
        ageBand = band
        predictor = PredictorService(
            mode: .active(.populationPrior(for: band))
        )
        // Task #162 — propagate band to the predictor so soft-resets
        // for Category C events route through the band-appropriate σ.
        await predictor.setAgeBand(band)
    }

    /// User changed their declared age band at runtime (task #97).
    /// Re-primes the predictor with the new band's prior and replays
    /// the full history. The replay reconstructs pause/retire modes
    /// from the persisted `CycleEvent` rows, so a user who was paused
    /// before the band change stays paused — but the *archived* prior
    /// reflects the new band. Net effect for users with N≥6 cycles:
    /// barely visible (posterior is data-dominated). For low-data
    /// users (N≤2): noticeable shift, which is the right behaviour —
    /// the band change is intentional.
    ///
    /// Reviewer B1 + B2 — previously this method also assigned a
    /// `.active(...)` predictor before calling `loadAndReplay`, which
    /// (a) was dead code (loadAndReplay's local-then-swap pattern
    /// immediately overwrites it) and (b) created a transient invariant
    /// violation where a paused user briefly appeared as active. Now
    /// only `ageBand` is updated; loadAndReplay reads it when building
    /// its fresh local predictor.
    func reprimeForAgeBand(_ band: AgeBand) async {
        ageBand = band
        didReplay = false
        await loadAndReplay()
    }

    /// Fetch all cycles and events in chronological order and replay them into
    /// a fresh predictor. Idempotent — repeat calls are no-ops.
    ///
    /// Concurrency note: this method has multiple `await` suspension points
    /// (predictor.observe / .apply per cycle event). The eager `didReplay`
    /// flag is NOT sufficient by itself because `rebuildCyclesFromDayEntries`
    /// — the typical caller — resets `didReplay = false` synchronously right
    /// before its await. A second `rebuild` enqueued while the first is
    /// suspended will pass the guard, run a parallel replay, and (without
    /// further care) overwrite `self.predictor` mid-loop of the first call.
    /// The audit-verified `concurrentLogDayDoesNotCorruptPredictor` test
    /// caught observedCount=22 instead of 7 under 8 parallel `logDay` calls
    /// — exactly that race.
    ///
    /// Fix: build into a LOCAL `PredictorService` for the whole replay
    /// duration, only swap `self.predictor` at the end. The swap is
    /// synchronous on the actor's executor, so external observers never
    /// see a half-built predictor. Multiple concurrent replays now each
    /// produce their own consistent local predictor and the last-finishing
    /// one wins — which is correct, since all of them see the same cycle
    /// table at their snapshot point.
    func loadAndReplay() async {
        guard !didReplay else { return }
        didReplay = true

        // One-time database migration: check all DayEntry rows for legacy timezone-local
        // midnight dates (which are NOT at UTC midnight, e.g. have non-zero UTC hours/minutes)
        // and normalize them permanently to UTC midnight (civilDay) to prevent retrieval failure
        // in dayEntry(for:) (disappearing log / missing delete button bug).
        let dayEntryDescriptor = FetchDescriptor<DayEntry>()
        if let dayEntries = try? modelContext.fetch(dayEntryDescriptor) {
            var migratedAny = false
            for entry in dayEntries {
                let normalized = entry.date.civilDay()
                if entry.date != normalized {
                    entry.date = normalized
                    migratedAny = true
                }
            }
            if migratedAny {
                persist()
                await rebuildCyclesFromDayEntries()
            }
        }

        // Build the local predictor against the currently-declared age
        // band (task #97). Without this, replay would reset the predictor
        // to the age-agnostic default and silently lose any band the
        // composition root or settings UI had just set.
        let localPredictor = PredictorService(
            mode: .active(.populationPrior(for: ageBand))
        )
        // Task #162 — propagate band so any soft-reset during replay
        // (e.g. replaying a stored Category C event) routes through
        // the band-appropriate σ. Without this, the local predictor's
        // .ageBand stays .unspecified default, and soft-resets during
        // replay collapse to the band-agnostic prior — actively wrong
        // for menopausal users.
        await localPredictor.setAgeBand(ageBand)

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
                    await localPredictor.apply(eventKind: kind, on: ev.date)
                }
                eventIndex += 1
            } else {
                // Calendar-day delta (task #99): DayEntries are already
                // civilDay-normalised at write time, so dateComponents
                // returns the exact integer day count even when the cycle
                // crosses a DST boundary. `timeIntervalSince / 86_400`
                // would have produced 27.96 or 28.04 here.
                let lengthDays = cycles[cycleIndex].startDate
                    .daysUntil(cycles[cycleIndex + 1].startDate)
                await localPredictor.observe(cycleLength: Double(lengthDays))
                cycleIndex += 1
            }
        }

        // Atomic swap of the active predictor. Synchronous on the actor's
        // executor — external observers never see a half-built predictor.
        self.predictor = localPredictor
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
        // Normalise to civilDay BEFORE any arithmetic (task #116). This
        // keeps `Cycle.startDate` on the same axis as `DayEntry.date` and
        // `CycleEvent.date`, so the rebuild merge in `loadAndReplay`
        // compares apples-to-apples, and so a 28-day cycle that straddles
        // a DST flip is recorded as exactly 28 d — not 27.96 or 28.04.
        let dayStart = date.civilDay()
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if let last = existing.first {
            // Debounce uses the raw 5-day threshold (robust against ±1h
            // DST drift). The observed cycle length uses Calendar-day
            // arithmetic so a DST-spanning cycle is exactly N days, not
            // N + 1/24 or N − 1/24. (Task #99.)
            let gap = dayStart.timeIntervalSince(last.startDate)
            if gap < 5 * 86_400 { return }   // debounce
            last.endDate = dayStart
            let lengthDays = last.startDate.daysUntil(dayStart)
            if lengthDays > 0 {
                await predictor.observe(cycleLength: Double(lengthDays))
            }
        }

        // Task #103 — idempotent DayEntry insert. Without this, the
        // Cycle row inserted below becomes an orphan: the next
        // `rebuildCyclesFromDayEntries()` derives Cycles from DayEntries
        // and deletes any Cycle not backed by a bleeding DayEntry, while
        // the predictor's length observation persists. Recording a
        // `.light` flow entry on the cycle-start day pins the Cycle
        // through future rebuilds and respects the canonical data flow
        // (DayEntries are the source of truth; Cycles are derived).
        var dayEntryLookup = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date == dayStart }
        )
        dayEntryLookup.fetchLimit = 1
        let existingEntry = (try? modelContext.fetch(dayEntryLookup))?.first
        if let existing = existingEntry {
            // Upgrade .none/.spotting → .light so the rebuild's bleeding-day
            // filter sees this entry. Otherwise a user who logged spotting
            // earlier and then taps "start period today" re-introduces the
            // orphan-Cycle bug under a different precondition (reviewer N3).
            // Never downgrade — preserve a heavier flow the user already set.
            if existing.flow.rawValue < FlowLevel.light.rawValue {
                existing.flow = .light
            }
        } else {
            modelContext.insert(DayEntry(date: dayStart, flow: .light))
        }

        let newCycle = Cycle(startDate: dayStart)
        modelContext.insert(newCycle)
        persist()
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
        let dayStart = date.civilDay()
        let lightRaw = FlowLevel.light.rawValue

        // Upsert DayEntry. Predicate-filtered fetch so SwiftData does the
        // lookup in SQLite instead of pulling every row across the actor.
        var lookup = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.date == dayStart })
        lookup.fetchLimit = 1
        let existingEntry = (try? modelContext.fetch(lookup))?.first

        // Capture the PRIOR bleeding status before we mutate, so we can tell
        // whether the rebuild is necessary. Task #118: previously the guard
        // below only checked the *new* flow — so editing an existing
        // bleeding day down to .none/.spotting bypassed the rebuild and
        // left the Cycle table + predictor with a stale observation.
        let wasBleeding = (existingEntry?.flow.rawValue ?? 0) >= lightRaw
        let isBleeding = flow.rawValue >= lightRaw

        if let existing = existingEntry {
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
        persist()

        // Future-dated entries never participate in cycle math — they live
        // as DayEntries for journaling but a future Cycle row would put
        // `currentCycleStart()` in the future and break day-in-cycle math.
        let today = Date.now.civilDay()
        guard dayStart <= today else { return }

        // Rebuild iff either the OLD or the NEW flow contributed to the
        // bleeding-day set. Catches three cases:
        //   - new bleeding entry              (was: false, is: true)
        //   - editing a bleeding day's level  (was: true,  is: true)
        //   - downgrading a bleeding day to .none/.spotting  ← #118 bug
        //                                     (was: true,  is: false)
        // If neither side was bleeding (e.g. a mood-only edit on a dry
        // day), the cycle table is invariant and we skip the rebuild.
        guard wasBleeding || isBleeding else { return }
        await rebuildCyclesFromDayEntries()
    }

    /// Rebuild the canonical `Cycle` table from the `DayEntry` table.
    ///
    /// Algorithm (cited):
    ///
    ///   1. Take all DayEntries with `flow >= .light`, chronologically.
    ///      Spotting (`flow == .spotting`) is excluded — FIGO 2018 / WHO
    ///      Belsey define cycle day 1 as bleeding requiring sanitary
    ///      protection (PMID 30198563; PMID 3048871).
    ///
    ///   2. Group consecutive bleeding days into **episodes** using the
    ///      WHO/Belsey rule: ≤ 2 dry days between bleeding days = same
    ///      episode; ≥ 3 dry days closes the episode. (Belsey 1988,
    ///      PMID 3048871 — the only formal codification.)
    ///
    ///   3. Group episodes into **cycles** using a FIGO-derived floor:
    ///      a new cycle starts when the next bleeding episode begins
    ///      ≥ 21 days after the previous cycle's day-1. Anything shorter
    ///      is intermenstrual / breakthrough bleeding within the same
    ///      cycle (FIGO 2018 frequent-menstruation cutoff <24 days, minus
    ///      reasonable variance — engineering convention, no single
    ///      textbook number exists).
    ///
    ///   4. Replace the Cycle table with the derived starts and replay
    ///      the predictor chronologically. Idempotent, order-independent —
    ///      out-of-order user backfill produces the same result as
    ///      logging the same dates in chronological order.
    private func rebuildCyclesFromDayEntries() async {
        let cal = Calendar.current
        let lightRaw = FlowLevel.light.rawValue
        let today = Date.now.civilDay()
        let allEntries = (try? modelContext.fetch(
            FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []
        // Only past + today bleeding contributes to the Cycle table. Future-
        // dated DayEntries remain in storage as journal entries but never
        // produce a Cycle row — otherwise the most recent Cycle's startDate
        // would be in the future, `currentCycleStart()` would return it, and
        // `todayDayInCycle` math collapses (today is "before" cycle day 1).
        //
        // `civilDay()` here (task #117): normalises each stored entry's
        // `date` to UTC midnight of its (year,month,day) at this user's
        // current timezone. Stored dates are already civilDay-encoded at
        // write time, but re-running it here defends against any stray
        // non-canonical Date that slipped past a write-site refactor.
        let bleedingDays = allEntries
            .filter { $0.flow.rawValue >= lightRaw }
            .map { $0.date.civilDay() }
            .filter { $0 <= today }

        // Steps 2 + 3 — Belsey episode rule + FIGO cycle floor. Shared
        // implementation in `PhaseBoundaries` (extracted 2026-05-22 to
        // eliminate the 3-way duplication across store / import-planner /
        // export-planner).
        let cycleStartDays = PhaseBoundaries.cycleStarts(
            fromBleedingDays: bleedingDays,
            calendar: cal
        )

        // Step 4 — replace Cycle table, replay predictor.
        let oldCycles = (try? modelContext.fetch(FetchDescriptor<Cycle>())) ?? []
        for c in oldCycles { modelContext.delete(c) }
        for start in cycleStartDays {
            modelContext.insert(Cycle(startDate: start))
        }
        // Set endDate on each cycle = next cycle's startDate. The inserted
        // models aren't directly exposed by SwiftData, so we re-fetch in
        // start-date order — one query, O(n) wire.
        let inserted = (try? modelContext.fetch(
            FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        )) ?? []
        for i in 0..<(max(inserted.count - 1, 0)) {
            inserted[i].endDate = inserted[i + 1].startDate
        }
        persist()

        // Reset and replay the predictor against the canonical cycle list.
        didReplay = false
        await loadAndReplay()
    }

    /// Delete the `DayEntry` for the given date if it exists.
    /// Does NOT remove the corresponding `Cycle` row — that's a separate
    /// action because removing a cycle invalidates downstream observations
    /// and requires a replay.
    func deleteDay(date: Date) async {
        let dayStart = date.civilDay()
        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.date == dayStart })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        for entry in matches {
            modelContext.delete(entry)
        }
        persist()
        // Deleting a bleeding day may have closed an episode early or
        // collapsed two cycles into one — let the rebuild handle it.
        await rebuildCyclesFromDayEntries()
    }

    // MARK: - Doctor PDF aggregator (task #46)

    /// Build the `DoctorPDFData` snapshot for the doctor-export PDF. Single
    /// actor entry point — gathers cycles, events, predictor state, and
    /// (optionally) the last 30 days of logged symptoms into one Sendable
    /// struct that the pure renderer consumes on the main actor.
    ///
    /// MDR posture: this method only surfaces data the user has logged or
    /// imported, plus predictor-derived statistics. No diagnostic
    /// interpretation. See `docs/research/2026-05-21-market-research-…`
    /// §4 for the design rationale.
    func doctorPDFData(
        maxCycles: Int = 24,
        includeEvents: Bool = true,
        includeSymptoms: Bool = false,
        patientHeader: String = "",
        now: Date = .now,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    ) async -> DoctorPDFData {
        // Cycles: pull (maxCycles + 1) starts so we can compute lengths
        // for all closed cycles. Newest-first display order.
        var descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = maxCycles + 1
        let cyclesDesc = (try? modelContext.fetch(descriptor)) ?? []
        let cyclesAsc = Array(cyclesDesc.reversed())  // oldest first for pairwise length

        // Bleeding-day count per cycle: scope the fetch to the window the
        // cycles cover so users with multi-year history don't pull
        // pre-history entries. (Reviewer rec.)
        let lightRaw = FlowLevel.light.rawValue
        let allLogged: [DayEntry]
        if let oldestStart = cyclesAsc.first?.startDate {
            let descriptor = FetchDescriptor<DayEntry>(
                predicate: #Predicate { $0.date >= oldestStart },
                sortBy: [SortDescriptor(\.date)]
            )
            allLogged = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            allLogged = []
        }

        var cycleRows: [DoctorPDFData.CycleRow] = []
        for i in 0..<cyclesAsc.count {
            let start = cyclesAsc[i].startDate
            let nextStart: Date? = i + 1 < cyclesAsc.count ? cyclesAsc[i + 1].startDate : nil
            let end = cyclesAsc[i].endDate ?? nextStart
            let lengthDays: Int? = end.map { start.daysUntil($0) }
            let upper = nextStart ?? Date.distantFuture
            let bleedingCount = allLogged.filter { entry in
                entry.date >= start && entry.date < upper && entry.flow.rawValue >= lightRaw
            }.count
            cycleRows.append(DoctorPDFData.CycleRow(
                startDate: start,
                endDate: cyclesAsc[i].endDate,
                lengthDays: lengthDays,
                bleedingDayCount: bleedingCount
            ))
        }
        // Display newest first; clip to maxCycles.
        cycleRows = Array(cycleRows.reversed().prefix(maxCycles))

        // Events.
        var eventRows: [DoctorPDFData.EventRow] = []
        if includeEvents {
            let events = allEvents()
            eventRows = events.map { snap in
                DoctorPDFData.EventRow(
                    date: snap.date,
                    germanLabel: snap.kind.germanLabel,
                    note: snap.note
                )
            }
        }

        // Symptoms: last 30 days. `loggedDays(in:)` is range-scoped.
        var symptomRows: [DoctorPDFData.SymptomRow]? = nil
        if includeSymptoms {
            let from = now.addingTimeInterval(-30 * 86_400).civilDay()
            let to = now.civilDay()
            let entries = (try? modelContext.fetch(
                FetchDescriptor<DayEntry>(
                    predicate: #Predicate { $0.date >= from && $0.date <= to },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )) ?? []
            symptomRows = entries.map { entry in
                let flowLabel: String? = entry.flow == .none ? nil : Self.germanFlowLabel(entry.flow)
                return DoctorPDFData.SymptomRow(
                    date: entry.date,
                    flowLabel: flowLabel,
                    symptoms: entry.symptoms,
                    mood: entry.moodRaw
                )
            }
        }

        // Predictor summary.
        let mode = await predictor.currentMode()
        let observedN = mode.activePredictor?.observedCount ?? mode.archivedPredictor?.observedCount ?? 0
        let mu = mode.activePredictor?.mu ?? mode.archivedPredictor?.mu

        let modeLabel: String
        switch mode {
        case .active:
            modeLabel = "aktiv"
        case .paused(_, _, let reason):
            modeLabel = "pausiert (\(Self.germanPauseReason(reason)))"
        case .retired(_, let reason):
            modeLabel = "beendet (\(Self.germanRetirementReason(reason)))"
        }

        // Upcoming prediction only when active.
        var prediction: DoctorPDFData.PredictionRow? = nil
        if mode.isActive {
            if let pred = await nextCalibratedPrediction(confidence: 0.90) {
                prediction = DoctorPDFData.PredictionRow(
                    estimatedDate: pred.estimate,
                    intervalLower: pred.interval.lowerBound,
                    intervalUpper: pred.interval.upperBound
                )
            }
        }

        let irregularityDeclared = hasPCOSDeclared()

        return DoctorPDFData(
            generatedAt: now,
            appVersion: appVersion,
            patientHeader: String(patientHeader.prefix(60)),  // hard cap
            observedCycleCount: observedN,
            averageCycleLengthDays: mu,
            predictorModeLabel: modeLabel,
            irregularityDeclared: irregularityDeclared,
            upcomingPrediction: prediction,
            cycles: cycleRows,
            events: eventRows,
            symptomEntries: symptomRows
        )
    }

    /// Consolidated snapshot for the Mein Zyklus tab + any other surface
    /// that needs a coherent multi-field view of the store. Closes the
    /// caller-side vintage drift flagged in the #120 review (was 5
    /// sequential awaits in `MyCycleSheet.reload()`).
    ///
    /// **Atomicity (honest framing)**: this method narrows the drift
    /// window to a *single* `predictor.currentMode()` actor hop. All
    /// other fields are synchronous SwiftData reads — they cannot
    /// interleave with each other on the model actor. Compared to the
    /// previous 5-hop version, the cross-actor exposure shrinks from
    /// 5 suspension points to 1. The remaining 1 is unavoidable
    /// without a unified `(mode, predictedLength)` predictor accessor.
    /// Tracked as part of #90's broader race audit.
    func myCycleSnapshot(pastCyclesLimit: Int = 6) async -> MyCycleSnapshot {
        // Sync SwiftData reads first — these run synchronously on the
        // model actor and cannot interleave.
        let cycles = pastCycleSummaries(limit: pastCyclesLimit)
        let events = allEvents()
        let lastStart = currentCycleStart()
        let bleeding: Set<Int>
        if let lastStart {
            bleeding = bleedingDaysInCurrentCycle(cycleStart: lastStart)
        } else {
            bleeding = []
        }
        // NEW-171 — per-user mensesEnd floor.
        let personalMedian = personalMedianMenses(limit: 6)
        // Single predictor round-trip — fetch mode and derive
        // predictedLength from the same `mode` value without a second
        // hop. (Reviewer rec — halves predictor traffic and removes
        // the second-suspension-point drift window.)
        let mode = await predictor.currentMode()
        let predictedLen = mode.activePredictor?.nextCycleLengthEstimate
            ?? Double(PhaseBoundaries.defaultCycleLength)
        // Task #193 / #83 Session 1 — surface the v2 mixture's cycle-
        // pattern indicator. The service computes it lazily (Gibbs runs
        // at most once between observations); the snapshot pays at most
        // one ~25ms cost per build, only when the user has reached the
        // 12-cycle graduation threshold.
        let cyclePattern = await predictor.cyclePattern()
        // Task #194 (Phase 3) — surface active recovery-profile state.
        // When non-nil, the UI replaces the cyclePattern badge with
        // recovery-mode copy. Cheap state read (no Gibbs hop).
        let recoveryState = await predictor.recoveryState()
        return MyCycleSnapshot(
            mode: mode,
            pastCycles: cycles,
            events: events,
            currentCycleStart: lastStart,
            predictedCycleLength: predictedLen,
            bleedingDaysInCurrentCycle: bleeding,
            personalMedianMenses: personalMedian,
            cyclePattern: cyclePattern,
            recoveryState: recoveryState
        )
    }

    /// Consolidated snapshot for `TidelineHomeView.refresh()` (task #90).
    /// Replaces seven sequential `await store.X()` calls with one — every
    /// cross-dependent field (`bleedingDays` ← `currentCycleStart`,
    /// `conditionalInterval` ← `todayDayInCycle` vs `cycleBoundaries`)
    /// is computed against a single consistent state read inside the
    /// actor's serial context. No interleaving with concurrent callers.
    func homeSnapshot(confidence: Double = 0.90, pastLimit: Int = 6) async -> HomeSnapshot {
        // Synchronous SwiftData reads — same actor, no suspension points.
        let cycles = pastCycleSummaries(limit: pastLimit)
        let lastStart = currentCycleStart()
        let bleed: Set<Int>
        if let lastStart {
            bleed = bleedingDaysInCurrentCycle(cycleStart: lastStart)
        } else {
            bleed = []
        }

        // todayDayInCycle is derived from lastStart on this actor (so it
        // can't drift relative to lastStart between the two reads). Matches
        // the calculation that used to live in the view at refresh()
        // line 503 — kept here to keep the snapshot self-consistent.
        let todayDayInCycle: Int
        if let lastStart {
            let dayCount = Calendar.current.dateComponents(
                [.day],
                from: lastStart.civilDay(),
                to: Date.now.civilDay()
            ).day ?? 0
            todayDayInCycle = max(1, dayCount + 1)
        } else {
            todayDayInCycle = 1
        }

        // NEW-171 — per-user mensesEnd floor from her past closed cycles'
        // bleeding-day medians. Nil for users with <3 closed cycles or
        // suspected under-logging (median < defaultMenses).
        let personalMedian = personalMedianMenses(limit: 6)
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: bleed,
            todayDayInCycle: todayDayInCycle,
            personalMedianMenses: personalMedian
        )

        // Single predictor round-trip to fetch the mode. All predictor-
        // derived values below read from this one `mode` snapshot.
        let mode = await predictor.currentMode()
        let predictedLen = mode.activePredictor?.nextCycleLengthEstimate
            ?? Double(PhaseBoundaries.defaultCycleLength)
        let predLenInt = Int(round(predictedLen))
        let cycleBoundaries = PhaseBoundaries.from(
            cycleLength: predLenInt,
            mensesEnd: mensesEnd
        )
        let observedN = mode.activePredictor?.observedCount ?? 0

        // Wave B / NEW-176 — build the PhaseBoundariesPosterior so the
        // calendar can render graduated-opacity menses days (#164). Only
        // available when the predictor is active AND α_post > 1 (predictive
        // variance is undefined otherwise — needs to land 2+ observations
        // past the prior to satisfy α > 1). Nil for paused/retired modes.
        let phaseBoundariesPosterior: PhaseBoundariesPosterior?
        if let p = mode.activePredictor, p.alpha > 1.0 {
            // β(κ+1) / ((α−1)κ) — predictive variance of the Student-t
            // posterior predictive. Matches `data/extract_conformal_residuals.py`'s
            // `predictive_variance(...)` exactly.
            let predVar = p.beta * (p.kappa + 1.0) / ((p.alpha - 1.0) * p.kappa)
            phaseBoundariesPosterior = PhaseBoundariesPosterior.from(
                mensesEnd: mensesEnd,
                cycleLengthMean: p.mu,
                cycleLengthPredictiveVariance: predVar,
                alphaPost: p.alpha,
                isWidenedRecovery: p.isInRecoveryWindow,
                isOngoingIrregularity: p.isOngoingIrregularity
            )
        } else {
            phaseBoundariesPosterior = nil
        }

        // Calibrated prediction — second predictor hop only when active.
        // `nextCalibratedPrediction` itself calls `nextPrediction` which
        // re-reads `mode` internally; that re-read is bounded inside this
        // method so it cannot interleave with caller mutations once
        // `homeSnapshot` has started executing on the actor.
        let calibrated: CalibratedPrediction?
        if mode.isActive {
            calibrated = await nextCalibratedPrediction(confidence: confidence)
        } else {
            calibrated = nil
        }

        // Conditional interval — same late-window gate the view used
        // (within 5 days of predicted cycle end). Kept inside the
        // snapshot so the gate input (`todayDayInCycle` vs
        // `cycleBoundaries.cycleLength`) is consistent.
        //
        // Task #193 Session 2 — prefer the v2 mixture's conditional
        // interval when the user has graduated (N ≥ 12). For irregular
        // users (PCOS, occasionally anovulatory), the mixture's right
        // tail extends honestly into the anovulatory regime, replacing
        // the falsely-tight single-component interval. For
        // mostly-ovulatory users the two intervals agree on the lower
        // bound; the upper bound may extend further into the tail by
        // design (reflecting the small posterior probability of
        // anovulatory cycles even for mostly-regular users). Fall back
        // to single-component when below graduation threshold or when
        // the mixture chain hasn't produced posterior samples.
        //
        // **False-precision invariant.** The mixture interval is *never*
        // narrower than the single-component interval in the regime
        // where both fire — the lower-bound parity is guarded by the
        // `conditionalLowerBoundParity` test in MixturePredictorTests.
        // If that test ever flakes, this route is the canary.
        //
        // **Calibration trade-off.** This path is NOT calibrated by the
        // ConformalCalibrator (#114). The calibrator wraps the single-
        // component predictive and hasn't been extended to wrap the
        // mixture yet — that's #124 (NEW-E), blocked on Fehring
        // licensing #155. At the graduation point we choose mixture
        // honesty (right tail correctness) over conformal calibration
        // (residual-based width adjustment). Magnitude of calibration
        // loss is unmeasured — empirical comparison blocked on #124.
        let conditionalDays: ClosedRange<Double>?
        if todayDayInCycle >= cycleBoundaries.cycleLength - 5 {
            let dSinceStart = max(0.0, Double(todayDayInCycle - 1))
            if let mixtureInterval = await predictor.mixtureConditionalInterval(
                daysSinceLastPeriod: dSinceStart,
                confidence: confidence
            ) {
                conditionalDays = mixtureInterval
            } else {
                conditionalDays = await predictor.conditionalInterval(
                    daysSinceLastPeriod: dSinceStart,
                    confidence: confidence
                )
            }
        } else {
            conditionalDays = nil
        }

        // Pull the typed terminal-mode reasons in a single pattern-match
        // each — the view used to do this with a separate switch on `mode`
        // *after* it had already left the actor, which was fine but is
        // now unified here.
        let pausedReason: PauseReason?
        if case .paused(_, _, let reason) = mode {
            pausedReason = reason
        } else {
            pausedReason = nil
        }
        let retiredReason: RetirementReason?
        if case .retired(_, let reason) = mode {
            retiredReason = reason
        } else {
            retiredReason = nil
        }

        // Audit follow-up — loss-aware suppression flag for the UI. Same
        // 28-day window as `NotificationGate` (CLAUDE.md hard rule). Surfaced
        // here so callers can hide the in-app pregnancy-test card and other
        // cycle-prediction surfaces during the suppression window. Pure
        // SwiftData read, no actor hop.
        let hasRecentLoss = hasRecentPregnancyLoss()

        return HomeSnapshot(
            mode: mode,
            pastCycles: cycles,
            currentCycleStart: lastStart,
            bleedingDays: bleed,
            todayDayInCycle: todayDayInCycle,
            cycleBoundaries: cycleBoundaries,
            observedCycleCount: observedN,
            calibratedPrediction: calibrated,
            conditionalIntervalDays: conditionalDays,
            pausedReason: pausedReason,
            retiredReason: retiredReason,
            hasRecentPregnancyLoss: hasRecentLoss,
            phaseBoundariesPosterior: phaseBoundariesPosterior,
            personalMedianMenses: personalMedian
        )
    }

    private static func germanFlowLabel(_ flow: FlowLevel) -> String {
        switch flow {
        case .none: return "—"
        case .spotting: return "Schmierblutung"
        case .light: return "leicht"
        case .medium: return "mittel"
        case .heavy: return "stark"
        }
    }

    private static func germanPauseReason(_ reason: PauseReason) -> String {
        switch reason {
        case .breastfeeding: return "Stillzeit"
        case .hormonalContraception: return "hormonelle Verhütung"
        case .hypothalamicAmenorrhea: return "hypothalamische Amenorrhoe"
        case .userInitiated: return "manuell"
        }
    }

    private static func germanRetirementReason(_ reason: RetirementReason) -> String {
        switch reason {
        case .hysterectomy: return "Hysterektomie"
        case .oophorectomy: return "Oophorektomie"
        case .userInitiated: return "manuell"
        }
    }

    /// Batch-import HealthKit menstrual-flow samples (task #71). Inserts
    /// one `DayEntry` per non-conflicting sample inside a single
    /// `modelContext.save()` and calls `rebuildCyclesFromDayEntries` ONCE
    /// at the end. Avoids N rebuilds for an N-day import.
    ///
    /// Conflict policy: when `skipExisting == true` and a `DayEntry`
    /// already exists for that civilDay, the imported sample is silently
    /// dropped. Counted in the returned `ImportResult`.
    ///
    /// Future-dated samples are dropped (already filtered by
    /// `HKImportPlanner`, but the guard is here too as defence in depth).
    func importHealthKitSamples(
        _ samples: [(date: Date, flow: FlowLevel)],
        skipExisting: Bool = true
    ) async -> ImportResult {
        guard !samples.isEmpty else {
            return ImportResult(importedDays: 0, skippedExistingDays: 0, droppedFutureDays: 0)
        }

        let today = Date.now.civilDay()
        var imported = 0
        var skippedExisting = 0
        var droppedFuture = 0

        // Pre-fetch all existing DayEntry dates into a Set so the conflict
        // check is O(1) instead of N SQLite queries per sample. For a
        // 500-day import that's 500 → 1 round-trips. (Reviewer rec.)
        let existingDays: Set<Date>
        if skipExisting {
            let all = (try? modelContext.fetch(
                FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\.date)])
            )) ?? []
            existingDays = Set(all.map { $0.date.civilDay() })
        } else {
            existingDays = []
        }

        for sample in samples {
            let dayStart = sample.date.civilDay()
            if dayStart > today {
                droppedFuture += 1
                continue
            }
            if skipExisting && existingDays.contains(dayStart) {
                skippedExisting += 1
                continue
            }
            modelContext.insert(DayEntry(
                date: dayStart,
                flow: sample.flow,
                moodRaw: nil,
                symptoms: [],
                note: ""
            ))
            imported += 1
        }

        persist()
        // One rebuild for the entire batch — replays predictor with the
        // full historical record in chronological order.
        if imported > 0 {
            await rebuildCyclesFromDayEntries()
        }

        return ImportResult(
            importedDays: imported,
            skippedExistingDays: skippedExisting,
            droppedFutureDays: droppedFuture
        )
    }

    /// Apply a flow level to a set of civilDays in one batched operation
    /// (task #79 — calendar range-select for bulk backfill).
    ///
    /// Upsert semantics per date:
    ///   - existing entry, `flow != .none`: overwrite `flow` only,
    ///     preserve `symptoms` / `mood` / `note` (orthogonal to flow).
    ///   - existing entry, `flow == .none` + no metadata: delete the row
    ///     (matches the single-day `logDay` convention that an empty
    ///     row is a non-row).
    ///   - existing entry, `flow == .none` + has metadata: write
    ///     `flow = .none` but keep the row (the note/mood/symptoms are
    ///     still real journal content).
    ///   - no existing entry: insert a fresh row with the chosen flow
    ///     and empty metadata.
    ///
    /// Future-dated entries are dropped (defence in depth — the UI
    /// shouldn't allow this but the store enforces it).
    ///
    /// Rebuilds the Cycle table + replays the predictor **exactly once**
    /// at the end, not N times. Mirrors the `importHealthKitSamples`
    /// pattern (one save, one rebuild).
    @discardableResult
    func logDayRange(dates: [Date], flow: FlowLevel) async -> BulkLogResult {
        guard !dates.isEmpty else {
            return BulkLogResult(written: 0, removed: 0, droppedFuture: 0)
        }

        let today = Date.now.civilDay()
        let lightRaw = FlowLevel.light.rawValue

        // Normalise input to civilDays + de-duplicate. Backward-tapped
        // ranges from the UI are already sorted before they reach here,
        // but the dedupe defends against any caller passing duplicates.
        let civilDates = Set(dates.map { $0.civilDay() })

        // Pre-fetch all existing entries whose date is in the input set,
        // in one query. O(1) per-date lookup instead of N round-trips.
        let existing = (try? modelContext.fetch(
            FetchDescriptor<DayEntry>(predicate: #Predicate { civilDates.contains($0.date) })
        )) ?? []
        var byDate: [Date: DayEntry] = [:]
        for entry in existing { byDate[entry.date] = entry }

        var written = 0
        var removed = 0
        var droppedFuture = 0
        var anyBleedingChange = false

        for dayStart in civilDates {
            if dayStart > today {
                droppedFuture += 1
                continue
            }

            if let entry = byDate[dayStart] {
                let wasBleeding = entry.flow.rawValue >= lightRaw
                if flow == .none
                    && entry.moodRaw == nil
                    && entry.symptoms.isEmpty
                    && entry.note.isEmpty
                {
                    // Empty row after this write — delete instead.
                    modelContext.delete(entry)
                    removed += 1
                    if wasBleeding { anyBleedingChange = true }
                } else {
                    // Bulk-write preserves `symptoms` / `mood` / `note`
                    // by NOT touching them. This diverges from the
                    // single-day `logDay` path (line ~189) which
                    // overwrites all four fields because LogDaySheet
                    // presents them all and a "save" implies the user
                    // confirmed every field. The range-picker only
                    // exposes flow, so it must not nuke journal data.
                    let willBleed = flow.rawValue >= lightRaw
                    entry.flow = flow
                    written += 1
                    if wasBleeding != willBleed { anyBleedingChange = true }
                }
            } else {
                if flow == .none {
                    // Nothing to insert — empty row with no metadata is
                    // semantically a no-op (matches `logDay` for the
                    // same input).
                    continue
                }
                modelContext.insert(DayEntry(
                    date: dayStart,
                    flow: flow,
                    moodRaw: nil,
                    symptoms: [],
                    note: ""
                ))
                written += 1
                if flow.rawValue >= lightRaw { anyBleedingChange = true }
            }
        }

        persist()
        // Single rebuild for the whole batch. Same gating as `logDay`:
        // only trigger when AT LEAST ONE row in the batch crossed the
        // `.light` bleeding threshold in either direction (.none/.spotting
        // ↔ .light/.medium/.heavy). Flow shifts entirely within the
        // bleeding band (e.g. .medium → .heavy) leave the bleeding-day
        // SET unchanged, and Cycle boundaries are derived purely from
        // that set (Belsey + FIGO grouping), so the table is invariant
        // under such shifts. The OR-accumulation across rows means the
        // rebuild fires even when only one row in a large batch flips.
        if anyBleedingChange {
            await rebuildCyclesFromDayEntries()
        }

        return BulkLogResult(
            written: written,
            removed: removed,
            droppedFuture: droppedFuture
        )
    }

    /// Record a life-event (Category A–E per `docs/design/disrupted-cycles.md`).
    /// Routes through `PredictorService.apply(eventKind:on:)` to perform the
    /// retire / pause / soft-reset / widen action.
    func addEvent(kind: EventKind, on date: Date, note: String = "") async {
        let event = CycleEvent(date: date.civilDay(), kind: kind, note: note)
        modelContext.insert(event)
        persist()
        // Events fold into the predictor at the right chronological point
        // during replay — calling rebuild rather than `predictor.apply`
        // directly keeps backfill order-independent.
        await rebuildCyclesFromDayEntries()
    }

    // MARK: - Irregular-cycle declaration (task #77)

    /// Whether the user has previously declared an ongoing irregularity
    /// (Category E — PCOS or otherwise). Single source of truth for the
    /// Settings toggle's initial state. **Hero text composition uses
    /// `CalibratedPrediction.isOngoingIrregularity` instead** so that a
    /// paused/retired user — whose pcosDeclared event still exists in
    /// SwiftData but no longer applies to a live predictor — doesn't see
    /// the "Deine Zyklen sind natürlich variabel" suffix attached to a
    /// non-existent prediction. (Reviewer rec #2 from the chunk-2c
    /// pre-implementation pass.)
    func hasPCOSDeclared() -> Bool {
        let pcosRaw = EventKind.pcosDeclared.rawValue
        let descriptor = FetchDescriptor<CycleEvent>(
            predicate: #Predicate { $0.kindRaw == pcosRaw }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    /// Remove every `pcosDeclared` event and rebuild from scratch. After
    /// this returns, the predictor's posterior reflects "the user has
    /// never declared irregularity" — past observations replay through
    /// the narrower-β prior they'd have used in that counterfactual.
    ///
    /// **Subtle semantic** (acknowledged design choice, fact-check 2026-05-21):
    /// if the user toggled irregularity on, logged N cycles under the
    /// wider posterior, then toggled off, this replay produces a
    /// *different* posterior than the user would have had if they'd
    /// kept the toggle off the whole time — only by the rebuild path,
    /// the observations are now replayed against the narrower prior.
    /// That's the right semantic ("show me what my predictor would look
    /// like if I'd never declared") and matches Pillar 4 (user-as-
    /// authority-on-their-own-data), but if a user expected "preserve
    /// past observations as widened", they'd be surprised. We accept
    /// this because the toggle is intended as a current-state signal,
    /// not a history flag.
    // MARK: - Event read/display (task #89)

    /// All `CycleEvent`s as Sendable snapshots, newest first. Used by the
    /// "Mein Zyklus" sheet to surface the events the app has been
    /// silently logging (PCOS declaration today; resume-after-pause,
    /// miscarriage, etc. in future tasks). Filters out events whose
    /// `kindRaw` no longer maps to a known `EventKind` — that can only
    /// happen if a future app version persists a new case and the user
    /// downgrades; safer to hide than to render an "unknown" row.
    /// True when ANY `EventKind.isPregnancyLoss` event sits in the
    /// trailing `window` interval before `asOf` (task #122). Powers the
    /// 28-day loss-aware notification suppression — CLAUDE.md hard
    /// rule that cycle-prediction notifications must NOT fire within
    /// 4 weeks of a logged pregnancy loss.
    ///
    /// Window semantics: event date in `(asOf - window, asOf]`. A loss
    /// dated exactly `asOf - window` ago is just outside the window
    /// (the timer has just expired). `asOf` is injectable so tests
    /// can pin specific edge cases without touching `Date.now`.
    ///
    /// Hybrid back-dating policy per Q1 decision: the event-date is
    /// the anchor (not the log date). A loss back-dated to 60 days
    /// ago returns false even if the user only just logged it — the
    /// suppression window for that specific loss has already elapsed.
    func hasRecentPregnancyLoss(
        within window: TimeInterval = 28 * 86_400,
        asOf reference: Date = .now
    ) -> Bool {
        let cutoff = reference.addingTimeInterval(-window)
        let descriptor = FetchDescriptor<CycleEvent>(
            predicate: #Predicate { $0.date > cutoff && $0.date <= reference }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        return candidates.contains { event in
            event.kind?.isPregnancyLoss == true
        }
    }

    func allEvents() -> [CycleEventSnapshot] {
        // Secondary sort on `kindRaw` ensures stable order when two
        // events share a date — otherwise the UI could shuffle rows
        // unpredictably across reloads.
        let descriptor = FetchDescriptor<CycleEvent>(
            sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.kindRaw)
            ]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap { row in
            guard let kind = row.kind else { return nil }
            return CycleEventSnapshot(
                persistentID: row.persistentModelID,
                date: row.date,
                kind: kind,
                note: row.note
            )
        }
    }

    /// Remove a single event by its persistent ID. Used by the events
    /// list to support swipe-to-delete. Rebuilds the predictor so the
    /// posterior reflects the event's absence — a deleted Category-C
    /// event un-soft-resets, a deleted Category-B event un-pauses, etc.
    /// Same "what would my predictor look like if this had never been
    /// logged" semantic documented on `deletePCOSDeclared`.
    func deleteEvent(persistentID: PersistentIdentifier) async {
        // Fetch then match against the persistent ID rather than using
        // the actor subscript `self[persistentID, as:]` — the latter
        // can throw `_InvalidFutureBackingData` when SwiftData hasn't
        // fully flushed a recent insert. A regular FetchDescriptor goes
        // through the disk store and always returns a stable row.
        let descriptor = FetchDescriptor<CycleEvent>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard let row = all.first(where: { $0.persistentModelID == persistentID }) else { return }
        modelContext.delete(row)
        persist()
        await rebuildCyclesFromDayEntries()
    }

    func deletePCOSDeclared() async {
        let pcosRaw = EventKind.pcosDeclared.rawValue
        let descriptor = FetchDescriptor<CycleEvent>(
            predicate: #Predicate { $0.kindRaw == pcosRaw }
        )
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        for event in matches {
            modelContext.delete(event)
        }
        persist()
        await rebuildCyclesFromDayEntries()
    }

    // MARK: - Reads

    func currentMode() async -> PredictorMode {
        await predictor.currentMode()
    }

    /// Number of cycle observations currently in the predictor's posterior.
    /// Used by the home view to decide whether to display a real prediction
    /// interval (≥3 observations) or a "still learning" low-data fallback.
    /// Threshold rationale: with κ₀=2 prior, at N<3 the posterior is still
    /// dominated by the prior — confidence intervals are >7 days wide which
    /// the design doc calls "rough estimate" territory. Three is also the
    /// threshold Clue publicly cites for predictions to become "accurate".
    func observedCycleCount() async -> Int {
        let mode = await predictor.currentMode()
        return mode.activePredictor?.observedCount ?? 0
    }

    /// Returns the Bayesian posterior mean estimate of cycle length,
    /// or the population default if the predictor is inactive or has low data.
    func predictedCycleLength() async -> Double {
        await predictor.currentMode().activePredictor?.nextCycleLengthEstimate ?? Double(PhaseBoundaries.defaultCycleLength)
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

        // Bypass the conformal wrapper for users whose posterior is
        // intentionally widened — Category E (ongoing irregularity / PCOS)
        // and Category C (recovery window after softReset). The Fehring
        // residuals were calibrated on a hyper-regular NFP cohort; applying
        // them on top of a widened NIG interval would collapse the honest
        // uncertainty back to ~9 days and violate Pillar 3 ("honest
        // uncertainty over false precision") plus disrupted-cycles.md
        // Category E ("range-only display"). Return the NIG interval as-is.
        if base.isOngoingIrregularity || base.isWidenedRecovery {
            return CalibratedPrediction(
                estimate: base.estimate,
                interval: base.interval,
                isWidenedRecovery: base.isWidenedRecovery,
                isOngoingIrregularity: base.isOngoingIrregularity
            )
        }

        // Use civilDay-anchored, calendar-arithmetic conversions so a DST
        // transition inside the calibrated horizon does not surface as a
        // wrong wall-clock date for the user (task #99).
        let nowAnchor = Date.now.civilDay()
        let pointDays = nowAnchor.daysUntil(base.estimate)
        let calibratedDays = ConformalCalibrator.shared.wrap(
            point: Double(pointDays),
            confidence: confidence
        )
        let low = nowAnchor.addingDays(calibratedDays.lowerBound)
        let high = nowAnchor.addingDays(calibratedDays.upperBound)
        return CalibratedPrediction(
            estimate: base.estimate,
            interval: low...high,
            isWidenedRecovery: base.isWidenedRecovery,
            isOngoingIrregularity: base.isOngoingIrregularity
        )
    }

    /// Median bleeding-day count per closed cycle across the most recent
    /// `limit` cycles. Returns nil when fewer than 3 closed cycles exist
    /// (insufficient data for a stable median).
    ///
    /// "Closed cycle" = a cycle that has a successor start date. The latest
    /// cycle is in progress and excluded from the count.
    ///
    /// Used by NEW-171 to set a personal floor on
    /// `PhaseBoundaries.mensesEnd` for users whose evidence shows their
    /// typical menses runs longer than the population default of 5 days.
    ///
    /// **Defensive against under-logging:** only reports a median if it's
    /// ≥ `defaultMensesDuration`. Lower medians may indicate the user
    /// missed light/spotting days rather than truly short bleeding —
    /// we cannot distinguish, so we fall back to the population default
    /// in that case (nil return).
    ///
    /// V5 validation against Fehring n=132 women ≥3 cycles: 40% have
    /// personal median > 5 d → real activation rate.
    func personalMedianMenses(limit: Int = 6) -> Int? {
        // Mirror `pastCycleSummaries(limit:)`: pull only the most recent
        // `limit + 1` cycles via `fetchLimit`, sorted reverse, then reverse
        // back. We need limit+1 because we count bleeding days per CLOSED
        // cycle, where closure is defined by having a successor start —
        // so we always discard the latest (in-progress) entry. Reviewer S1.
        var descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 1
        let cyclesDesc = (try? modelContext.fetch(descriptor)) ?? []
        guard cyclesDesc.count >= 2 else { return nil }   // need next-cycle start
        let cycles = Array(cyclesDesc.reversed())   // oldest → newest

        let lightRaw = FlowLevel.light.rawValue
        var perCycleBleedingDays: [Int] = []
        // For each closed cycle (has a successor), count bleeding-quality
        // DayEntries in [start, nextStart). Belsey grouping is already
        // reflected in the Cycle table by #156's rebuild — these counts
        // are per-cycle bleeding days, not per-episode.
        for i in 0..<(cycles.count - 1) {
            let start = cycles[i].startDate
            let nextStart = cycles[i + 1].startDate
            let entryDesc = FetchDescriptor<DayEntry>(
                predicate: #Predicate { $0.date >= start && $0.date < nextStart }
            )
            let entries = (try? modelContext.fetch(entryDesc)) ?? []
            let count = entries.filter { $0.flow.rawValue >= lightRaw }.count
            perCycleBleedingDays.append(count)
        }
        guard perCycleBleedingDays.count >= 3 else { return nil }

        let sorted = perCycleBleedingDays.sorted()
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
        // Defensive: only report when median is at or above the population
        // default. Lower values may indicate under-logging; can't disambiguate.
        return median >= PhaseBoundaries.defaultMensesDuration ? median : nil
    }

    /// Summary of past cycles for the home-view sparkline. Returns each
    /// closed cycle's start date and derived length in days, ordered
    /// oldest → newest.
    func pastCycleSummaries(limit: Int = 6) -> [CycleSummary] {
        // Pull only the most recent `limit + 1` cycles from SwiftData — we
        // need `limit + 1` because closed cycles are derived from consecutive
        // pairs (length = startDate[i+1] - startDate[i]). Reading the whole
        // table into memory and then `.suffix`-ing was O(all-cycles-ever)
        // for a fixed-size output.
        var descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 1
        let cyclesDesc = (try? modelContext.fetch(descriptor)) ?? []
        let cycles = Array(cyclesDesc.reversed())
        guard cycles.count >= 2 else { return [] }
        var out: [CycleSummary] = []
        for i in 0..<(cycles.count - 1) {
            let length = Int(round(
                cycles[i + 1].startDate.timeIntervalSince(cycles[i].startDate) / 86_400
            ))
            guard length > 0 else { continue }
            out.append(CycleSummary(startDate: cycles[i].startDate, lengthDays: length))
        }
        return out
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
        return bleedingDaysInCurrentCycle(cycleStart: start)
    }

    /// Overload that accepts an already-fetched cycle start so the caller
    /// (e.g. `refresh()`) doesn't pay for a second `Cycle` fetch. Filters
    /// `DayEntry` to bleeding-quality rows on/after the cycle start.
    func bleedingDaysInCurrentCycle(cycleStart: Date) -> Set<Int> {
        let dayStart = cycleStart.civilDay()
        // Narrow the fetch to dates ≥ cycleStart in SQLite (predicate on
        // raw enum cases isn't supported reliably in SwiftData #Predicate,
        // so flow filtering happens in Swift on the much smaller set).
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= dayStart }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var out: Set<Int> = []
        for entry in entries where entry.flow.rawValue >= FlowLevel.light.rawValue {
            let entryDay = entry.date.civilDay()
            let days = Calendar.current.dateComponents([.day], from: dayStart, to: entryDay).day ?? -1
            if days >= 0 { out.insert(days + 1) }
        }
        return out
    }

    /// Full snapshot of a single `DayEntry`, used by the editor sheet to
    /// load existing values when the user opens an already-logged day.
    /// Without this, the editor would always start with default `.light` /
    /// empty symptoms / empty note and overwrite real saved data on Save.
    func dayEntry(for date: Date) -> DayEntrySnapshot? {
        let dayStart = date.civilDay()
        var descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.date == dayStart })
        descriptor.fetchLimit = 1
        guard let entry = (try? modelContext.fetch(descriptor))?.first else { return nil }
        return DayEntrySnapshot(
            date: entry.date,
            flow: entry.flow,
            mood: entry.moodRaw,
            symptoms: Set(entry.symptoms),
            note: entry.note
        )
    }

    /// Lightweight per-day record for the calendar grid. Each entry covers a
    /// real `DayEntry` row in SwiftData — days with no row are simply absent
    /// from the array. `hasExtras` is true when the user logged anything
    /// beyond a flow level (mood, symptoms, or a note).
    func loggedDays() -> [CalendarDayRecord] {
        let entries = (try? modelContext.fetch(
            FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []
        return entries.map { e in
            CalendarDayRecord(
                date: e.date,
                flow: e.flow,
                hasExtras: e.moodRaw != nil || !e.symptoms.isEmpty || !e.note.isEmpty,
                mood: e.moodRaw,
                hasSymptoms: !e.symptoms.isEmpty,
                hasNote: !e.note.isEmpty
            )
        }
    }

    /// Same as `loggedDays()` but scoped to a date range — used by the
    /// calendar grid which only ever renders a single month + neighbors.
    /// Avoids unbounded full-table scans on calendar appear.
    func loggedDays(in range: ClosedRange<Date>) -> [CalendarDayRecord] {
        let lo = range.lowerBound.civilDay()
        let hi = range.upperBound.civilDay()
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= lo && $0.date <= hi },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.map { e in
            CalendarDayRecord(
                date: e.date,
                flow: e.flow,
                hasExtras: e.moodRaw != nil || !e.symptoms.isEmpty || !e.note.isEmpty,
                mood: e.moodRaw,
                hasSymptoms: !e.symptoms.isEmpty,
                hasNote: !e.note.isEmpty
            )
        }
    }

    /// All cycle start dates, oldest first. Used by the calendar to colour
    /// each day by its phase (lookup: most-recent start ≤ date).
    func cycleStartDates() -> [Date] {
        let cycles = (try? modelContext.fetch(
            FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        )) ?? []
        return cycles.map(\.startDate)
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
    public let isOngoingIrregularity: Bool
}

/// Single record consumed by the calendar grid.
public struct CalendarDayRecord: Sendable, Identifiable {
    public let date: Date
    public let flow: FlowLevel
    public let hasExtras: Bool
    public let mood: Int?
    public let hasSymptoms: Bool
    public let hasNote: Bool
    public var id: Date { date }
}

/// Full snapshot of a `DayEntry`, used by the editor sheet to pre-load
/// existing values when the user opens an already-logged day.
public struct DayEntrySnapshot: Sendable, Equatable {
    public let date: Date
    public let flow: FlowLevel
    public let mood: Int?
    public let symptoms: Set<String>
    public let note: String
}

/// Consolidated snapshot of everything `MyCycleSheet` needs in one
/// atomic actor hop (task #120 follow-up). Eliminates the multi-await
/// vintage drift where six sequential `await store.X()` calls could
/// individually see different mutation states.
struct MyCycleSnapshot: Sendable {
    let mode: PredictorMode
    let pastCycles: [CycleSummary]
    let events: [CycleEventSnapshot]
    let currentCycleStart: Date?
    let predictedCycleLength: Double
    let bleedingDaysInCurrentCycle: Set<Int>
    /// Per-user mensesEnd floor (NEW-171). Nil when <3 closed cycles or
    /// suspected under-logging.
    let personalMedianMenses: Int?
    /// Task #193 / #83 Session 1 — v2 mixture-derived cycle-pattern
    /// indicator. Nil when the user has fewer than 12 observed cycles
    /// (graduation threshold), is paused/retired, or has just had a
    /// Category A/B/C event that reset the mixture sidecar.
    let cyclePattern: CyclePattern?
    /// Task #194 (Phase 3) — active recovery-profile state. Non-nil
    /// when the user logged a Category C event with a defined
    /// `RecoveryProfile` and the recovery window hasn't yet
    /// graduated. UI uses this to override the `cyclePattern` badge
    /// with "Im Erholungsprozess <event-phrase> (Zyklus N von M)".
    let recoveryState: PredictorService.ActiveRecovery?
}

/// Consolidated snapshot of everything `TidelineHomeView.refresh()` needs
/// in one atomic actor hop (task #90). Closes the multi-await vintage
/// drift where up to seven sequential `await store.X()` calls could
/// interleave with concurrent mutations from another refresh trigger
/// (sheet dismissal, phase-strip edit, resume-flow event) and produce
/// internally inconsistent `@State` writes — e.g. `bleedingDays` computed
/// against a `currentCycleStart` that's already been invalidated by a
/// rebuild that ran between the two awaits.
struct HomeSnapshot: Sendable {
    let mode: PredictorMode
    let pastCycles: [CycleSummary]
    let currentCycleStart: Date?
    let bleedingDays: Set<Int>
    let todayDayInCycle: Int
    let cycleBoundaries: PhaseBoundaries
    let observedCycleCount: Int
    let calibratedPrediction: CalibratedPrediction?
    /// Days-range conditional interval. Nil when the user is not within
    /// 5 days of the predicted cycle end (the late-mode evaluation window).
    let conditionalIntervalDays: ClosedRange<Double>?
    let pausedReason: PauseReason?
    let retiredReason: RetirementReason?
    /// True when the user has logged an `EventKind.isPregnancyLoss` event
    /// within the trailing 28 days. The home view uses this flag to suppress
    /// cycle-prediction surfaces that would be inappropriate during the
    /// post-loss window — matching the same hard rule that gates outbound
    /// notifications via `NotificationGate`. CLAUDE.md hard rule.
    let hasRecentPregnancyLoss: Bool
    /// Wave B / #164 — uncertainty-aware phase boundaries for graduated-
    /// opacity calendar rendering. Nil for paused/retired modes or when
    /// the NIG posterior hasn't accumulated enough observations to define
    /// a predictive variance (α_post ≤ 1). When nil, callers fall back to
    /// the crisp `cycleBoundaries` and render constant opacity.
    let phaseBoundariesPosterior: PhaseBoundariesPosterior?
    /// Per-user menses-length floor (NEW-171). Nil for users with <3
    /// closed cycles or suspected under-logging. Exposed here so the
    /// calendar's per-cycle `mensesEnd` derivation can use the same
    /// floor we already use in this snapshot.
    let personalMedianMenses: Int?
}

/// Outcome of a `importHealthKitSamples` batch call (task #71).
public struct ImportResult: Sendable, Equatable {
    public let importedDays: Int
    public let skippedExistingDays: Int
    public let droppedFutureDays: Int

    public var totalProcessed: Int { importedDays + skippedExistingDays + droppedFutureDays }
}

/// Outcome of a `logDayRange` bulk-backfill call (task #79).
/// `written` covers both inserts and in-place updates; `removed`
/// tracks rows deleted because the bulk write left them empty.
public struct BulkLogResult: Sendable, Equatable {
    public let written: Int
    public let removed: Int
    public let droppedFuture: Int

    public var totalProcessed: Int { written + removed + droppedFuture }
}

/// Snapshot of a single `CycleEvent` for the events-list UI (task #89).
/// `persistentID` is the SwiftData identifier — used by the list to
/// route a swipe-delete back to the actor via `deleteEvent(persistentID:)`.
public struct CycleEventSnapshot: Sendable, Identifiable {
    public let persistentID: PersistentIdentifier
    public let date: Date
    public let kind: EventKind
    public let note: String

    public var id: PersistentIdentifier { persistentID }
}
