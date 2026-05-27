import Foundation
import StoreKit
import Observation

/// Wraps StoreKit 2 for Tideline's single non-consumable "support" purchase.
///
/// **Generous-free model (R31, post-v2 reprioritization 2026-05-26):** the
/// entire app works without purchase. The IAP is framed as supporting
/// development — no feature gating exists. This service's responsibilities
/// are reduced to:
///   - Fetch product metadata for display (price + localized title)
///   - Perform purchase + handle `Transaction.updates`
///   - Restore-purchase path for reinstall / new device (iCloud Apple ID)
///   - Persist the "has supported" entitlement (UserDefaults; survives app
///     reinstall via App Store receipt restore, which is the source of truth)
///
/// `@MainActor` + `@Observable` so SwiftUI views react to `hasSupported`,
/// `isPurchasing`, and `lastError` changes without explicit binding.
///
/// **No telemetry.** No transaction data leaves the device beyond what
/// StoreKit itself sends to Apple's servers as part of the purchase flow.
/// Apple is the processor (CLAUDE.md compliant — no third-party SDKs).
@MainActor
@Observable
public final class StoreKitService {

    /// App Store Connect product identifier for the single non-consumable.
    /// Pricing tier 5 (~€4.99 per R1 decision).
    public static let productID = "com.carliderzerstoere.tideline.support"

    /// Persisted "has supported" cache key. Source of truth is the
    /// App Store receipt; this cache enables instant UI without re-querying
    /// `Transaction.currentEntitlements` on every view render.
    private static let entitlementKey = "tideline.hasSupported"

    public private(set) var product: Product?
    public private(set) var hasSupported: Bool
    public private(set) var isPurchasing: Bool = false
    public private(set) var lastError: StoreError?

    /// Background listener for cross-device transaction sync (user buys
    /// on another device with the same Apple ID, or Apple issues a refund).
    private var transactionListener: Task<Void, Never>?

    /// Transaction IDs we've already processed this session. StoreKit
    /// delivers each verified transaction twice — once via `purchase()`'s
    /// return value, once via `Transaction.updates`. Both code paths land
    /// in `processTransaction()`; without this set, `setSupported` writes
    /// UserDefaults twice and broadcasts `@Observable` change twice,
    /// causing SwiftUI to re-render `SupportSheet` redundantly.
    /// Cleared only by service deallocation — IDs are stable across the
    /// session, so per-session dedup is sufficient.
    private var processedTransactionIDs: Set<UInt64> = []

    public enum StoreError: Error, LocalizedError, Sendable, Equatable {
        case productUnavailable
        case purchaseFailed(String)
        case verificationFailed

