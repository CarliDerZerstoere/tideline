import Testing
import Foundation
@testable import Tideline

/// We can't drive `Product.purchase()` or `Transaction.updates` from a plain
/// unit-test target — those require StoreKitTest with a `.storekit`
/// configuration file attached to the test plan. (Worth doing before App
/// Store submission; out of scope for the Phase 2B pre-TestFlight cut.)
///
/// What we *can* test, and what these tests cover, are the pure decision
/// points that don't touch Apple's servers:
///
///   1. **Persistence round-trip** — `setSupported(true)` writes to
///      UserDefaults; a fresh instance reads it back as `hasSupported`.
///   2. **No-product purchase guard** — calling `purchase()` before
///      `loadProduct()` succeeded must set `lastError = .productUnavailable`
///      and never crash.
///   3. **StoreError surface** — every case yields a non-empty German
///      `errorDescription` (regression test: a future case that forgets to
///      add a message would silently surface as `nil` in SupportSheet UI).
///
/// Isolation: every test passes its own `UserDefaults(suiteName:)` so the
/// production `tideline.hasSupported` key in standard defaults is never
/// touched by the test process. (A leaked `true` value there would make
/// SupportSheet show the post-purchase state on the next dev run.)
@MainActor
@Suite("StoreKitService — pure decision points + persistence")
struct StoreKitServiceTests {

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "tideline.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Persistence round-trip

    @Test("Fresh service with empty defaults reports hasSupported = false")
    func freshDefaultsNotSupported() {
        let defaults = makeIsolatedDefaults()
        let service = StoreKitService(userDefaults: defaults)
        #expect(service.hasSupported == false)
    }

    @Test("Pre-seeded defaults hydrate hasSupported = true on init")
    func preSeededDefaultsHydrate() {
        let defaults = makeIsolatedDefaults()
        defaults.set(true, forKey: "tideline.hasSupported")
        let service = StoreKitService(userDefaults: defaults)
        #expect(service.hasSupported == true)
    }

    @Test("Service init does not crash on a fresh UserDefaults suite")
    func initSurvivesEmptyDefaults() {
        let defaults = makeIsolatedDefaults()
        _ = StoreKitService(userDefaults: defaults)
        // Reaching here without a crash is the assertion. Listener task is
        // spawned via Task.detached; the [weak self] reference means the
        // service is free to deallocate at the end of this test scope.
    }

    // MARK: - Purchase guard

    @Test("purchase() without a loaded product surfaces productUnavailable")
    func purchaseWithoutProductFails() async {
        let defaults = makeIsolatedDefaults()
        let service = StoreKitService(userDefaults: defaults)
        // No loadProduct() call → service.product is nil.
        await service.purchase()
        #expect(service.lastError == .productUnavailable)
        #expect(service.isPurchasing == false)
        #expect(service.hasSupported == false)
    }

    // MARK: - StoreError surface

    @Test("Every StoreError case yields a non-empty German errorDescription")
    func everyErrorHasGermanMessage() {
        let cases: [StoreKitService.StoreError] = [
            .productUnavailable,
            .purchaseFailed("dummy"),
            .verificationFailed,
        ]
        for c in cases {
            let desc = c.errorDescription
            #expect(desc != nil, "case \(c) has nil errorDescription")
            #expect(!(desc ?? "").isEmpty, "case \(c) has empty errorDescription")
        }
    }

    @Test("purchaseFailed embeds the underlying message")
    func purchaseFailedEmbedsMessage() {
        let err = StoreKitService.StoreError.purchaseFailed("Netzwerk weg")
        #expect(err.errorDescription?.contains("Netzwerk weg") == true)
    }

    @Test("StoreError is Equatable for SwiftUI binding diffing")
    func errorIsEquatable() {
        // SupportSheet uses `if let error = storeKit.lastError` — the
        // Observable runtime relies on Equatable to skip redundant view
        // updates. If a future refactor removes Equatable conformance
        // the UI will re-render on every event loop tick.
        #expect(StoreKitService.StoreError.productUnavailable
                == StoreKitService.StoreError.productUnavailable)
        #expect(StoreKitService.StoreError.purchaseFailed("a")
                != StoreKitService.StoreError.purchaseFailed("b"))
    }

    // MARK: - productID constant

    // MARK: - Lazy init (regression: Apple-Account prompt at launch)

    @Test("Init does NOT touch StoreKit — listener + entitlement refresh are lazy")
    func lazyInitDoesNotTouchStoreKit() async {
        // Owner-reported regression 2026-05-26: previous init() ran the
        // Transaction.updates listener setup + refreshEntitlement
        // synchronously, which triggered a "Sign in to Apple Account"
        // system prompt on app launch for users without a signed-in
        // Apple ID. Tideline is generous-free — nobody should see that
        // prompt unless they actively open SupportSheet.
        //
        // This test pins the contract: post-init, `hasPrepared` is false.
        // A future refactor that re-introduces eager listener setup will
        // fail this assertion before it reaches a user.
        let defaults = makeIsolatedDefaults()
        let service = StoreKitService(userDefaults: defaults)
        #expect(service._testIsPrepared == false,
                "StoreKit must not be touched until loadProduct()/restore() — see regression note")
    }

    @Test("loadProduct() flips the lazy-init gate")
    func loadProductPrepares() async {
        let defaults = makeIsolatedDefaults()
        let service = StoreKitService(userDefaults: defaults)
        #expect(service._testIsPrepared == false)
        await service.loadProduct()
        #expect(service._testIsPrepared == true)
    }

    @Test("productID matches the App Store Connect identifier")
    func productIDIsStable() {
        // Regression guard: a typo here breaks every running install at
        // once (StoreKit returns no product for the new ID). The string
        // must match what's configured in App Store Connect.
        #expect(StoreKitService.productID == "com.carliderzerstoere.tideline.support")
    }

    // MARK: - lastError lifecycle

    @Test("purchase() clears prior lastError before attempting")
    func purchaseClearsPriorError() async {
        let defaults = makeIsolatedDefaults()
        let service = StoreKitService(userDefaults: defaults)
        // Seed an error from a previous failed restore.
        await service.restore()  // will fail in unit-test env (no AppStore.sync)
        // Force a known error state.
        service.simulateError(.purchaseFailed("älterer Fehler"))
        #expect(service.lastError == .purchaseFailed("älterer Fehler"))

        // Now purchase() with no product should overwrite that error with
        // .productUnavailable — proving the old error didn't persist.
        await service.purchase()
        #expect(service.lastError == .productUnavailable)
    }

    @Test("restore() clears prior lastError before attempting")
    func restoreClearsPriorError() async {
        let defaults = makeIsolatedDefaults()
        let service = StoreKitService(userDefaults: defaults)
        service.simulateError(.purchaseFailed("vorheriger Fehler"))
        #expect(service.lastError != nil)

        // The actual AppStore.sync() call will fail in the unit-test
        // sandbox (no signed-in user), so lastError will end up as the
        // new failure — but the point is the OLD error doesn't linger
        // unchanged. Test: after restore(), lastError is either nil
        // (success — won't happen in test) OR a different error than
        // the seeded one.
        await service.restore()
        #expect(service.lastError != .purchaseFailed("vorheriger Fehler"))
    }
}
