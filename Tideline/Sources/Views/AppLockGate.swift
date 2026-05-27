import SwiftUI

/// Root-level container that gates app content behind the optional app-lock.
///
/// Responsibilities:
///   1. Owns the `isUnlocked` state and the `lastBackgroundedAt` timestamp.
///   2. Reads `@AppStorage("appLockEnabled")` and `@AppStorage("appLockTimeoutSeconds")` so
///      the settings UI can flip them and we react.
///   3. Triggers authentication on cold start, and on foreground if the
///      backgrounded interval exceeded the configured timeout.
///   4. Shows the `PrivacyOverlay` whenever the scene goes `.inactive` and
///      the lock is enabled (prevents app-switcher data leak).
///
/// Pass-through behaviour when `appLockEnabled == false`: content renders as
/// normal, no auth, no overlay. The feature truly does not affect users who
/// haven't opted in.
struct AppLockGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @AppStorage("appLockTimeoutSeconds") private var appLockTimeoutSeconds: Int = 0

    @State private var isUnlocked: Bool = false
    @State private var lastBackgroundedAt: Date? = nil
    @State private var capability: AppLockCapability = .none
    @State private var lastError: String? = nil
    @State private var isAuthenticating: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    private let service = AppLockService()

    var body: some View {
        ZStack {
            content()

            // PrivacyOverlay sits ABOVE the content but BELOW the lock view.
            // It's only visible while .inactive (and only when the lock is on).
            if appLockEnabled && scenePhase != .active {
                PrivacyOverlay()
                    .zIndex(1)
            }

            if appLockEnabled && !isUnlocked {
                AppLockView(
                    capability: capability,
                    lastError: lastError,
                    onUnlockTap: { Task { await tryAuthenticate(reason: "Tideline entsperren") } }
                )
                .zIndex(2)
                .transition(.opacity)
            }
        }
        .task {
            capability = service.capability()
            if appLockEnabled {
                // Cold start with lock on → prompt immediately.
                await tryAuthenticate(reason: "Tideline entsperren")
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onChange(of: appLockEnabled) { _, enabled in
            // Settings toggled at runtime. If turned off, instantly unlock.
            // If turned on, the settings flow already auth'd to confirm, so
            // we stay unlocked here — the next backgrounding will re-lock.
            if !enabled {
                isUnlocked = true
                lastError = nil
            }
        }
    }

    // MARK: - Scene phase

    private func handleScenePhase(_ newPhase: ScenePhase) {
        guard appLockEnabled else { return }
        switch newPhase {
        case .background:
            lastBackgroundedAt = .now
        case .active:
            // Re-lock if the timeout has elapsed since we backgrounded.
            // We MUST clear `lastBackgroundedAt` after evaluating, otherwise
            // a subsequent `.inactive → .active` transition (e.g. control
            // centre peek, incoming call) would re-evaluate the stale
            // timestamp and — with timeoutSeconds == 0, the default — keep
            // re-locking on every transient overlay.
            if let bgAt = lastBackgroundedAt {
                let elapsed = Date.now.timeIntervalSince(bgAt)
                lastBackgroundedAt = nil
                if elapsed >= Double(appLockTimeoutSeconds) {
                    isUnlocked = false
                    lastError = nil
                    Task { await tryAuthenticate(reason: "Tideline entsperren") }
                }
            }
        case .inactive:
            // Don't change lock state here — `.inactive` fires for transient
            // overlays (control center peek, incoming call) where we should
            // not force a re-auth.
            break
        @unknown default:
            break
        }
    }

    // MARK: - Auth

    private func tryAuthenticate(reason: String) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let result = await service.authenticate(reason: reason)
        switch result {
        case .success:
            withAnimation(.easeOut(duration: 0.2)) {
                isUnlocked = true
                lastError = nil
            }
        case .userCancelled:
            // Stay locked; user can tap Entsperren again.
            lastError = nil
        case .failed:
            lastError = "Authentifizierung fehlgeschlagen — erneut versuchen."
        case .unavailable:
            // Device authentication is unavailable (passcode disabled, biometric
            // not enrolled, etc.). The previous behaviour here was to defensively
            // UNLOCK so the user wasn't bricked, but that violates Pillar 1: a
            // user who opted into App-Lock explicitly chose privacy over
            // convenience. Silently exposing their cycle data when device
            // capability regresses is wrong.
            //
            // Fail-closed: stay locked, show a clear recovery path. The user
            // can either re-enable their device passcode/biometric in iOS
            // Settings (then return — the next scene-active will re-prompt)
            // or disable Tideline app-lock from device-Settings → Tideline
            // path. There is no in-app override because doing so would
            // require trusting an actor who has already proven they can't
            // authenticate.
            //
            // Recovery-path note: going to Settings.app DOES background
            // Tideline → on return `handleScenePhase(.active)` runs with a
            // non-nil `lastBackgroundedAt`, so `tryAuthenticate` re-fires
            // and picks up the new device-auth capability. No additional
            // poll needed.
            lastError = "Geräte-Authentifizierung ist nicht verfügbar. Bitte aktiviere einen Geräte-Code oder Face ID in den iPhone-Einstellungen."
            isUnlocked = false
        }
    }
}
