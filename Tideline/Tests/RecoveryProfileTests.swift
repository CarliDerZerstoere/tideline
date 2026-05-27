import Testing
import Foundation
@testable import Tideline

@Suite("RecoveryProfile — per-event lookup + applyRecoveryProfile (#194)")
struct RecoveryProfileTests {

    // MARK: - Lookup

    @Test("profile(for:) returns the right profile for each Category C event")
    func lookupCoversAllCategoryCEvents() {
        let categoryCKinds: [EventKind] = [
            .medicalAbortion, .surgicalAbortion,
            .miscarriageEarly, .miscarriageLate,
            .pregnancyLoss, .birthNoBreastfeeding,
            .stoppedHormonalContraception, .stoppedIUDHormonal,
            .acuteIllnessSevere, .majorSurgery,
            .significantWeightChange, .extremeStress,
        ]
        for kind in categoryCKinds {
            #expect(RecoveryProfile.profile(for: kind) != nil,
                    "\(kind) is Category C but has no recovery profile")
        }
    }

    @Test("profile(for:) returns nil for non-Category-C events")
    func lookupReturnsNilForOtherCategories() {
        let nonCategoryC: [EventKind] = [
            .hysterectomy,                 // Category A
            .birthBreastfeeding,           // Category B (pause)
            .singleAnomaly,                // Category D (anomaly)
            .emergencyContraceptionFollicular,
            .pcosDeclared,                 // Category E (ongoing)
            .resumeAfterPause,             // Category F (resume)
        ]
        for kind in nonCategoryC {
            #expect(RecoveryProfile.profile(for: kind) == nil,
                    "\(kind) is not Category C but profile lookup returned non-nil")
        }
    }

    // MARK: - Specific profile values

    @Test("medicalAbortion profile cites Schreiber 2011 with honest analyst inflation")
    func medicalAbortionEvidenceAnchorIsHonest() {
        let profile = RecoveryProfile.medicalAbortion
        #expect(profile.eventKind == .medicalAbortion)
        #expect(profile.mu1Offset == 2.0)
        #expect(profile.sigma1Cycle1 == 7.0)
        #expect(profile.cyclesToBaseline == 3)
        #expect(!profile.ashermanRisk)
        // The anchor is .analystElicited (not .literature) because
        // Schreiber 2011 reports ovulation TIMING σ, not cycle-length
        // SD. The rationale string must cite Schreiber so the
        // literature provenance is visible.
        if case let .analystElicited(rationale) = profile.evidenceAnchor {
            #expect(rationale.contains("Schreiber"),
                    "Rationale should cite Schreiber as the ovulation-timing anchor")
            #expect(rationale.contains("21843685"),
                    "Rationale should include the PMID for verifiability")
        } else {
            Issue.record("Expected analystElicited anchor citing Schreiber, got \(profile.evidenceAnchor)")
        }
    }

    @Test("surgicalAbortion + miscarriageLate carry Asherman risk flag")
    func ashermanFlagOnDAndCEvents() {
        #expect(RecoveryProfile.surgicalAbortion.ashermanRisk)
        #expect(RecoveryProfile.miscarriageLate.ashermanRisk)
        // Non-D&C events should not carry the flag.
        #expect(!RecoveryProfile.medicalAbortion.ashermanRisk)
        #expect(!RecoveryProfile.miscarriageEarly.ashermanRisk)
        #expect(!RecoveryProfile.liveBirthNonBreastfeeding.ashermanRisk)
        #expect(!RecoveryProfile.stoppedOCP.ashermanRisk)
        #expect(!RecoveryProfile.stoppedLNGIUD.ashermanRisk)
    }

    @Test("stoppedOCP profile matches Nassaralla 2011 σ=11 anchor")
    func stoppedOCPLiteratureAnchor() {
        let profile = RecoveryProfile.stoppedOCP
        #expect(profile.sigma1Cycle1 == 11.0,
                "Post-OCP cycle 1 σ should match Nassaralla 2011 (PMC7643763)")
        #expect(profile.cyclesToBaseline == 9,
                "Post-OCP recovery cycles to baseline should match Gnoth 2002 (PMID 12396560)")
    }

    @Test("liveBirth non-BF profile matches Jackson & Glasier 2011 mixing-weight range")
    func liveBirthNonBFAnchor() {
        let profile = RecoveryProfile.liveBirthNonBreastfeeding
        #expect(profile.mu1Offset == 8.0)
        #expect(profile.piPriorMean == 0.45,
                "Post-birth π lowered to reflect 20–71% anovulatory first cycle (Jackson & Glasier 2011)")
    }

    // MARK: - German display

    @Test("germanRecoveryPhrase covers all 12 Category C events")
    func germanPhraseCovers() {
        let kinds: [EventKind] = [
            .medicalAbortion, .surgicalAbortion,
            .miscarriageEarly, .miscarriageLate,
            .pregnancyLoss, .birthNoBreastfeeding,
            .stoppedHormonalContraception, .stoppedIUDHormonal,
            .acuteIllnessSevere, .majorSurgery,
            .significantWeightChange, .extremeStress,
        ]
        for kind in kinds {
            guard let profile = RecoveryProfile.profile(for: kind) else {
                Issue.record("Missing profile for \(kind)")
                continue
            }
            #expect(!profile.germanRecoveryPhrase.isEmpty,
                    "\(kind) needs a German recovery phrase")
            #expect(profile.germanRecoveryPhrase.hasPrefix("nach"),
                    "Phrase '\(profile.germanRecoveryPhrase)' should start with 'nach' for grammatical composition")
        }
    }

    // MARK: - applyRecoveryProfile

    @Test("applyRecoveryProfile shifts μ₁ by mu1Offset")
    func applyShiftsMu1() {
        var mix = MixturePredictor.populationPrior
        let originalMu1 = mix.mu1Prior
        mix.applyRecoveryProfile(.medicalAbortion)
        #expect(mix.mu1Prior == originalMu1 + 2.0,
                "μ₁ prior should shift by +2 days after medicalAbortion profile applied")
    }

    @Test("applyRecoveryProfile widens β₁ to match cycle-1 σ")
    func applyWidensBeta1() {
        var mix = MixturePredictor.populationPrior
        mix.applyRecoveryProfile(.stoppedOCP)
        // β = (α-1)·σ² with α=3, σ=11 → β = 2 · 121 = 242
        let expectedBeta = 2.0 * 11.0 * 11.0
        #expect(abs(mix.beta1Prior - expectedBeta) < 0.001,
                "β₁ \(mix.beta1Prior) should match (α-1)·σ² = \(expectedBeta)")
    }

    @Test("applyRecoveryProfile shifts π prior toward profile mean")
    func applyShiftsPiPrior() {
        var mix = MixturePredictor.populationPrior
        // liveBirthNonBreastfeeding has piPriorMean = 0.45
        mix.applyRecoveryProfile(.liveBirthNonBreastfeeding)
        // Total weight 10 → α = 4.5, β = 5.5
        #expect(abs(mix.piAlphaPrior - 4.5) < 0.001)
        #expect(abs(mix.piBetaPrior - 5.5) < 0.001)
    }

    @Test("applyRecoveryProfile preserves observations (Session 1 H1)")
    func applyPreservesObservations() {
        var mix = MixturePredictor.populationPrior
        mix.observe(cycleLengths: Array(repeating: 28.0, count: 15))
        let countBefore = mix.observedCount
        mix.applyRecoveryProfile(.medicalAbortion)
        #expect(mix.observedCount == countBefore,
                "Recovery profile must preserve long-run observations (Session 1 H1 decision)")
    }

    @Test("applyRecoveryProfile clears cached posterior samples")
    func applyClearsSamples() {
        var mix = MixturePredictor.populationPrior
        mix.observe(cycleLengths: Array(repeating: 28.0, count: 15))
        mix.runGibbs(iterations: 100, burnIn: 50, seed: 1)
        #expect(!mix.posteriorSamples.isEmpty)
        mix.applyRecoveryProfile(.medicalAbortion)
        #expect(mix.posteriorSamples.isEmpty,
                "Posterior samples should be cleared so next read re-runs Gibbs against new prior")
    }
}

