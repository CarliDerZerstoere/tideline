import SwiftUI

/// Settings UI for the optional app-lock.
///
/// Lives inside `MoreSettingsSheet`. On its own here so other settings sheets
/// (e.g. Mein Zyklus settings) can also embed it if needed.
///
/// Critical UX rule: turning the toggle ON or OFF triggers an immediate auth
/// challenge. This serves two purposes:
///   1. Activation: confirms the device can actually auth — prevents the user
///      from locking themselves out if e.g. Face ID is misconfigured.
///   2. Deactivation: prevents someone with short physical access to an
///      unlocked phone from silently disabling the lock.
struct AppLockSettingsSection: View {
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @AppStorage("appLockTimeoutSeconds") private var appLockTimeoutSeconds: Int = 0

    @State private var capability: AppLockCapability = .none
    @State private var inFlight: Bool = false
    @State private var lastError: String? = nil

    private let service = AppLockService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App-Sperre")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { appLockEnabled },
                    set: { newValue in toggleRequested(newValue) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toggleTitle)
                            .font(.system(size: 15, weight: .semibold))
                        if capability == .none {
                            Text("Stelle in den iOS-Einstellungen einen Code oder Face ID ein, um die App-Sperre zu aktivieren.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(capabilitySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(capability == .none || inFlight)
                .padding(.vertical, 4)
                // A11y sweep (audit fix #131): one accessible utterance for
                // the toggle, capability-aware so VoiceOver users hear the
                // same context the sighted label provides.
                .accessibilityLabel("\(toggleTitle). \(capability == .none ? "Stelle in den iOS-Einstellungen einen Code oder Face ID ein, um die App-Sperre zu aktivieren." : capabilitySubtitle)")

                if appLockEnabled {
                    Divider().padding(.vertical, 8)
                    timeoutPicker
                }

                if let lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(.top, 8)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .task {
            capability = service.capability()
        }
    }

    // MARK: - Sub-views

    private var timeoutPicker: some View {
        HStack {
            Text("Sperren")
                .font(.system(size: 15))
            Spacer()
            Picker("", selection: $appLockTimeoutSeconds) {
                Text("Sofort").tag(0)
                Text("Nach 1 Minute").tag(60)
                Text("Nach 5 Minuten").tag(300)
                Text("Nach 15 Minuten").tag(900)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    // MARK: - Strings

    private var toggleTitle: String {
        switch capability {
        case .biometric(.faceID):  return "App-Sperre mit Face ID"
        case .biometric(.touchID): return "App-Sperre mit Touch ID"
        case .biometric(.opticID): return "App-Sperre mit Optic ID"
        case .passcodeOnly:        return "App-Sperre mit Code"
        case .none:                return "App-Sperre"
        }
    }

    private var capabilitySubtitle: String {
        switch capability {
        case .biometric: return "Tideline fragt beim Öffnen nach deiner Biometrie. Daten bleiben unsichtbar bis du entsperrst."
        case .passcodeOnly: return "Tideline fragt beim Öffnen nach dem Gerätecode."
        case .none: return ""
        }
    }

    // MARK: - Toggle flow

    private func toggleRequested(_ newValue: Bool) {
        // Both activation and deactivation require successful auth first.
        // If the user cancels, we don't apply the change.
        guard capability != .none else { return }
        guard !inFlight else { return }
        inFlight = true
        lastError = nil

        let reason = newValue
            ? "App-Sperre aktivieren"
            : "App-Sperre deaktivieren"

        Task { @MainActor in
            let result = await service.authenticate(reason: reason)
            inFlight = false
            switch result {
            case .success:
                appLockEnabled = newValue
            case .userCancelled:
                // No state change; toggle visually returns because we never set it.
                break
            case .failed:
                lastError = "Authentifizierung fehlgeschlagen."
            case .unavailable:
                lastError = "Authentifizierung gerade nicht möglich."
            }
        }
    }
}
