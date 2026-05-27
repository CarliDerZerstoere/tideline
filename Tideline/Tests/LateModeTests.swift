import Testing
import Foundation
import SwiftData
@testable import Tideline

// MARK: - LateMilestoneBucket — boundaries + verbatim copy pinning

@Suite("LateMilestoneBucket — boundaries (task #78)")
struct LateMilestoneBucketTests {

    @Test("daysLate ≤ 0 returns nil")
    func nonPositiveReturnsNil() {
        #expect(LateMilestone.bucket(daysLate: 0) == nil)
        #expect(LateMilestone.bucket(daysLate: -1) == nil)
        #expect(LateMilestone.bucket(daysLate: -100) == nil)
    }

    @Test("1–4 days → slightlyLate")
    func slightlyLateRange() {
        #expect(LateMilestone.bucket(daysLate: 1) == .slightlyLate)
        #expect(LateMilestone.bucket(daysLate: 2) == .slightlyLate)
        #expect(LateMilestone.bucket(daysLate: 4) == .slightlyLate)
    }

    @Test("5–9 days → noticeablyLate")
    func noticeablyLateRange() {
        #expect(LateMilestone.bucket(daysLate: 5) == .noticeablyLate)
        #expect(LateMilestone.bucket(daysLate: 9) == .noticeablyLate)
    }

    @Test("10–14 days → pregnancyTestWindow")
    func pregnancyTestWindowRange() {
        #expect(LateMilestone.bucket(daysLate: 10) == .pregnancyTestWindow)
        #expect(LateMilestone.bucket(daysLate: 12) == .pregnancyTestWindow)
        #expect(LateMilestone.bucket(daysLate: 14) == .pregnancyTestWindow)
    }

    @Test("15–29 days → persistentlyLate")
    func persistentlyLateRange() {
        #expect(LateMilestone.bucket(daysLate: 15) == .persistentlyLate)
        #expect(LateMilestone.bucket(daysLate: 29) == .persistentlyLate)
    }

    @Test("30+ days → longOverdue")
    func longOverdueRange() {
        #expect(LateMilestone.bucket(daysLate: 30) == .longOverdue)
        #expect(LateMilestone.bucket(daysLate: 100) == .longOverdue)
        #expect(LateMilestone.bucket(daysLate: 365) == .longOverdue)
    }
}

/// Pins the EU-MDR-reviewed copy lifted verbatim from
/// `docs/design/late-mode-implementation.md`. If anyone edits the copy
/// in one place without updating the other, these tests fail loudly.
/// **Do not edit the expected strings to make a failing test pass —
/// update the design doc and the implementation together.**
@Suite("LateMilestoneBucket — verbatim copy pin")
struct LateMilestoneCopyTests {

    @Test("Headlines match the design doc table")
    func headlinesPin() {
        #expect(LateMilestoneBucket.slightlyLate.headline == "Etwas später als erwartet")
        #expect(LateMilestoneBucket.noticeablyLate.headline == "Spürbar später")
        #expect(LateMilestoneBucket.pregnancyTestWindow.headline == "Information zum Zeitpunkt")
        #expect(LateMilestoneBucket.persistentlyLate.headline == "Weiterhin später als erwartet")
        #expect(LateMilestoneBucket.longOverdue.headline == "Lange überfällig")
    }

    @Test("slightlyLate body — singular form for 1 day")
    func slightlyLateSingular() {
        let body = LateMilestoneBucket.slightlyLate.body(daysLate: 1)
        // Non-numeric "ein paar Tage in jede Richtung" replaced the
        // earlier "±5 Tage" — AWHS within-person SD is ~3.79–5.33d for
        // adults but rises to 11.19d at 50+, so a hard ±5 understates
        // the perimenopausal extreme. Fact-check 2026-05-21.
        #expect(body == "Deine Periode liegt 1 Tag über der erwarteten Zeit. Bei den meisten Personen schwankt ein Zyklus um ein paar Tage in jede Richtung. Beobachte ruhig weiter.")
    }

    @Test("slightlyLate body — plural form for N>1 days")
    func slightlyLatePlural() {
        let body = LateMilestoneBucket.slightlyLate.body(daysLate: 3)
        #expect(body == "Deine Periode liegt 3 Tage über der erwarteten Zeit. Bei den meisten Personen schwankt ein Zyklus um ein paar Tage in jede Richtung. Beobachte ruhig weiter.")
    }

