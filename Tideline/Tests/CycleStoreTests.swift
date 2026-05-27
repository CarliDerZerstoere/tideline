import Testing
import Foundation
import SwiftData
@testable import Tideline

@Suite("CycleStore — SwiftData ↔ Predictor bridge")
struct CycleStoreTests {

    /// Build an in-memory container with all three model types.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("startPeriod inserts a Cycle row")
    func startPeriodInserts() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.startPeriod(on: .now)
        // Verify the Cycle landed in SwiftData.
        let count = await store.cycleCountForTests()
        #expect(count == 1)
    }

    /// Task #103 — `startPeriod(on:)` used to insert a `Cycle` row without
    /// a matching `DayEntry`. The next `rebuildCyclesFromDayEntries()`
    /// would derive cycles from the (empty) bleeding-day set and silently
    /// delete the orphan Cycle, leaving a predictor observation persisted
    /// against no visible cycle. We force the rebuild via `deleteDay` on
    /// an unrelated date (rebuild fires unconditionally there) and assert
    /// the cycle survives.
    @Test("startPeriod no longer creates orphan Cycle rows (rebuild keeps the row)")
    func startPeriodSurvivesRebuild() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let today = Date.now.civilDay()
        await store.startPeriod(on: today)
        #expect(await store.cycleCountForTests() == 1)

        // Force a rebuild via a no-op delete on an unrelated date. The
        // rebuild reads bleeding DayEntries — without the #103 fix the
        // set would be empty, the Cycle table would be wiped, and this
        // assertion would fall to 0.
        let unrelated = Calendar.current.date(byAdding: .day, value: -90, to: today)!
        await store.deleteDay(date: unrelated)
        #expect(await store.cycleCountForTests() == 1)
    }

    @Test("two startPeriod calls 28 days apart feed predictor a 28-day observation")
    func twoStartsObserveLength() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        // Task #116: pin both endpoints to civil-day anchors via
        // Calendar.date(byAdding:.day,…) so a DST flip within the 28-day
        // window can't drift the observed length to 27.96 or 28.04.
        let cal = Calendar.current
        let secondStart = Date.now.civilDay()
        let firstStart = cal.date(byAdding: .day, value: -28, to: secondStart)!
        await store.startPeriod(on: firstStart)
        await store.startPeriod(on: secondStart)
        let mode = await store.currentMode()
        guard let p = mode.activePredictor else {
            Issue.record("Expected active predictor")
            return
        }
        #expect(p.observedCount == 1)
        // After observing one 28-day cycle with κ₀=2 prior and μ₀=28.7
        // (AWHS canonical, task #94): μ' = (2·28.7 + 28) / 3 = 28.467
        #expect(abs(p.mu - 28.467) < 0.01)
    }

    @Test("addEvent with .hysterectomy transitions to retired")
    func categoryAEventRetires() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.startPeriod(on: Date(timeIntervalSinceNow: -28 * 86_400))
        await store.addEvent(kind: .hysterectomy, on: .now)
        let mode = await store.currentMode()
        #expect(mode.isRetired)
        let prediction = await store.nextPrediction()
        #expect(prediction == nil)
    }

    /// Cold-start replay should produce the same predictor state as the
    /// session that originally logged the cycles. Uses `logDay` (not
    /// `startPeriod`) so the persisted state mirrors a real user — which
    /// is what production replay actually reads (DayEntries rebuild into
    /// Cycles, not Cycle rows persisted directly).
    @Test("cold-start replay reconstructs predictor state from persisted DayEntries")
    func coldStartReplay() async throws {
        let container = try makeContainer()
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -150 * 86_400).civilDay()

        // Phase 1: populate via a store, then discard it.
        do {
            let store = CycleStore(modelContainer: container)
            for offsetDays in [0, 28, 57, 86] {
                await store.logDay(
                    date: cal.date(byAdding: .day, value: offsetDays, to: baseline)!,
                    flow: .medium
                )
            }
            let muBefore = await store.currentMode().activePredictor?.mu ?? 0
            #expect(muBefore > 28.5 && muBefore < 29.0)
        }

        // Phase 2: fresh store on the same container — replays the saved
        // DayEntries through `rebuildCyclesFromDayEntries` → `loadAndReplay`.
        let fresh = CycleStore(modelContainer: container)
        await fresh.loadAndReplay()
        let muAfter = await fresh.currentMode().activePredictor?.mu ?? 0
        #expect(muAfter > 28.5 && muAfter < 29.0)
        let observed = await fresh.currentMode().activePredictor?.observedCount ?? -1
        #expect(observed == 3)  // 4 cycles → 3 cycle lengths
    }

    /// Regression for task #113: this test used to call `startPeriod` 3×
    /// directly, which inserts `Cycle` rows without `DayEntry` rows. When
    /// `addEvent` then triggered `rebuildCyclesFromDayEntries`, the rebuild
    /// found zero DayEntries and deleted every Cycle — so `loadAndReplay`
    /// ran the soft reset against a fresh `populationPrior`, and asserting
    /// κ=2.0 + observedCount=0 was trivially satisfied by a full wipeout.
    /// That hid the real bug-class: a wipeout would silently replace the
    /// user's learned μ with the AWHS 28.7 d population mean, throwing
    /// away weeks of personalisation.
    ///
    /// The fix is twofold: (a) use `logDay` so DayEntries persist through
    /// the rebuild; (b) deliberately shift the posterior μ away from the
    /// population prior using a non-28-day cycle, so the test would
    /// observably fail if μ ever reverted.
    @Test("Category C event between cycles soft-resets the posterior — μ preserved, not wiped")
    func eventBetweenCycles() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -150 * 86_400).civilDay()

        // Log bleeding days via the production entry point so they survive
        // the post-event rebuild. Use one 31-day cycle to shift μ measurably
        // away from the population prior (28.7) so a wipeout would diverge.
        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(date: cal.date(byAdding: .day, value: 31, to: baseline)!, flow: .medium)
        await store.logDay(date: cal.date(byAdding: .day, value: 62, to: baseline)!, flow: .medium)

        let before = await store.currentMode().activePredictor
        try #require(before != nil)
        let muBefore = before!.mu
        #expect(before!.observedCount == 2)
        // Two 31-day observations against μ₀=28.7, κ₀=2:
        //   after #1: μ = (2·28.7 + 31)/3 = 29.467, κ = 3
        //   after #2: μ = (3·29.467 + 31)/4 = 29.850, κ = 4
        // Tolerance is loose to allow for rebuild rounding via 86_400-math.
        #expect(abs(muBefore - 29.850) < 0.05)
        // Crucial: μ has moved away from populationPrior — so a wipeout
        // would now be visibly different from a soft reset.
        #expect(abs(muBefore - 28.7) > 1.0)

        await store.addEvent(
            kind: .majorSurgery, // Category C — soft-reset semantics
            on: cal.date(byAdding: .day, value: 70, to: baseline)!
        )
        let after = await store.currentMode().activePredictor
        try #require(after != nil)
        #expect(after!.kappa == 2.0)
        #expect(after!.alpha == 3.0)
        #expect(after!.observedCount == 0)
        // Soft-reset contract: μ is preserved exactly. A wipeout would
        // leave μ at 28.7 here — abs(28.7 - 29.85) ≈ 1.15, far above 1e-9.
        #expect(abs(after!.mu - muBefore) < 1e-9)
    }

    /// Companion to `eventBetweenCycles`: even if soft-reset preserves μ
    /// the moment it fires, follow-up cycles must continue to update
    /// against that preserved μ — not snap back to populationPrior. This
    /// is the regression that would surface if someone later "simplified"
    /// `softReset()` by calling `self = .populationPrior`.
    @Test("After soft-reset, subsequent cycles update against the preserved μ, not the population prior")
    func softResetPreservesMuForFollowupObservations() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -200 * 86_400).civilDay()

        // Three 31-day cycles → 2 observations, μ ≈ 29.85.
        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(date: cal.date(byAdding: .day, value: 31, to: baseline)!, flow: .medium)
        await store.logDay(date: cal.date(byAdding: .day, value: 62, to: baseline)!, flow: .medium)

        // Disruption event.
        await store.addEvent(
            kind: .majorSurgery,
            on: cal.date(byAdding: .day, value: 65, to: baseline)!
        )

        // One more bleeding day at +93 → cycle 3→4 length = 93-62 = 31 d.
        // That's the single post-event observation we want to test against.
        await store.logDay(date: cal.date(byAdding: .day, value: 93, to: baseline)!, flow: .medium)

        let after = await store.currentMode().activePredictor
        try #require(after != nil)
        // One observation post-reset → κ should be 3, observedCount 1.
        #expect(after!.observedCount == 1)
        #expect(after!.kappa == 3.0)
        // μ updates against the preserved 29.85: (2·29.85 + 31)/3 = 30.233.
        // If μ had been wiped to 28.7, we'd see (2·28.7 + 31)/3 ≈ 29.467 —
        // a 0.77-day delta. Tolerance well inside that gap.
        #expect(abs(after!.mu - 30.233) < 0.1, "μ = \(after!.mu), expected ≈ 30.233 (preserved-μ path)")
    }

    @Test("logDay with spotting does NOT start a cycle")
    func logDaySpottingNoCycle() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.logDay(date: .now, flow: .spotting)
        let count = await store.cycleCountForTests()
        #expect(count == 0)
    }

    @Test("logDay with light flow starts a cycle")
    func logDayLightStartsCycle() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.logDay(date: .now, flow: .light)
        let count = await store.cycleCountForTests()
        #expect(count == 1)
    }

    @Test("logDay on day 2 of an ongoing period does NOT start a new cycle")
    func logDayContinuationDoesNotStart() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let day1 = Calendar.current.startOfDay(for: .now).addingTimeInterval(-86_400)
        let day2 = Calendar.current.startOfDay(for: .now)
        await store.logDay(date: day1, flow: .medium)
        await store.logDay(date: day2, flow: .heavy)
        let count = await store.cycleCountForTests()
        #expect(count == 1)
    }

    @Test("logDay upserts the DayEntry on re-log")
    func logDayUpserts() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.logDay(date: .now, flow: .light, symptoms: ["cramps"])
        await store.logDay(date: .now, flow: .heavy, symptoms: ["cramps", "fatigue"])
        let entries = await store.dayEntryCountForTests()
        #expect(entries == 1)
        let flow = await store.flowForDayForTests(date: .now)
        #expect(flow == .heavy)
    }

    @Test("deleteDay removes the DayEntry")
    func deleteDayRemoves() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.logDay(date: .now, flow: .light)
        await store.deleteDay(date: .now)
        let entries = await store.dayEntryCountForTests()
        #expect(entries == 0)
    }

    @Test("nextCalibratedPrediction returns a tighter interval than NIG baseline (regular cycles)")
    func conformalNarrowsInterval() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()
        for i in 0..<4 {
            await store.logDay(
                date: cal.date(byAdding: .day, value: i * 28, to: baseline)!,
                flow: .medium
            )
        }
        let baseline90 = await store.nextPrediction(confidence: 0.90)
        let calibrated = await store.nextCalibratedPrediction(confidence: 0.90)
        guard let baseline90, let calibrated else {
            Issue.record("Expected both predictions to exist")
            return
        }
        let baselineWidth = baseline90.interval.upperBound.timeIntervalSince(baseline90.interval.lowerBound)
        let calibratedWidth = calibrated.interval.upperBound.timeIntervalSince(calibrated.interval.lowerBound)
        // Fehring 90th-percentile residual = 4.571 days → 9.14-day interval.
        // NIG predictor at κ=3 → ~12-day interval. Conformal should be tighter.
        #expect(calibratedWidth < baselineWidth)
        #expect(calibrated.isOngoingIrregularity == false)
    }

    /// Regression for task #114: after `pcosDeclared`, the calibrated
    /// interval must NOT shrink to Fehring's ~9-day window. The Fehring
    /// reference cohort was hyper-regular NFP users; using their residuals
    /// to compress a deliberately-widened PCOS posterior would violate
    /// Pillar 3 ("honest uncertainty over false precision") and
    /// disrupted-cycles.md Category E ("range-only display"). The fix
    /// bypasses the conformal wrapper for ongoing-irregularity users.
    @Test("PCOS-declared user bypasses conformal — calibrated interval equals NIG interval")
    func pcosBypassesConformal() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()
        for i in 0..<4 {
            await store.logDay(
                date: cal.date(byAdding: .day, value: i * 28, to: baseline)!,
                flow: .medium
            )
        }
        // Declare PCOS — this widens β by 2.5× and sets the
        // isOngoingIrregularity flag on the active predictor.
        await store.addEvent(kind: .pcosDeclared, on: .now)

        let base = await store.nextPrediction(confidence: 0.90)
        let calibrated = await store.nextCalibratedPrediction(confidence: 0.90)
        try #require(base != nil)
        try #require(calibrated != nil)

        // The calibrated path must signal the irregularity downstream so
        // the UI can switch to range-only display.
        #expect(calibrated!.isOngoingIrregularity == true)

        // The calibrated interval must be the widened NIG interval, not
        // the Fehring-narrowed one — i.e. identical (to the second) to
        // the uncalibrated base interval.
        let baseLow = base!.interval.lowerBound.timeIntervalSince1970
        let baseHigh = base!.interval.upperBound.timeIntervalSince1970
        let calLow = calibrated!.interval.lowerBound.timeIntervalSince1970
        let calHigh = calibrated!.interval.upperBound.timeIntervalSince1970
        #expect(abs(calLow - baseLow) < 1.0)
        #expect(abs(calHigh - baseHigh) < 1.0)

        // Sanity: a PCOS interval should be wider than the Fehring
        // 9.14-day reference.
        let calWidthDays = (calHigh - calLow) / 86_400
        #expect(calWidthDays > 9.14, "PCOS interval was \(calWidthDays)d — should exceed Fehring 9.14d")
    }
}

