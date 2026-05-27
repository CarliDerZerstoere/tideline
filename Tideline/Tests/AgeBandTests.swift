import Testing
import Foundation
import SwiftData
@testable import Tideline

/// Tests for `AgeBand` + the age-stratified population prior (task #97).
/// Pins exact AWHS-published within-person SD values so a fact-check
/// later catches any drift; pins the AppStorage round-trip; and pins
/// the predictor's posterior interval scales correctly with band.
@Suite("AgeBand — AWHS-stratified prior (task #97)")
struct AgeBandTests {

    // MARK: - AWHS values (verbatim from PMC10226714)

    @Test("Adolescent SD matches AWHS 5.33")
    func adolescentSD() {
        #expect(AgeBand.adolescent.withinPersonSDDays == 5.33)
    }

    @Test("Reproductive (20–39) SD uses AWHS 35–39 value 3.79")
    func reproductiveSD() {
        #expect(AgeBand.reproductive.withinPersonSDDays == 3.79)
    }

    @Test("Perimenopausal-early (40–44) SD snaps to AWHS 45–49 value 5.42")
    func perimenopausalEarlySD() {
        // Step extrapolation — flagged in AgeBand.swift docs.
        #expect(AgeBand.perimenopausalEarly.withinPersonSDDays == 5.42)
    }

    @Test("Perimenopausal (45–49) SD matches AWHS 5.42")
    func perimenopausalSD() {
        #expect(AgeBand.perimenopausal.withinPersonSDDays == 5.42)
    }

    @Test("Menopausal (50+) SD matches AWHS 11.19")
    func menopausalSD() {
        #expect(AgeBand.menopausal.withinPersonSDDays == 11.19)
    }

    @Test("Unspecified SD is the 5.0 modeling-choice fallback")
    func unspecifiedSDFallback() {
        // This number is NOT in AWHS — it's a modeling choice (see
        // AgeBand.swift comment). The test pins the constant so a
        // future change requires a deliberate test edit.
        #expect(AgeBand.unspecified.withinPersonSDDays == 5.0)
    }

    // MARK: - Display ordering

    @Test("displayOrder lists real bands first, .unspecified last")
    func displayOrder() {
        let order = AgeBand.displayOrder
        #expect(order.first == .adolescent)
        #expect(order.last == .unspecified)
        #expect(order.count == AgeBand.allCases.count)
    }

    @Test("Every band has a non-empty German label")
    func germanLabels() {
        for band in AgeBand.allCases {
            #expect(!band.germanLabel.isEmpty)
        }
    }

    // MARK: - AppStorage round-trip

    @Test("RawValue round-trip preserves every case")
    func rawValueRoundTrip() {
        for band in AgeBand.allCases {
            let raw = band.rawValue
            let parsed = AgeBand(rawValue: raw)
            #expect(parsed == band)
        }
    }

    // MARK: - Predictor factory

    @Test("populationPrior(for: .reproductive) equals existing static populationPrior")
    func reproductiveMatchesLegacyStatic() {
        let legacy = CyclePredictor.populationPrior
        let banded = CyclePredictor.populationPrior(for: .reproductive)
        // Task #158 — corrected NIG formula is β = (α−1)·σ² with σ=3.79
        // (AWHS exact) for both. Now they ARE identical (previously
        // diverged because legacy used rounded 3.7 and the factory used
        // exact 3.79). E[σ²] = β/(α−1) = 28.7282/2 = 14.3641 = 3.79².
        #expect(banded.mu == legacy.mu)
        #expect(banded.kappa == legacy.kappa)
        #expect(banded.alpha == legacy.alpha)
        #expect(abs(legacy.beta - 28.7282) < 0.001)
        #expect(abs(banded.beta - 28.7282) < 0.001)
    }

    @Test("populationPrior(for: .adolescent) yields a wider β than reproductive")
    func adolescentWiderThanReproductive() {
        let young = CyclePredictor.populationPrior(for: .adolescent)
        let mid = CyclePredictor.populationPrior(for: .reproductive)
        #expect(young.beta > mid.beta)
        // σ² ratio: 5.33² / 3.79² ≈ 1.977 → β ratio same.
        let ratio = young.beta / mid.beta
        #expect(abs(ratio - 1.977) < 0.01)
    }