    @Test("noticeablyLate body — three causes, no Schlafmangel")
    func noticeablyLateBody() {
        let body = LateMilestoneBucket.noticeablyLate.body(daysLate: 7)
        // "Schlafmangel" dropped — published evidence is on shift work
        // and circadian disruption, not acute sleep loss. Stress, Reise,
        // and Krankheit all have at least plausible support. Fact-check
        // 2026-05-21.
        #expect(body == "7 Tage über der Erwartung. Stress, Reise oder Krankheit können einen Zyklus verschieben. Du kannst ein Ereignis loggen, falls dir eines davon einfällt.")
    }

    @Test("pregnancyTest body — test-reliability framing")
    func pregnancyTestBody() {
        let body = LateMilestoneBucket.pregnancyTestWindow.body(daysLate: 12)
        // Reworded from "viele Personen machen um diese Zeit…" (an
        // uncited population-behaviour claim) to "ein Schwangerschaftstest
        // ist ab jetzt zuverlässig" — anchored in Cole 2004 (PMID
        // 14749643): home tests are >97% sensitive ~1 week past the
        // expected period. "als Orientierung, nicht als Empfehlung"
        // suffix preserved as the regulatory hairline. Fact-check
        // 2026-05-21.
        #expect(body == "Tag 12 über der Erwartung. Ein Schwangerschaftstest ist ab jetzt zuverlässig — als Orientierung, nicht als Empfehlung.")
    }

    @Test("longOverdue body — non-directive doctor-referral phrasing")
    func longOverdueBody() {
        let body = LateMilestoneBucket.longOverdue.body(daysLate: 35)
        // Softened from "ist sinnvoll" → "ist jederzeit möglich" because
        // ACOG/ASRM define secondary amenorrhea at ≥90 days, not 30.
        // At 30+ we surface the option without recommending it; the
        // app stays on the wellness side. Fact-check 2026-05-21.
        #expect(body == "Tag 35 über der Erwartung. Wenn du dir unsicher bist, ist eine ärztliche Einschätzung jederzeit möglich — Tideline diagnostiziert nicht. Du kannst die Vorhersage zurücksetzen, wenn dein Rhythmus sich neu sortiert.")
    }
}

// MARK: - HeroStateBuilder.predictionIntervalText — composition pipeline

/// Table-driven coverage for the four-flag composition rules. The
/// precedence is documented in `HeroStateBuilder.swift`. Any change to
/// the order (low-data first, then late-headline, then suffixes) must
/// update both the docstring and these tests.
@Suite("predictionIntervalText composition (tasks #77/#78/#101/#102)")
struct PredictionIntervalCompositionTests {

    /// Helper to construct a fixed `Beginnt etwa zwischen …` headline reliably.
    /// Uses the same formatter as production — `.day().month()` — to
    /// avoid asserting on the runtime locale's day/month preference.
    ///
    /// Wording updated 2026-05-25 in lock-step with HeroStateBuilder
    /// Option-A fix (was "Periode etwa <lo> – <hi>", which read as a
    /// duration; the interval is actually the credible interval on the
    /// START date). New phrasing makes the start-window semantic
    /// explicit so the hero stops contradicting the calendar's
    /// point-estimate menses rings.
    private func sampleInterval() -> ClosedRange<Date> {
        // Build "May 26 – June 1" in UTC so the test is locale/TZ stable
        // up to the day-of-month rendering itself.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let low = DateComponents(calendar: cal, timeZone: cal.timeZone, year: 2026, month: 5, day: 26).date!
        let high = DateComponents(calendar: cal, timeZone: cal.timeZone, year: 2026, month: 6, day: 1).date!
        return low...high
    }

    private func expectedBaseHeadline() -> String {
        let iv = sampleInterval()
        let lo = iv.lowerBound.formatted(.dateTime.day().month())
        let hi = iv.upperBound.formatted(.dateTime.day().month())
        return "Beginnt etwa zwischen \(lo) und \(hi)"
    }

    @Test("Low-data fallback wins when observedCount < 3, regardless of other flags")
    func lowDataDominates() {
        // observedCount=0 → 3 cycles remaining
        let t0 = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 0,
            isWidenedRecovery: true, isOngoingIrregularity: true, isWideLate: true
        )
        #expect(t0 == "Wir lernen deinen Rhythmus kennen — erste Schätzung nach 3 weiteren Zyklen.")

