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

    init() {
        do {
            let container = try ModelContainer(
                for: Cycle.self, DayEntry.self, CycleEvent.self
            )
            self.modelContainer = container
            self.store = CycleStore(modelContainer: container)
            self.healthKit = HealthKitService()
        } catch {
            fatalError("Failed to construct ModelContainer: \(error)")
        }
    }
}
