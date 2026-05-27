import SwiftUI

/// Gate logic for the Resume-After-Pause sheet (task #74).
///
/// Pure function so the eligibility rules are unit-testable without spinning
/// up SwiftUI. See `docs/design/disrupted-cycles.md` § Resumption Flow for
/// the design rationale; defaults match the doc's >60-day threshold.
struct ResumeSheetGate {
    /// Show the Resume sheet iff:
    ///   1. `mode` is `.paused` (Category B). `.active` and `.retired` never trigger.
    ///   2. There is a `mostRecentBleedingDay` and it is *after* the pause
    ///      started. Stale bleeding from before the pause (e.g., the period
    ///      that preceded the user starting hormonal contraception) must
    ///      not trigger the sheet — otherwise a paused user with no fresh
    ///      logs would see this sheet pop every cooldown rollover.
    ///   3. The pause is at least `minPauseDuration` old. Defends against
    ///      lochia (postpartum bleeding up to ~6 weeks) auto-prompting.
    ///   4. Either no prior dismissal, or the dismissal is older than
    ///      `dismissCooldown`. "Später" buys a week of breathing room.
    static func shouldShow(
        mode: PredictorMode,
        mostRecentBleedingDay: Date?,
        dismissedAt: Date?,
        now: Date,
        minPauseDuration: TimeInterval = 60 * 86_400,
        dismissCooldown: TimeInterval = 7 * 86_400
    ) -> Bool {
        guard case .paused(_, let since, _) = mode else { return false }
        guard let bleed = mostRecentBleedingDay, bleed > since else { return false }
        guard now.timeIntervalSince(since) >= minPauseDuration else { return false }
        if let dismissedAt, now.timeIntervalSince(dismissedAt) < dismissCooldown {
            return false
        }
        return true
    }
}

/// Resume-After-Pause sheet. Surfaces when a Category-B paused user
/// (breastfeeding, hormonal contraception, hypothalamic amenorrhea)
/// logs bleeding again. Asks whether to restart predictions.
///
/// The sheet is purely presentational. The parent owns the
/// `addEvent(.resumeAfterPause)` call and the "Später" timestamp write,
/// using its `.sheet(isPresented:onDismiss:)` hook to discriminate the
/// confirmed-resume path from any other dismissal (including swipe-down).
///
/// **Deliberate v1 simplification:** `docs/design/disrupted-cycles.md`
/// § Resumption Flow specifies three options (fresh / from archived /
/// continue pause). We collapse to two because `.resumeAfterPause` already
/// soft-resets the archived posterior — μ is kept as a hint, κ/α/β reset.
/// A truly "fresh" path would also wipe μ, which we don't currently expose
/// and which Pillar 4 ("user is the authority on her own data") makes a
/// bit awkward to invent — μ is the user's data, not the app's. Re-open
/// the third option if user research surfaces a need.
struct ResumeAfterPauseSheet: View {
    let pauseReason: PauseReason
    let onResume: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headline
                    bodyCopy
                    Spacer(minLength: 12)
                    primaryButton
                    secondaryButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PageBackground.color(scheme: colorScheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var headline: some View {
        Text("Willkommen zurück")
            .tidelineSerifHeadline(size: 32, relativeTo: .largeTitle)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private var bodyCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Du hast deinen Zyklus seit \(Self.pauseReasonGenitive(pauseReason)) pausiert.")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Es sieht so aus, als wäre dein Zyklus wieder da. Möchtest du die Vorhersage neu starten?")
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private var primaryButton: some View {
        Button {
            onResume()
            dismiss()
        } label: {
            Text("Ja, neu lernen")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        // A11y sweep (audit fix #131): the styled button needs an explicit
        // hint because its visual primary-action affordance (gradient,
        // shadow) doesn't translate to VoiceOver.
        .accessibilityLabel("Ja, neu lernen")
        .accessibilityHint("Setzt die Zyklusvorhersage zurück und beginnt neu mit der aktuellen Periode.")
    }

    private var secondaryButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Später")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Später")
        .accessibilityHint("Schließt diesen Hinweis. Du wirst beim nächsten App-Start erneut gefragt.")
    }

    private static let coralGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.48, blue: 0.48), Color(red: 0.88, green: 0.38, blue: 0.38)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// German genitive ("seit der Stillzeit", "seit der hormonellen Verhütung").
    /// Separate from `TidelineHomeView.germanLabel(for: PauseReason)` because
    /// that one is nominative ("Stillzeit") and doesn't slot after "seit ___".
    static func pauseReasonGenitive(_ reason: PauseReason) -> String {
        switch reason {
        case .breastfeeding: return "der Stillzeit"
        case .hormonalContraception: return "der hormonellen Verhütung"
        case .hypothalamicAmenorrhea: return "der hypothalamischen Amenorrhoe"
        case .userInitiated: return "deiner Pause"
        }
    }
}

#Preview("Breastfeeding") {
    ResumeAfterPauseSheet(pauseReason: .breastfeeding, onResume: {})
}

#Preview("Hormonal contraception") {
    ResumeAfterPauseSheet(pauseReason: .hormonalContraception, onResume: {})
}