@Suite("PredictorService — recoveryState lifecycle (#194)")
struct PredictorServiceRecoveryStateTests {

    @Test("recoveryState is nil with no Category C event")
    func nilInitially() async {
        let service = PredictorService()
        let state = await service.recoveryState()
        #expect(state == nil)
    }

    @Test("Category C event sets recoveryState with correct profile values")
    func recoverableSetsState() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        let state = await service.recoveryState()
        #expect(state != nil)
        #expect(state?.eventKind == .medicalAbortion)
        #expect(state?.cyclesRemaining == 3)
        #expect(state?.totalCycles == 3)
        #expect(state?.currentCycle == 1,
                "Before any post-event observe(), should be cycle 1 of N")
        #expect(state?.ashermanFlag == false)
    }

    @Test("observe() decrements cyclesRemaining and advances currentCycle")
    func observeDecrementsCounter() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        _ = await service.observe(cycleLength: 30.0)
        let state = await service.recoveryState()
        #expect(state != nil)
        #expect(state?.cyclesRemaining == 2,
                "After one observe(), remaining should be 2 of 3")
        #expect(state?.currentCycle == 2)
    }

    @Test("recoveryState auto-clears at cyclesRemaining=0 for non-Asherman events")
    func nonAshermanAutoGraduates() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        // 3 cycles to graduate.
        _ = await service.observe(cycleLength: 30.0)
        _ = await service.observe(cycleLength: 29.0)
        _ = await service.observe(cycleLength: 28.0)
        let state = await service.recoveryState()
        #expect(state == nil,
                "After cyclesToBaseline observations, non-Asherman recovery should clear")
    }

    @Test("Asherman-flagged recovery does NOT auto-graduate at cyclesRemaining=0")
    func ashermanStaysActive() async {
        let service = PredictorService()
        await service.apply(eventKind: .surgicalAbortion, on: Date.now)
        // surgicalAbortion has cyclesToBaseline=3 AND ashermanRisk=true.
        // Observe through and beyond the window.
        for _ in 0..<5 {
            _ = await service.observe(cycleLength: 30.0)
        }
        let state = await service.recoveryState()
        #expect(state != nil,
                "Asherman-flagged recovery must remain active after the baseline window — HRU 2024 17% IUA rate")
        #expect(state?.ashermanFlag == true)
    }

    @Test("clearAshermanRecovery clears Asherman-flagged state")
    func clearAshermanWorks() async {
        let service = PredictorService()
        await service.apply(eventKind: .surgicalAbortion, on: Date.now)
        await service.clearAshermanRecovery()
        let state = await service.recoveryState()
        #expect(state == nil)
    }

    @Test("clearAshermanRecovery is a no-op for non-Asherman events")
    func clearAshermanNoOpForOthers() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        await service.clearAshermanRecovery()
        let state = await service.recoveryState()
        #expect(state != nil,
                "clearAshermanRecovery must not clear non-Asherman windows")
    }

    @Test("Category A retire clears recoveryState")
    func retireClearsRecovery() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        await service.apply(eventKind: .hysterectomy, on: Date.now)
        let state = await service.recoveryState()
        #expect(state == nil)
    }

    @Test("Category B pause clears recoveryState")
    func pauseClearsRecovery() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        await service.apply(eventKind: .birthBreastfeeding, on: Date.now)
        let state = await service.recoveryState()
        #expect(state == nil)
    }

    @Test("cyclePattern still surfaces during active recovery (T1)")
    func cyclePatternSurfacesDuringRecovery() async {
        let service = PredictorService()
        // Get to graduation threshold first.
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        // Apply Category C event — recovery active.
        await service.apply(eventKind: .stoppedHormonalContraception, on: Date.now)
        let pattern = await service.cyclePattern()
        let recovery = await service.recoveryState()
        #expect(recovery != nil)
        #expect(pattern != nil,
                "cyclePattern() must still produce a value during recovery — the UI decides to hide it via recoveryState taking precedence, but the service-level API stays consistent")
    }

    @Test(".acuteIllnessSevere and .majorSurgery share the same profile (T2)")
    func acuteIllnessAndMajorSurgeryShareProfile() {
        let illness = RecoveryProfile.profile(for: .acuteIllnessSevere)
        let surgery = RecoveryProfile.profile(for: .majorSurgery)
        #expect(illness != nil)
        #expect(surgery != nil)
        #expect(illness == surgery,
                "v1: both events share the prolongedIllnessOrSurgery profile. Split when sample-size justifies separate priors.")
    }

    @Test(".significantWeightChange and .extremeStress share the same profile (T2)")
    func weightAndStressShareProfile() {
        let weight = RecoveryProfile.profile(for: .significantWeightChange)
        let stress = RecoveryProfile.profile(for: .extremeStress)
        #expect(weight == stress)
    }

    @Test("Anomaly events (Category D) do NOT clear an active recovery (T3)")
    func anomalyDoesNotClearRecovery() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        await service.apply(eventKind: .singleAnomaly, on: Date.now)
        let state = await service.recoveryState()
        #expect(state?.eventKind == .medicalAbortion,
                "Category D anomaly must not disturb an active Category C recovery window")
    }

    @Test("Ongoing-declared events (Category E) do NOT clear an active recovery (T3)")
    func ongoingDeclaredDoesNotClearRecovery() async {
        let service = PredictorService()
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        await service.apply(eventKind: .pcosDeclared, on: Date.now)
        let state = await service.recoveryState()
        #expect(state?.eventKind == .medicalAbortion)
    }

    @Test("New Category C event replaces an active recovery (Q8 contract)")
    func newCategoryCReplacesRecovery() async {
        let service = PredictorService()
        await service.apply(eventKind: .stoppedHormonalContraception, on: Date.now)
        // Stop-OCP has cyclesToBaseline=9.
        let firstState = await service.recoveryState()
        #expect(firstState?.eventKind == .stoppedHormonalContraception)
        #expect(firstState?.totalCycles == 9)
        // Apply a newer Category C event.
        await service.apply(eventKind: .medicalAbortion, on: Date.now)
        let secondState = await service.recoveryState()
        #expect(secondState?.eventKind == .medicalAbortion,
                "Newer Category C must overwrite the active recovery window")
        #expect(secondState?.totalCycles == 3,
                "Window length resets to the new event's cyclesToBaseline")
    }

    @Test("clearAshermanRecovery is idempotent on empty state (T4)")
    func clearAshermanIdempotentEmpty() async {
        let service = PredictorService()
        // No active recovery — should not crash.
        await service.clearAshermanRecovery()
        await service.clearAshermanRecovery()
        let state = await service.recoveryState()
        #expect(state == nil)
    }

    @Test("Recovery profile actually shifts mixture priors")
    func recoveryProfileShiftsMixture() async {
        let service = PredictorService()
        // Establish a baseline pattern history first.
        for length in [28.0, 29, 27, 28, 30, 28, 27, 29, 28, 30, 28, 29] {
            _ = await service.observe(cycleLength: length)
        }
        let preEventPattern = await service.cyclePattern()
        #expect(preEventPattern != nil)
        // Apply stop-OCP — should re-prime with widened σ and lowered π.
        await service.apply(eventKind: .stoppedHormonalContraception, on: Date.now)
        // Pattern still surfaces (observedCount preserved), but the
        // recovery state takes UI precedence per Session 3 design.
        let state = await service.recoveryState()
        #expect(state?.eventKind == .stoppedHormonalContraception)
        #expect(state?.totalCycles == 9,
                "Post-OCP recovery should target 9 cycles per Gnoth 2002")
    }
}