/// Task #122 — `CycleStore.hasRecentPregnancyLoss(within:asOf:)` is the
/// loss-aware notification suppression's data source. Pins the window
/// semantics + the EventKind filter so a future refactor that widens
/// the filter (e.g. to all `EventCategory.recoverable`) would
/// visibly regress these tests.
@Suite("CycleStore.hasRecentPregnancyLoss — task #122")
struct HasRecentPregnancyLossTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let cal = Calendar.current

    @Test("Empty store returns false")
    func emptyStoreNoLoss() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let result = await store.hasRecentPregnancyLoss(asOf: .now)
        #expect(result == false)
    }

    @Test("Loss event 14 days ago is in-window")
    func lossInWindow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: now)!
        await store.addEvent(kind: .miscarriageEarly, on: fourteenDaysAgo)
        // Default 28d window.
        let result = await store.hasRecentPregnancyLoss(asOf: now)
        #expect(result == true)
    }

    @Test("Loss event 29 days ago is out-of-window (>28d)")
    func lossOutOfWindow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        let twentyNineDaysAgo = cal.date(byAdding: .day, value: -29, to: now)!
        await store.addEvent(kind: .miscarriageEarly, on: twentyNineDaysAgo)
        let result = await store.hasRecentPregnancyLoss(asOf: now)
        #expect(result == false,
                "Hybrid policy (Q1) — back-dated losses older than the window must NOT retroactively trigger suppression")
    }

    @Test("Non-loss recoverable events do not trigger suppression")
    func nonLossRecoverableEventsIgnored() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        let recently = cal.date(byAdding: .day, value: -5, to: now)!
        // acuteIllnessSevere is Category C (recoverable) but NOT a loss.
        await store.addEvent(kind: .acuteIllnessSevere, on: recently)
        await store.addEvent(kind: .extremeStress, on: recently)
        await store.addEvent(kind: .stoppedHormonalContraception, on: recently)
        let result = await store.hasRecentPregnancyLoss(asOf: now)
        #expect(result == false)
    }

    @Test("Birth (Category C but not loss) does not trigger suppression")
    func birthDoesNotTriggerSuppression() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        let recently = cal.date(byAdding: .day, value: -5, to: now)!
        await store.addEvent(kind: .birthNoBreastfeeding, on: recently)
        let result = await store.hasRecentPregnancyLoss(asOf: now)
        #expect(result == false, "Birth is Category C but not a pregnancy loss — no notification suppression")
    }

    /// Task #136 — standalone `.pregnancyLoss` event must trigger the
    /// same suppression as the medically-specific loss kinds. Pins the
    /// end-to-end path: log `.pregnancyLoss` → store query returns true
    /// within window → NotificationGate would suppress
    /// `.latePeriodCheckIn`.
    @Test("Standalone pregnancyLoss (NEW-J) triggers suppression like specific losses")
    func standalonePregnancyLossTriggersSuppression() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        let recently = cal.date(byAdding: .day, value: -10, to: now)!
        await store.addEvent(kind: .pregnancyLoss, on: recently)
        let result = await store.hasRecentPregnancyLoss(asOf: now)
        #expect(result == true,
                "Standalone neutral loss event must trigger suppression — otherwise users who chose not to sub-categorise get no protection")
    }

    @Test("Multiple losses — any one in-window triggers true")
    func multipleLossesAnyInWindow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        // Old loss (outside window) + recent loss (inside window).
        await store.addEvent(
            kind: .miscarriageEarly,
            on: cal.date(byAdding: .day, value: -200, to: now)!
        )
        await store.addEvent(
            kind: .medicalAbortion,
            on: cal.date(byAdding: .day, value: -10, to: now)!
        )
        let result = await store.hasRecentPregnancyLoss(asOf: now)
        #expect(result == true)
    }

    @Test("Custom window respected (7-day window)")
    func customWindow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        // Loss 10 days ago: outside a 7-day window, inside a 28-day window.
        await store.addEvent(
            kind: .miscarriageLate,
            on: cal.date(byAdding: .day, value: -10, to: now)!
        )
        let sevenDay = await store.hasRecentPregnancyLoss(within: 7 * 86_400, asOf: now)
        let twentyEightDay = await store.hasRecentPregnancyLoss(within: 28 * 86_400, asOf: now)
        #expect(sevenDay == false)
        #expect(twentyEightDay == true)
    }

    @Test("asOf parameter respected — past reference point ignores future events")
    func asOfParameter() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let now = Date.now
        // Loss happens "now".
        await store.addEvent(kind: .surgicalAbortion, on: now)
        // Reference point 60 days BEFORE the loss → loss is in the future
        // relative to reference, must not count.
        let pastReference = cal.date(byAdding: .day, value: -60, to: now)!
        let result = await store.hasRecentPregnancyLoss(asOf: pastReference)
        #expect(result == false)
    }
}