        let t1 = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 1,
            isWidenedRecovery: false, isOngoingIrregularity: true, isWideLate: false
        )
        #expect(t1 == "Wir lernen deinen Rhythmus kennen — erste Schätzung nach 2 weiteren Zyklen.")

        let t2 = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 2,
            isWidenedRecovery: false, isOngoingIrregularity: false, isWideLate: false
        )
        #expect(t2 == "Wir lernen deinen Rhythmus kennen — erste Schätzung nach 1 weiteren Zyklus.")
    }

    @Test("No flags ≥3 observations → plain date range")
    func plainInterval() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 5,
            isWidenedRecovery: false, isOngoingIrregularity: false, isWideLate: false
        )
        #expect(text == expectedBaseHeadline())
    }

    @Test("Ongoing-irregularity appends PCOS disclaimer")
    func pcosAppends() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 5,
            isWidenedRecovery: false, isOngoingIrregularity: true, isWideLate: false
        )
        #expect(text == expectedBaseHeadline() + " · Deine Zyklen sind natürlich variabel.")
    }

    @Test("isWideLate replaces headline with 'Keine klare Schätzung'")
    func wideLateHeadline() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 5,
            isWidenedRecovery: false, isOngoingIrregularity: false, isWideLate: true
        )
        #expect(text == "Keine klare Schätzung")
    }

    @Test("isWideLate + ongoing-irregularity → 'Keine klare Schätzung · Deine Zyklen sind…'")
    func wideLatePlusPCOS() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 5,
            isWidenedRecovery: false, isOngoingIrregularity: true, isWideLate: true
        )
        #expect(text == "Keine klare Schätzung · Deine Zyklen sind natürlich variabel.")
    }

    @Test("interval == nil and not late returns nil")
    func nilIntervalReturnsNil() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: nil, observedCount: 5,
            isWidenedRecovery: false, isOngoingIrregularity: false, isWideLate: false
        )
        #expect(text == nil)
    }

    /// The widened-recovery suffix is currently unreachable in production
    /// (recovery window ⇔ observedCount < 3, where low-data fallback
    /// wins first). This test pins the suffix string against drift in
    /// case the coupling is later loosened.
    @Test("Widened-recovery suffix at observedCount≥3 (currently unreachable in production)")
    func widenedRecoverySuffix() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 5,
            isWidenedRecovery: true, isOngoingIrregularity: false, isWideLate: false
        )
        #expect(text == expectedBaseHeadline() + " · Die Schätzung wird mit neuen Zyklen schärfer.")
    }

    @Test("Both suffixes append in stable order: recovery then PCOS")
    func bothSuffixesOrder() {
        let text = HeroStateBuilder.predictionIntervalText(
            interval: sampleInterval(), observedCount: 5,
            isWidenedRecovery: true, isOngoingIrregularity: true, isWideLate: false
        )
        #expect(text == expectedBaseHeadline()
                + " · Die Schätzung wird mit neuen Zyklen schärfer."
                + " · Deine Zyklen sind natürlich variabel.")
    }
}

// MARK: - HeroStateBuilder.deriveHeroState — state machine

@Suite("deriveHeroState — state machine (tasks #77/#78)")
struct HeroStateMachineTests {

    private func makeBoundaries(cycleLength: Int = 29, mensesEnd: Int = 5) -> PhaseBoundaries {
        PhaseBoundaries.from(cycleLength: cycleLength, mensesEnd: mensesEnd)
    }

    /// Compact constructor for `HeroInputs` with defaults that match the
    /// "common, uneventful, active mode" case. Tests override only the
    /// fields they care about.
    private func inputs(
        mode: PredictorMode = .active(.populationPrior),
        lastStart: Date? = .now,
        todayDayInCycle: Int = 10,
        cycleBoundaries: PhaseBoundaries? = nil,
        observedCount: Int = 5,
        calibratedInterval: ClosedRange<Date>? = nil,
        conditionalInterval: ClosedRange<Date>? = nil,
        conditionalWidthDays: Double? = nil,
        isWidenedRecovery: Bool = false,
        isOngoingIrregularity: Bool = false,
        pausedLabel: String? = nil,
        retiredLabel: String? = nil
    ) -> HeroInputs {
        HeroInputs(
            mode: mode,
            lastStart: lastStart,
            todayDayInCycle: todayDayInCycle,
            cycleBoundaries: cycleBoundaries ?? makeBoundaries(),
            observedCount: observedCount,
            calibratedInterval: calibratedInterval,
            conditionalInterval: conditionalInterval,
            conditionalWidthDays: conditionalWidthDays,
            isWidenedRecovery: isWidenedRecovery,
            isOngoingIrregularity: isOngoingIrregularity,
            pausedLabel: pausedLabel,
            retiredLabel: retiredLabel
        )
    }

