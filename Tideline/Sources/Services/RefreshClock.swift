import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Bumps `tick` whenever iOS fires `significantTimeChangeNotification`
/// — Apple's documented signal for "timezone changed OR clock crossed
/// midnight." Views that hold cached "today" or `displayedMonth` state
/// observe `tick` via `.onChange(of: clock.tick)` and refresh.
///
/// **Why a single shared clock instead of per-view observers:**
/// 3-way duplication (CalendarSheet / TidelineHomeView / MyCycleSheet)
/// would mean a future view addition silently misses the refresh path.
/// Centralised here = one wire to remember.
///
/// **Why @Observable, not Combine:** matches the existing service
/// pattern in `AppContainer` (`StoreKitService`, etc.) and integrates
/// natively with SwiftUI's `.onChange` without `@Published`.
///
/// **Lifetime:** owned by `AppContainer`; lives for the app process.
/// The notification observer is removed in `deinit` defensively, though
/// in practice the singleton outlives the process.
@MainActor
@Observable
public final class RefreshClock {

    /// Increments each time the OS reports a significant time change.
    /// Views key their `.onChange` modifiers on this. Initial value 0;
    /// monotonically increasing (with `&+=` overflow wrap for safety).
    public private(set) var tick: Int = 0

    public init() {
        #if canImport(UIKit)
        // `UIApplication.significantTimeChangeNotification` fires on:
        //   - User changes timezone (manually or auto via location)
        //   - Clock crosses midnight in the device's current timezone
        //   - User toggles 12h/24h time
        // We forward all of these as a single "refresh" signal — the
        // views don't care which trigger fired, only that "today" might
        // have moved.
        //
        // We intentionally discard the returned observer token. The
        // closure is retained internally by NotificationCenter for as
        // long as `self` lives; `self` lives for the app-process
        // lifetime (held by `AppContainer`). Swift 6 strict concurrency
        // forbids accessing MainActor state from a nonisolated deinit,
        // so explicit removal in deinit isn't possible. The
        // process-termination cleanup the OS does is sufficient.
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification arrives on the main thread per the queue
            // parameter, so MainActor isolation is preserved.
            MainActor.assumeIsolated {
                self?.tick &+= 1
            }
        }
        #endif
    }

    /// Test surface: lets unit tests simulate a time change without
    /// requiring UIKit's real notification to fire. Internal-only;
    /// production callers should never need to bump the tick directly.
    internal func _testBump() {
        tick &+= 1
    }
}
