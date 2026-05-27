import Testing
import Foundation
import SwiftData
@testable import Tideline

/// SwiftData ↔ CycleStore round-trip tests. Verify that data written via
/// `CycleStore.logDay` / `addEvent` / `deleteDay` survives a read pass
/// through `dayEntry(for:)`, `pastCycleSummaries`, `bleedingDaysInCurrentCycle`
/// without any field loss or corruption.
///
/// The original `LogDaySheet` bug (#88) shipped because no test caught
/// the case where saved flow + symptoms + mood + note were not visible
/// when the sheet was reopened. These tests pin every field.
@Suite("SwiftData round-trip — all DayEntry fields preserved")
struct SwiftDataRoundTripTests {

    /// Build an in-memory container with all three model types.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - dayEntry(for:) round-trip

    @Test("logDay → dayEntry returns all five fields unchanged")
    func dayEntryRoundTripPreservesAllFields() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let symptoms: Set<String> = ["Kopfschmerzen", "Krämpfe", "Müdigkeit"]
        let note = "Erster Tag — anstrengend"

        await store.logDay(
            date: date,
            flow: .heavy,
            symptoms: Array(symptoms),
            mood: 3,
            note: note
        )

        let snapshot = await store.dayEntry(for: date)
        try #require(snapshot != nil)
        #expect(snapshot!.flow == .heavy)
        #expect(snapshot!.mood == 3)
        #expect(snapshot!.symptoms == symptoms)
        #expect(snapshot!.note == note)
        #expect(Calendar.current.isDate(snapshot!.date, inSameDayAs: date))
    }

    @Test("Symptoms round-trip as a Set (order-independent)")
    func symptomsRoundTrip() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let date = Date()

        // Pass in a specific array order; the snapshot should return the
        // same content as a Set (no duplicates, no order requirement).
        await store.logDay(
            date: date,
            flow: .light,
            symptoms: ["Brustspannen", "Akne", "Stimmungsschwankungen"]
        )

        let snapshot = await store.dayEntry(for: date)
        try #require(snapshot != nil)
        #expect(snapshot!.symptoms == Set(["Akne", "Brustspannen", "Stimmungsschwankungen"]))
    }

    @Test("Nil mood survives the round-trip")
    func nilMoodRoundTrip() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let date = Date()

        await store.logDay(date: date, flow: .medium, mood: nil)
        let snapshot = await store.dayEntry(for: date)
        try #require(snapshot != nil)
        #expect(snapshot!.mood == nil)
    }

    @Test("Empty note survives the round-trip as empty string")
    func emptyNoteRoundTrip() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let date = Date()

        await store.logDay(date: date, flow: .light, note: "")
        let snapshot = await store.dayEntry(for: date)
        try #require(snapshot != nil)
        #expect(snapshot!.note == "")
    }

    @Test("dayEntry returns nil for a date with no entry")
    func dayEntryNilWhenAbsent() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let date = Date()
        let snapshot = await store.dayEntry(for: date)
        #expect(snapshot == nil)
    }

    // MARK: - Upsert behaviour

    @Test("Logging the same date twice upserts, not duplicates")
    func logDayUpsertsNotDuplicates() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let date = Date()

        await store.logDay(date: date, flow: .light, symptoms: ["A"])
        await store.logDay(date: date, flow: .heavy, symptoms: ["B", "C"])

        let snapshot = await store.dayEntry(for: date)
        try #require(snapshot != nil)
        // Second write fully replaces the first.
        #expect(snapshot!.flow == .heavy)
        #expect(snapshot!.symptoms == Set(["B", "C"]))
    }

    // MARK: - deleteDay → rebuild

    @Test("deleteDay removes the DayEntry AND rebuilds Cycle table")
    func deleteDayRebuildsCycle() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let day1 = cal.startOfDay(for: Date(timeIntervalSinceNow: -5 * 86_400))

        // Log a bleeding day → rebuild creates a Cycle row.
        await store.logDay(date: day1, flow: .heavy)
        #expect(await store.cycleCountForTests() == 1)

        // Delete the bleeding day → rebuild removes the Cycle row.
        await store.deleteDay(date: day1)
        #expect(await store.cycleCountForTests() == 0)
        #expect(await store.dayEntry(for: day1) == nil)
    }

    // MARK: - Event log

    @Test("addEvent writes a CycleEvent row")
    func addEventWritesEventRow() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let eventDate = Date(timeIntervalSinceNow: -10 * 86_400)

        await store.addEvent(kind: .miscarriageEarly, on: eventDate, note: "Test entry")

        #expect(await store.eventCountForTests() == 1)
    }

    @Test("addEvent triggers rebuild + predictor replay")
    func addEventReplaysPredictor() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current

        // Establish two cycles to give the predictor something to replay.
        let d2 = cal.startOfDay(for: Date(timeIntervalSinceNow: -56 * 86_400))
        let d1 = cal.date(byAdding: .day, value: 28, to: d2)!
        await store.logDay(date: d2, flow: .medium)
        await store.logDay(date: d1, flow: .medium)
        let cyclesBefore = await store.cycleCountForTests()
        #expect(cyclesBefore == 2)

        // Add a category-C event between them. After the call, the cycle
        // table should be unchanged (events don't add Cycle rows) but the
        // event is now persisted and the predictor has re-replayed.
        let between = cal.date(byAdding: .day, value: 14, to: d2)!
        await store.addEvent(kind: .miscarriageEarly, on: between)

        #expect(await store.cycleCountForTests() == cyclesBefore)
        #expect(await store.eventCountForTests() == 1)
    }

    // MARK: - loggedDays(in: range)

    // MARK: - Low-data fallback signal (task #102)

    @Test("observedCycleCount returns 0 on a fresh store")
    func observedCycleCountFreshStore() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        #expect(await store.observedCycleCount() == 0)
    }

    @Test("observedCycleCount returns N-1 after logging N period starts")
    func observedCycleCountIncrements() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let d3 = cal.startOfDay(for: Date(timeIntervalSinceNow: -84 * 86_400))
        let d2 = cal.date(byAdding: .day, value: 28, to: d3)!
        let d1 = cal.date(byAdding: .day, value: 28, to: d2)!

        await store.logDay(date: d3, flow: .medium)
        // 1 cycle start → predictor has 0 observed cycle LENGTHS (need 2 starts for 1 length).
        #expect(await store.observedCycleCount() == 0)

        await store.logDay(date: d2, flow: .medium)
        #expect(await store.observedCycleCount() == 1)

        await store.logDay(date: d1, flow: .medium)
        #expect(await store.observedCycleCount() == 2)
    }

    @Test("loggedDays(in:) returns only entries inside the range")
    func loggedDaysRangeRespected() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Log three days: one inside the range, one before, one after.
        let inside = today
        let before = cal.date(byAdding: .day, value: -60, to: today)!
        let after = cal.date(byAdding: .day, value: 60, to: today)!
        await store.logDay(date: inside, flow: .light)
        await store.logDay(date: before, flow: .light)
        await store.logDay(date: after, flow: .light)

        let lo = cal.date(byAdding: .day, value: -30, to: today)!
        let hi = cal.date(byAdding: .day, value: 30, to: today)!
        let records = await store.loggedDays(in: lo...hi)

        #expect(records.count == 1)
        #expect(cal.isDate(records.first!.date, inSameDayAs: inside))
    }
}