/// Task #79 — `logDayRange(dates:flow:)` is the bulk-backfill API the
/// CalendarSheet range-select feature calls. These tests pin the
/// upsert semantics (preserve note/mood/symptoms on overwrite),
/// the empty-row deletion convention, future-date defence, and the
/// single-rebuild promise.
@Suite("logDayRange — bulk backfill (task #79)")
struct LogDayRangeTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let cal = Calendar.current

    private func days(from start: Date, count: Int) -> [Date] {
        (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start.civilDay()) }
    }

    @Test("Empty input is a no-op")
    func emptyInputIsNoOp() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let result = await store.logDayRange(dates: [], flow: .medium)
        #expect(result == BulkLogResult(written: 0, removed: 0, droppedFuture: 0))
        #expect(await store.cycleCountForTests() == 0)
    }

    @Test("Five fresh days with .medium → 5 inserts + 1 cycle")
    func fiveFreshInserts() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        let range = days(from: start, count: 5)
        let result = await store.logDayRange(dates: range, flow: .medium)
        #expect(result.written == 5)
        #expect(result.removed == 0)
        #expect(result.droppedFuture == 0)
        // Cycle table has one row (5 consecutive bleeding days = 1 cycle).
        #expect(await store.cycleCountForTests() == 1)
    }

    @Test("Overwriting flow preserves note + mood + symptoms")
    func overwritePreservesMetadata() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        // Day 1 has a rich pre-existing entry.
        await store.logDay(
            date: start,
            flow: .light,
            symptoms: ["Krampf", "Müdigkeit"],
            mood: 3,
            note: "Tag 1 fühlt sich okay an"
        )
        // Bulk-apply .heavy to days 1–3.
        let result = await store.logDayRange(dates: days(from: start, count: 3), flow: .heavy)
        #expect(result.written == 3)
        // Day 1's flow upgraded; note/mood/symptoms intact.
        let snap = await store.dayEntry(for: start)
        #expect(snap?.flow == .heavy)
        #expect(snap?.note == "Tag 1 fühlt sich okay an")
        #expect(snap?.mood == 3)
        #expect(snap?.symptoms.contains("Krampf") == true)
        #expect(snap?.symptoms.contains("Müdigkeit") == true)
    }

    @Test("flow=.none on entries with no metadata deletes the row")
    func noneOnEmptyDeletesRow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        let range = days(from: start, count: 3)
        // Seed the rows.
        await store.logDayRange(dates: range, flow: .medium)
        #expect(await store.cycleCountForTests() == 1)
        // Wipe them.
        let wipe = await store.logDayRange(dates: range, flow: .none)
        #expect(wipe.removed == 3)
        #expect(wipe.written == 0)
        // Rows gone → Cycle table empty.
        #expect(await store.cycleCountForTests() == 0)
        #expect(await store.dayEntry(for: start) == nil)
    }

    @Test("flow=.none on entries WITH metadata keeps the row")
    func noneOnEntriesWithMetadataKeepsRow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        await store.logDay(date: start, flow: .medium, symptoms: ["Krampf"], mood: 2, note: "")
        // Bulk .none on this row — the symptom + mood must keep the row alive.
        let result = await store.logDayRange(dates: [start], flow: .none)
        #expect(result.written == 1)
        #expect(result.removed == 0)
        let snap = await store.dayEntry(for: start)
        #expect(snap?.flow == FlowLevel.none)
        #expect(snap?.symptoms.contains("Krampf") == true)
        #expect(snap?.mood == 2)
    }

    @Test("flow=.none on dates with no existing row is a no-op")
    func noneOnNoExistingRowIsNoOp() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        let result = await store.logDayRange(dates: days(from: start, count: 5), flow: .none)
        #expect(result.written == 0)
        #expect(result.removed == 0)
    }

    @Test("Future-dated dates are dropped (defence in depth)")
    func futureDatesDropped() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let future = cal.date(byAdding: .day, value: 14, to: Date.now.civilDay())!
        let result = await store.logDayRange(dates: [future], flow: .medium)
        #expect(result.written == 0)
        #expect(result.droppedFuture == 1)
        #expect(await store.dayEntry(for: future) == nil)
    }

    /// Reviewer N9 — `.spotting` is below the bleeding threshold;
    /// upgrading it to `.light` IS a bleeding-state flip and must
    /// trigger the rebuild that derives a new Cycle row. Pins the
    /// load-bearing transition the gating in `anyBleedingChange`
    /// relies on.
    @Test(".spotting → .light range-write fires rebuild and creates a cycle")
    func spottingToLightFiresRebuild() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        // Pre-seed one spotting day. Below threshold → no Cycle row.
        await store.logDay(date: start, flow: .spotting)
        #expect(await store.cycleCountForTests() == 0)
        // Range-upgrade to .light → crosses the threshold → rebuild.
        let result = await store.logDayRange(dates: [start], flow: .light)
        #expect(result.written == 1)
        // New Cycle row materialised.
        #expect(await store.cycleCountForTests() == 1)
    }

    /// Reviewer B2 — pin that `.none` over a bleeding row with metadata
    /// still triggers the rebuild and shrinks the Cycle table. The
    /// existing "keepsRow" test only checked the row survived; this
    /// catches a future optimisation that might skip the rebuild on
    /// the preserved-row branch.
    @Test(".none over bleeding row with note shrinks the Cycle table")
    func noneOverBleedingRowWithNoteShrinksCycles() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -30 * 86_400).civilDay()
        // Seed one bleeding day (creates a Cycle row) with a note.
        await store.logDay(date: start, flow: .medium, symptoms: [], mood: nil, note: "Krampf")
        #expect(await store.cycleCountForTests() == 1)
        // Bulk-write .none — row stays (note is real journal content)
        // but the bleeding-day set loses this date → Cycle goes away.
        let result = await store.logDayRange(dates: [start], flow: .none)
        #expect(result.written == 1)
        #expect(result.removed == 0)
        #expect(await store.cycleCountForTests() == 0)
        let snap = await store.dayEntry(for: start)
        #expect(snap?.note == "Krampf")
    }

    @Test("Single rebuild — predictor.observedCount reflects post-batch state")
    func singleRebuildPredictorCoherence() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let start = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        // Cycle 1: 5 bleeding days.
        await store.logDayRange(dates: days(from: start, count: 5), flow: .medium)
        // Cycle 2: 5 bleeding days starting 28 days later.
        let cycle2Start = cal.date(byAdding: .day, value: 28, to: start)!
        await store.logDayRange(dates: days(from: cycle2Start, count: 5), flow: .medium)
        // Cycle 3: 5 bleeding days starting 28 days later.
        let cycle3Start = cal.date(byAdding: .day, value: 56, to: start)!
        await store.logDayRange(dates: days(from: cycle3Start, count: 5), flow: .medium)

        let mode = await store.currentMode()
        // 3 cycles → 2 length observations.
        #expect(mode.activePredictor?.observedCount == 2)
        // μ should have moved away from the 28.7 prior toward 28.
        if let mu = mode.activePredictor?.mu {
            #expect(mu < 28.7)
        }
    }
}

