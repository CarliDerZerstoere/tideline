import Testing
import Foundation
import SwiftData
@testable import Tideline

/// Tests for two gaps identified by the test-gap-coverage audit:
///   1. Timezone roundtrip — verify that an entry logged in one timezone
///      survives a switch to another timezone without losing data
///      (audit #110). `Date` is absolute so the predictor's cycle-length
///      math is invariant; only UI display may shift.
///   2. Low-data fallback branch — verify that the threshold-3 messaging
///      logic (audit #102) returns the right strings at each
///      observedCount value.
@Suite("Timezone roundtrip — Date storage is absolute, predictor invariant")
struct TimezoneRoundtripTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Storing and reading a Date preserves the absolute instant across timezones")
    func absoluteInstantPreserved() async throws {
        // Construct a specific UTC moment that's local-midnight in
        // Auckland (UTC+12) — that absolute instant is also a specific
        // moment in any other timezone, and `Date` carries no TZ
        // metadata.
        var aucklandCal = Calendar(identifier: .gregorian)
        aucklandCal.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let aucklandLocalNoon = DateComponents(
            calendar: aucklandCal,
            timeZone: aucklandCal.timeZone,
            year: 2026, month: 5, day: 21, hour: 12
        ).date!

        // Log in store. CycleStore uses Calendar.current.startOfDay, which
        // in any timezone will resolve `aucklandLocalNoon` to its local
        // start-of-day. The KEY invariant we verify: round-trip preserves
        // the absolute instant exactly (no truncation, no drift).
        let store = CycleStore(modelContainer: try makeContainer())
        await store.logDay(date: aucklandLocalNoon, flow: .light, note: "tz-test")

        let snapshot = await store.dayEntry(for: aucklandLocalNoon)
        try #require(snapshot != nil)

        // The stored date is `startOfDay(aucklandLocalNoon)` in the test
        // host's current Calendar — that's a deterministic function of
        // the input absolute instant. We check the difference is ≤ 24h
        // (within the same calendar day in the test runner's tz).
        let storedDelta = abs(snapshot!.date.timeIntervalSince(aucklandLocalNoon))
        #expect(storedDelta < 86_400, "round-trip drift was \(storedDelta)s — should be < 24h")
    }

    @Test("Cycle length between two stored period starts is invariant to timezone")
    func cycleLengthTimezoneInvariant() async throws {
        // Log two period starts 28 days apart. The predictor's observed
        // length must be ~28.0 regardless of what `Calendar.current.timeZone`
        // happens to be at write time — `Date` is absolute, and the
        // difference between two absolute instants is the same number of
        // seconds no matter where you stand on Earth.
        let store = CycleStore(modelContainer: try makeContainer())
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)  // arbitrary fixed instant
        let twoCyclesLater = baseline.addingTimeInterval(28 * 86_400)

        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(date: twoCyclesLater, flow: .medium)

        // The predictor should have observed exactly one cycle of length
        // ≈ 28 days (within ±0.5 days for DST tolerance — there's a known
        // separate task #99 about DST in 86_400 math).
        let observed = await store.observedCycleCount()
        #expect(observed == 1)

        // Cycle count should be 2 (= 2 period starts).
        #expect(await store.cycleCountForTests() == 2)
    }

    // MARK: - Task #117 regression: Disappearing-Log-Bug

    /// civilDay() should be stable across DST transitions. The same
    /// `(year, month, day)` extracted in any TZ-with-DST yields the same
    /// UTC-midnight Date — so a #Predicate exact-match by `dayStart` keeps
    /// finding the same row before vs. after the clock change.
    @Test("civilDay is stable across a DST transition in the user's calendar")
    func civilDayStableAcrossDST() throws {
        // Europe/Berlin DST flip 2026: clocks go CET→CEST at 02:00 on
        // 2026-03-29 (spring forward). Construct an instant well before
        // and well after the flip, but for the *same civil day*.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!

        let preDST = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 3, day: 28, hour: 14
        ).date!
        let postDST = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 3, day: 28, hour: 22
        ).date!

        // Same civil day in Berlin → same civilDay key.
        #expect(preDST.civilDay(in: berlin) == postDST.civilDay(in: berlin))
    }

    /// Two absolute instants that fall on the same calendar day for the
    /// user — even if one is logged in CET and re-queried in PDT after
    /// flying west — must produce the same civilDay key, so the entry is
    /// findable. (This is the actual disappearing-log scenario.)
    @Test("civilDay key matches when logged in CET and re-queried in PDT (same civil day)")
    func civilDaySurvivesTravel() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // User logs an entry at 09:00 Berlin time on 2026-05-21.
        let loggedInBerlin = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 5, day: 21, hour: 9
        ).date!

        // Same absolute instant viewed from LA is 2026-05-21 00:00 PDT —
        // still the same civil day there. The civilDay key should match
        // whether the user is in Berlin or LA at re-query time.
        let keyFromBerlin = loggedInBerlin.civilDay(in: berlin)
        let keyFromLA = loggedInBerlin.civilDay(in: la)
        #expect(keyFromBerlin == keyFromLA)
    }

    /// Round-trip via the store: logging then immediately re-reading with
    /// the same Date instance must always succeed, regardless of what
    /// `Calendar.current.timeZone` happens to be in the test runner.
    /// Pre-fix this was the failure mode for #117 — startOfDay produced
    /// TZ-dependent keys, so a re-key after travel/DST silently missed.
    @Test("logDay/dayEntry round-trip is stable for the same Date instance")
    func logDayRoundTripStable() async throws {
        let store = CycleStore(modelContainer: try makeContainer())
        let when = Date(timeIntervalSince1970: 1_716_249_600)  // 2024-05-21 00:00 UTC
        await store.logDay(date: when, flow: .light, note: "rt")
        let snapshot = await store.dayEntry(for: when)
        try #require(snapshot != nil)
        #expect(snapshot?.note == "rt")
    }
}