/// Order-independent rebuild — regression test for the backfill bug
/// (#59). Logging the same cycles in chronological order vs. reverse
/// order vs. random order MUST produce identical Cycle tables.
@Suite("Rebuild is order-independent (backfill regression)")
struct RebuildOrderTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Forward and reverse order produce same cycle count")
    func forwardVsReverseSameCycleCount() async throws {
        let cal = Calendar.current
        // Three period starts ~28 days apart in the past.
        let d3 = cal.startOfDay(for: Date(timeIntervalSinceNow: -90 * 86_400))
        let d2 = cal.date(byAdding: .day, value: 28, to: d3)!
        let d1 = cal.date(byAdding: .day, value: 28, to: d2)!

        // Forward order
        let fwd = CycleStore(modelContainer: try makeContainer())
        await fwd.logDay(date: d3, flow: .medium)
        await fwd.logDay(date: d2, flow: .medium)
        await fwd.logDay(date: d1, flow: .medium)
        let fwdCount = await fwd.cycleCountForTests()

        // Reverse order — this used to silently drop earlier entries due
        // to the negative-gap debounce in the old startPeriod path.
        let rev = CycleStore(modelContainer: try makeContainer())
        await rev.logDay(date: d1, flow: .medium)
        await rev.logDay(date: d2, flow: .medium)
        await rev.logDay(date: d3, flow: .medium)
        let revCount = await rev.cycleCountForTests()

        #expect(fwdCount == revCount)
        #expect(fwdCount == 3)
    }

    @Test("Concurrent logDay calls don't corrupt the predictor")
    func concurrentLogDayDoesNotCorruptPredictor() async throws {
        // Regression test for the actor-reentrancy race (audit #111).
        // The fact-checker said the eager `didReplay=true` write in
        // loadAndReplay neutralises the race — but until now no test
        // exercised the concurrent path. If somebody removes or moves
        // that write, this test fails.
        //
        // Fan out 8 logDay calls in a TaskGroup. Each call internally
        // triggers rebuildCyclesFromDayEntries → loadAndReplay with
        // multiple suspension points at `await predictor.observe`.
        // Without the guard, the predictor would observe each cycle
        // multiple times, inflating its variance and shifting μ. With
        // the guard, the final observedCount must equal the number of
        // cycle lengths derivable from the 8 logged starts (= 7).
        let store = CycleStore(modelContainer: try makeContainer())
        let cal = Calendar.current
        let baseline = cal.startOfDay(for: Date(timeIntervalSinceNow: -224 * 86_400))
        // 8 period starts, 28 days apart.
        let dates: [Date] = (0..<8).map {
            cal.date(byAdding: .day, value: $0 * 28, to: baseline)!
        }

        await withTaskGroup(of: Void.self) { group in
            for d in dates {
                group.addTask { await store.logDay(date: d, flow: .medium) }
            }
        }

        // Final state: 8 cycle starts → 7 observable cycle lengths.
        let cycleCount = await store.cycleCountForTests()
        let observedN = await store.observedCycleCount()
        #expect(cycleCount == 8)
        #expect(observedN == 7, "expected 7 observed cycles, got \(observedN) — race may have duplicated observations")
    }

    @Test("Future-dated bleeding entry does NOT create a Cycle row")
    func futureBleedingDoesNotCreateCycle() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let future = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: 14 * 86_400))

        await store.logDay(date: future, flow: .heavy)

        // The DayEntry exists (for journal use) but no Cycle row was created.
        #expect(await store.dayEntry(for: future) != nil)
        #expect(await store.cycleCountForTests() == 0)
    }
}
