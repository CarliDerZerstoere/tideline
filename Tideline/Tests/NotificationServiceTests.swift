import Testing
import Foundation
import UserNotifications
@testable import Tideline

/// Tests for the pure-logic parts of `NotificationService` — the
/// authorization-status mapping and the privacy-content builder.
/// The UN* passthrough wrappers (`requestAuthorization`, `schedule`,
/// etc.) need the iOS runtime and aren't covered here — they're
/// 3-line wrappers around the system API.
@Suite("NotificationService — pure logic (task #85)")
@MainActor
struct NotificationServiceTests {

    // MARK: - Authorization status mapping

    @Test("mapAuthorizationStatus covers every UN status")
    func authorizationStatusMapping() {
        #expect(mapAuthorizationStatus(.notDetermined) == .notDetermined)
        #expect(mapAuthorizationStatus(.denied) == .denied)
        #expect(mapAuthorizationStatus(.authorized) == .authorized)
        #expect(mapAuthorizationStatus(.provisional) == .provisional)
        #expect(mapAuthorizationStatus(.ephemeral) == .ephemeral)
    }

    // MARK: - makePrivacyContent

    @Test("makePrivacyContent uses the generic app name as title")
    func privacyContentTitleIsGeneric() {
        let svc = NotificationService()
        let content = svc.makePrivacyContent(category: .latePeriodCheckIn)
        #expect(content.title == "Tideline")
    }

    @Test("makePrivacyContent body never contains cycle/period words")
    func privacyContentBodyIsSafe() {
        let svc = NotificationService()
        let categories: [NotificationCategory] = [
            .latePeriodCheckIn,
            .pregnancyTestMilestone,
            .general,
        ]
        // Words that MUST NOT appear in any lockscreen-visible body.
        let forbidden = ["Periode", "Zyklus", "schwanger", "Schwanger", "Eisprung", "Ovulation", "Blutung", "Menstruation"]
        for category in categories {
            let content = svc.makePrivacyContent(category: category)
            for word in forbidden {
                #expect(!content.body.contains(word),
                        "Lockscreen body for \(category) contains '\(word)' — CLAUDE.md hard rule violation")
            }
        }
    }

    @Test("makePrivacyContent body never contains numeric cycle-day info")
    func privacyContentBodyHasNoNumbers() {
        let svc = NotificationService()
        let content = svc.makePrivacyContent(
            category: .latePeriodCheckIn,
            privatePayload: ["dayInCycle": "42"]
        )
        // The "42" must live in userInfo, NOT in the body.
        #expect(!content.body.contains("42"))
        #expect(content.userInfo["dayInCycle"] as? String == "42")
    }

    @Test("makePrivacyContent userInfo includes category for routing")
    func privacyContentCategoryRoutes() {
        let svc = NotificationService()
        let content = svc.makePrivacyContent(category: .pregnancyTestMilestone)
        #expect(content.userInfo["category"] as? String == "pregnancyTestMilestone")
    }

    @Test("makePrivacyContent ignores attempts to overwrite category via payload")
    func privacyContentCategoryShadowingIgnored() {
        let svc = NotificationService()
        let content = svc.makePrivacyContent(
            category: .pregnancyTestMilestone,
            privatePayload: ["category": "evilOverride", "dayInCycle": "5"]
        )
        // Category survives the shadowing attempt.
        #expect(content.userInfo["category"] as? String == "pregnancyTestMilestone")
        // The legit payload key still lands.
        #expect(content.userInfo["dayInCycle"] as? String == "5")
    }

    @Test("makePrivacyContent attaches default sound")
    func privacyContentSound() {
        let svc = NotificationService()
        let content = svc.makePrivacyContent(category: .latePeriodCheckIn)
        #expect(content.sound == .default)
    }
}
