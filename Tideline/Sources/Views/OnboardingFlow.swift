import SwiftUI

/// First-launch onboarding flow (task #76). 5-step state machine:
///   privacy → lastPeriod → tracking → healthKit (offer) → finish
///
/// On finish:
///   1. Persists tracking-preference toggles to @AppStorage
///   2. If user provided a period date, awaits `store.startPeriod(on:)`
///   3. Flips `hasCompletedOnboarding = true` → `OnboardingGate` swaps
///      in `AppLockGate { RootView() }` and the flow tears down.
///
/// Per CLAUDE.md pillars: no account creation, no premium upsell, no
/// social syncing, no telemetry. All copy is German (DACH-first launch).
struct OnboardingFlow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cycleStore) private var store

    @State private var step: OnboardingStep = .privacy
    @State private var lastPeriodSelection: LastPeriodChoice? = nil
    @State private var lastPeriodDate: Date = Date.now.addingDays(-14)
    @State private var trackMood: Bool = false
    @State private var trackSymptoms: Bool = false
    @State private var trackNotes: Bool = false
    @State private var showHKImport: Bool = false
    @State private var isFinishing: Bool = false
    /// Task #97 — locally selected age band. `.unspecified` is the
    /// default + the "Lieber nicht angeben" explicit-decline option;
    /// persisted to AppStorage only at `finish()` so the user can
    /// back out without leaving a trace.
    @State private var ageBandSelection: AgeBand = .unspecified

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage(TrackingPreferences.moodEnabledKey) private var persistedMood: Bool = false
    @AppStorage(TrackingPreferences.symptomsEnabledKey) private var persistedSymptoms: Bool = false
    @AppStorage(TrackingPreferences.notesEnabledKey) private var persistedNotes: Bool = false
    @AppStorage("userAgeBand") private var persistedAgeBand: String = AgeBand.unspecified.rawValue

    // Wave-B fix (4.4): step order reflows so the calibration question
    // (ageBand) is positioned BEFORE the personal-data question
    // (lastPeriod). The previous order — privacy → lastPeriod → tracking
    // → ageBand → healthKit — broke the emotional register mid-flow: the
    // user answered "when did your body do something" (intimate) and
    // then hit "what category are you" (form-like), creating a jolt.
    // Reordered to: privacy (architectural promise) → ageBand
    // (calibration setup) → lastPeriod (now contextualised by the
    // previous answer: "your age range helps us calibrate this
    // estimate") → tracking (preference toggles) → healthKit (offer).
    //
    // The raw values preserve case ordering — that's what the page-dot
    // progress indicator reads — so the order in this enum IS the
    // user-visible order.
    enum OnboardingStep: Int, CaseIterable {
        case privacy = 0
        case ageBand = 1
        case lastPeriod = 2
        case tracking = 3
        case healthKit = 4
    }

    private var dateRange: ClosedRange<Date> {
        Date.now.addingDays(-365) ... Date.now
    }

    var body: some View {
        ZStack {
            PageBackground.color(scheme: colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch step {
                    case .privacy: privacyStep
                    case .lastPeriod: lastPeriodStep
                    case .tracking: trackingStep
                    case .ageBand: ageBandStep
                    case .healthKit: healthKitStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack {
                Spacer()
                pageDots
                    .padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $showHKImport, onDismiss: {
            Task { await finish() }
        }) {
            HealthKitImportSheet()
        }
    }

    // MARK: - Page dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
        }
        // VoiceOver gets a single progress utterance instead of "1, 2, 3, 4"
        // pellets — gives the user orientation without noise. (Reviewer rec.)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt \(step.rawValue + 1) von \(OnboardingStep.allCases.count)")
    }

    // MARK: - Step 1: Privacy (NEW-K — task #137)
    //
    // Promoted from "hidden DisclosureGroup detail" to first-class.
    // Bullets are synced verbatim to PrivacyDisclosureSection (#123) so a
    // post-#123-iteration grep for any of these strings updates both
    // sites. Onboarding deliberately omits the "Speicherort: SwiftData /
    // SQLite" bullet — less technical surface for first-time users.

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            privacyArchitectureDiagram
                .padding(.bottom, 4)

            Text("Willkommen bei Tideline.")
                .tidelineSerifHeadline(size: 32, relativeTo: .largeTitle)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Text("Deine Zyklusdaten bleiben auf diesem Gerät.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            // Wave-B fix (4.4): privacy bullets reorganised so control-
            // reinforcing claims (uninstall = data deleted, no cloud
            // sync) sit ABOVE the fold and the only nuanced caveat
            // (iCloud-Backup of iOS itself, which we don't control)
            // stays inside the DisclosureGroup. The previous structure
            // collapsed control-reinforcing AND nuanced material together
            // into the disclosure, which signalled "fine print" rather
            // than "additional confidence."
            VStack(alignment: .leading, spacing: 10) {
                bullet("Alle Eintragungen werden lokal auf deinem iPhone gespeichert.")
                // TODO(#126): When iCloud private sync ships, revise to
                // "kein Konto, kein Login, optionale iCloud-Synchronisation
                // (Standard: aus)". The same line + TODO live in
                // PrivacyDisclosureSection.swift; both sites must update
                // together so the onboarding promise and the settings
                // proof stay consistent.
                bullet("Kein Konto, kein Login, keine Cloud-Synchronisation.")
                bullet("Keine Analytics-Tools, keine Drittanbieter-SDKs.")
                bullet("Tideline hat keinen Server, an den deine Daten gehen — sie verlassen dein Gerät nicht.")
                // Promoted out of the disclosure (Wave-B 4.4) — this
                // reinforces user control and belongs above the fold.
                bullet("Beim Deinstallieren werden alle Tideline-Daten zusammen mit der App gelöscht.")
                // Promoted out of the disclosure — the Apple-Health
                // bidirectionality is an honest scope note, not a
                // caveat; users should see it before opening anything.
                bullet("Apple Health ist eine separate, von Apple verwaltete Datenbank. Wenn du Tideline mit Apple Health verbunden hast, fließen Periodendaten in beide Richtungen — die in Apple Health gespeicherten Daten verwaltest du dort eigenständig.")
            }

            // Wave-B (4.4): the only remaining DisclosureGroup item is
            // the iCloud-Backup nuance — a true caveat about an iOS
            // setting Tideline doesn't control. Keeping THIS one
            // collapsed is the right "we'll mention it but not lead
            // with it" treatment because the only action the user can
            // take is to know it exists and decide for themselves
            // whether to leave iCloud-Backup on.
            DisclosureGroup("Hinweis zu iCloud-Backup") {
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Tideline synchronisiert nichts in die Cloud. Falls du iOS-Backups in iCloud aktiviert hast, sichert iOS allerdings auch Tidelines lokale Datenbank dorthin — verschlüsselt, aber auf Apple-Servern.")
                }
                .padding(.top, 8)
            }
            .font(.subheadline)
            .padding(14)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 12)
            )

            Spacer(minLength: 16)
            // Wave-B (4.4): privacy → ageBand (was → lastPeriod). New
            // order: architectural promise first, calibration setup
            // second, then the personal "when did your last period start"
            // question, which now reads as "answer the personal question
            // so we can apply the calibration we just set up."
            primaryButton("Weiter") {
                step = .ageBand
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Privacy architecture diagram (NEW-K / #137)
    //
    // Three SF Symbols arranged side by side: iPhone with a shield (data
    // on the device, protected), and two crossed-out icons (cloud +
    // person) to communicate "no cloud, no account" without words. The
    // verbal explanation lives in the bullets below the diagram — this
    // is the at-a-glance visual that makes the architecture promise
    // graspable before the user reads anything.
    private var privacyArchitectureDiagram: some View {
        HStack(spacing: 26) {
            Spacer()
            // iPhone with shield = local-on-device, protected
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: "iphone")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white, Color(red: 0.93, green: 0.48, blue: 0.48))
                        .offset(x: 14, y: 14)
                }
                Text("Lokal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Crossed-out cloud = no sync, no cloud storage
            VStack(spacing: 6) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Keine Cloud")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Crossed-out person = no account, no login
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Kein Konto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        // Reviewer B2 — the bullets below the diagram carry the same
        // information verbatim ("Lokal" / "Keine Cloud" / "Kein Konto" →
        // bullet 1 + bullet 2). Hiding the diagram from VoiceOver avoids
        // triple-reading the same claim. The diagram is decorative
        // reinforcement; semantics live in the bullets.
        .accessibilityHidden(true)
    }

    // MARK: - Step 2: Last period

    private var lastPeriodStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Wann hat deine letzte Periode begonnen?")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                radioRow(
                    label: "An einem bestimmten Tag",
                    isSelected: isSpecificDateSelected
                ) {
                    lastPeriodSelection = .specificDate(lastPeriodDate)
                }

                if isSpecificDateSelected {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { lastPeriodDate },
                            set: { newDate in
                                lastPeriodDate = newDate
                                lastPeriodSelection = .specificDate(newDate)
                            }
                        ),
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.leading, 28)
                }

                radioRow(
                    label: "Vor kurzem — ich logge ab heute",
                    isSelected: lastPeriodSelection == .recently
                ) {
                    lastPeriodSelection = .recently
                }

                radioRow(
                    label: "Weiß ich nicht genau",
                    isSelected: lastPeriodSelection == .unsure
                ) {
                    lastPeriodSelection = .unsure
                }
            }

            Spacer(minLength: 16)
            // Wave-B (4.4): lastPeriod → tracking (unchanged target;
            // the reorder swap is in the upstream step, not this leg).
            primaryButton(
                "Weiter",
                disabled: lastPeriodSelection == nil,
                accessibilityHintWhenDisabled: "Wähle zuerst eine der drei Optionen"
            ) {
                step = .tracking
            }
        }
    }

    private var isSpecificDateSelected: Bool {
        if case .specificDate = lastPeriodSelection { return true }
        return false
    }

    private func radioRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Step 3: Tracking preferences

    private var trackingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Was möchtest du tracken?")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Text("Du kannst das jederzeit ändern.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                fixedRow(label: "Periode & Tage", subtitle: "Immer aktiviert")
                Toggle("Stimmung", isOn: $trackMood)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(rowBackground)
                Toggle("Symptome", isOn: $trackSymptoms)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(rowBackground)
                Toggle("Notizen", isOn: $trackNotes)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(rowBackground)
            }
            .font(.body)

            Spacer(minLength: 16)
            // Wave-B (4.4): tracking → healthKit (was → ageBand). The
            // ageBand step now precedes lastPeriod, so the post-tracking
            // leg jumps straight to the final HK offer.
            primaryButton("Weiter") {
                step = .healthKit
            }
        }
    }

    // MARK: - Step 2: Age band (task #97). Promoted to step-2 in Wave-B (4.4) — was step-4.

    private var ageBandStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Audit Wave-A fix (4.4): switched from `person.badge.clock`
            // (which read as "attendance tracking" — scheduling/HR
            // semantics) to `figure.stand`, a neutral human-figure
            // glyph that doesn't carry institutional connotations.
            // The step is asking about something personal and
            // biological; the glyph should match that register.
            Image(systemName: "figure.stand")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color(red: 0.42, green: 0.55, blue: 0.71))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

            Text("Welcher Altersbereich passt zu dir?")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Text("Tideline nutzt diese Angabe nur, um deine anfängliche Schätzung realistischer zu machen. Sie wird ausschließlich lokal gespeichert.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(AgeBand.displayOrder, id: \.rawValue) { band in
                    ageBandRow(band)
                }
            }

            Spacer(minLength: 16)
            // Wave-B (4.4): ageBand → lastPeriod (was → healthKit). The
            // calibration answer is now ready to be applied to the
            // personal "when did your last period start" question, which
            // is the next step.
            primaryButton("Weiter") {
                step = .lastPeriod
            }
        }
    }

    @ViewBuilder
    private func ageBandRow(_ band: AgeBand) -> some View {
        let isSelected = ageBandSelection == band
        Button {
            ageBandSelection = band
        } label: {
            HStack {
                Text(band.localizedLabel)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color(red: 0.93, green: 0.48, blue: 0.48).opacity(0.10)
                    : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected
                            ? Color(red: 0.93, green: 0.48, blue: 0.48).opacity(0.55)
                            : Color.clear,
                        lineWidth: 1.0
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowBackground: some ShapeStyle {
        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03)
    }

    private func fixedRow(label: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step 4: HealthKit offer

    private var healthKitStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.pink)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

            Text("Bisherige Daten aus Apple Health?")
                .tidelineSerifHeadline(size: 28, relativeTo: .title)
                .fontDesign(.serif)
                .italic()
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Text("Wenn du schon Apple Health benutzt, können wir deine Zyklusdaten von dort übernehmen — alles bleibt auf deinem Gerät.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            primaryButton("Ja, importieren", disabled: isFinishing) {
                showHKImport = true
            }

            Button("Später") {
                Task { await finish() }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(isFinishing)
        }
    }

    // MARK: - Shared primary button

    private func primaryButton(
        _ title: String,
        disabled: Bool = false,
        accessibilityHintWhenDisabled: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Self.coralGradient, in: RoundedRectangle(cornerRadius: 14))
                .opacity(disabled ? 0.5 : 1.0)
                .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(disabled ? 0 : 0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityHint(disabled ? (accessibilityHintWhenDisabled ?? "") : "")
    }

    private static let coralGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.48, blue: 0.48), Color(red: 0.88, green: 0.38, blue: 0.38)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Finish

    private func finish() async {
        guard !isFinishing else { return }
        isFinishing = true

        // Persist tracking prefs.
        persistedMood = trackMood
        persistedSymptoms = trackSymptoms
        persistedNotes = trackNotes
        // Task #97 — persist age band + apply it to the predictor before
        // any logged data lands. `setAgeBand` replaces the predictor's
        // mode in-place, which is safe here because `loadAndReplay`
        // hasn't run yet (the gate hasn't flipped to RootView's `.task`).
        persistedAgeBand = ageBandSelection.rawValue
        if let store {
            await store.setAgeBand(ageBandSelection)
        }

        // Await the period seed before flipping the gate. The await runs
        // to completion regardless — we're called from an unstructured
        // `Task { ... }` outside the view's `.task` scope, so SwiftUI
        // teardown doesn't cancel it.
        if case .specificDate(let date) = lastPeriodSelection, let store {
            await store.startPeriod(on: date)
        }

        // Flip the gate inside `withAnimation` so the OnboardingGate's
        // `.transition(.opacity)` actually runs (reviewer rec — without
        // the explicit animation block, SwiftUI does an instant swap).
        withAnimation(.easeInOut(duration: 0.35)) {
            hasCompletedOnboarding = true
        }
    }
}

#Preview {
    OnboardingFlow()
}
