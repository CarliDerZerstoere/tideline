import SwiftUI
import SwiftData

@main
struct TidelineApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.cycleStore, container.store)
                .environment(\.healthKitService, container.healthKit)
                .task {
                    await container.store.loadAndReplay()
                }
        }
        .modelContainer(container.modelContainer)
    }
}

// MARK: - Environment plumbing

private struct CycleStoreKey: EnvironmentKey {
    static let defaultValue: CycleStore? = nil
}

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: HealthKitService? = nil
}

extension EnvironmentValues {
    var cycleStore: CycleStore? {
        get { self[CycleStoreKey.self] }
        set { self[CycleStoreKey.self] = newValue }
    }
    var healthKitService: HealthKitService? {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }
}
