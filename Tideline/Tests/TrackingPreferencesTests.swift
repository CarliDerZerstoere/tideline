import Testing
import Foundation
@testable import Tideline

/// Tests for `TrackingPreferences` (task #76). Pins the AppStorage key
/// strings + default-false behaviour. Uses an ephemeral `UserDefaults`
/// suite so tests don't pollute the simulator's main defaults.
@Suite("TrackingPreferences — onboarding-set tracking flags")
struct TrackingPreferencesTests {

    /// Build a fresh defaults store for each test, scoped to a UUID
    /// suite name so tests are hermetic.
    private func freshDefaults() -> UserDefaults {
        let suite = "tideline.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("Key constants are non-empty + distinct")
    func keyConstantsValid() {
        let keys = [
            TrackingPreferences.moodEnabledKey,
            TrackingPreferences.symptomsEnabledKey,
            TrackingPreferences.notesEnabledKey
        ]
        for key in keys { #expect(!key.isEmpty) }
        #expect(Set(keys).count == keys.count, "Keys must be distinct")
    }

    @Test("Default snapshot on fresh defaults returns all false")
    func defaultSnapshotAllFalse() {
        let defaults = freshDefaults()
        let snap = TrackingPreferences.snapshot(defaults: defaults)
        #expect(snap.moodEnabled == false)
        #expect(snap.symptomsEnabled == false)
        #expect(snap.notesEnabled == false)
    }

    @Test("Writing true to each key surfaces in the snapshot")
    func snapshotReflectsWrites() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: TrackingPreferences.moodEnabledKey)
        defaults.set(true, forKey: TrackingPreferences.symptomsEnabledKey)
        defaults.set(true, forKey: TrackingPreferences.notesEnabledKey)
        let snap = TrackingPreferences.snapshot(defaults: defaults)
        #expect(snap.moodEnabled)
        #expect(snap.symptomsEnabled)
        #expect(snap.notesEnabled)
    }

    @Test("Snapshot Equatable: same flags equal")
    func snapshotEquatable() {
        let a = TrackingPreferences.Snapshot(moodEnabled: true, symptomsEnabled: false, notesEnabled: true)
        let b = TrackingPreferences.Snapshot(moodEnabled: true, symptomsEnabled: false, notesEnabled: true)
        let c = TrackingPreferences.Snapshot(moodEnabled: false, symptomsEnabled: false, notesEnabled: true)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("LastPeriodChoice cases compose correctly")
    func lastPeriodChoiceCases() {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let a = LastPeriodChoice.specificDate(date)
        let b = LastPeriodChoice.specificDate(date)
        let c = LastPeriodChoice.recently
        let d = LastPeriodChoice.unsure
        #expect(a == b)
        #expect(a != c)
        #expect(c != d)
    }
}
