import SwiftUI

/// Root-level container that gates app content behind first-launch
/// onboarding (task #76). Sibling pattern to `AppLockGate`:
/// `@AppStorage` flag drives pass-through vs. flow display, no
/// observable cost to users who've already onboarded.
///
/// **Composition order** (TidelineApp): this gate wraps `AppLockGate`,
/// because a brand-new install has no app-lock yet and no data to
/// protect. After `hasCompletedOnboarding` flips to true, `AppLockGate`
/// takes over with its own pass-through-when-disabled behaviour.
///
/// **Accessibility** (audit fix #131): this is a pure router — it has
/// no user-facing controls of its own. All a11y labelling lives in the
/// child (`OnboardingFlow` for the not-yet-onboarded path, or `content()`
/// thereafter). No `.accessibilityLabel` is required at this layer.
struct OnboardingGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        if hasCompletedOnboarding {
            content()
        } else {
            OnboardingFlow()
                .transition(.opacity)
        }
    }
}