/// Task #90 — `homeSnapshot()` is the single atomic accessor the home
/// view uses to read everything it needs. These tests pin its
/// cross-field invariants: the fields must be internally consistent
/// because they're computed against the same actor-locked state. If a
/// future refactor splits the accessor back into multiple awaits, the
/// invariants would only hold by coincidence and the home view's
/// mixed-vintage race re-opens.
@Suite("homeSnapshot — single-hop home view accessor (task #90)")
struct HomeSnapshotTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Empty store: all-null snapshot, mode is active populationPrior")
    func emptyStore() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let snap = await store.homeSnapshot()

        #expect(snap.mode.isActive)
        #expect(snap.pastCycles.isEmpty)
        #expect(snap.currentCycleStart == nil)
        #expect(snap.bleedingDays.isEmpty)
        #expect(snap.observedCycleCount == 0)
        #expect(snap.pausedReason == nil)
        #expect(snap.retiredReason == nil)
        // todayDayInCycle defaults to 1 when there's no cycle anchor
        // (downstream UI treats this as "no current cycle to render").
        #expect(snap.todayDayInCycle == 1)
    }

    @Test("Three logged 28-day cycles: pastCycles populated, predictor learned")
    func threeCycles() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        for offsetDays in [0, 28, 56] {
            await store.logDay(
                date: cal.date(byAdding: .day, value: offsetDays, to: baseline)!,
                flow: .medium
            )
        }
        let snap = await store.homeSnapshot()

        #expect(snap.mode.isActive)
        #expect(snap.pastCycles.count == 2)
        #expect(snap.currentCycleStart != nil)
        #expect(snap.observedCycleCount == 2)
        // Posterior should have moved toward 28 from the 28.7 prior.
        if let active = snap.mode.activePredictor {
            #expect(active.mu < 28.7)
            #expect(active.mu > 28.0)
        } else {
            Issue.record("Expected active predictor")
        }
    }

    @Test("Hysterectomy → retiredReason populated, calibratedPrediction nil")
    func retiredSnapshot() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.startPeriod(on: Date(timeIntervalSinceNow: -28 * 86_400))
        await store.addEvent(kind: .hysterectomy, on: .now)

        let snap = await store.homeSnapshot()
        #expect(snap.mode.isRetired)
        #expect(snap.retiredReason == .hysterectomy)
        #expect(snap.pausedReason == nil)
        #expect(snap.calibratedPrediction == nil)
    }

    @Test("Breastfeeding pause → pausedReason populated, calibratedPrediction nil")
    func pausedSnapshot() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.startPeriod(on: Date(timeIntervalSinceNow: -28 * 86_400))
        await store.addEvent(kind: .birthBreastfeeding, on: .now)

        let snap = await store.homeSnapshot()
        #expect(snap.mode.isPaused)
        #expect(snap.pausedReason == .breastfeeding)
        #expect(snap.retiredReason == nil)
        #expect(snap.calibratedPrediction == nil)
    }

    /// Task #105 — `pastCycles` is sourced from the SwiftData `Cycle`
    /// table, not the predictor's posterior. A paused or retired
    /// predictor still has all of the user's prior cycles available
    /// for the home view's sparkline. This test pins that contract so
    /// a future refactor that gates pastCycles on `mode.isActive`
    /// would visibly regress.
    @Test("pastCycles populated regardless of predictor mode (paused + retired)")
    func pastCyclesSurviveModeTransitions() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()
        // Log 4 cycles 28 days apart → pastCycleSummaries returns 3.
        for offsetDays in [0, 28, 56, 84] {
            await store.logDay(
                date: cal.date(byAdding: .day, value: offsetDays, to: baseline)!,
                flow: .medium
            )
        }
        let active = await store.homeSnapshot()
        #expect(active.pastCycles.count == 3)

        // Pause → sparkline must still see all 3 past cycles.
        await store.addEvent(kind: .birthBreastfeeding, on: .now)
        let paused = await store.homeSnapshot()
        #expect(paused.mode.isPaused)
        #expect(paused.pastCycles.count == 3,
                "Paused predictor must not hide the user's prior cycle history from the sparkline")

        // Retire (Category A trumps pause) → sparkline still shows all 3.
        await store.addEvent(kind: .hysterectomy, on: .now)
        let retired = await store.homeSnapshot()
        #expect(retired.mode.isRetired)
        #expect(retired.pastCycles.count == 3,
                "Retired predictor must not hide the user's prior cycle history from the sparkline")
    }

    /// Cross-field invariant: the snapshot's individual fields must
    /// stay mutually consistent because they're all derived from one
    /// actor-locked state read. This pins the consistency the home
    /// view depends on.
    @Test("Cross-field invariant: pausedReason ⇔ mode.isPaused, same for retired")
    func crossFieldConsistency() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -60 * 86_400).civilDay()

        // Phase 1 — active mode with a known cycle.
        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(
            date: cal.date(byAdding: .day, value: 28, to: baseline)!,
            flow: .medium
        )
        let active = await store.homeSnapshot()
        #expect(active.mode.isActive)
        #expect(active.pausedReason == nil)
        #expect(active.retiredReason == nil)
        // bleedingDays indices must be in 1...todayDayInCycle (or empty).
        if !active.bleedingDays.isEmpty {
            #expect(active.bleedingDays.allSatisfy { $0 >= 1 && $0 <= active.todayDayInCycle })
        }

        // Phase 2 — pause. pausedReason ⇔ mode.isPaused.
        await store.addEvent(kind: .birthBreastfeeding, on: .now)
        let paused = await store.homeSnapshot()
        #expect(paused.mode.isPaused == (paused.pausedReason != nil))
        #expect(paused.mode.isRetired == (paused.retiredReason != nil))

        // Phase 3 — retire (Category A overrides pause). retiredReason ⇔ mode.isRetired.
        await store.addEvent(kind: .hysterectomy, on: .now)
        let retired = await store.homeSnapshot()
        #expect(retired.mode.isRetired)
        #expect(retired.retiredReason != nil)
        #expect(retired.pausedReason == nil)
    }

    /// Concurrent snapshots interleaved with mutators must each remain
    /// internally consistent. Pinned as a *structural* regression net:
    /// the invariant holds today because mutators and the snapshot
    /// share the model actor, so any future non-actor read path would
    /// trip this test. Reviewer follow-up on task #90.
    @Test("Concurrent snapshots interleaved with mutators stay internally consistent")
    func concurrentSnapshotsWithMutatorsRemainConsistent() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        await store.logDay(date: baseline, flow: .medium)

        await withTaskGroup(of: HomeSnapshot?.self) { group in
            // 10 reader tasks.
            for _ in 0..<10 {
                group.addTask { await store.homeSnapshot() }
            }
            // 3 mutator tasks racing the readers — each lands a real
            // mutation (new bleeding day on a distinct offset). The
            // snapshot's cross-field invariants must hold for every
            // returned snapshot regardless of which mutators have or
            // haven't landed at observation time.
            for offset in [28, 56, 84] {
                group.addTask {
                    let date = cal.date(byAdding: .day, value: offset, to: baseline)!
                    await store.logDay(date: date, flow: .medium)
                    return nil
                }
            }
            for await snap in group {
                guard let snap else { continue }
                #expect(snap.mode.isPaused == (snap.pausedReason != nil))
                #expect(snap.mode.isRetired == (snap.retiredReason != nil))
                if snap.currentCycleStart != nil {
                    if !snap.bleedingDays.isEmpty {
                        #expect(snap.bleedingDays.allSatisfy { $0 >= 1 && $0 <= snap.todayDayInCycle })
                    }
                } else {
                    #expect(snap.bleedingDays.isEmpty)
                }
            }
        }
    }

    /// Concurrent snapshots must each return an internally consistent
    /// view — even if a mutator runs between two callers, no single
    /// snapshot quilts across that mutation. Pins task #90's promise.
    @Test("Concurrent homeSnapshot calls each see an internally consistent view")
    func concurrentSnapshotsAreInternallyConsistent() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -60 * 86_400).civilDay()
        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(
            date: cal.date(byAdding: .day, value: 28, to: baseline)!,
            flow: .medium
        )

        // 10 concurrent snapshot reads. Each must individually satisfy
        // the cross-field invariant — pausedReason ⇔ mode.isPaused etc.
        await withTaskGroup(of: HomeSnapshot.self) { group in
            for _ in 0..<10 {
                group.addTask { await store.homeSnapshot() }
            }
            for await snap in group {
                #expect(snap.mode.isPaused == (snap.pausedReason != nil))
                #expect(snap.mode.isRetired == (snap.retiredReason != nil))
                if let _ = snap.currentCycleStart {
                    if !snap.bleedingDays.isEmpty {
                        #expect(snap.bleedingDays.allSatisfy { $0 >= 1 && $0 <= snap.todayDayInCycle })
                    }
                } else {
                    #expect(snap.bleedingDays.isEmpty)
                }
            }
        }
    }
}

