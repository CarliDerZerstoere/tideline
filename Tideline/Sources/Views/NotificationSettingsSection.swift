import SwiftUI
import UIKit

/// Settings section for the notification scaffolding (task #85).
///
/// Mirrors `AppLockSettingsSection` shape:
///   - Master toggle bound to `@AppStorage("notificationsMasterEnabled")`.
///   - On toggle ON, request iOS permission if `.notDetermined`.
///   - On `.denied`, the toggle disables itself and surfaces a deep-link
///     to Tideline's notification page in iOS Settings.
///   - Re-polls authorization on scenePhase `.active` so iOS-Settings
///     changes made while the app was backgrounded surface immediately.
///
/// CLAUDE.md hard rules respected at this layer:
///   - Master toggle is **opt-in, default OFF** (pillar 5: don't push
///     notifications on users who haven't asked for them).
///   - All notification *content* sent through `NotificationService`
///     uses `makePrivacyContent`, which enforces the lockscreen-safe
///     title/body — that's a service-level invariant, not surfaced here.
struct NotificationSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("notificationsMasterEnabled") private var enabled: Bool = false

    @State private var authStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var hasLoaded: Bool = false
    @State private var inFlight: Bool = false

    private let service = NotificationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mitteilungen")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: toggleBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mitteilungen aktivieren")
                            .font(.system(size: 15, weight: .semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!hasLoaded || inFlight || authStatus == .denied)
                .padding(.vertical, 4)
                // A11y sweep (audit fix #131): VoiceOver gets a single
                // utterance covering both the action and the current iOS
                // permission state — otherwise the secondary subtitle
                // (which mutates with auth status) reads as a separate
                // disconnected message.
                .accessibilityLabel("Mitteilungen aktivieren. \(subtitle)")
                // When iOS-denied, the toggle is disabled and a deep-link
                // appears underneath. Point VoiceOver users at the deep
                // link so they don't get stuck on the disabled toggle.
                .accessibilityHint(authStatus == .denied
                    ? "Mitteilungen sind in den iPhone-Einstellungen deaktiviert. Tippe auf 'In iPhone-Einstellungen öffnen' unten, um sie wieder zuzulassen."
                    : "Wenn aktiviert, schickt Tideline lokal generierte Erinnerungen zu Zykluskontrolle und späten Perioden."
                )

                if authStatus == .denied {
                    Divider()
                        .padding(.vertical, 10)
                    deniedFooter
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
        }
        .task {
            await refreshAuthStatus()
            hasLoaded = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            // iOS-Settings changes made while we were backgrounded are
            // only visible after a re-poll on .active.
            if newPhase == .active {
                Task { await refreshAuthStatus() }
            }
        }
    }

    // MARK: - Subtitle copy

    private var subtitle: String {
        switch authStatus {
        case .authorized, .provisional, .ephemeral:
            return "Erinnerungen für Zyklusphasen und Zyklusereignisse — lokal generiert, ohne Cloud."
        case .denied:
            return "Du hast Mitteilungen für Tideline in den iPhone-Einstellungen deaktiviert."
        case .notDetermined, .unknown:
            return "Erinnerungen für Zyklusphasen und Zyklusereignisse — lokal generiert, ohne Cloud."
        }
    }

    // MARK: - Denied footer

    @ViewBuilder
    private var deniedFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button {
                openSystemSettings()
            } label: {
                Text("In iPhone-Einstellungen öffnen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Binding

    /// Custom setter so a user-flip can trigger the async permission
    /// request without an `.onChange` (which can't reliably distinguish
    /// user-tap from programmatic init — same rationale documented in
    /// `CycleIrregularitySection`).
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { enabled && (authStatus == .authorized || authStatus == .provisional || authStatus == .ephemeral) },
            set: { newValue in
                Task { await handleToggleFlip(to: newValue) }
            }
        )
    }

    // MARK: - Effects

    private func refreshAuthStatus() async {
        authStatus = await service.authorizationStatus()
        // If iOS denied permission since last we checked, force the
        // AppStorage flag off so the in-app state matches reality.
        // The toggleBinding's get also defends against this, but a
        // direct AppStorage write keeps things consistent for other
        // readers (notification schedulers consult AppStorage too).
        if authStatus == .denied && enabled {
            enabled = false
            await service.cancelAll()
        }
    }

    private func handleToggleFlip(to newValue: Bool) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        if newValue {
            // User flipped ON. Path depends on current iOS state.
            switch authStatus {
            case .notDetermined:
                let result = await service.requestAuthorization()
                authStatus = result
                if result == .authorized || result == .provisional || result == .ephemeral {
                    enabled = true
                } else {
                    enabled = false
                }
            case .authorized, .provisional, .ephemeral:
                enabled = true
            case .denied:
                // Permission was revoked since we last checked. Cannot
                // flip on without iOS Settings; toggle stays disabled
                // and the denied footer is already showing.
                enabled = false
            case .unknown:
                enabled = false
            }
        } else {
            // User flipped OFF. Honour it immediately + cancel pending
            // work so nothing fires against a now-disabled preference.
            enabled = false
            await service.cancelAll()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
