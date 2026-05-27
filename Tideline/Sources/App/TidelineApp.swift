import SwiftUI
import SwiftData

@main
struct TidelineApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            // Onboarding wraps AppLock because a brand-new install has no
            // app-lock yet and no data to protect. After onboarding flips
            // `hasCompletedOnboarding`, AppLockGate takes over with normal
            // pass-through (lock is opt-in, default off). Task #76.
            OnboardingGate {
                AppLockGate {
                    RootView()
                        .task {
                            // Task #97 — prime the predictor with the
                            // user's declared age band before replay.
                            // The order matters: setAgeBand swaps in a
                            // fresh predictor with the right prior,
                            // then loadAndReplay applies observations
                            // against it.
                            await container.primeFromUserDefaults()
                            await container.store.loadAndReplay()
                        }
                }
            }
            // Inject at the outermost level so both onboarding (HK import
            // offer + initial period seed) and RootView see the same
            // services. SwiftUI inherits environment down the tree —
            // the previous inner re-injection was dead code.
            .environment(\.cycleStore, container.store)
            .environment(\.healthKitService, container.healthKit)
            .environment(\.storeKitService, container.storeKit)
            .environment(\.refreshClock, container.clock)
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

private struct StoreKitServiceKey: EnvironmentKey {
    static let defaultValue: StoreKitService? = nil
}

private struct RefreshClockKey: EnvironmentKey {
    static let defaultValue: RefreshClock? = nil
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
    var storeKitService: StoreKitService? {
        get { self[StoreKitServiceKey.self] }
        set { self[StoreKitServiceKey.self] = newValue }
    }
    var refreshClock: RefreshClock? {
        get { self[RefreshClockKey.self] }
        set { self[RefreshClockKey.self] = newValue }
    }
}