/// NEW-171 — per-user mensesEnd floor via `CycleStore.personalMedianMenses()`.
/// The unit math is pinned by `MensesHeuristicTests`; these tests pin the
/// SwiftData integration that derives the median from real Cycle + DayEntry
/// rows. Together they cover the full data path.
@Suite("CycleStore.personalMedianMenses — SwiftData integration (NEW-171)")
struct PersonalMedianMensesTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Log a complete cycle: start period on `start`, then mark `bleedingDays`
    /// days from start as `.medium` flow, optionally close by starting the
    /// next cycle on `nextStart`.
    private func seedCycle(
        store: CycleStore,
        start: Date,
        bleedingDays: Int
    ) async {
        await store.startPeriod(on: start)
        let cal = Calendar.current
        // startPeriod already inserts one .light DayEntry on day 1 (#103).
        // Upgrade to .medium and add the remaining days. This mirrors how
        // a real user logs flow.
        for offset in 0..<bleedingDays {
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            await store.logDay(date: day, flow: .medium)
        }
    }

    @Test("nil with fewer than 3 closed cycles")
    func nilForLowData() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = Date.now.civilDay()
        // Two starts — only one closed cycle, not enough for a median.
        await seedCycle(store: store, start: cal.date(byAdding: .day, value: -60, to: today)!, bleedingDays: 5)
        await seedCycle(store: store, start: cal.date(byAdding: .day, value: -30, to: today)!, bleedingDays: 5)
        let result = await store.personalMedianMenses(limit: 6)
        #expect(result == nil)
    }

    @Test("Three closed cycles with 7 bleeding days each → median 7")
    func medianSevenForLongPeriods() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = Date.now.civilDay()
        // 4 starts → 3 closed cycles, each with 7 bleeding days.
        for offset in stride(from: -120, through: -30, by: 30) {
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            await seedCycle(store: store, start: start, bleedingDays: 7)
        }
        let result = await store.personalMedianMenses(limit: 6)
        #expect(result == 7)
    }

    @Test("Median 4 → nil (defensive: below defaultMenses suggests under-logging)")
    func nilForLowMedian() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = Date.now.civilDay()
        // 4 starts → 3 closed cycles with 4 bleeding days each.
        for offset in stride(from: -120, through: -30, by: 30) {
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            await seedCycle(store: store, start: start, bleedingDays: 4)
        }
        let result = await store.personalMedianMenses(limit: 6)
        #expect(result == nil, "median 4 < defaultMenses 5 → nil per defensive gating")
    }

    @Test("Mixed [5, 7, 6] → median 6")
    func mixedDataMedian() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = Date.now.civilDay()
        let counts = [5, 7, 6]
        for (i, days) in counts.enumerated() {
            let offset = -120 + i * 30
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            await seedCycle(store: store, start: start, bleedingDays: days)
        }
        // Need a 4th start to close the 3rd cycle.
        let closeStart = cal.date(byAdding: .day, value: -120 + 3 * 30, to: today)!
        await seedCycle(store: store, start: closeStart, bleedingDays: 5)
        let result = await store.personalMedianMenses(limit: 6)
        #expect(result == 6, "median([5, 7, 6]) = 6")
    }

    @Test("limit caps the window — only most recent N closed cycles count")
    func limitCapsRecentWindow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = Date.now.civilDay()
        // 5 closed cycles: oldest 3 short (4d), most recent 2 long (7d).
        // Need ≥3 closed cycles for a median (defensive minimum), so smallest
        // meaningful limit is 3.
        //   - limit=3: last 3 closed cycles → counts [4, 7, 7] → median 7
        //   - limit=10: all 5 closed cycles → counts [4, 4, 4, 7, 7] → median 4
        //     → 4 < defaultMenses 5 → returns nil (defensive gate)
        let counts = [4, 4, 4, 7, 7]
        for (i, days) in counts.enumerated() {
            let offset = -180 + i * 30
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            await seedCycle(store: store, start: start, bleedingDays: days)
        }
        let closeStart = cal.date(byAdding: .day, value: -180 + counts.count * 30, to: today)!
        await seedCycle(store: store, start: closeStart, bleedingDays: 5)

        let resultRecent = await store.personalMedianMenses(limit: 3)
        #expect(resultRecent == 7, "last 3 closed → [4, 7, 7] → median 7")

        let resultLargeLimit = await store.personalMedianMenses(limit: 10)
        #expect(resultLargeLimit == nil, "all 5 → median 4 → defensive nil")
    }

    @Test("limit < 3 returns nil even with abundant data (defensive minimum)")
    func limitBelowMinimumReturnsNil() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = Date.now.civilDay()
        // 5 closed cycles all with 7 bleeding days.
        for i in 0..<6 {
            let offset = -150 + i * 30
            let start = cal.date(byAdding: .day, value: offset, to: today)!
            await seedCycle(store: store, start: start, bleedingDays: 7)
        }
        // limit=2 would only let us see 2 closed cycles — below the
        // defensive ≥3 minimum — so we must return nil regardless of data.
        let result = await store.personalMedianMenses(limit: 2)
        #expect(result == nil, "limit=2 < 3 required → nil even with stable 7-d periods")
    }
}

