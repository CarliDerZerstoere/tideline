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

    @Test("two startPeriod calls 28 days apart feed predictor a 28-day observation")
    func twoStartsObserveLength() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let firstStart = Date(timeIntervalSinceNow: -28 * 86_400)
        await store.startPeriod(on: firstStart)
        await store.startPeriod(on: .now)
        let mode = await store.currentMode()
        guard let p = mode.activePredictor else {
            Issue.record("Expected active predictor")
            return
        }
        #expect(p.observedCount == 1)
        // After observing one 28-day cycle with κ=2 prior and μ=29:
        // μ' = (2·29 + 28) / 3 = 28.667
        #expect(abs(p.mu - 28.667) < 0.01)
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

    @Test("cold-start replay reconstructs predictor state from persisted rows")
    func coldStartReplay() async throws {
        let container = try makeContainer()

        // Phase 1: populate via a store, then discard it.
        do {
            let store = CycleStore(modelContainer: container)
            let baseline = Date(timeIntervalSinceNow: -150 * 86_400)
            await store.startPeriod(on: baseline)
            await store.startPeriod(on: baseline.addingTimeInterval(28 * 86_400))
            await store.startPeriod(on: baseline.addingTimeInterval(57 * 86_400))
            await store.startPeriod(on: baseline.addingTimeInterval(86 * 86_400))
            let muBefore = await store.currentMode().activePredictor?.mu ?? 0
            #expect(muBefore > 28.5 && muBefore < 29.0)
        }

        // Phase 2: fresh store on the same container — should replay history.
        let fresh = CycleStore(modelContainer: container)
        await fresh.loadAndReplay()
        let muAfter = await fresh.currentMode().activePredictor?.mu ?? 0
        #expect(muAfter > 28.5 && muAfter < 29.0)
        let observed = await fresh.currentMode().activePredictor?.observedCount ?? -1
        #expect(observed == 3)  // 4 cycles → 3 cycle lengths
    }

    @Test("Category C event between cycles soft-resets the posterior")
    func eventBetweenCycles() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let baseline = Date(timeIntervalSinceNow: -150 * 86_400)
        await store.startPeriod(on: baseline)
        await store.startPeriod(on: baseline.addingTimeInterval(28 * 86_400))
        await store.startPeriod(on: baseline.addingTimeInterval(56 * 86_400))
        // Miscarriage between cycle 3 and cycle 4 — soft reset preserves μ, resets κ.
        await store.addEvent(
            kind: .miscarriageEarly,
            on: baseline.addingTimeInterval(70 * 86_400)
        )
        let after = await store.currentMode().activePredictor
        #expect(after?.kappa == 2.0)
        #expect(after?.observedCount == 0)
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

    @Test("nextCalibratedPrediction returns a tighter interval than NIG baseline")
    func conformalNarrowsInterval() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let baseline = Date(timeIntervalSinceNow: -120 * 86_400)
        for i in 0..<4 {
            await store.startPeriod(on: baseline.addingTimeInterval(Double(i) * 28 * 86_400))
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

    func flowForDayForTests(date: Date) -> FlowLevel? {
        let dayStart = Calendar.current.startOfDay(for: date)
        let all = (try? modelContext.fetch(FetchDescriptor<DayEntry>())) ?? []
        return all.first(where: { Calendar.current.isDate($0.date, inSameDayAs: dayStart) })?.flow
    }
}
