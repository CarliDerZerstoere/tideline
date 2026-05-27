import Foundation
import LocalAuthentication

/// Wraps `LAContext` for the app-lock feature.
///
/// Uses `LAPolicy.deviceOwnerAuthentication` so iOS handles the
/// biometric-then-passcode fallback internally — we don't need to chain two
/// policies ourselves. The user gets Face ID (or Touch ID) first; if it
/// fails or isn't enrolled, iOS shows its own passcode sheet.
///
/// `@MainActor` because `LAContext` callbacks come back on whatever queue
/// they want — we always hop back to main before publishing state.
@MainActor
final class AppLockService {

    /// Probe what's currently available on the device.
    func capability() -> AppLockCapability {
        let ctx = LAContext()
        var error: NSError?

        // .deviceOwnerAuthentication is what we actually use at runtime; check
        // it first so we get a single yes/no on "can the user auth at all".
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .none
        }

        // If biometrics specifically are available, surface which kind so the
        // UI can pick the right icon (face/finger). If not, the device has a
        // passcode but no biometric — still usable.
        var biometricError: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError) {
            switch ctx.biometryType {
            case .faceID:  return .biometric(.faceID)
            case .touchID: return .biometric(.touchID)
            case .opticID: return .biometric(.opticID)
            case .none:    return .passcodeOnly
            @unknown default: return .passcodeOnly
            }
        }

        return .passcodeOnly
    }

    /// Request authentication. Returns once the user has either succeeded,
    /// cancelled, or iOS gives up.
    ///
    /// `reason` is the localized string iOS shows on the Face ID / passcode
    /// sheet. Must be human-readable; iOS displays it.
    func authenticate(reason: String) async -> AuthResult {
        // Fresh context per request: LAContext caches successful evaluations
        // for ~30 s, and reusing one across calls would let a previous
        // success silently re-unlock without prompting.
        let ctx = LAContext()
        ctx.localizedFallbackTitle = ""  // hide the "Enter Password" button on the biometric sheet; iOS provides the passcode flow via the policy fallback

        var canEvaluateError: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            return .unavailable(canEvaluateError)
        }

        do {
            let success = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success : .failed
        } catch let laError as LAError {
            return mapLAErrorCode(laError.code)
        } catch {
            return .unavailable(error as NSError)
        }
    }
}

/// What authentication methods this device currently supports.
enum AppLockCapability: Equatable {
    case biometric(BiometricKind)
    case passcodeOnly
    case none
}

enum BiometricKind: Equatable {
    case faceID
    case touchID
    case opticID
}

/// Outcome of one auth attempt.
enum AuthResult: Equatable {
    case success
    case userCancelled
    case failed
    case unavailable(Error?)

    static func == (lhs: AuthResult, rhs: AuthResult) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success), (.userCancelled, .userCancelled), (.failed, .failed):
            return true
        case (.unavailable, .unavailable):
            return true
        default:
            return false
        }
    }
}

/// Pure mapping function from an `LAError.Code` to our `AuthResult`. Lives
/// outside `authenticate(reason:)` so it can be unit-tested without
/// constructing an LAContext or running a real auth flow.
@MainActor
func mapLAErrorCode(_ code: LAError.Code) -> AuthResult {
    switch code {
    case .userCancel, .systemCancel, .appCancel, .userFallback:
        return .userCancelled
    case .authenticationFailed, .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
        return .failed
    case .invalidContext, .notInteractive:
        return .unavailable(LAError(code))
    default:
        return .failed
    }
}