/// Regression for task #118 — the user-reported delete bugs (2026-05-21).
/// Both Path A (flow-downgrade to .none) and Path B (deleteDay/trash button)
/// must remove the day from the bleeding-day set, rebuild the Cycle table,
/// and drop any predictor observation that depended on that day.
@Suite("Delete paths must invalidate cycles + predictor (task #118)")
struct DeletePathTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Set up a 2-cycle history (period 1 at baseline, period 2 at +28d)
    /// → predictor has observedCount = 1 and a 28-day observation in its
    /// posterior. The exact μ shift is what we check before/after.
    private func setupTwoCycles(_ store: CycleStore, baseline: Date) async {
        let cal = Calendar.current
        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(
            date: cal.date(byAdding: .day, value: 28, to: baseline)!,
            flow: .medium
        )
    }

    /// Path A: edit the second period's bleed day to flow=.none via the
    /// production logDay path. The pre-#118 guard exited early because the
    /// new flow wasn't `>= .light`, so the Cycle table and predictor were
    /// left with the stale 28-day observation.
    @Test("Path A: setting a bleeding day's flow to .none rebuilds cycles + predictor")
    func flowDowngradeToNoneRebuildsCycles() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        let secondPeriod = cal.date(byAdding: .day, value: 28, to: baseline)!

        await setupTwoCycles(store, baseline: baseline)
        try #require(await store.cycleCountForTests() == 2)
        try #require(await store.observedCycleCount() == 1)

        // Path A — "I made a mistake, no bleeding that day after all".
        await store.logDay(date: secondPeriod, flow: .none)

        // The cycle table must drop the second cycle (its only bleed day is
        // gone from the bleeding-day set).
        #expect(await store.cycleCountForTests() == 1)
        // The predictor must drop its observation — back to populationPrior
        // territory.
        let mode = await store.currentMode()
        try #require(mode.activePredictor != nil)
        #expect(mode.activePredictor!.observedCount == 0)
        #expect(abs((mode.activePredictor?.mu ?? 0) - 28.7) < 0.01)
    }

    /// Path A variant: downgrade to .spotting (also non-bleeding for cycle
    /// purposes). Same expected outcome.
    @Test("Path A variant: setting flow to .spotting rebuilds the same way")
    func flowDowngradeToSpottingRebuildsCycles() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        let secondPeriod = cal.date(byAdding: .day, value: 28, to: baseline)!

        await setupTwoCycles(store, baseline: baseline)
        await store.logDay(date: secondPeriod, flow: .spotting)

        #expect(await store.cycleCountForTests() == 1)
        #expect(await store.observedCycleCount() == 0)
    }

    /// Path B: tap "Eintrag löschen" → `deleteDay(date:)`. This was already
    /// calling `rebuildCyclesFromDayEntries` before this fix, but until
    /// this test we never asserted the downstream Cycle/predictor
    /// invariants after a delete — so a future regression could silently
    /// strand observations.
    @Test("Path B: deleteDay on a bleeding day removes the cycle + predictor observation")
    func deleteDayInvalidatesCycleAndPredictor() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        let secondPeriod = cal.date(byAdding: .day, value: 28, to: baseline)!

        await setupTwoCycles(store, baseline: baseline)
        try #require(await store.cycleCountForTests() == 2)
        try #require(await store.observedCycleCount() == 1)

        await store.deleteDay(date: secondPeriod)

        #expect(await store.cycleCountForTests() == 1)
        #expect(await store.observedCycleCount() == 0)
        // And the DayEntry itself is gone.
        let snapshot = await store.dayEntry(for: secondPeriod)
        #expect(snapshot == nil)
    }

    /// Edge: a mood-only edit on a dry day must NOT trigger a rebuild — it
    /// would be wasted work AND would mask a future regression of the
    /// bleeding-flip detection. Pinning the optimisation here.
    @Test("Edit of a non-bleeding day's mood only does not change cycle math")
    func nonBleedingMoodEditPreservesCycleMath() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -90 * 86_400).civilDay()
        let dryDay = cal.date(byAdding: .day, value: 10, to: baseline)!

        await setupTwoCycles(store, baseline: baseline)
        let muBefore = await store.currentMode().activePredictor?.mu ?? -1
        let cyclesBefore = await store.cycleCountForTests()

        // Mood/note only on a never-bleeding day.
        await store.logDay(date: dryDay, flow: .none, mood: 2, note: "just felt good")

        #expect(await store.cycleCountForTests() == cyclesBefore)
        let muAfter = await store.currentMode().activePredictor?.mu ?? -2
        #expect(abs(muAfter - muBefore) < 1e-9)
    }
}

