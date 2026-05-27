import SwiftUI
import SwiftData

/// The home view. Three vertical surfaces:
///   1. TidelineHero — atmospheric beach scene (fixed at top, doesn't scroll)
///   2. ScrollView with cards (CyclePhaseStrip + TideSparkline) over the cream sheet
///   3. Bottom tab bar — 4-tab layout post-D1: Mein Zyklus / Kalender / Loggen (FAB) / Mehr
///
/// Mood logging lives inside `LogDaySheet`'s detail section — surfacing it on
/// the home screen as a separate row felt redundant.
struct TidelineHomeView: View {
    @Environment(\.cycleStore) private var store
    @Environment(\.colorScheme) private var colorScheme
    /// Task #110 — TZ change / midnight rollover signal.
    @Environment(\.refreshClock) private var clock
    // Default to clinical naming (Menstruation / Follikelphase / …) rather
    // than the tide metaphor. New AppStorage key so a previously stored
    // `useTideNaming = true` doesn't override the new default.
    @AppStorage(PhaseNamingSettingsSection.storageKey) private var useClinicalNaming: Bool = true
    private var useTideNaming: Bool { !useClinicalNaming }

    @State private var heroState: HeroState = .empty
    @State private var pastCycles: [CycleSummary] = []
    @State private var currentCycleStart: Date?
    @State private var currentCycleBoundaries: PhaseBoundaries = .populationDefault
    @State private var todayDayInCycle: Int = 1
    @State private var bleedingDays: Set<Int> = []
    @State private var showLogSheet: Bool = false
    @State private var showCalendarSheet: Bool = false
    @State private var showMyCycleSheet: Bool = false
    @State private var showMoreSheet: Bool = false
    // Statistik tab dropped on 2026-05-22 per roadmap decision D1 — the
    // Mein Zyklus 3-layer redesign (NEW-A) absorbs its retrospective job.
    // Reintroduce as a HealthKit-charts surface post-#71 if empirical
    // demand emerges.

    // Task #74 — Resume-After-Pause sheet. `pausedReason` is captured during
    // `refresh()` so the `.sheet` builder closure (which can't `await` the
    // store) has the reason on hand at presentation time. `resumeConfirmed`
    // discriminates the "Ja" path from swipe-down or "Später" inside the
    // sheet's `onDismiss` handler.
    @State private var showResumeSheet: Bool = false
    @State private var pausedReason: PauseReason? = nil
    @State private var resumeConfirmed: Bool = false
    @AppStorage("resumeSheetDismissedAtTI") private var resumeSheetDismissedAtTI: Double = 0

    /// Audit follow-up — loss-aware suppression for in-app cycle-prediction
    /// surfaces. Mirrors the 28-day rule the NotificationGate uses for
    /// outbound notifications. While true, the LateMilestoneCard (and any
    /// other "your period is due / take a test" prompts) are hidden.
    @State private var hasRecentPregnancyLoss: Bool = false

    /// Master gate from the More-tab settings. Read here so `refresh()` can
    /// pass it through to the NotificationCoordinator without a separate
    /// fetch. Default OFF per CLAUDE.md pillar 5.
    @AppStorage("notificationsMasterEnabled") private var notificationsEnabled: Bool = false

    /// Bridges the unwired `NotificationGate` + `NotificationService` pair
    /// to actual scheduled local notifications. Created once per view
    /// instance so cancel-then-schedule pairs share a single
    /// `NotificationService` lifetime. Audit fix for #122 / #85.
    private let notificationCoordinator = NotificationCoordinator()

    @State private var scrollOffset: CGFloat = 0
    @State private var animateIn: Bool = false
    @State private var topSafeAreaInset: CGFloat = TidelineHomeView.systemTopSafeAreaInset()

