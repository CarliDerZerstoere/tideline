import SwiftUI

/// Static lock screen. Shown by `AppLockGate` whenever the app is locked.
/// No data, no tab bar, no peek of content — just the wordmark, the
/// capability-appropriate icon, and an Entsperren button.
///
/// All authentication logic lives in the parent (`AppLockGate`) via
/// `AppLockService`. This view just renders state and reports tap intent.
struct AppLockView: View {
    let capability: AppLockCapability
    let lastError: String?
    let onUnlockTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PageBackground.color(scheme: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("Tideline")
                    .font(.system(size: 44, weight: .bold, design: .serif).italic())
                    .foregroundStyle(Color.primary)

                Image(systemName: lockIcon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                if let lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                Spacer()

                Button(action: onUnlockTap) {
                    HStack(spacing: 8) {
                        Image(systemName: lockIcon)
                            .font(.system(size: 17, weight: .semibold))
                        Text("Entsperren")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color(red: 0.91, green: 0.44, blue: 0.44))
                    )
                    .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.30), radius: 12, y: 4)
                }
                .accessibilityLabel("Tideline mit \(authMethodName) entsperren")
                .accessibilityHint("Deine Zyklusdaten sind privat und werden erst nach erfolgreicher Authentifizierung angezeigt.")
                .padding(.bottom, 64)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tideline gesperrt")
    }

    private var authMethodName: String {
        switch capability {
        case .biometric(.faceID):  return "Face ID"
        case .biometric(.touchID): return "Touch ID"
        case .biometric(.opticID): return "Optic ID"
        case .passcodeOnly:        return "Code"
        case .none:                return "Code"
        }
    }

    private var lockIcon: String {
        switch capability {
        case .biometric(.faceID):  return "faceid"
        case .biometric(.touchID): return "touchid"
        case .biometric(.opticID): return "opticid"
        case .passcodeOnly, .none: return "lock.fill"
        }
    }
}

#Preview("Face ID") {
    AppLockView(capability: .biometric(.faceID), lastError: nil, onUnlockTap: {})
}

#Preview("Passcode + error") {
    AppLockView(capability: .passcodeOnly, lastError: "Authentifizierung fehlgeschlagen — erneut versuchen", onUnlockTap: {})
}
