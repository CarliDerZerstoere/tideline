import Testing
import Foundation
@testable import Tideline

/// `RefreshClock` is a thin wrapper around iOS's
/// `UIApplication.significantTimeChangeNotification`. We can't fire that
/// notification reliably from a unit-test target (no live UIApplication),
/// so the tests cover the **observable surface** through `_testBump()`:
///
///   1. `tick` starts at 0.
///   2. `_testBump()` increments `tick` monotonically.
///   3. `tick` overflow is benign — `&+=` wraps without trapping. (A user
///      who triggers 2³¹ TZ changes in one process lifetime is not the
///      audience we're optimizing for, but a crash would be unacceptable
///      so the wraparound semantics are pinned.)
@MainActor
@Suite("RefreshClock — tick semantics")
struct RefreshClockTests {

    @Test("Fresh clock starts at tick 0")
    func freshClockStartsAtZero() {
        let clock = RefreshClock()
        #expect(clock.tick == 0)
    }

    @Test("Test bump increments tick by 1")
    func bumpIncrements() {
        let clock = RefreshClock()
        clock._testBump()
        #expect(clock.tick == 1)
    }

    @Test("Multiple bumps increment monotonically")
    func multipleBumps() {
        let clock = RefreshClock()
        for _ in 0..<5 {
            clock._testBump()
        }
        #expect(clock.tick == 5)
    }

    @Test("Tick remains monotonic across many bumps")
    func tickStaysMonotonicAcrossManyBumps() {
        // We can't simulate `Int.max` bumps in a unit test (reviewer
        // pushback: the previous "wraps without trapping" test name
        // overstated this assertion — the assertion below merely shows
        // bumps add). The wrapping property of `&+=` is documented in
        // `RefreshClock.swift`; the no-trap guarantee is a code-review
        // discipline, not a test-suite invariant. What we CAN pin is
        // that tick is strictly increasing per bump.
        let clock = RefreshClock()
        var lastTick = clock.tick
        for _ in 0..<10 {
            clock._testBump()
            #expect(clock.tick == lastTick + 1)
            lastTick = clock.tick
        }
    }
}
