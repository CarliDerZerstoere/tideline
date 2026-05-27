import Foundation
import SwiftData

/// Composition root. Owns the SwiftData container and the service actors that
/// the UI consumes. Constructed once in `TidelineApp.init` and passed down via
/// the environment.
///
/// Why this exists: SwiftUI's `.modelContainer(for:)` convenience modifier
/// creates a container the views can see, but our `CycleStore` needs to attach
/// to the *same* container instance. Building the container explicitly here
/// lets us hand it both to SwiftUI (via `.modelContainer(_:)`) and to the
/// store (via its `@ModelActor` init).
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let store: CycleStore
    let healthKit: HealthKitService
    let storeKit: StoreKitService
    /// Bumps on TZ change / midnight rollover — views key `.onChange(of:)`
    /// on `clock.tick` to refresh cached "today" / displayedMonth state.
    /// Task #110.
    let clock: RefreshClock

    init() {
        do {
            // Audit fix — bind the container to `SchemaV1` (versioned) +
            // `TidelineMigrationPlan` instead of the untracked positional
            // list. The plan is empty today (V1 is the only schema we've
            // ever shipped), but the type machinery is in place so future
            // V1→V2 transitions can ship as a real migration stage rather
            // than a destructive rebuild. See `Models/SchemaV1.swift`.
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TidelineMigrationPlan.self,
                configurations: []
            )
            self.modelContainer = container
            self.store = CycleStore(modelContainer: container)
            self.healthKit = HealthKitService()
            self.storeKit = StoreKitService()
            self.clock = RefreshClock()
        } catch {
            fatalError("Failed to construct ModelContainer: \(error)")
        }
    }

    /// Apply the persisted user-declared age band to the predictor's
    /// initial prior (task #97). MUST run before `store.loadAndReplay()`
    /// — otherwise the replay uses the default `.unspecified` prior and
    /// any band the user set on an earlier launch is silently lost.
    /// AppContainer can't do this in `init` because @ModelActor calls
    /// must `await`; the caller is `TidelineApp.task`, which awaits in
    /// sequence: primeFromUserDefaults → loadAndReplay.
    func primeFromUserDefaults() async {
        let raw = UserDefaults.standard.string(forKey: "userAgeBand")
            ?? AgeBand.unspecified.rawValue
        let band = AgeBand(rawValue: raw) ?? .unspecified
        await store.setAgeBand(band)
    }
}