        public var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return "Produkt momentan nicht verfügbar."
            case .purchaseFailed(let msg):
                return "Kauf fehlgeschlagen: \(msg)"
            case .verificationFailed:
                return "Transaktion konnte nicht verifiziert werden."
            }
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.hasSupported = userDefaults.bool(forKey: Self.entitlementKey)
        self.transactionListener = nil
        // **Deliberately lazy.** The Transaction.updates listener +
        // refreshEntitlement() call used to fire from init(), which on
        // a fresh simulator or a device with no Apple Account signed in
        // triggered the system "Sign in to Apple Account" prompt at app
        // launch. Tideline is generous-free — nobody should see an
        // Apple-Account nag just to use the app. StoreKit is now only
        // touched when the user opens SupportSheet (which calls
        // `loadProduct()` → `prepareIfNeeded()`). Owner-reported regression
        // 2026-05-26.
    }

    /// True once `prepareIfNeeded()` has set up the listener + done the
    /// initial entitlement refresh. Gates lazy init so repeated
    /// `loadProduct()` calls don't re-subscribe.
    private var hasPrepared: Bool = false

    private let userDefaults: UserDefaults

    // MARK: - Product loading

    /// Fetch product metadata from the App Store. Idempotent. Safe to call
    /// multiple times; updates `product` if successful, leaves it unchanged
    /// on failure (generous-free model — UI falls back to hardcoded price).
    ///
    /// Also performs the one-time StoreKit setup (Transaction.updates
    /// listener + initial entitlement refresh) on first call. This is the
    /// only entry point that should be touched from view code — calling
    /// it lazily from `SupportSheet.task` is what keeps the Apple-Account
    /// sign-in prompt off the launch path.
    public func loadProduct() async {
        await prepareIfNeeded()
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            // Product fetch failure is non-fatal under generous-free.
            // The SupportSheet displays a hardcoded fallback price.
        }
    }

    /// One-shot lazy initialisation: sets up the Transaction.updates
    /// listener and refreshes the cached entitlement against StoreKit's
    /// authoritative view. Idempotent (gated by `hasPrepared`). Called
    /// from `loadProduct()` and `restore()` — the two paths a user can
    /// reach SupportSheet through.
    private func prepareIfNeeded() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        transactionListener = makeTransactionListener()
        await refreshEntitlement()
    }

    // MARK: - Purchase

    /// Initiate purchase. No-op if no product loaded.
    /// Sets `isPurchasing = true` for the duration; UI binds to this for
    /// progress indication. Errors land on `lastError`.
    public func purchase() async {
        guard let product else {
            lastError = .productUnavailable
            return
        }
        // Clear any prior error before a fresh attempt so the SupportSheet
        // doesn't keep showing a stale red message after a successful retry.
        lastError = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                try await processTransaction(verification)
            case .userCancelled:
                // Silent — user dismissed sheet. Not an error.
                break
            case .pending:
                // Parental approval / SCA required. Transaction listener
                // will fire when resolved; no UI action needed here.
                break
            @unknown default:
                lastError = .purchaseFailed("Unbekanntes Ergebnis")
            }
        } catch {
            lastError = .purchaseFailed(error.localizedDescription)
        }
    }

    /// Restore previously purchased entitlement. Used when user reinstalls
    /// the app or signs into a new device with the same Apple ID.
    /// `AppStore.sync()` triggers a server-side refresh, then we iterate
    /// `currentEntitlements` to find our productID.
    public func restore() async {
        // Clear any prior error so a successful retry doesn't leave the
        // last failure message lingering in the UI.
        lastError = nil
        // Ensure the listener is alive before AppStore.sync() so we
        // catch any new transactions it surfaces.
        await prepareIfNeeded()
        do {
            try await AppStore.sync()
        } catch {
            lastError = .purchaseFailed(error.localizedDescription)
            return
        }
        await refreshEntitlement()
    }

    // MARK: - Internal

    /// Check `Transaction.currentEntitlements` for our product and update
    /// `hasSupported`. Called on launch + after restore + after refund.
    ///
    /// **Offline-safe semantics (reviewer audit 2026-05-26):** if iteration
    /// completes without observing ANY transaction for our productID, we
    /// leave cached state alone. This avoids the silent-revocation bug
    /// where an offline launch (no network → empty iteration) would clear
    /// a paying user's `hasSupported`. Apple's documented refund path
    /// yields the original transaction with `revocationDate` set, so we
    /// only downgrade on that explicit signal.
    private func refreshEntitlement() async {
        var observedOurProduct = false
        var stillEntitled = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result,
               transaction.productID == Self.productID {
                observedOurProduct = true
                if transaction.revocationDate == nil {
                    stillEntitled = true
                }
                // Don't break — keep iterating in case StoreKit yields the
                // refunded transaction after a newer non-revoked one.
            }
        }
        if observedOurProduct {
            setSupported(stillEntitled)
        }
        // else: offline / transient — keep cached state.
    }

    private func processTransaction(_ verification: VerificationResult<Transaction>) async throws {
        switch verification {
        case .verified(let transaction):
            // Dedup against the listener: a successful `purchase()` and a
            // `Transaction.updates` push both deliver the same verified
            // transaction. We must still call `finish()` on subsequent
            // deliveries (idempotent per Apple) but we can skip the
            // observable state writes to avoid redundant SwiftUI renders.
            let alreadyProcessed = processedTransactionIDs.contains(transaction.id)
            if !alreadyProcessed {
                processedTransactionIDs.insert(transaction.id)
                // Non-consumable: revocationDate != nil means refunded.
                if transaction.revocationDate == nil {
                    setSupported(true)
                } else {
                    setSupported(false)
                }
            }
            await transaction.finish()
        case .unverified:
            throw StoreError.verificationFailed
        }
    }

    private func setSupported(_ value: Bool) {
        hasSupported = value
        userDefaults.set(value, forKey: Self.entitlementKey)
    }

    /// Detached task that consumes `Transaction.updates` for the lifetime
    /// of the service. Handles cross-device purchases (same Apple ID) and
    /// Apple-issued refunds while the app is running.
    private func makeTransactionListener() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.processTransactionFromListener(result)
            }
        }
    }

    /// Hop back to MainActor + apply the verified transaction. Separate
    /// method to keep the listener `Task.detached` body small and avoid
    /// nested `MainActor.run { Task { ... } }` patterns.
    private func processTransactionFromListener(_ result: VerificationResult<Transaction>) async {
        try? await processTransaction(result)
    }

    // MARK: - Test surface

    /// Seed `lastError` from a test. Lets unit tests verify that a stale
    /// error is cleared before a fresh `purchase()` or `restore()` attempt
    /// — without that verification, a regression where a future refactor
    /// drops the `lastError = nil` line would silently re-introduce the
    /// "stale red message lingers after success" bug. Internal-only;
    /// production callers go through `purchase()` / `restore()`.
    internal func simulateError(_ error: StoreError) {
        self.lastError = error
    }

    /// Test-only inspector for the lazy-init gate. Returns true once
    /// `prepareIfNeeded()` has run. The Apple-Account-prompt-on-launch
    /// regression (owner-reported 2026-05-26) was caused by eager
    /// Transaction-listener setup in init(); we pin the lazy contract
    /// with `StoreKitServiceTests.lazyInitDoesNotTouchStoreKit`.
    internal var _testIsPrepared: Bool { hasPrepared }
}