    @Test("populationPrior(for: .menopausal) yields the widest β")
    func menopausalWidest() {
        let mid = CyclePredictor.populationPrior(for: .reproductive)
        let menopausal = CyclePredictor.populationPrior(for: .menopausal)
        // 11.19² / 3.79² ≈ 8.72.
        let ratio = menopausal.beta / mid.beta
        #expect(abs(ratio - 8.72) < 0.05)
    }

    @Test("Predictive interval at N=0 widens with band")
    func predictiveIntervalScalesWithBand() {
        let mid = CyclePredictor.populationPrior(for: .reproductive)
        let young = CyclePredictor.populationPrior(for: .adolescent)
        let menopausal = CyclePredictor.populationPrior(for: .menopausal)

        let midScale = mid.predictiveScale
        let youngScale = young.predictiveScale
        let menoScale = menopausal.predictiveScale

        #expect(youngScale > midScale)
        #expect(menoScale > youngScale)
    }
}

/// Tests for the `CycleStore` age-band wiring (task #97). Pins the
/// composition-root contract: `setAgeBand` MUST run before
/// `loadAndReplay` for the band to influence the posterior.
@Suite("CycleStore age-band wiring (task #97)")
struct CycleStoreAgeBandTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Cycle.self, DayEntry.self, CycleEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("setAgeBand swaps the predictor's prior")
    func setAgeBandSwapsPrior() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.setAgeBand(.menopausal)
        let mode = await store.currentMode()
        let beta = mode.activePredictor?.beta ?? 0
        // Menopausal: σ=11.19 → β = (α−1)·σ² = 2·125.2161 ≈ 250.43
        // (task #158 corrected from prior 3·σ²=375.5).
        #expect(abs(beta - 250.4322) < 0.01)
    }

    /// Reviewer T1 — pause mode is persisted as a CycleEvent and must
    /// survive a band change. Without this test, a future refactor of
    /// `reprimeForAgeBand` that skipped the replay (or re-introduced
    /// the unconditional `.active(...)` assignment) would silently
    /// un-pause breastfeeding users.
    @Test("Paused mode survives reprimeForAgeBand (replay reconstructs the pause)")
    func reprimeKeepsPaused() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.setAgeBand(.reproductive)
        // Pause via the persisted-event path.
        await store.addEvent(kind: .birthBreastfeeding, on: .now)
        let before = await store.currentMode()
        #expect(before.isPaused)

        await store.reprimeForAgeBand(.menopausal)

        let after = await store.currentMode()
        #expect(after.isPaused, "Pause must survive band change — events drive the mode, the band only chooses the prior")
        // The archived posterior's β reflects the new band's prior
        // (with a single observation folded in from the cycle that
        // closed at the pause moment, if any).
        if let archived = after.archivedPredictor {
            #expect(archived.beta > 100.0, "Menopausal prior β=250.43 (task #158 corrected); after data folding it should stay well above the reproductive band's range")
        }
    }

    /// Reviewer T2 — pin the cold-launch ordering contract. If a future
    /// refactor moves `setAgeBand` after `loadAndReplay`, this test
    /// catches it: replay against `.unspecified` then a no-op
    /// `setAgeBand(.menopausal)` would not reflect the menopausal
    /// prior. Test exercises the full primeFromUserDefaults → replay
    /// sequence in a single store instance.
    @Test("Cold-launch: setAgeBand before loadAndReplay applies the band's prior")
    func coldLaunchAppliesBand() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        // Mimic AppContainer.primeFromUserDefaults reading "menopausal".
        await store.setAgeBand(.menopausal)
        // Mimic RootView.task awaiting loadAndReplay (empty store, but
        // the predictor's prior must reflect the band).
        await store.loadAndReplay()

        let beta = await store.currentMode().activePredictor?.beta ?? 0
        // Menopausal: β = (α−1)·σ² = 2·125.2161 ≈ 250.43 (task #158).
        #expect(abs(beta - 250.4322) < 0.01, "After cold-launch the predictor must carry the menopausal prior, not the .unspecified fallback")
    }

    /// Reviewer T3 — double-setAgeBand idempotency. Two calls with the
    /// same band, separated by an observation, must not discard the
    /// observation. Without the idempotency guard the second call
    /// would rebuild the predictor and zero `observedCount`.
    @Test("Double setAgeBand with the same band preserves observations between calls")
    func doubleSetAgeBandIsIdempotent() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.setAgeBand(.reproductive)
        // Land one cycle-length observation directly via the predictor.
        let cal = Calendar.current
        let start = Date(timeIntervalSinceNow: -60 * 86_400).civilDay()
        await store.logDay(date: start, flow: .medium)
        await store.logDay(date: cal.date(byAdding: .day, value: 28, to: start)!, flow: .medium)
        let observed = await store.currentMode().activePredictor?.observedCount ?? -1
        #expect(observed == 1)
        // Second call with the same band must not discard state.
        await store.setAgeBand(.reproductive)
        let observedAfter = await store.currentMode().activePredictor?.observedCount ?? -1
        #expect(observedAfter == 1)
    }

    // MARK: - Task #162 — age-band-aware softReset

    /// Pure CyclePredictor-level test: softReset(forBand:) routes through
    /// the band's σ. Independent of PredictorService / CycleStore actor
    /// wiring; pins the math.
    @Test("softReset(forBand: .menopausal) routes to band-appropriate β (not reproductive)")
    func softResetMenopausalBand() {
        var p = CyclePredictor.populationPrior(for: .menopausal)
        p.observe(cycleLengths: [28, 30, 27, 29, 30])
        p.softReset(forBand: .menopausal)
        // Menopausal: β = 2 · 11.19² = 250.4322
        #expect(abs(p.beta - 250.4322) < 0.001)
        #expect(p.observedCount == 0)
    }

    @Test("softReset(forBand: .adolescent) routes correctly")
    func softResetAdolescentBand() {
        var p = CyclePredictor.populationPrior(for: .adolescent)
        p.observe(cycleLengths: [28, 30, 27])
        p.softReset(forBand: .adolescent)
        // Adolescent: β = 2 · 5.33² = 56.8178
        #expect(abs(p.beta - 56.8178) < 0.001)
    }

    @Test("softReset() no-arg defaults to .unspecified (β=50.0)")
    func softResetNoArgDefaultsToUnspecified() {
        var p = CyclePredictor.populationPrior
        p.observe(cycleLengths: [28, 30, 27])
        p.softReset()
        // .unspecified: σ=5.0 → β = 2·25 = 50.0
        #expect(abs(p.beta - 50.0) < 1e-9)
    }

    /// End-to-end: a menopausal user logs a Category C event (miscarriage).
    /// The post-event β must reflect their menopausal band (~250) NOT
    /// collapse to reproductive-band β=28.7. This is the user-visible
    /// bug task #162 was opened to fix.
    @Test("Menopausal user post-Category-C event keeps menopausal β (task #162 regression)")
    func menopausalUserPostCategoryCKeepsMenopausalPrior() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.setAgeBand(.menopausal)
        // Log a Category C event (miscarriage).
        await store.addEvent(kind: .miscarriageEarly, on: .now)
        let mode = await store.currentMode()
        let beta = mode.activePredictor?.beta ?? 0
        // Without #162: β would have collapsed to 28.7 (reproductive).
        // With #162: β stays in menopausal-band territory (~250).
        #expect(beta > 200.0,
                "Post-event β=\(beta) — must reflect menopausal band, not reproductive collapse")
    }

    @Test("reprimeForAgeBand changes the prior + preserves logged observations")
    func reprimeKeepsObservations() async throws {
        let container = try makeContainer()
        let store = CycleStore(modelContainer: container)
        await store.setAgeBand(.reproductive)
        // Log 2 cycles 28 days apart so the predictor has observations.
        let cal = Calendar.current
        let baseline = Date(timeIntervalSinceNow: -60 * 86_400).civilDay()
        await store.logDay(date: baseline, flow: .medium)
        await store.logDay(date: cal.date(byAdding: .day, value: 28, to: baseline)!, flow: .medium)

        let observedBefore = await store.currentMode().activePredictor?.observedCount ?? -1
        #expect(observedBefore == 1)

        // Reprime to menopausal — observations must persist via replay.
        await store.reprimeForAgeBand(.menopausal)

        let observedAfter = await store.currentMode().activePredictor?.observedCount ?? -1
        #expect(observedAfter == 1)
        // β is now scaled to the menopausal band, but reduced by the
        // one observation that was replayed.
        let betaAfter = await store.currentMode().activePredictor?.beta ?? 0
        // Menopausal prior β=250.43 (task #158 — was 375.5 before
        // NIG-formula correction). After one cycle observation the
        // posterior β grows slightly (squared deviation term). Floor
        // chosen below the reproductive band's β=28.7 by a wide margin
        // so any regression that drops the menopausal prior's σ-scale
        // is caught.
        #expect(betaAfter > 200.0)
    }
}
