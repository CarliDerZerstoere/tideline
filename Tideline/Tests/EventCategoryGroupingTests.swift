import Testing
import Foundation
@testable import Tideline

/// Tests for `EventCategoryGrouping` (task #75). Pins the user-intent
/// grouping of `EventKind` so the LogEventSheet picker has a stable
/// source of truth. Adding a new `EventKind` without grouping it makes
/// the future-proofing test fail loudly.
@Suite("EventCategoryGrouping — user-intent partitioning")
struct EventCategoryGroupingTests {

    @Test("Every EventKind maps to exactly one group")
    func everyKindMapsToExactlyOneGroup() {
        for kind in EventKind.allCases {
            // The total function never aborts — we don't need to assert
            // non-nil. We do assert the inverse (events(in:) round-trip).
            let group = EventCategoryGrouping.userGroup(for: kind)
            #expect(EventCategoryGrouping.events(in: group).contains(kind),
                    "userGroup(for: \(kind)) -> \(group) but events(in: \(group)) doesn't include it")
        }
    }

    @Test("Every group has a non-empty German label")
    func everyGroupHasGermanLabel() {
        for group in EventUserGroup.allCases {
            #expect(!group.germanLabel.isEmpty)
        }
    }

    @Test("Every group has at least one event")
    func everyGroupNonEmpty() {
        for group in EventUserGroup.allCases {
            #expect(!EventCategoryGrouping.events(in: group).isEmpty,
                    "Group \(group) has no events — orphan group")
        }
    }

    @Test("Sensitive flag matches Cat A + Cat C losses")
    func sensitiveFlagCorrect() {
        // Cat A retirement events derive from the algorithm-internal
        // category enum — adding a NEW Cat A event automatically gets
        // flagged sensitive (the picker shows the warm acknowledgment).
        // Cat C losses stay as a manual subset because Cat C also
        // contains non-loss events (birthNoBreastfeeding, illness, etc.)
        // that don't warrant the soft copy. (Reviewer rec #9.)
        let catALosses = EventKind.allCases.filter { $0.category == .complete }
        let catCLosses: Set<EventKind> = [
            .medicalAbortion, .surgicalAbortion,
            .miscarriageEarly, .miscarriageLate,
            .pregnancyLoss  // task #136 NEW-J — standalone catchall
        ]
        let expected = Set(catALosses).union(catCLosses)
        for kind in EventKind.allCases {
            let shouldBeSensitive = expected.contains(kind)
            #expect(EventCategoryGrouping.isSensitive(kind) == shouldBeSensitive,
                    "isSensitive(\(kind)) should be \(shouldBeSensitive)")
        }
    }

    @Test("Sensitivity tone splits retirement from loss")
    func sensitivityToneSplit() {
        // Cat A → .retirement (permanent, no "loslegen" copy)
        // Cat C losses → .loss (recoverable)
        for kind in [EventKind.hysterectomy, .oophorectomy] {
            #expect(EventCategoryGrouping.sensitivityTone(kind) == .retirement)
        }
        for kind in [EventKind.medicalAbortion, .surgicalAbortion, .miscarriageEarly, .miscarriageLate, .pregnancyLoss] {
            #expect(EventCategoryGrouping.sensitivityTone(kind) == .loss)
        }
        // Neutral events → .none
        for kind in [EventKind.singleAnomaly, .pcosDeclared, .birthBreastfeeding, .stoppedHormonalContraception] {
            #expect(EventCategoryGrouping.sensitivityTone(kind) == .none)
        }
    }

    @Test("userVisibleEvents excludes auto-fired resumeAfterPause")
    func userVisibleHidesResumeAfterPause() {
        let misc = EventCategoryGrouping.userVisibleEvents(in: .misc)
        #expect(!misc.contains(.resumeAfterPause),
                "resumeAfterPause should be hidden from the manual picker — auto-fired by ResumeAfterPauseSheet")
        // But raw events() still includes it (used by tests + future surfaces).
        #expect(EventCategoryGrouping.events(in: .misc).contains(.resumeAfterPause))
    }

    @Test("allGroupsInOrder matches EventUserGroup.allCases order")
    func groupOrderStable() {
        let a = EventCategoryGrouping.allGroupsInOrder
        let b = EventCategoryGrouping.allGroupsInOrder
        #expect(a == b)
        #expect(a == EventUserGroup.allCases)
    }

    @Test("userGroup(for:) is deterministic")
    func userGroupDeterministic() {
        for kind in EventKind.allCases {
            let first = EventCategoryGrouping.userGroup(for: kind)
            let second = EventCategoryGrouping.userGroup(for: kind)
            #expect(first == second)
        }
    }

    @Test("Sum of group sizes equals total EventKind count (future-proofing)")
    func totalCoverage() {
        let total = EventUserGroup.allCases.reduce(0) { acc, group in
            acc + EventCategoryGrouping.events(in: group).count
        }
        #expect(total == EventKind.allCases.count,
                "An EventKind is not assigned to any group, or appears in two")
    }

    @Test("Pregnancy group contains the 7 expected events")
    func pregnancyGroupExpectedMembers() {
        let expected: Set<EventKind> = [
            .birthBreastfeeding, .birthNoBreastfeeding,
            .miscarriageEarly, .miscarriageLate,
            .medicalAbortion, .surgicalAbortion,
            .pregnancyLoss  // task #136 NEW-J — neutral standalone catchall
        ]
        let actual = Set(EventCategoryGrouping.events(in: .pregnancy))
        #expect(actual == expected)
    }

    @Test("Contraception group contains 8 expected events")
    func contraceptionGroupExpectedMembers() {
        let expected: Set<EventKind> = [
            .startedCombinedContraception,
            .startedProgestinOnlyContraception,
            .startedIUDHormonal,
            .startedInjectableContraception,
            .stoppedHormonalContraception,
            .stoppedIUDHormonal,
            .emergencyContraceptionFollicular,
            .emergencyContraceptionPeriOrLuteal
        ]
        let actual = Set(EventCategoryGrouping.events(in: .contraception))
        #expect(actual == expected)
    }
}