/// Regression coverage for the events-list API exposed in task #89.
/// `allEvents()` powers the "Mein Zyklus" sheet; `deleteEvent(persistentID:)`
/// is the swipe-to-delete path. Together they need to satisfy three
/// invariants:
///   1. Newest event first (date-descending sort).
///   2. Unknown `kindRaw` rows are dropped, not surfaced as "Unbekannt".
///   3. Deleting an event un-applies its predictor side effect via the
///      rebuild path (same semantic as `deletePCOSDeclared`).
@Suite("Events list API (task #89)")
struct EventListAPITests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Empty store → allEvents returns []")
    func allEventsEmpty() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let events = await store.allEvents()
        #expect(events.isEmpty)
    }

    @Test("allEvents returns snapshots sorted newest-first")
    func allEventsSortedDescending() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -100 * 86_400).civilDay()

        // Log three events in non-chronological order; the API must
        // still return them newest-first.
        await store.addEvent(
            kind: .majorSurgery,
            on: cal.date(byAdding: .day, value: 30, to: baseline)!
        )
        await store.addEvent(
            kind: .pcosDeclared,
            on: cal.date(byAdding: .day, value: 60, to: baseline)!
        )
        await store.addEvent(
            kind: .significantWeightChange,
            on: cal.date(byAdding: .day, value: 10, to: baseline)!
        )

        let events = await store.allEvents()
        try #require(events.count == 3)
        #expect(events[0].kind == .pcosDeclared)        // day 60 — newest
        #expect(events[1].kind == .majorSurgery)        // day 30
        #expect(events[2].kind == .significantWeightChange)  // day 10 — oldest
    }

    @Test("deleteEvent(persistentID:) removes the row and replays the predictor")
    func deleteEventReplaysPredictor() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()

        // Set up: 3 regular 28d cycles → 2 observations.
        for i in 0..<3 {
            await store.logDay(
                date: cal.date(byAdding: .day, value: i * 28, to: baseline)!,
                flow: .medium
            )
        }
        try #require(await store.observedCycleCount() == 2)
        let muBeforeDeclare = await store.currentMode().activePredictor?.mu ?? -1

        // Add a PCOS event mid-history. With β-widening applied, μ
        // shifts slightly because the rebuild's local-predictor replay
        // observes the same cycles against a widened posterior.
        await store.addEvent(kind: .pcosDeclared, on: .now)
        #expect((await store.allEvents()).count == 1)

        // Now delete it via the new API.
        let events = await store.allEvents()
        try #require(events.count == 1)
        await store.deleteEvent(persistentID: events[0].persistentID)

        // Event is gone.
        #expect((await store.allEvents()).isEmpty)

        // Predictor's μ snaps back to the pre-declaration value because
        // replay no longer encounters the .pcosDeclared event.
        let muAfterDelete = await store.currentMode().activePredictor?.mu ?? -2
        #expect(abs(muAfterDelete - muBeforeDeclare) < 0.01,
                "μ after delete (\(muAfterDelete)) should match pre-declare (\(muBeforeDeclare))")
    }

    @Test("deleteEvent on a stale id is a no-op")
    func deleteEventOnMissingIDNoOp() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        // Add then delete to capture a now-stale persistent ID.
        await store.addEvent(kind: .pcosDeclared, on: .now)
        let events = await store.allEvents()
        try #require(events.count == 1)
        let staleID = events[0].persistentID
        await store.deleteEvent(persistentID: staleID)
        // Calling again with the same (now-missing) id must not crash.
        await store.deleteEvent(persistentID: staleID)
        #expect((await store.allEvents()).isEmpty)
    }
}