    /// Read the current window's top safe-area inset synchronously so the
    /// top bar lands below the status bar/Dynamic Island on the very first
    /// frame, before the preference-key measurement has a chance to fire.
    private static func systemTopSafeAreaInset() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let inset = scene?.windows.first { $0.isKeyWindow }?.safeAreaInsets.top
            ?? scene?.windows.first?.safeAreaInsets.top
            ?? 47
        return inset > 0 ? inset : 47
    }

    /// Wave-B fix (1.2): true when today's cycle day appears in the
    /// `bleedingDays` set sourced from the live HomeSnapshot. Powers the
    /// FAB icon swap (plus → checkmark) so the user can tell at a glance
    /// whether they've already logged today's period. Bleeding-specific
    /// rather than "any DayEntry" because the user's "did I log?" mental
    /// model is about the period, not about ancillary mood notes.
    private var loggedBleedingToday: Bool {
        bleedingDays.contains(todayDayInCycle)
    }

    /// Wave-B fix (1.3): one-tap fast path for "Periode heute begonnen"
    /// triggered by long-pressing the FAB. Mirrors Clue's pattern of
    /// making the most-important data point (cycle start) a single
    /// interaction rather than a sheet round-trip.
    ///
    /// Uses `logDay(... flow: .medium)` so the call matches the new
    /// LogDaySheet default — the user gets the same posterior input
    /// whether they take the fast path or the full sheet. `refresh()`
    /// then folds the new entry into the hero + strip + sparkline +
    /// notification reschedule in one atomic pass.
    private func logTodayFast() async {
        guard let store else { return }
        await store.logDay(date: .now, flow: .medium)
        await refresh()
    }

    /// Audit Wave-A fix (1.4): pull the hero's prediction interval string
    /// out of the current `heroState` so the CyclePhaseStrip can echo it
    /// in its summary block. Returns nil for paused/retired/empty states
    /// (no prediction to display). Both `.active` and `.late` carry the
    /// text; `.empty`/`.paused`/`.retired` do not.
    private var predictionTextForStrip: String? {
        switch heroState {
        case .active(let model):
            return model.predictionIntervalText
        case .late(let model):
            return model.intervalText
        case .empty, .paused, .retired:
            return nil
        }
    }

    private var activeGlowColor: Color {
        switch heroState {
        case .empty:
            return colorScheme == .dark
                ? Color(red: 0.30, green: 0.22, blue: 0.42)
                : Color(red: 0.88, green: 0.45, blue: 0.38)
        case .active(let model):
            return PhasePalette.color(for: model.phase, scheme: colorScheme)
        case .late(let model):
            // Late mode keeps the user's last-known palette (#78).
            return PhasePalette.color(for: model.lastKnownPhase, scheme: colorScheme)
        case .paused, .retired:
            return PhasePalette.neutralColor(scheme: colorScheme)
        }
    }

    private var secondaryGlowColor: Color {
        switch heroState {
        case .empty:
            return colorScheme == .dark ? Color(hex: 0x4a1830) : Color(hex: 0xfacf9a)
        case .active(let model):
            return secondaryGlow(for: model.phase)
        case .late(let model):
            return secondaryGlow(for: model.lastKnownPhase)
        case .paused, .retired:
            return colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.85)
        }
    }

    /// Phase → secondary-glow color helper. Pulled out of the
    /// `activeGlowColor` switch so both `.active` and `.late` (which
    /// keeps the user's last-known phase) can resolve through one
    /// table. (#78)
    private func secondaryGlow(for phase: CyclePhase) -> Color {
        switch phase {
        case .menses: return Color(hex: 0x8a3040)
        case .follicular: return Color(hex: 0x3E8890)
        case .ovulation: return Color(hex: 0xe07060)
        case .lutealEarly, .lutealLate: return Color(hex: 0x4a1830)
        }
    }

    private var headerOpacity: Double {
        // Clamp scrollOffset to ≤0 so positive overscroll (rubber-band pull-down)
        // doesn't produce a negative input and fight the ramp. The 90pt ramp
        // (was 50pt) prevents a partial-opacity flash at natural rest, where
        // the zero-height geometry marker can land a few points negative.
        let clamped = min(0, scrollOffset)
        return min(1.0, max(0.0, -clamped / 90.0))
    }

    // MARK: - Top bar color helpers

    /// Scalar t: 0 = hero fully visible, 1 = frosted header fully opaque.
    /// Used to drive continuous crossfades instead of a hard threshold.
    private var topBarT: Double { headerOpacity }

    /// Border colour for the settings button.
    /// Interpolates white/0.35 (over hero) → white/0.12 (over header, light) or white/0.15 (dark).
    /// Keeping the base colour white avoids needing Color.init(r:g:b:) mixing.
    /// The visual shift from a slightly stronger white ring to a faint one reads naturally.
    private var topBarButtonBorder: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.15)
        }
        // Crossfade opacity 0.35 → 0.12 as header fades in.
        let opacity = 0.35 * (1 - topBarT) + 0.12 * topBarT
        return Color.white.opacity(opacity)
    }

    /// Premium dynamic pearlescent linear gradient that shifts center based on
    /// scroll offset to simulate physical light reflection over the photo hero!
    private var unscrolledWordmarkGradient: LinearGradient {
        let offsetFraction = min(1.0, max(0.0, -scrollOffset / 300.0))
        // Shifts the reflection center from left to right as you scroll
        let startX = -0.25 + (offsetFraction * 0.7)
        return LinearGradient(
            colors: [
                Color(hex: 0xD5DEE2), // Polished platinum/silver
                Color(hex: 0xFFFCF6), // Pearl warm cream
                Color.white,          // Intense diamond highlight
                Color(hex: 0xFFFCF6), // Pearl warm cream
                Color(hex: 0xBCC7CD)  // Brushed steel shadow stop
            ],
            startPoint: .init(x: startX, y: 0.0),
            endPoint: .init(x: startX + 0.6, y: 1.0)
        )
    }

    /// Scrolled wordmark gradient: blends the base text color with a touch of
    /// the active phase's theme color to tie the header organically to the
    /// current cycle phase state. Also shifts slightly with scroll offset.
    private var scrolledWordmarkGradient: LinearGradient {
        let offsetFraction = min(1.0, max(0.0, -scrollOffset / 300.0))
        let startX = -0.15 + (offsetFraction * 0.6)
        let themeColor = activeGlowColor
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(hex: 0x9CA3AF), // Matte silver
                    themeColor.opacity(0.85),
                    Color.white,          // Brilliant highlight
                    themeColor.opacity(0.85),
                    Color(hex: 0x4B5563)  // Dark steel
                ],
                startPoint: .init(x: startX, y: 0.0),
                endPoint: .init(x: startX + 0.6, y: 1.0)
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(hex: 0x1F2937), // Charcoal
                    themeColor.opacity(0.95),
                    Color(hex: 0x6B7280), // Steel reflection
                    themeColor.opacity(0.95),
                    Color(hex: 0x111827)  // Deep obsidian
                ],
                startPoint: .init(x: startX, y: 0.0),
                endPoint: .init(x: startX + 0.6, y: 1.0)
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background Layer: Cream/dark background with ambient animated gradient color blobs
            ZStack {
                PageBackground.color(scheme: colorScheme)
                    .ignoresSafeArea()

                // Measure top safe area inset dynamically
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: TopSafeAreaInsetPreferenceKey.self, value: proxy.safeAreaInsets.top)
                }
                .ignoresSafeArea()

                // Ambient tide layer in its own subview so its phase animation
                // doesn't invalidate `TidelineHomeView.body` 60×/sec (was the
                // driver behind every glow/header/crossfade recompute).
                HomeAmbientLayer(
                    primary: activeGlowColor,
                    secondary: secondaryGlowColor
                )
            }

            // Atmospheric 3D Parallax Header Layer
            TidelineHero(
                state: heroState,
                useTideNaming: useTideNaming,
                scrollOffset: scrollOffset
            )
            .allowsHitTesting(false) // Gestures pass through to ScrollView
            
            // Interactive ScrollView
            ScrollView {
                VStack(spacing: 0) {
                    // Hidden geometry marker to record scroll position
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    // Floating window spacing matching the hero height
                    Color.clear
                        .frame(height: 382)

                    // Cards Layout with Premium Spring Cascade Entrance
                    VStack(spacing: 14) {
                        if let start = currentCycleStart {
                            opaqueCard {
                                CyclePhaseStrip(
                                    cycleStartDate: start,
                                    boundaries: currentCycleBoundaries,
                                    bleedingDays: bleedingDays,
                                    today: todayDayInCycle,
                                    useTideNaming: useTideNaming,
                                    // Audit Wave-A fix (1.4): echo the
                                    // hero's prediction text into the
                                    // strip so the next-period range
                                    // stays visible after the user
                                    // scrolls past the hero. Pulled
                                    // from `heroState` so the two
                                    // surfaces never drift.
                                    predictionText: predictionTextForStrip,
                                    onDataChanged: { Task { await refresh() } }
                                )
                            }
                            .offset(y: animateIn ? 0 : 50)
                            .opacity(animateIn ? 1 : 0)
                            .animation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.05), value: animateIn)
                        }

                        // Late-mode milestone card (#78): appears directly
                        // below the phase strip when the user is past the
                        // expected cycle length. The bucket copy and
                        // headline are owned by `LateMilestoneBucket` —
                        // see `docs/design/late-mode-implementation.md`
                        // for the EU-MDR-reviewed wording.
                        //
                        // Audit follow-up — gated on `hasRecentPregnancyLoss`
                        // (28-day window, set by `CycleStore.homeSnapshot`).
                        // The same CLAUDE.md hard rule that gates outbound
                        // notifications via `NotificationGate` applies here:
                        // a "many people take a pregnancy test now" prompt
                        // is exactly the kind of message that compounds
                        // grief with mistimed reminders when shown right
                        // after a logged loss. Silence is valid (Pillar 4).
                        if case .late(let lateModel) = heroState, !hasRecentPregnancyLoss {
                            LateMilestoneCard(daysLate: lateModel.daysLate)
                                .offset(y: animateIn ? 0 : 50)
                                .opacity(animateIn ? 1 : 0)
                                .animation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.10), value: animateIn)
                        }

                        opaqueCard {
                            TideSparkline(
                                cycles: pastCycles,
                                // Audit fix — per-cycle detail view is
                                // tracked separately and not in v1 scope.
                                // Make the tap a no-op explicitly rather
                                // than leaving a silent dead-end TODO;
                                // route the user to the Mein-Zyklus tab
                                // which already has the per-cycle list.
                                onCycleTap: { _ in
                                    showMyCycleSheet = true
                                }
                            )
                        }
                        .offset(y: animateIn ? 0 : 50)
                        .opacity(animateIn ? 1 : 0)
                        .animation(.spring(response: 0.75, dampingFraction: 0.80).delay(0.15), value: animateIn)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            // Hide the default vertical scroll indicator — it appears as a
            // thin white pill on the right edge during drag and conflicts
            // with the photo-driven aesthetic.
            .scrollIndicators(.hidden)
            // LOW: The GeometryReader inside this ScrollView reads frames in the
            // "scroll" coordinate space. If you rename or move this modifier, the
            // preference-key offset measurement silently breaks (returns 0 forever).
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                // Dead-band: suppress sub-pixel offset noise so we don't
                // invalidate `body` (and all phase/glow/gradient computeds)
                // on every 60-fps scroll tick when the user isn't actually
                // moving. Saves a lot of re-renders during a still drag.
                if abs(value - scrollOffset) > 1.0 {
                    scrollOffset = value
                }
            }
            .onPreferenceChange(TopSafeAreaInsetPreferenceKey.self) { value in
                topSafeAreaInset = value
            }

            // Fixed Top Bar Overlay for Wordmark & Interactive settings
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topSafeAreaInset)

                    // Wordmark only (settings icon removed — Settings live in
                    // the "Mehr" tab now). Wordmark shifted down with extra
                    // top padding so it sits lower under the dynamic island.
                    HStack(spacing: 10) {
                        Image("tideline_app_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .opacity(colorScheme == .dark ? 0.9 : 1.0)

                        ZStack(alignment: .leading) {
                            // 1. Embossed Shadow / Highlight Layer (3D bevel chisel effect)
                            Text("Tideline")
                                .tidelineSerifHeadline(size: 22, relativeTo: .headline)
                                .fontDesign(.serif)
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .offset(x: -0.5, y: -0.5)
                                .opacity(colorScheme == .dark ? 1.0 : (1 - topBarT))

                            Text("Tideline")
                                .tidelineSerifHeadline(size: 22, relativeTo: .headline)
                                .fontDesign(.serif)
                                .foregroundColor(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.60))
                                .offset(x: 0.5, y: 0.5)
                                .opacity(colorScheme == .dark ? 1.0 : (1 - topBarT))

                            // 2. Pearl Shimmering Text (Unscrolled state over atmospheric hero)
                            Text("Tideline")
                                .tidelineSerifHeadline(size: 22, relativeTo: .headline)
                                .fontDesign(.serif)
                                .foregroundStyle(unscrolledWordmarkGradient)
                                .opacity(colorScheme == .dark ? 1.0 : (1 - topBarT))

                            // 3. Metallic/Phase-Blended Shimmering Text (Scrolled state over frosted header)
                            Text("Tideline")
                                .tidelineSerifHeadline(size: 22, relativeTo: .headline)
                                .fontDesign(.serif)
                                .foregroundStyle(scrolledWordmarkGradient)
                                .opacity(colorScheme == .dark ? 0.0 : topBarT)
                        }
                        .shadow(color: .black.opacity(scrollOffset < -40 ? 0 : 0.18), radius: 6, y: 1)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    // Bumped from 22 → 44 so the logo + wordmark sit
                    // clear of the system clock under the Dynamic Island
                    // on Pro/Pro Max devices.
                    .padding(.top, 44)
                    .padding(.bottom, 12)
                }
                .background(
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        Rectangle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .frame(height: 0.5)
                    }
                    .opacity(headerOpacity)
                )
                
                Spacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            tabBar
        }
        .onAppear {
            // Fire the entrance animation immediately after first layout.
            // (Tide phase animation lives inside HomeAmbientLayer's
            // TimelineView and pauses on Low Power / Reduce Motion — no
            // top-level repeatForever here anymore.)
            withAnimation(.spring(response: 0.75, dampingFraction: 0.80)) {
                animateIn = true
            }
        }
        .task {
            await refresh()
        }
        .onChange(of: clock?.tick) { oldValue, newValue in
            // Task #110 — on TZ change or midnight, refresh the hero
            // state so day-in-cycle math picks up the new "today."
            // Guard against the env-injection nil→0 cold-launch fire
            // that would double-load on top of the `.task` block above.
            guard let oldValue, let newValue, newValue != oldValue else { return }
            Task { await refresh() }
        }
        // Audit fix for #122 / #85 — when the user flips the master
        // notifications toggle in the Mehr-tab settings, fold that change
        // into the current scheduled set immediately. Without this the
        // newly-enabled gate would not produce any scheduled notifications
        // until the next state-change refresh trigger, which could be
        // hours away.
        .onChange(of: notificationsEnabled) { _, _ in
            Task { await refresh() }
        }
        .sheet(isPresented: $showLogSheet, onDismiss: { Task { await refresh() } }) {
            LogDaySheet()
        }
        .sheet(isPresented: $showCalendarSheet, onDismiss: { Task { await refresh() } }) {
            CalendarSheet()
        }
        .sheet(isPresented: $showMyCycleSheet) {
            MyCycleSheet()
        }
        .sheet(isPresented: $showMoreSheet) {
            MoreSettingsSheet()
        }
        .sheet(isPresented: $showResumeSheet, onDismiss: {
            // Discriminate between "Ja, neu lernen" (resumeConfirmed = true,
            // set by the sheet's primary button before dismiss) and any other
            // dismissal — Später button, swipe-down, programmatic. The latter
            // path writes the cooldown timestamp; the former fires the event.
            if resumeConfirmed {
                resumeConfirmed = false
                Task {
                    await store?.addEvent(kind: .resumeAfterPause, on: Date.now)
                    await refresh()
                }
            } else {
                resumeSheetDismissedAtTI = Date.now.timeIntervalSinceReferenceDate
            }
        }) {
            if let reason = pausedReason {
                ResumeAfterPauseSheet(
                    pauseReason: reason,
                    onResume: { resumeConfirmed = true }
                )
            }
        }
    }

    /// Opaque card container. Solid fill (instead of `.regularMaterial`)
    /// to avoid stacking a backdrop-blur on top of the photo+gradient —
    /// that combo was the dominant cost on this screen during scroll.
    private var cardFillColor: Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.17, blue: 0.18)
            : Color.white.opacity(0.96)
    }

    @ViewBuilder
    private func opaqueCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(cardFillColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                // Outer subtle border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18), lineWidth: 0.5)
            )
            .overlay(
                // Inner delicate dynamic phase glow border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                activeGlowColor.opacity(colorScheme == .dark ? 0.25 : 0.15),
                                activeGlowColor.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.02 : 0.05), radius: 8, x: 0, y: 3)
            .shadow(color: activeGlowColor.opacity(colorScheme == .dark ? 0.06 : 0.03), radius: 10, x: 0, y: 4)
    }

    // MARK: - Bottom tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(label: "Mein Zyklus") {
                showMyCycleSheet = true
            } icon: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tabSecondaryColor)
            }

            tabButton(label: "Kalender") {
                showCalendarSheet = true
            } icon: {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tabSecondaryColor)
            }

            tabButton(label: "Loggen", isPrimary: true) {
                showLogSheet = true
            } icon: {
                // Wave-B 1.2: FAB icon swaps to a checkmark when today
                // already has a bleeding entry — Clue/Flo pattern. The
                // signal answers "did I log my period today?" at a
                // glance without the user having to scan the phase
                // strip for a coral drop under the thumb. We gate on
                // bleeding specifically (not "any DayEntry") because a
                // mood-only entry doesn't satisfy the "is my period
                // tracked?" mental model — false confidence is worse
                // than no signal.
                Image(systemName: loggedBleedingToday ? "checkmark" : "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    // Animate the swap so the change is visible the moment
                    // the sheet dismisses + refresh() lands.
                    .contentTransition(.symbolEffect(.replace))
            }
            // Wave-B 1.3: long-press fast path — Clue-style one-tap
            // "period started today." Reduces the most-important data
            // point in the app (cycle start) from 3 taps (FAB → flow
            // picker → save) to 1 tap + 1 long-press. The full
            // LogDaySheet stays available for editing details.
            //
            // The .contextMenu modifier attaches to the trailing tab-
            // bar button. iOS opens the menu on long-press; tap still
            // opens the sheet as before. Gated on store availability
            // because the underlying log call would no-op without it.
            .contextMenu {
                if store != nil {
                    Button {
                        Task { await logTodayFast() }
                    } label: {
                        Label("Periode heute begonnen", systemImage: "drop.fill")
                    }
                    Button {
                        showLogSheet = true
                    } label: {
                        Label("Tag bearbeiten…", systemImage: "pencil")
                    }
                }
            }

            tabButton(label: "Mehr") {
                showMoreSheet = true
            } icon: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tabSecondaryColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25))
                    .frame(height: 0.5)
                Spacer()
            }
        )
    }

    /// Hoisted so it isn't reconstructed in every `tabButton` body call.
    private static let coralFabGradient = LinearGradient(
        colors: [Color(red: 0.93, green: 0.48, blue: 0.48), Color(red: 0.88, green: 0.38, blue: 0.38)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Tab button: primary slot is a circular coral FAB; secondary slots are
    /// outline-style icon + label.
    @ViewBuilder
    private func tabButton<Icon: View>(
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isPrimary {
                    ZStack {
                        Circle()
                            .fill(Self.coralFabGradient)
                            .frame(width: 46, height: 46)
                            .shadow(color: Color(red: 0.91, green: 0.44, blue: 0.44).opacity(0.35), radius: 12, y: 4)
                        icon()
                    }
                } else {
                    icon()
                        .frame(width: 44, height: 44)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tabSecondaryColor)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(store == nil && isPrimary)
        .accessibilityLabel(label)
    }

    private var tabSecondaryColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.42)
            : Color.black.opacity(0.40)
    }

    // MARK: - Data refresh

    private func refresh() async {
        guard let store else { return }

        // Task #90 — single atomic snapshot. Replaces seven sequential
        // `await store.X()` calls whose interleaving could quilt
        // mixed-vintage @State across two concurrent refreshes (sheet-
        // dismiss + phase-strip onDataChanged is the common trigger).
        // All cross-dependent fields are computed inside the actor; the
        // assignments below are pure synchronous transforms.
        let snap = await store.homeSnapshot()

        pastCycles = snap.pastCycles
        currentCycleStart = snap.currentCycleStart
        bleedingDays = snap.bleedingDays
        todayDayInCycle = snap.todayDayInCycle
        currentCycleBoundaries = snap.cycleBoundaries
        hasRecentPregnancyLoss = snap.hasRecentPregnancyLoss

        let conditionalWidthDays = snap.conditionalIntervalDays.map {
            $0.upperBound - $0.lowerBound
        }
        let conditionalDateRange: ClosedRange<Date>? = snap.conditionalIntervalDays.flatMap { range in
            guard let start = snap.currentCycleStart else { return nil }
            let anchor = start.civilDay()
            let lo = anchor.addingDays(range.lowerBound)
            let hi = anchor.addingDays(range.upperBound)
            return lo...hi
        }

        let pausedLabel = snap.pausedReason.map(germanLabel(for:))
        let retiredLabel = snap.retiredReason.map(germanLabel(for:))

        heroState = HeroStateBuilder.deriveHeroState(HeroInputs(
            mode: snap.mode,
            lastStart: snap.currentCycleStart,
            todayDayInCycle: snap.todayDayInCycle,
            cycleBoundaries: snap.cycleBoundaries,
            observedCount: snap.observedCycleCount,
            calibratedInterval: snap.calibratedPrediction?.interval,
            conditionalInterval: conditionalDateRange,
            conditionalWidthDays: conditionalWidthDays,
            isWidenedRecovery: snap.calibratedPrediction?.isWidenedRecovery ?? false,
            isOngoingIrregularity: snap.calibratedPrediction?.isOngoingIrregularity ?? false,
            pausedLabel: pausedLabel,
            retiredLabel: retiredLabel
        ))

        // Audit fix for #122 / #85 — reschedule local notifications against
        // the fresh snapshot. The coordinator cancels prior pending requests
        // and re-emits new ones gated by `NotificationGate.shouldDeliver`,
        // so loss-suppression + master-toggle + paused/retired modes all
        // resolve to the right scheduled set without delta logic here.
        //
        // Why call it from `refresh()`: every state change that affects what
        // notifications should fire (cycle start, mode transition, event
        // logged, toggle flipped) already triggers a `refresh()`. Folding
        // the reschedule into the same call eliminates a separate observer
        // surface that would have to mirror those same triggers.
        // `snap.cycleBoundaries.cycleLength` is `Int(round(μ))` from the
        // posterior — sub-day quantisation is invisible against a 10:00
        // local-time fire anchor, so we don't need to thread the raw Double.
        let predictedLen = Double(snap.cycleBoundaries.cycleLength)
        await notificationCoordinator.reschedule(
            currentCycleStart: snap.currentCycleStart,
            predictedCycleLength: predictedLen,
            masterEnabled: notificationsEnabled,
            hasRecentLoss: snap.hasRecentPregnancyLoss,
            isActive: snap.mode.isActive
        )

        // Task #74 — Resume-After-Pause eligibility check.
        //
        // Re-entry guard: while the sheet is already presented, do not re-
        // evaluate. A refresh() triggered by an unrelated event (e.g.,
        // onDataChanged from the phase strip) would otherwise flicker
        // isPresented and reset the dismissed-flag interaction.
        if !showResumeSheet {
            pausedReason = snap.pausedReason
            let dismissedAt: Date? = resumeSheetDismissedAtTI > 0
                ? Date(timeIntervalSinceReferenceDate: resumeSheetDismissedAtTI)
                : nil
            // Most-recent bleeding day = cycle-start + (maxOffset - 1) days.
            // Used by the gate to reject stale bleeding (logged before the
            // pause started) — otherwise a paused user who logged a period
            // before starting contraception would see this sheet pop every
            // cooldown rollover for months. (Reviewer rec #3.)
            let recentBleed: Date? = {
                guard let start = snap.currentCycleStart,
                      let maxOffset = snap.bleedingDays.max() else { return nil }
                return start.addingDays(Double(maxOffset - 1))
            }()
            // Require pausedReason to be present alongside showResumeSheet
            // so the .sheet builder never presents an empty body if mode
            // races from .paused → .active mid-refresh. (Reviewer rec #2.)
            showResumeSheet = (snap.pausedReason != nil) && ResumeSheetGate.shouldShow(
                mode: snap.mode,
                mostRecentBleedingDay: recentBleed,
                dismissedAt: dismissedAt,
                now: Date.now
            )
        }
    }

    private func germanLabel(for reason: PauseReason) -> String {
        switch reason {
        case .breastfeeding: return "Stillzeit"
        case .hormonalContraception: return "hormonelle Verhütung"
        case .hypothalamicAmenorrhea: return "hypothalamische Amenorrhoe"
        case .userInitiated: return "manuell pausiert"
        }
    }

    private func germanLabel(for reason: RetirementReason) -> String {
        switch reason {
        case .hysterectomy: return "Hysterektomie"
        case .oophorectomy: return "Oophorektomie"
        case .userInitiated: return "manuell beendet"
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TopSafeAreaInsetPreferenceKey: PreferenceKey {
    typealias Value = CGFloat
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Home-view ambient layer. Pulled into its own view so the 15-fps tide
/// phase animation only invalidates this subtree — the home view's body
/// (with glow colors, header opacity, crossfades, hero, scroll content,
/// tab bar) is no longer re-evaluated on every animation tick.
private struct HomeAmbientLayer: View {
    let primary: Color
    let secondary: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycleSeconds: Double = 18

    var body: some View {
        ZStack {
            // Static radial washes — see AmbientTideBackground for the
            // rationale: animating gradient centers forces full-screen GPU
            // rasterization per frame. Freezing them is essentially free
            // after first render; the perceived motion comes from the
            // tide-lines stroke layered on top.
            RadialGradient(
                colors: [primary.opacity(colorScheme == .dark ? 0.24 : 0.14), .clear],
                center: .init(x: 0.15, y: 0.20),
                startRadius: 40,
                endRadius: 550
            )
            RadialGradient(
                colors: [secondary.opacity(colorScheme == .dark ? 0.18 : 0.10), .clear],
                center: .init(x: 0.85, y: 0.75),
                startRadius: 50,
                endRadius: 450
            )

            // Only the curves animate. 10 fps hard cap via `.periodic`
            // (unlike `.animation(minimumInterval:)` which is a floor).
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let phase = shouldPause ? 0 : currentPhase(ctx.date)
                TideLinesShape(phase: phase)
                    .stroke(
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03),
                        style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                    )
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private var shouldPause: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func currentPhase(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds
        return CGFloat(t * 2 * .pi)
    }
}

struct TideLinesShape: Shape {
    var phase: CGFloat

    // `animatableData` was removed (2026-05-21) because the TimelineView
    // host already drives `phase` discretely at 10 fps. Declaring
    // `animatableData` opted the shape into SwiftUI's interpolation
    // engine, which redraws at display refresh rate (120 Hz on Pro Max
    // ProMotion) between every TimelineView tick — making the supposedly
    // 10-fps tide a 120-fps stroke. This produced visible jank during
    // half-detent sheet presentation, where the system was simultaneously
    // animating the sheet rise AND blurring the parent layer. Without
    // `animatableData` the shape snaps to the new `phase` each tick,
    // which is visually indistinguishable for a slow drift.

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveCount = 5
        let spacing: CGFloat = 55
        
        for i in 0..<waveCount {
            let yOffset = CGFloat(i) * spacing + rect.height * 0.22
            path.move(to: CGPoint(x: -20, y: yOffset))
            
            let w = rect.width + 40
            let control1 = CGPoint(
                x: w * 0.33,
                y: yOffset - 18 * sin(phase + CGFloat(i) * 0.4)
            )
            let control2 = CGPoint(
                x: w * 0.66,
                y: yOffset + 18 * cos(phase + CGFloat(i) * 0.4)
            )
            let end = CGPoint(x: w, y: yOffset)
            
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }
}