    @Test("paused mode wins over everything else")
    func pausedDominates() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            mode: .paused(archived: .populationPrior, since: .now, reason: .breastfeeding),
            todayDayInCycle: 50, observedCount: 10,
            isOngoingIrregularity: true,
            pausedLabel: "Stillzeit"
        ))
        #expect(state == .paused(reasonLabel: "Stillzeit"))
    }

    @Test("retired mode wins over everything else")
    func retiredDominates() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            mode: .retired(since: .now, reason: .hysterectomy),
            todayDayInCycle: 50, observedCount: 10,
            isOngoingIrregularity: true,
            retiredLabel: "Hysterektomie"
        ))
        #expect(state == .retired(reasonLabel: "Hysterektomie"))
    }

    @Test("nil lastStart yields .empty even with an active predictor")
    func nilLastStartYieldsEmpty() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            lastStart: nil, todayDayInCycle: 1, observedCount: 0
        ))
        #expect(state == .empty)
    }

    @Test("Day 29 of 29 is active, not late (boundary case)")
    func dayEqualsCycleLengthStillActive() {
        let state = HeroStateBuilder.deriveHeroState(inputs(todayDayInCycle: 29))
        if case .active = state { } else {
            Issue.record("Expected .active at todayDayInCycle == cycleLength, got \(state)")
        }
    }

    @Test("Day 30 of 29 transitions to late mode")
    func dayAboveCycleLengthTransitionsToLate() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            todayDayInCycle: 30, conditionalWidthDays: 8.0
        ))
        guard case .late(let model) = state else {
            Issue.record("Expected .late at todayDayInCycle > cycleLength, got \(state)")
            return
        }
        #expect(model.daysLate == 1)
        #expect(model.todayDay == 30)
        #expect(model.cycleLength == 29)
        #expect(model.isWide == false)  // 8d < 14d threshold
    }

    @Test("Late mode with conditionalWidth > 14 days flips isWide=true")
    func wideConditionalFlipsIsWide() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            todayDayInCycle: 40, conditionalWidthDays: 18.0,
            isOngoingIrregularity: true
        ))
        guard case .late(let model) = state else {
            Issue.record("Expected .late")
            return
        }
        #expect(model.isWide == true)
        #expect(model.intervalText == "Keine klare Schätzung · Deine Zyklen sind natürlich variabel.")
    }

    @Test("Late mode with nil conditionalWidth treats interval as wide")
    func nilWidthTreatedAsWide() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            todayDayInCycle: 35, conditionalWidthDays: nil
        ))
        guard case .late(let model) = state else {
            Issue.record("Expected .late")
            return
        }
        #expect(model.isWide == true)
    }

    @Test("Late mode carries the lastKnownPhase from the cycle's final day")
    func lastKnownPhaseIsLutealLate() {
        // For a 29-day cycle, day 29 is in luteal-late territory by
        // the standard PhaseBoundaries computation. The late model
        // should carry that as `lastKnownPhase`.
        let state = HeroStateBuilder.deriveHeroState(inputs(
            todayDayInCycle: 31, conditionalWidthDays: 10.0
        ))
        guard case .late(let model) = state else {
            Issue.record("Expected .late")
            return
        }
        #expect(model.lastKnownPhase == .lutealLate)
    }

    // MARK: - Additional coverage flagged by review

    @Test("Active-mode field round-trip with full inputs")
    func activeModelFieldRoundTrip() throws {
        // Use UTC-aligned dates so `predictedDay` produces deterministic
        // day counts independent of the test runner's timezone.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let lastStart = DateComponents(calendar: cal, timeZone: cal.timeZone,
                                       year: 2026, month: 5, day: 1).date!
        let low = DateComponents(calendar: cal, timeZone: cal.timeZone,
                                 year: 2026, month: 5, day: 26).date!
        let high = DateComponents(calendar: cal, timeZone: cal.timeZone,
                                  year: 2026, month: 6, day: 1).date!

        let state = HeroStateBuilder.deriveHeroState(inputs(
            lastStart: lastStart, todayDayInCycle: 10,
            calibratedInterval: low...high,
            isOngoingIrregularity: true
        ))
        guard case .active(let m) = state else {
            Issue.record("Expected .active, got \(state)")
            return
        }
        #expect(m.todayDay == 10)
        #expect(m.cycleLength == 29)
        // May 1 → May 26 is 25 calendar days → day 26 (1-indexed).
        #expect(m.predictedLowerDay == 26)
        // May 1 → June 1 is 31 calendar days → day 32 (1-indexed).
        #expect(m.predictedUpperDay == 32)
        // PCOS suffix is appended.
        #expect(m.predictionIntervalText?.contains("Deine Zyklen sind natürlich variabel") == true)
    }

    @Test("isWideLate=true with nil interval still returns 'Keine klare Schätzung'")
    func wideLateWithNilInterval() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            todayDayInCycle: 50, conditionalInterval: nil, conditionalWidthDays: 20.0
        ))
        guard case .late(let m) = state else {
            Issue.record("Expected .late")
            return
        }
        #expect(m.isWide == true)
        #expect(m.intervalText == "Keine klare Schätzung")
    }

    @Test("daysLate=31 produces a late state whose daysLate maps to longOverdue bucket")
    func builderToBucketBridge() {
        let state = HeroStateBuilder.deriveHeroState(inputs(
            todayDayInCycle: 60, conditionalWidthDays: 5.0
        ))
        guard case .late(let m) = state else {
            Issue.record("Expected .late")
            return
        }
        #expect(m.daysLate == 31)
        #expect(LateMilestone.bucket(daysLate: m.daysLate) == .longOverdue)
    }

    // MARK: - Integration: real CycleStore → HeroInputs → deriveHeroState

    /// Integration helper — builds a real in-memory CycleStore, logs the
    /// supplied bleeding days, then assembles the same `HeroInputs` that
    /// `TidelineHomeView.refresh()` builds. Returns the derived state.
    /// Mirrors the production wiring at TidelineHomeView.swift:486-540 so
    /// future drift in that path is caught at CI time.
    private func deriveStateFromRealStore(
        bleedingOffsetDays: [Int],
        todayOffsetDays: Int,
        applyEvent: (kind: EventKind, dayOffset: Int)? = nil
    ) async throws -> (state: HeroState, observedN: Int) {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let store = CycleStore(modelContainer: container)

        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -200 * 86_400).civilDay()
        for off in bleedingOffsetDays {
            let d = cal.date(byAdding: .day, value: off, to: baseline)!
            await store.logDay(date: d, flow: .medium)
        }
        if let ev = applyEvent {
            let d = cal.date(byAdding: .day, value: ev.dayOffset, to: baseline)!
            await store.addEvent(kind: ev.kind, on: d)
        }

        // Pretend "today" is offset N days after baseline (lets us probe
        // arbitrary points in the cycle deterministically).
        let today = cal.date(byAdding: .day, value: todayOffsetDays, to: baseline)!.civilDay()
        let mode = await store.currentMode()
        let lastStart = await store.currentCycleStart()
        let observedN = await store.observedCycleCount()

        let dayCount: Int
        if let lastStart {
            dayCount = cal.dateComponents([.day], from: lastStart.civilDay(), to: today).day ?? 0
        } else {
            dayCount = 0
        }
        let todayDayInCycle = max(1, dayCount + 1)

        let bleed: Set<Int>
        if let start = lastStart {
            // Run the same logic the home view uses to derive the
            // bleeding-day set, scoped to the current cycle.
            bleed = Set(bleedingOffsetDays.compactMap { off -> Int? in
                let d = cal.date(byAdding: .day, value: off, to: baseline)!.civilDay()
                guard d >= start.civilDay() && d <= today else { return nil }
                let dayCount = cal.dateComponents([.day], from: start.civilDay(), to: d).day ?? 0
                return dayCount + 1
            })
        } else {
            bleed = []
        }
        let mensesEnd = PhaseBoundaries.mensesEnd(
            bleedingDays: bleed,
            todayDayInCycle: todayDayInCycle
        )
        let predLen = Int(round(await store.predictedCycleLength()))
        let boundaries = PhaseBoundaries.from(cycleLength: predLen, mensesEnd: mensesEnd)

        let calibrated = mode.activePredictor != nil
            ? await store.nextCalibratedPrediction(confidence: 0.90)
            : nil
        let dSinceStart = max(0.0, Double(todayDayInCycle - 1))
        let conditionalDays: ClosedRange<Double>?
        if todayDayInCycle >= boundaries.cycleLength - 5 {
            conditionalDays = await store.conditionalIntervalForLatePeriod(
                daysSinceLastPeriod: dSinceStart, confidence: 0.90
            )
        } else {
            conditionalDays = nil
        }
        let conditionalWidth = conditionalDays.map { $0.upperBound - $0.lowerBound }
        let conditionalDateRange: ClosedRange<Date>? = conditionalDays.flatMap { r in
            guard let start = lastStart else { return nil }
            let anchor = start.civilDay()
            return anchor.addingDays(r.lowerBound)...anchor.addingDays(r.upperBound)
        }

        let state = HeroStateBuilder.deriveHeroState(HeroInputs(
            mode: mode,
            lastStart: lastStart,
            todayDayInCycle: todayDayInCycle,
            cycleBoundaries: boundaries,
            observedCount: observedN,
            calibratedInterval: calibrated?.interval,
            conditionalInterval: conditionalDateRange,
            conditionalWidthDays: conditionalWidth,
            isWidenedRecovery: calibrated?.isWidenedRecovery ?? false,
            isOngoingIrregularity: calibrated?.isOngoingIrregularity ?? false,
            pausedLabel: nil,
            retiredLabel: nil
        ))
        return (state, observedN)
    }

    @Test("Integration: 5 logged cycles + today inside expected window → .active")
    func integrationActiveInsideWindow() async throws {
        // Bleed days at 0, 28, 56, 84, 112 → 4 cycle observations, μ≈28.
        // Today at offset 120 → day 9 of current cycle (well inside).
        let result = try await deriveStateFromRealStore(
            bleedingOffsetDays: [0, 28, 56, 84, 112],
            todayOffsetDays: 120
        )
        if case .active = result.state { } else {
            Issue.record("Expected .active inside window, got \(result.state)")
        }
        #expect(result.observedN == 4)
    }

    @Test("Integration: 5 logged cycles + today past expected end → .late")
    func integrationLatePastWindow() async throws {
        // Last cycle starts at +112; with μ≈28 the expected end is +140.
        // Today at +145 → day 34 of a ~28-day cycle → 6 days late.
        let result = try await deriveStateFromRealStore(
            bleedingOffsetDays: [0, 28, 56, 84, 112],
            todayOffsetDays: 145
        )
        guard case .late(let m) = result.state else {
            Issue.record("Expected .late past expected end, got \(result.state)")
            return
        }
        #expect(m.daysLate >= 4 && m.daysLate <= 8,
                "daysLate=\(m.daysLate) — expected ~6 with μ≈28")
    }

    @Test("Integration: hysterectomy event → .retired regardless of last cycle")
    func integrationRetired() async throws {
        let result = try await deriveStateFromRealStore(
            bleedingOffsetDays: [0, 28, 56],
            todayOffsetDays: 80,
            applyEvent: (kind: .hysterectomy, dayOffset: 70)
        )
        if case .retired = result.state { } else {
            Issue.record("Expected .retired after hysterectomy event, got \(result.state)")
        }
    }

    @Test("Integration: no logged cycles → .empty")
    func integrationEmpty() async throws {
        let result = try await deriveStateFromRealStore(
            bleedingOffsetDays: [],
            todayOffsetDays: 10
        )
        #expect(result.state == .empty)
    }

    @Test("lastKnownPhase always reflects boundaries.phase(forDay: cycleLength)")
    func lastKnownPhaseMatchesBoundaryLookup() {
        // Across a few realistic cycle lengths, the late model's
        // `lastKnownPhase` must equal what PhaseBoundaries would have
        // reported at the final day of the cycle. This is a
        // structural assertion that catches a future regression where
        // the builder hardcodes `.lutealLate` instead of routing
        // through the boundaries table.
        for length in [21, 28, 29, 35] {
            let b = makeBoundaries(cycleLength: length, mensesEnd: 5)
            let state = HeroStateBuilder.deriveHeroState(inputs(
                todayDayInCycle: length + 2,
                cycleBoundaries: b,
                conditionalWidthDays: 8.0
            ))
            guard case .late(let m) = state else {
                Issue.record("Expected .late for cycleLength=\(length)")
                continue
            }
            #expect(m.lastKnownPhase == b.phase(forDay: length),
                    "lastKnownPhase mismatch at cycleLength=\(length)")
        }
    }
}