// MARK: - Test-only extension

extension CycleStore {
    /// Test-only fetch count of cycles, since `modelContext` is actor-isolated.
    func cycleCountForTests() -> Int {
        let descriptor = FetchDescriptor<Cycle>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func dayEntryCountForTests() -> Int {
        let descriptor = FetchDescriptor<DayEntry>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func eventCountForTests() -> Int {
        let descriptor = FetchDescriptor<CycleEvent>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func flowForDayForTests(date: Date) -> FlowLevel? {
        let dayStart = Calendar.current.startOfDay(for: date)
        let all = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        return all.first(where: { Calendar.current.isDate($0.date, inSameDayAs: dayStart) })?.flow
    }

    func pcosEventCountForTests() -> Int {
        let pcosRaw = EventKind.pcosDeclared.rawValue
        let descriptor = FetchDescriptor<CycleEvent>(
            predicate: #Predicate { $0.kindRaw == pcosRaw }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func firstEventDateForTests() -> Date? {
        let descriptor = FetchDescriptor<CycleEvent>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor))?.first?.date
    }
}

/// Regression for the integration gap closed alongside #117: life events
/// must also be civilDay-normalised on write, so they sort onto the same
/// axis as cycles during `loadAndReplay`'s merge step. Before this fix,
/// an event logged at 14:00 local time (= midday absolute) would land
/// *after* a same-day cycle anchored at UTC midnight, even though the
/// user considered them the same calendar day.
@Suite("addEvent normalises CycleEvent.date to civilDay")
struct AddEventCivilDayTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Event logged at 14:00 local time is stored at civilDay midnight, not the raw instant")
    func addEventStoresCivilDay() async throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let mid = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 5, day: 21, hour: 14, minute: 17
        ).date!

        let store = CycleStore(modelContainer: try makeContainer())
        await store.addEvent(kind: .majorSurgery, on: mid, note: "tz-event")

        let stored = await store.firstEventDateForTests()
        try #require(stored != nil)
        #expect(stored == mid.civilDay())
    }
}

/// Regression for task #100: the UI's phase strip and calendar grid
/// should size against the predictor's posterior μ, not a hardcoded
/// `PhaseBoundaries.defaultCycleLength`. `predictedCycleLength()` is the
/// single source of truth both surfaces read. These tests pin its
/// contract: returns μ when active, falls back to the population default
/// when paused/retired or empty.
@Suite("predictedCycleLength reflects posterior μ (task #100)")
struct PredictedCycleLengthTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Empty store returns the population default cycle length")
    func emptyStoreReturnsDefault() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let len = await store.predictedCycleLength()
        // Active predictor on populationPrior → μ = 28.7.
        #expect(abs(len - 28.7) < 0.01)
    }

    @Test("After observing 31-day cycles, predictedCycleLength tracks μ away from 28.7")
    func reflectsLearnedPosterior() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()
        for i in 0..<4 {
            await store.logDay(
                date: cal.date(byAdding: .day, value: i * 31, to: baseline)!,
                flow: .medium
            )
        }
        let len = await store.predictedCycleLength()
        let mu = await store.currentMode().activePredictor?.mu ?? -1
        // The value the UI consumes must equal the underlying μ exactly —
        // not a separate hardcoded default. After 3 observations of 31 d
        // against μ₀=28.7 κ₀=2, μ has drifted well above 30.
        #expect(abs(len - mu) < 1e-9)
        #expect(len > 30.0, "len = \(len), should be > 30 after three 31d observations")
    }

    @Test("hasPCOSDeclared returns false on a fresh store")
    func hasPCOSDeclaredEmpty() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let result = await store.hasPCOSDeclared()
        #expect(result == false)
    }

    @Test("hasPCOSDeclared returns true after addEvent(.pcosDeclared)")
    func hasPCOSDeclaredAfterAdd() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        await store.addEvent(kind: .pcosDeclared, on: .now)
        let result = await store.hasPCOSDeclared()
        #expect(result == true)
    }

    @Test("hasPCOSDeclared ignores non-PCOS events")
    func hasPCOSDeclaredIgnoresOtherEvents() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        await store.addEvent(kind: .majorSurgery, on: .now)
        let result = await store.hasPCOSDeclared()
        #expect(result == false)
    }

    @Test("deletePCOSDeclared removes the event, predictor un-widens, μ-shift visible")
    func deletePCOSDeclaredUnwidens() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()

        // Log 4 regular 28d cycles → 3 observations against a normal-β
        // prior; μ converges toward 28.
        for i in 0..<4 {
            let d = cal.date(byAdding: .day, value: i * 28, to: baseline)!
            await store.logDay(date: d, flow: .medium)
        }
        let muBeforeIrregular = await store.currentMode().activePredictor?.mu ?? -1

        // Declare irregularity (today). Posterior widens but μ moves
        // only marginally (event is between observations and replay).
        await store.addEvent(kind: .pcosDeclared, on: .now)
        #expect(await store.hasPCOSDeclared() == true)
        #expect(await store.pcosEventCountForTests() == 1)

        // Now undeclare. The replay path removes the widening event and
        // rebuilds the posterior — should land back near the pre-
        // declaration μ (rebuild is deterministic against the same data).
        await store.deletePCOSDeclared()
        #expect(await store.hasPCOSDeclared() == false)
        #expect(await store.pcosEventCountForTests() == 0)

        let muAfterUndeclare = await store.currentMode().activePredictor?.mu ?? -2
        #expect(abs(muAfterUndeclare - muBeforeIrregular) < 0.01)
    }

    @Test("deletePCOSDeclared is a no-op when no PCOS event exists")
    func deletePCOSDeclaredNoOp() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        // No events at all — deletePCOSDeclared should complete without
        // throwing and leave the store empty.
        await store.deletePCOSDeclared()
        #expect(await store.hasPCOSDeclared() == false)
    }

    @Test("Retired predictor falls back to default rather than returning stale μ")
    func retiredFallsBackToDefault() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400).civilDay()
        for i in 0..<3 {
            await store.logDay(
                date: cal.date(byAdding: .day, value: i * 31, to: baseline)!,
                flow: .medium
            )
        }
        // Category A event retires the predictor.
        await store.addEvent(kind: .hysterectomy, on: .now)

        let len = await store.predictedCycleLength()
        // No active predictor → fallback to defaultCycleLength.
        #expect(len == Double(PhaseBoundaries.defaultCycleLength))
    }
}
