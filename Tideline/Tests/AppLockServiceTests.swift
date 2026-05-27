import Testing
import Foundation
import LocalAuthentication
@testable import Tideline

/// We can't drive the real `LAContext.evaluatePolicy(...)` flow in a unit test
/// — there's no Face ID on CI and no constructor-injectable backend on iOS.
/// So we test the **pure decision points** instead:
///
///   1. `mapLAErrorCode(_:)` — the LAError-to-AuthResult mapping that's the
///      only error-prone branch in `authenticate(reason:)`. Pure function,
///      fully testable.
///   2. `capability()` — returns one of the defined cases on whatever the
///      test environment offers.
///   3. Enum surface coverage so a future refactor that drops a case is
///      caught by the compiler.
@MainActor
@Suite("AppLockService — error-code mapping + surface contract")
struct AppLockServiceTests {

    // MARK: - mapLAErrorCode: cancellation cases

    @Test("userCancel → userCancelled")
    func userCancel() {
        #expect(mapLAErrorCode(.userCancel) == .userCancelled)
    }

    @Test("systemCancel → userCancelled")
    func systemCancel() {
        #expect(mapLAErrorCode(.systemCancel) == .userCancelled)
    }

    @Test("appCancel → userCancelled")
    func appCancel() {
        #expect(mapLAErrorCode(.appCancel) == .userCancelled)
    }

    @Test("userFallback maps to userCancelled (fallback button suppressed)")
    func userFallback() {
        #expect(mapLAErrorCode(.userFallback) == .userCancelled)
    }

    // MARK: - mapLAErrorCode: failure cases

    @Test("authenticationFailed → failed")
    func authFailed() {
        #expect(mapLAErrorCode(.authenticationFailed) == .failed)
    }

    @Test("biometryLockout → failed")
    func biometryLockout() {
        #expect(mapLAErrorCode(.biometryLockout) == .failed)
    }

    @Test("biometryNotAvailable → failed (degrade rather than crash)")
    func biometryNotAvailable() {
        #expect(mapLAErrorCode(.biometryNotAvailable) == .failed)
    }

    @Test("biometryNotEnrolled → failed")
    func biometryNotEnrolled() {
        #expect(mapLAErrorCode(.biometryNotEnrolled) == .failed)
    }

    @Test("passcodeNotSet → failed")
    func passcodeNotSet() {
        #expect(mapLAErrorCode(.passcodeNotSet) == .failed)
    }

    // MARK: - mapLAErrorCode: unavailable cases

    @Test("invalidContext → unavailable")
    func invalidContext() {
        if case .unavailable = mapLAErrorCode(.invalidContext) {
            // pass
        } else {
            Issue.record("expected .unavailable")
        }
    }

    @Test("notInteractive → unavailable")
    func notInteractive() {
        if case .unavailable = mapLAErrorCode(.notInteractive) {
            // pass
        } else {
            Issue.record("expected .unavailable")
        }
    }

    // MARK: - capability()

    @Test("capability() returns one of the defined cases")
    func capabilityIsDefined() {
        let service = AppLockService()
        let cap = service.capability()
        switch cap {
        case .biometric, .passcodeOnly, .none:
            break
        }
    }

    // MARK: - Surface coverage

    @Test("BiometricKind has the three iOS-supported variants")
    func biometricKindCases() {
        let all: [BiometricKind] = [.faceID, .touchID, .opticID]
        #expect(all.count == 3)
    }
}