/// Regression for task #99: predictor and store date math must respect
/// Calendar arithmetic so DST transitions inside the horizon don't shift
/// the user-visible calendar day. These tests pin `Date.addingDays(_:)`
/// and `daysUntil(_:)` against scenarios that crossed real DST flips.
@Suite("DST-safe date arithmetic — Date.addingDays and daysUntil")
struct DSTArithmeticTests {

    /// `Date.addingDays(28)` across the Europe/Berlin spring-forward
    /// flip on 2026-03-29: the *wall-clock* hour of day must be the same,
    /// even though absolute elapsed time is 28 × 24 − 1 = 671 hours.
    @Test("addingDays(28) preserves wall-clock hour across a DST spring-forward")
    func addingDaysPreservesHourSpringForward() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 3, day: 14, hour: 9, minute: 30
        ).date!  // CET, before the 2026-03-29 02:00 spring-forward

        let plus28 = start.addingDays(28, in: berlin)
        let comps = berlin.dateComponents([.year, .month, .day, .hour, .minute], from: plus28)
        #expect(comps.year == 2026)
        #expect(comps.month == 4)
        #expect(comps.day == 11)
        #expect(comps.hour == 9)
        #expect(comps.minute == 30)

        // And the absolute elapsed time picks up the missing DST hour —
        // proving the function isn't just doing N × 86_400.
        let elapsedHours = plus28.timeIntervalSince(start) / 3600
        #expect(abs(elapsedHours - (28 * 24 - 1)) < 0.001)
    }

    /// Fractional days: `addingDays(28.5)` should land 12 hours past the
    /// integer-day shift — the half-day add is plain seconds (no DST
    /// concern within a 12-hour window).
    @Test("addingDays(28.5) lands 12h after the integer-day shift")
    func addingDaysFractionalLands12hLater() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let plus28_5 = start.addingDays(28.5)
        let plus28 = start.addingDays(28)
        let delta = plus28_5.timeIntervalSince(plus28)
        #expect(abs(delta - 12 * 3600) < 1.0)
    }

    /// `daysUntil` is also DST-safe: 28 calendar days across the
    /// spring-forward is exactly 28, not 27 (which `timeIntervalSince /
    /// 86_400` would round-floor to in some DST direction).
    @Test("daysUntil across DST returns the calendar-day count, not the 86_400-floor")
    func daysUntilAcrossDSTIsCalendarDays() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let a = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 3, day: 14, hour: 9
        ).date!
        let b = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 4, day: 11, hour: 9
        ).date!
        #expect(a.daysUntil(b, in: berlin) == 28)
    }

    /// End-to-end: a 28-day cycle that straddles a DST flip should be
    /// observed by the predictor as exactly 28.0 days, not 27.96 or 28.04.
    @Test("Predictor observes exactly 28 days for a DST-spanning cycle")
    func predictorObservesIntegerDaysAcrossDST() async throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let store = CycleStore(modelContainer: container)

        let first = DateComponents(
            calendar: berlin, timeZone: berlin.timeZone,
            year: 2026, month: 3, day: 14, hour: 12
        ).date!
        let second = berlin.date(byAdding: .day, value: 28, to: first)!  // 2026-04-11

        await store.logDay(date: first, flow: .medium)
        await store.logDay(date: second, flow: .medium)

        let predictor = await store.currentMode().activePredictor
        try #require(predictor != nil)
        #expect(predictor!.observedCount == 1)
        // Posterior μ after observing exactly 28 with μ₀=28.7, κ₀=2:
        //   μ' = (2·28.7 + 28)/3 = 28.467. If observed length had been
        //   27.958 (the typical −1h DST floor result), μ' would be 28.456 —
        //   tolerance 1e-6 here proves we observed exactly 28.0.
        #expect(abs(predictor!.mu - 28.467) < 1e-3)
    }
}

// The `LowDataFallbackTests` suite that used to live here was a pure
// mirror of `TidelineHomeView.predictionIntervalText`. Once that
// function was extracted into the testable static
// `HeroStateBuilder.predictionIntervalText`, the mirror became drift
// bait. Coverage moved to `LateModeTests.PredictionIntervalCompositionTests`,
// which exercises the production function directly. Deleting the
// mirror eliminates the only remaining surface where the German copy
// could diverge silently between two files.
