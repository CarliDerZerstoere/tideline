import Foundation
import os.signpost

/// Lightweight `os_signpost` plumbing so the calendar's hot paths show up
/// as distinct intervals in Instruments → "os_signpost" lane (or the
/// SwiftUI/Time Profiler templates' signpost track).
///
/// **How to capture a trace:**
///   1. Build the app for Release on device (a real iPhone, not the
///      simulator — debug builds add SwiftUI overhead that distorts the
///      relative cost of the candidate culprits below).
///   2. Xcode → Product → Profile (⌘I) → choose **Time Profiler**.
///   3. In Instruments, add the **os_signpost** lane (View → Add
///      Instrument). Filter on subsystem `com.tideline.perf`.
///   4. Hit record, exercise the lag: open the calendar, swipe months
///      back and forth a few times, tap a day, dismiss.
///   5. Inspect the signpost intervals:
///        - `reload` — total async refresh time after a sheet dismiss
///          or month change.
///        - `recomputePhases` — synchronous phase-grid computation on
///          the MainActor.
///        - `computeMensesEnd` — the all-history scan flagged by the
///          swift-expert review.
///        - `shiftMonth` — wall-clock between user swipe and grid swap.
///        - `tideTick` — fires once per `AmbientTideBackground` tick;
///          lets you read the actual TimelineView rate (claim: 10 fps).
///
/// If `recomputePhases` dominates → culprit #3 (window scoping) is real.
/// If `tideTick` exceeds ~10/sec or its surrounding paint cost is large
/// → culprit #1 (TideLinesShape.animatableData) is real.
/// If post-reload there are many short `body`-evaluation samples in the
/// Time Profiler without a corresponding signpost → culprit #2 (state
/// batching) is real.
///
/// All signposts are no-ops in Release with `RELEASE_NO_SIGNPOSTS` set,
/// but we leave them in by default so the next profiling pass is a
/// recompile away.
enum PerfSignpost {
    static let log = OSLog(subsystem: "com.tideline.perf", category: "calendar")

    /// Synchronous wrap for hot paths that don't await.
    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try body()
    }

    /// Manual begin/end pair for async functions. Swift 6 strict
    /// concurrency makes the closure-wrapping `async` variant awkward
    /// (the captured-self closure needs to be Sendable when crossing the
    /// actor boundary of the helper), so we expose primitives instead.
    /// Usage:
    /// ```
    /// let id = PerfSignpost.begin("reload")
    /// defer { PerfSignpost.end("reload", id: id) }
    /// ```
    @inline(__always)
    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    @inline(__always)
    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    /// Point-in-time event marker (no duration). Use for tick-rate
    /// measurements like the ambient TimelineView.
    @inline(__always)
    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
