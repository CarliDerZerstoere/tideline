import SwiftUI

/// Cream background + Tideline wordmark, shown over the app's root content
/// whenever the scene phase is `.inactive` and the app-lock is enabled.
///
/// Why this exists: iOS captures a snapshot of every app when it transitions
/// to background — that snapshot is what the app-switcher shows. If a user
/// flicks open the switcher while Tideline is unlocked, cycle data is
/// briefly visible in the preview. Covering the content during `.inactive`
/// (which fires *before* `.background`) ensures the snapshot iOS captures
/// is this neutral cover instead of the real data.
struct PrivacyOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PageBackground.color(scheme: colorScheme)
                .ignoresSafeArea()

            Text("Tideline")
                .font(.system(size: 44, weight: .bold, design: .serif).italic())
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }
}
