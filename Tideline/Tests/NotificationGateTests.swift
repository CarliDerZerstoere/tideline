import Testing
import Foundation
@testable import Tideline

/// Tests for `NotificationGate` — the pure decision function that
/// future schedulers consult before calling `NotificationService.schedule`
/// (task #85). #122 will extend this with loss-window suppression;
/// these tests pin the today-shape of the gate so #122 catches its
/// own regression net.
@Suite("NotificationGate — eligibility decisions (task #85)")
struct NotificationGateTests {

    @Test("Master off blocks every category")
    func masterOffBlocksAll() {
        for category in [
            NotificationCategory.latePeriodCheckIn,
            .pregnancyTestMilestone,
            .general,
        ] {
            #expect(NotificationGate.shouldDeliver(
                category: category,
                masterEnabled: false
            ) == false)
        }
    }

    @Test("Master on allows latePeriodCheckIn")
    func masterOnAllowsLatePeriod() {
        #expect(NotificationGate.shouldDeliver(
            category: .latePeriodCheckIn,
            masterEnabled: true
        ) == true)
    }

    @Test("Master on allows pregnancyTestMilestone")
    func masterOnAllowsPregnancyTest() {
        #expect(NotificationGate.shouldDeliver(
            category: .pregnancyTestMilestone,
            masterEnabled: true
        ) == true)
    }

    @Test("Master on allows general")
    func masterOnAllowsGeneral() {
        #expect(NotificationGate.shouldDeliver(
            category: .general,
            masterEnabled: true
        ) == true)
    }

    // MARK: - Task #122 loss-aware suppression

    @Test("Recent loss suppresses latePeriodCheckIn even when master is on")
    func recentLossSuppressesLateCheckIn() {
        #expect(NotificationGate.shouldDeliver(
            category: .latePeriodCheckIn,
            masterEnabled: true,
            hasRecentLoss: true
        ) == false)
    }

    @Test("Recent loss suppresses pregnancyTestMilestone even when master is on")
    func recentLossSuppressesPregnancyTest() {
        #expect(NotificationGate.shouldDeliver(
            category: .pregnancyTestMilestone,
            masterEnabled: true,
            hasRecentLoss: true
        ) == false)
    }

    @Test("Recent loss does NOT suppress general category")
    func recentLossDoesNotSuppressGeneral() {
        #expect(NotificationGate.shouldDeliver(
            category: .general,
            masterEnabled: true,
            hasRecentLoss: true
        ) == true)
    }

    @Test("hasRecentLoss=false leaves all categories deliverable when master is on")
    func noRecentLossAllowsAllCategories() {
        for category in [
            NotificationCategory.latePeriodCheckIn,
            .pregnancyTestMilestone,
            .general,
        ] {
            #expect(NotificationGate.shouldDeliver(
                category: category,
                masterEnabled: true,
                hasRecentLoss: false
            ) == true)
        }
    }

    @Test("Master-off blocks suppressed AND unsuppressed categories")
    func masterOffOverridesLossLogic() {
        // hasRecentLoss is irrelevant when master is off — suppression
        // ordering must put master first.
        for hasLoss in [true, false] {
            for category in [
                NotificationCategory.latePeriodCheckIn,
                .pregnancyTestMilestone,
                .general,
            ] {
                #expect(NotificationGate.shouldDeliver(
                    category: category,
                    masterEnabled: false,
                    hasRecentLoss: hasLoss
                ) == false)
            }
        }
    }

    // MARK: - EventKind.isPregnancyLoss mapping (task #122)

    @Test("Pregnancy losses are flagged isPregnancyLoss == true")
    func pregnancyLossFlagTrueCases() {
        #expect(EventKind.miscarriageEarly.isPregnancyLoss == true)
        #expect(EventKind.miscarriageLate.isPregnancyLoss == true)
        #expect(EventKind.medicalAbortion.isPregnancyLoss == true)
        #expect(EventKind.surgicalAbortion.isPregnancyLoss == true)
    }

    /// Task #136 — the standalone "I had a loss" catchall must inherit
    /// the same isPregnancyLoss flag as the specific loss kinds, so a
    /// user who logs `.pregnancyLoss` (without sub-categorising) gets
    /// the same 28-day notification suppression as someone who logs
    /// `.miscarriageEarly`.
    @Test("Standalone pregnancyLoss inherits isPregnancyLoss flag")
    func standalonePregnancyLossFlagged() {
        #expect(EventKind.pregnancyLoss.isPregnancyLoss == true)
        #expect(EventKind.pregnancyLoss.category == .recoverable)
    }

    @Test("Non-loss events (including birth + Cat-C non-pregnancy) are NOT flagged")
    func pregnancyLossFlagFalseCases() {
        // Birth is Category C but NOT a loss — must not trigger suppression.
        #expect(EventKind.birthNoBreastfeeding.isPregnancyLoss == false)
        #expect(EventKind.birthBreastfeeding.isPregnancyLoss == false)
        // Other Cat C events (illness, stress, weight, stopping HC) — NOT losses.
        #expect(EventKind.acuteIllnessSevere.isPregnancyLoss == false)
        #expect(EventKind.extremeStress.isPregnancyLoss == false)
        #expect(EventKind.stoppedHormonalContraception.isPregnancyLoss == false)
        // Cat A (permanent retire) — also not losses in this sense.
        #expect(EventKind.hysterectomy.isPregnancyLoss == false)
        // Cat D (anomaly), Cat E (ongoing) — never losses.
        #expect(EventKind.singleAnomaly.isPregnancyLoss == false)
        #expect(EventKind.pcosDeclared.isPregnancyLoss == false)
    }

    /// RawValue round-trip — the category routing in
    /// `NotificationService.makePrivacyContent` writes the raw value to
    /// `userInfo["category"]`, so future on-open routing has to be able
    /// to parse it back. This pins the round-trip for every case.
    @Test("Every NotificationCategory round-trips through rawValue")
    func categoryRawValueRoundTrip() {
        for category in [
            NotificationCategory.latePeriodCheckIn,
            .pregnancyTestMilestone,
            .general,
        ] {
            let raw = category.rawValue
            let parsed = NotificationCategory(rawValue: raw)
            #expect(parsed == category)
        }
    }
}
