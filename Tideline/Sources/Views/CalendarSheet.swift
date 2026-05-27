import SwiftUI

/// Month-grid calendar. Each day:
///   • Phase-colored ring (menses/follicular/ovulation/luteal) computed from
///     the closest preceding cycle start.
///   • Coral BloodDrop on bleeding days.
///   • Small dot indicator when extras (mood/symptoms/note) were logged.
///   • Today gets a filled background.
/// Tap a day → opens `LogDaySheet` for that date (edit mode).
struct CalendarSheet: View {
    @Environment(\.cycleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Task #110 — listens for `significantTimeChangeNotification` (TZ
    /// change or midnight rollover) to refresh stale "today" captures.
    @Environment(\.refreshClock) private var clock

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var reloadCounter: Int = 0
    @State private var records: [Date: CalendarDayRecord] = [:]

    /// Wave-B fix (4.2): one-time hint pointing at "Mehrere Tage" for
    /// new users who land on an empty calendar. Dismissable via @AppStorage
    /// so it stays gone after the user either uses range-select once OR
    /// taps the close (×) on the hint card. Without this nudge, the
    /// range-select feature — explicitly designed for new users importing
    /// history — was invisible until the user wandered into it.
    @AppStorage("calendarRangeHintDismissed") private var rangeHintDismissed: Bool = false
    @State private var cycleStarts: [Date] = []
    @State private var averageLength: Int = PhaseBoundaries.defaultCycleLength
    /// Per-user mensesEnd floor (NEW-171). Nil for users with <3 closed
    /// cycles or suspected under-logging — falls back to defaultMenses.
    @State private var personalMedianMenses: Int? = nil
    @State private var editingDate: IdentifiableDate? = nil
    /// Pre-computed phase per day for the currently displayed month.
    @State private var phaseByDay: [Date: CyclePhase] = [:]
    /// Pre-computed next calibrated prediction from the store.
    @State private var nextPrediction: CalibratedPrediction? = nil
    /// Direction of month transition (positive = forward, negative = backward).
    @State private var monthTransitionDirection: Int = 0
    /// True when shifting months, temporarily freezing ambient backgrounds to preserve GPU bandwidth.
    @State private var isTransitioning: Bool = false

    // MARK: - Task #79 range-select state

    /// True when the user has tapped "Mehrere Tage". Tap targets switch
    /// from "open LogDaySheet for this day" to "set an anchor".
    @State private var selectingMode: Bool = false
    /// First tapped date in selecting mode. `secondAnchor` is filled on
    /// the next tap; together they materialise the range.
    @State private var firstAnchor: Date? = nil
    @State private var secondAnchor: Date? = nil
    /// Shown briefly when the user's second tap would exceed the 31-day cap.
    @State private var showRangeCapHint: Bool = false
    /// Pushed when the user taps "Anwenden" on the range chip — drives
    /// the `RangeFlowPickerSheet` presentation.
    @State private var showRangePicker: Bool = false
    /// Set by `RangeFlowPickerSheet` on dismiss. Non-nil → user confirmed
    /// the flow choice; nil → cancelled.
    @State private var pickerChosenFlow: FlowLevel? = nil
    /// Brief banner after a successful bulk-write — "5 Tage als Mittel eingetragen."
    @State private var lastBulkResult: BulkLogResult? = nil
    /// Cached day list for the visible month grid. Promoted from a computed
    /// `var` to @State so it doesn't run twice per month change (once for
    /// `recomputePhases()` and once for the grid render). Repopulated only
    /// when `displayedMonth` actually changes.
    @State private var monthDays: [Date?] = []

    private let cal = Calendar.current
    private let weekdaySymbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        ZStack(alignment: .top) {
            // Background Layer: Cream/dark wash + ambient tide layer (animated
            // in a child view so its 15fps tick doesn't invalidate this sheet's
            // body — calendar grid + records dict stay quiet).
            PageBackground.color(scheme: colorScheme)
                .ignoresSafeArea()
            // Pause the tide animation while LogDaySheet is up: the parent
            // gets re-rasterized every frame with the moving tide as input
            // during the sheet-rise blur, which produced the half-detent
            // jank the user reported.
            AmbientTideBackground(
                primary: coral,
                secondary: turquoise,
                animate: editingDate == nil && !isTransitioning
            )

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    // Reserve room for the visible top-bar HStack only.
                    Spacer().frame(height: 56)
                    
                    // Calendar Frosted Container Card
                    VStack(spacing: 16) {
                        header
                        weekdayHeader
                        monthGrid
                            .contentShape(Rectangle())
                            .gesture(monthSwipeGesture)
                    }
                    .padding(18)
                    // Solid card instead of `.regularMaterial` — backdrop-blur
                    // over an animated ambient layer is the dominant GPU cost.
                    .background(
                        (colorScheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white.opacity(0.96)),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 10, y: 4)

                    // Wave-B 4.2: range-select empty-state hint. Only
                    // shows when (a) the user has no logged days yet AND
                    // (b) they haven't dismissed the hint before AND
                    // (c) range-select isn't already engaged. Tap the
                    // hint to enter selecting mode immediately; tap the
                    // × to dismiss forever. Aligned with the design
                    // doctrine that empty states should invite, not
                    // instruct.
                    if records.isEmpty && !rangeHintDismissed && !selectingMode {
                        rangeSelectHintCard
                    }

                    // Poetic Legend Card
                    poeticLegendCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)

            // Frosted Custom Header Top Bar (Replaces NavigationStack style)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // In a sheet there's no status bar to clear (the parent owns
                    // it). A small breathing-room spacer is enough; using a
                    // `GeometryReader` here forced a re-layout pass per frame
                    // during scroll/resize.
                    Color.clear.frame(height: 8)
                    
                    HStack(spacing: 10) {
                        Text("Kalender")
                            .font(.system(size: 24, weight: .bold, design: .serif).italic())
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Button {
                            toggleSelectingMode()
                        } label: {
                            Text(selectingMode ? "Fertig wählen" : "Mehrere Tage")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectingMode ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectingMode
                                        ? Color(hex: 0xE87070)
                                        : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        selectingMode ? Color.clear : Color.primary.opacity(0.12),
                                        lineWidth: 1.0
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selectingMode ? "Mehrfachauswahl beenden" : "Mehrere Tage auswählen")

                        Button("Fertig") {
                            dismiss()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.0))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .background(
                    // Was `.ultraThinMaterial` — backdrop-blur of the
                    // animated ambient layer per frame was visible lag.
                    ZStack(alignment: .bottom) {
                        (colorScheme == .dark
                            ? Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.92)
                            : Color.white.opacity(0.90))
                        Rectangle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .frame(height: 0.5)
                    }
                )
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            rangeActionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .task { await reload() }
        .onChange(of: clock?.tick) { oldValue, newValue in
            // Task #110 — on TZ change or midnight, "today" moved.
            // Guard against the env-injection nil→0 transition that
            // fires on every cold launch right after `.task` already
            // ran reload() — without the guard we'd double-load.
            guard let oldValue, let newValue, newValue != oldValue else { return }
            Task { await reload() }
        }
        .sensoryFeedback(.selection, trigger: displayedMonth)
        .sheet(item: $editingDate, onDismiss: { Task { await reload() } }) { wrapped in
            LogDaySheet(date: wrapped.date)
        }
        .sheet(isPresented: $showRangePicker, onDismiss: {
            if let chosen = pickerChosenFlow {
                pickerChosenFlow = nil
                Task { await commitRangeWrite(flow: chosen) }
            }
        }) {
            RangeFlowPickerSheet(
                dayCount: selectedRangeDates.count,
                chosenFlow: $pickerChosenFlow
            )
        }
    }

    /// Bottom chip that appears in selecting mode once a range exists.
    /// Tap "Anwenden" → opens the flow picker. Tap "Abbrechen" → exits
    /// selecting mode. Also shows the brief "max. 31 Tage" hint and the
    /// post-write "X Tage eingetragen" confirmation banner.
    @ViewBuilder
    private var rangeActionBar: some View {
        if let result = lastBulkResult {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0x6BAA75))
                Text(bulkResultLabel(result))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                (colorScheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white.opacity(0.96)),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 8, y: 3)
            .task {
                // Auto-dismiss the banner after 3 s.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { lastBulkResult = nil }
            }
        } else if selectingMode && !selectedRangeDates.isEmpty {
            VStack(spacing: 8) {
                if showRangeCapHint {
                    Text("max. 31 Tage gleichzeitig")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                if futureDroppedCount > 0 {
                    Text("\(futureDroppedCount) Tag\(futureDroppedCount == 1 ? "" : "e") in der Zukunft übersprungen")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                HStack(spacing: 10) {
                    Text("\(selectedRangeDates.count) Tage ausgewählt")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Button("Anwenden") {
                        showRangePicker = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xE87070), in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    (colorScheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white.opacity(0.96)),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 10, y: 4)
            }
        }
    }

    private func bulkResultLabel(_ result: BulkLogResult) -> String {
        if result.written > 0 && result.removed == 0 {
            return "\(result.written) Tage eingetragen."
        } else if result.removed > 0 && result.written == 0 {
            return "\(result.removed) Tage entfernt."
        } else {
            return "\(result.totalProcessed) Tage aktualisiert."
        }
    }

    /// Horizontal swipe on the month grid → previous/next month.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.5 else { return }
                if dx < -50 {
                     shiftMonth(by: 1)
                } else if dx > 50 {
                     shiftMonth(by: -1)
                }
            }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 38, height: 38)
                    .background(
                        (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1.0))
            }
            .accessibilityLabel("Vorheriger Monat")
            Spacer()
            VStack(spacing: 4) {
                Text(monthTitle)
                    .font(.system(size: 19, weight: .bold, design: .serif).italic())
                    .foregroundStyle(Color.primary)
                // Audit Wave-A fix (1.5): "Heute" jump button. After
                // scrolling 6 months back to check "when did my period
                // start in November?", returning to today required
                // 6 chevron taps. This button collapses that to one.
                // Shown only when off-current-month so it doesn't add
                // noise in the steady-state view.
                if !isShowingCurrentMonth {
                    Button {
                        jumpToToday()
                    } label: {
                        Text("Heute")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color(red: 0.93, green: 0.48, blue: 0.48).opacity(0.12))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color(red: 0.93, green: 0.48, blue: 0.48).opacity(0.30), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zurück zum aktuellen Monat")
                    .accessibilityHint("Springt im Kalender zurück auf den heutigen Monat.")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isShowingCurrentMonth)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 38, height: 38)
                    .background(
                        (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1.0))
            }
            .accessibilityLabel("Nächster Monat")
        }
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.year().month(.wide))
    }

    /// True when `displayedMonth` is the current calendar month. Used to
    /// hide the "Heute" jump pill when it would be a no-op.
    private var isShowingCurrentMonth: Bool {
        let now = Date.now
        let displayed = cal.dateComponents([.year, .month], from: displayedMonth)
        let current = cal.dateComponents([.year, .month], from: now)
        return displayed.year == current.year && displayed.month == current.month
    }

    /// Audit Wave-A fix (1.5): jump back to the current month. Reuses
    /// the existing `shiftMonth` machinery (cancel pending reload,
    /// synchronous grid swap, then refetch) by setting the displayed
    /// month and recomputing the delta — keeps animation + perf-signpost
    /// behaviour identical to chevron taps.
    private func jumpToToday() {
        guard !isShowingCurrentMonth else { return }
        let now = Date.now
        let displayed = cal.dateComponents([.year, .month], from: displayedMonth)
        let current = cal.dateComponents([.year, .month], from: now)
        guard let dY = current.year, let dM = current.month,
              let bY = displayed.year, let bM = displayed.month
        else { return }
        // Total month delta = (Y-diff * 12) + M-diff. Positive = forward.
        let delta = (dY - bY) * 12 + (dM - bM)
        if delta != 0 {
            shiftMonth(by: delta)
        }
    }

    private func shiftMonth(by delta: Int) {
        PerfSignpost.interval("shiftMonth") {
            guard let new = cal.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
            monthTransitionDirection = delta
            isTransitioning = true
            withAnimation(.easeInOut(duration: 0.22)) {
                displayedMonth = new
                monthDays = computeMonthDays()
            }
            Task { await reload() }
        }
    }

    // MARK: - Weekday row

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.80))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grid

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            // Index-based ID: leading/trailing pad slots are all `nil` and
            // would collide under `id: \.self` (LazyVGrid logs "ID used by
            // multiple child views"). Indices are unique per slot.
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(for: date)
                } else {
                    Color.clear.frame(height: cellHeight)
                }
            }
        }
        // Whole-grid identity keyed on the (month, data-shape) tuple.
        //
        // Why `displayedMonth` alone wasn't enough (task #118 Path B):
        // when the user deleted a `DayEntry` from inside `LogDaySheet`,
        // the data layer correctly removed the row and rebuilt the
        // Cycle table, but `records.count` decreased while the month
        // stayed the same → the grid kept showing the cached cell with
        // its blood-drop indicator until the user swiped to a different
        // month and back. Including `records.count` + `cycleStarts.count`
        // in the identity flips the grid whenever the data shape
        // changes (delete, add, rebuild) without forcing a rebuild on
        // every reload — month-swipe perf is unchanged because the
        .id("\(displayedMonth.timeIntervalSinceReferenceDate)-\(reloadCounter)")
        .transition(.opacity)
    }

    private let cellHeight: CGFloat = 48

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let isToday = cal.isDate(date, inSameDayAs: .now)
        let record = records[date]
        let phase = phase(for: date)
        let color = phaseColor(phase)
        let inRange = isDateInSelectedRange(date)
        let isAnchor = isFirstAnchor(date)
        // Future dates are non-tappable in selecting mode (the store
        // would drop them anyway — better to disable visibly).
        let isFutureDay = date > Date.now.civilDay()
        
        let isInArrivalWindow = nextPrediction?.interval.contains(date.civilDay()) ?? false

        Button {
            if selectingMode {
                if !isFutureDay { tapInSelectingMode(date) }
            } else {
                editingDate = IdentifiableDate(date: date)
            }
        } label: {
            ZStack {
                if inRange {
                    // Task #160 — range-select uses teal, NOT the menses
                    // coral (0xE87070). Coral is reserved for "you logged
                    // / are predicted to have a period" — overloading it
                    // for "this day is part of the bulk-backfill range"
                    // made the two states visually ambiguous.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0x3E8890).opacity(colorScheme == .dark ? 0.30 : 0.18))
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08))
                        .shadow(color: .black.opacity(0.04), radius: 3)
                } else if phase != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(colorScheme == .dark ? 0.22 : 0.12))
                } else if isInArrivalWindow && !inRange {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0xE87070).opacity(colorScheme == .dark ? 0.16 : 0.08))
                }

                if isInArrivalWindow && !inRange {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color(hex: 0xE87070).opacity(colorScheme == .dark ? 0.85 : 0.65),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 3])
                        )
                }

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        inRange
                            // Task #160 — teal matches the range-select fill.
                            ? Color(hex: 0x3E8890).opacity(isAnchor ? 0.95 : 0.55)
                            : (isToday
                                ? Color.primary.opacity(0.35)
                                : (isInArrivalWindow && !inRange
                                    ? Color.clear
                                    : color.opacity(phase == nil ? 0.06 : 0.40))),
                        lineWidth: isAnchor ? 1.8 : 1.0
                    )

                VStack(spacing: 2) {
                    Text("\(cal.component(.day, from: date))")
                        .font(.system(size: 14, weight: (isToday || phase != nil || inRange || isInArrivalWindow) ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundColor(isToday ? .primary : (phase != nil || inRange || isInArrivalWindow ? Color.primary : .secondary))
                    HStack(spacing: 2) {
                        if let record, record.flow.rawValue >= FlowLevel.light.rawValue {
                            BloodDrop()
                                .fill(coral)
                                .frame(width: 5, height: 7)
                        }
                        if let record {
                            if record.hasSymptoms {
                                Circle()
                                    .fill(color.opacity(0.80))
                                    .frame(width: 3.5, height: 3.5)
                            }
                            if record.mood != nil {
                                Star()
                                    .fill(moodColor(for: record.mood))
                                    .frame(width: 6, height: 6)
                            }
                            if record.hasNote {
                                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                                    .fill(Color.primary.opacity(0.40))
                                    .frame(width: 5, height: 2)
                            }
                        }
                    }
                    .frame(height: 7)
                }
            }
            .frame(height: cellHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isToday && !inRange ? 1.05 : (inRange ? 1.03 : 1.0))
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: inRange)
            .opacity(selectingMode && isFutureDay ? 0.35 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, record: record, phase: phase))
    }

    // MARK: - Range-select helpers (task #79)

    private func toggleSelectingMode() {
        if selectingMode {
            // Exit cleanly — clear state so a re-entry starts fresh.
            selectingMode = false
            firstAnchor = nil
            secondAnchor = nil
            showRangeCapHint = false
        } else {
            selectingMode = true
            lastBulkResult = nil
        }
    }

    private func tapInSelectingMode(_ date: Date) {
        let civil = date.civilDay()
        // No first anchor → set it.
        guard let first = firstAnchor else {
            firstAnchor = civil
            return
        }
        // Tap on the existing first anchor → clear the range.
        if civil == first && secondAnchor == nil {
            firstAnchor = nil
            return
        }
        // Set / replace the second anchor. If the chosen range exceeds
        // the cap, we still record the tap but flip the hint flag so
        // the UI can show the inline message; the materialised range
        // returned by the helper will be the clamped 31-day version.
        secondAnchor = civil
        showRangeCapHint = CalendarRangeSelection.exceedsCap(
            firstAnchor: first,
            secondAnchor: civil,
            calendar: cal
        )
    }

    /// Materialised range, clamped to past-or-today. The store ALSO
    /// drops future dates (defence in depth), but doing the clamp in
    /// the UI keeps the day-count chip and the picker's "Auf N Tage
    /// anwenden" label honest — without this, tapping today + a
    /// future date would show e.g. "19 Tage" but only write 1.
    /// (Reviewer N3.)
    private var selectedRangeDates: [Date] {
        let raw = rawSelectedRangeDates
        let today = Date.now.civilDay()
        return raw.filter { $0 <= today }
    }

    /// Pre-clamp raw range. Used to detect "user tapped into the future"
    /// for the secondary hint.
    private var rawSelectedRangeDates: [Date] {
        guard let first = firstAnchor else { return [] }
        guard let second = secondAnchor else { return [first.civilDay()] }
        return CalendarRangeSelection.materialise(
            firstAnchor: first,
            secondAnchor: second,
            calendar: cal
        )
    }

    /// Count of selected dates that fell in the future (dropped from
    /// `selectedRangeDates`). Drives the "X Tage in der Zukunft
    /// übersprungen" hint. (Reviewer N3.)
    private var futureDroppedCount: Int {
        rawSelectedRangeDates.count - selectedRangeDates.count
    }

    private func isDateInSelectedRange(_ date: Date) -> Bool {
        // Use the RAW range here (not the future-clamped one) so the
        // user still sees their second tap land visually, even when it
        // sits in the future. The accompanying hint tells them those
        // days will be skipped; the cells are also dimmed via the
        // `isFutureDay` opacity branch in `dayCell`.
        guard selectingMode, !rawSelectedRangeDates.isEmpty else { return false }
        let civil = date.civilDay()
        return rawSelectedRangeDates.contains(civil)
    }

    private func isFirstAnchor(_ date: Date) -> Bool {
        guard selectingMode, let first = firstAnchor else { return false }
        return date.civilDay() == first
    }

    /// Commit the chosen flow against the materialised range. Closes
    /// selecting mode, surfaces a brief "X Tage eingetragen" banner,
    /// and reloads the calendar.
    private func commitRangeWrite(flow: FlowLevel) async {
        guard let store else { return }
        let dates = selectedRangeDates
        guard !dates.isEmpty else { return }
        let result = await store.logDayRange(dates: dates, flow: flow)
        lastBulkResult = result
        selectingMode = false
        firstAnchor = nil
        secondAnchor = nil
        showRangeCapHint = false
        await reload()
    }

    // MARK: - Poetic Legend

    /// Wave-B 4.2: empty-state nudge pointing at "Mehrere Tage". Lives
    /// directly below the calendar card so the user sees it after their
    /// eye finishes scanning the empty grid. Tap the card body to
    /// activate selecting mode (saves them finding the toolbar button);
    /// tap × to dismiss forever via the AppStorage flag.
    private var rangeSelectHintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hast du früher deinen Zyklus getrackt?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Tippe auf „Mehrere Tage\u{201C} oben rechts, um vergangene Tage schnell als Periode einzutragen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button {
                rangeHintDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hinweis ausblenden")
        }
        .padding(14)
        .background(
            (colorScheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white.opacity(0.96)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 0.93, green: 0.48, blue: 0.48).opacity(0.30), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 6, y: 2)
        .onTapGesture {
            // Card-body tap activates selecting mode directly so the
            // user doesn't have to find the toolbar button after
            // reading the hint. The × button still works because
            // SwiftUI hits the inner button first.
            toggleSelectingMode()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Doppeltippen aktiviert die Mehrfachauswahl.")
    }

    private var poeticLegendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Zyklusphasen & Bedeutung")
                .font(.system(size: 16, weight: .bold, design: .serif).italic())
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                legendRow(color: coral, name: "Menstruation", desc: "Zeit der Erneuerung & inneren Ruhe")
                legendRow(color: turquoise, name: "Follikelphase", desc: "Zeit des Aufbaus & kreativen Tatendrangs")
                legendRow(color: teal, name: "Ovulation", desc: "Zeit der Fülle, Ausstrahlung & Energie")
                legendRow(color: purple, name: "Lutealphase", desc: "Zeit der Einkehr & emotionalen Harmonie")
                
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            Color(hex: 0xE87070).opacity(0.60),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 3])
                        )
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erwarteter Periodenbeginn")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("90%-Intervall für den Start der nächsten Periode")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
        // Solid card — was `.regularMaterial`.
        .background(
            (colorScheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white.opacity(0.96)),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.03), radius: 8, y: 3)
    }

    private func legendRow(color: Color, name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.30 : 0.15))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(color.opacity(0.60), lineWidth: 1.0)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                Text(desc)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Date math

    /// Compute the day list for `displayedMonth`. Called once when the
    /// month changes (in `shiftMonth(by:)` and at first appear), result
    /// stored in `monthDays` so subsequent renders just read the array.
    private func computeMonthDays() -> [Date?] {
        var components = cal.dateComponents([.year, .month], from: displayedMonth)
        components.day = 1
        guard let firstOfMonth = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let weekday = cal.component(.weekday, from: firstOfMonth)  // 1 = Sun, 2 = Mon...
        // Convert to Monday-first: Mon=0, Tue=1, ..., Sun=6
        let leadingBlanks = (weekday + 5) % 7
        var out: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                out.append(d.civilDay())
            }
        }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    // MARK: - Phase lookup

    private func phase(for date: Date) -> CyclePhase? {
        phaseByDay[date]
    }

    /// Pre-compute one phase per visible day. Delegates the actual
    /// projection rules to `PhaseBoundaries.projectedPhase(...)` — see
    /// that helper for the closed-cycle (no modulo) vs. forward-projected
    /// (modulo wrap) distinction. mensesEnd per cycle is derived from
    /// the user's logged bleeding via `computeMensesEndByCycle`, sharing
    /// the same heuristic with the home-view phase strip.
    private func recomputePhases() {
        PerfSignpost.interval("recomputePhases") {
            recomputePhasesImpl()
        }
    }

    private func recomputePhasesImpl() {
        let starts = cycleStarts.map { $0.civilDay() }
        let cycleLen = max(averageLength, 1)
        let defaultMensesEnd = PhaseBoundaries.defaultMensesDuration

        // Pre-compute mensesEnd per cycle from the loaded records. Cycles
        // for which we have no bleeding data in the current ±2-month
        // window fall back to the population default of 5.
        let mensesEndByCycle = PerfSignpost.interval("computeMensesEnd") {
            computeMensesEndByCycle(starts: starts, defaultMensesEnd: defaultMensesEnd)
        }

        // Delegate per-day projection to the pure helper so the calendar +
        // the regression tests share one source of truth. See
        // `PhaseBoundaries.projectedPhase(for:...)` for the rules around
        // closed-cycle days (no modulo) vs. forward-projected days (modulo).
        var out: [Date: CyclePhase] = [:]
        for case let d? in monthDays {
            guard let phase = PhaseBoundaries.projectedPhase(
                for: d,
                cycleStarts: starts,
                cycleLength: cycleLen,
                mensesEndByCycle: mensesEndByCycle,
                defaultMensesEnd: defaultMensesEnd,
                calendar: cal
            ) else { continue }
            out[d] = phase
        }
        phaseByDay = out
    }

    /// For each cycle start, derive its `mensesEnd` from the bleeding days
    /// in `records`, sharing the algorithm with the home view via
    /// `PhaseBoundaries.mensesEnd(...)`. Cycles with no bleeding records
    /// loaded (because they fall outside the current ±2-month window) get
    /// the population default.
    ///
    /// We build a 1-indexed `Set<Int>` of bleeding days within this cycle
    /// and a clamped `todayDayInCycle` for the cycle, then delegate.
    private func computeMensesEndByCycle(starts: [Date], defaultMensesEnd: Int) -> [Date: Int] {
        var result: [Date: Int] = [:]
        let lightRaw = FlowLevel.light.rawValue
        let today = Date.now.civilDay()

        // Filter starts to cycles that can overlap with the visible month.
        // We only scan cycle starts that fall before the last day of the visible month
        // and no earlier than 50 days before the first day of the visible month.
        guard let firstDay = monthDays.compactMap({ $0 }).min(),
              let lastDay = monthDays.compactMap({ $0 }).max() else {
            return [:]
        }
        let minAllowedStart = cal.date(byAdding: .day, value: -50, to: firstDay) ?? firstDay
        let filteredStarts = starts.filter { $0 >= minAllowedStart && $0 <= lastDay }

        for s in filteredStarts {
            // Collect bleeding days for this cycle as 1-indexed offsets
            // (day 1 = `s` itself). Cap the scan at today and at the
            // window we care about (averageLength + buffer).
            var bleedingForThisCycle: Set<Int> = []
            let scanLimit = min(averageLength + 10, 60)
            for offset in 0..<scanLimit {
                guard let dayDate = cal.date(byAdding: .day, value: offset, to: s) else { break }
                let dayStart = dayDate.civilDay()
                if dayStart > today { break }
                if let record = records[dayStart], record.flow.rawValue >= lightRaw {
                    bleedingForThisCycle.insert(offset + 1)
                }
            }
            let daysSinceStart = cal.dateComponents([.day], from: s, to: today).day ?? 0
            let todayInThisCycle = max(1, daysSinceStart + 1)
            result[s] = PhaseBoundaries.mensesEnd(
                bleedingDays: bleedingForThisCycle,
                todayDayInCycle: todayInThisCycle,
                personalMedianMenses: personalMedianMenses,
                defaultMenses: defaultMensesEnd
            )
        }
        return result
    }

    private func phaseColor(_ phase: CyclePhase?) -> Color {
        switch phase {
        case .menses: return coral
        case .follicular: return turquoise
        case .ovulation: return teal
        case .lutealEarly, .lutealLate: return purple
        case nil: return .secondary
        }
    }

    private let coral = Color(hex: 0xE87070)
    private let turquoise = Color(hex: 0x82BDC4)
    private let teal = Color(hex: 0x3E8890)
    private let purple = Color(hex: 0x7A6098)

    // MARK: - Data load

    private func reload() async {
        let signpostID = PerfSignpost.begin("reload")
        defer {
            reloadCounter += 1
            isTransitioning = false
            PerfSignpost.end("reload", id: signpostID)
        }

        guard let store else { return }
        // Window the DayEntry fetch to the displayed month ±2 months so a
        // multi-year user doesn't pull every row on each sheet appearance.
        let center = displayedMonth.civilDay()
        let lo = cal.date(byAdding: .month, value: -2, to: center) ?? center
        let hi = cal.date(byAdding: .month, value: 2, to: center) ?? center
        // Five independent reads — fan out with `async let` so the actor
        // serves them concurrently instead of N sequential round-trips.
        async let entriesA = store.loggedDays(in: lo...hi)
        async let startsA = store.cycleStartDates()
        async let predLenA = store.predictedCycleLength()
        async let nextPredictionA = store.nextCalibratedPrediction(confidence: 0.90)
        async let personalMedianA = store.personalMedianMenses(limit: 6)
        let entries = await entriesA
        let starts = await startsA
        let predLenDouble = await predLenA
        let nextPred = await nextPredictionA
        let personalMed = await personalMedianA
        var dict: [Date: CalendarDayRecord] = [:]
        for e in entries {
            dict[e.date.civilDay()] = e
        }
        records = dict
        cycleStarts = starts
        averageLength = Int(round(predLenDouble))
        nextPrediction = nextPred
        personalMedianMenses = personalMed
        // First-load: populate the grid day list. On subsequent reloads
        // `shiftMonth(by:)` already keeps it in sync, but the very first
        // appear has an empty array.
        if monthDays.isEmpty {
            monthDays = computeMonthDays()
        }
        recomputePhases()
    }

    private func accessibilityLabel(for date: Date, record: CalendarDayRecord?, phase: CyclePhase?) -> String {
        var parts: [String] = [date.formatted(.dateTime.weekday(.wide).day().month())]
        if let phase {
            parts.append(phase.clinicalName)
        }
        let isInArrivalWindow = nextPrediction?.interval.contains(date.civilDay()) ?? false
        if isInArrivalWindow {
            parts.append("Erwarteter Periodenbeginn")
        }
        if let record, record.flow.rawValue >= FlowLevel.light.rawValue {
            parts.append("Blutung")
        }
        if record?.hasExtras == true {
            parts.append("Symptome geloggt")
        }
        return parts.joined(separator: ", ")
    }
}

private struct IdentifiableDate: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
}

struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2
        let rc = r * 0.4
        let points = 5
        var angle = -CGFloat.pi / 2
        let angleIncrement = CGFloat.pi / CGFloat(points)
        
        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? r : rc
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            angle += angleIncrement
        }
        path.closeSubpath()
        return path
    }
}

extension CalendarSheet {
    private func moodColor(for mood: Int?) -> Color {
        guard let mood else { return .secondary }
        switch mood {
        case 1: return Color(hex: 0x8A3040) // Very low
        case 2: return Color(hex: 0x7A6098) // Low
        case 3: return Color(hex: 0x82BDC4) // Neutral
        case 4: return Color(hex: 0x3E8890) // High
        case 5: return Color(hex: 0xE87070) // Very high (energy)
        default: return Color.primary.opacity(0.40)
        }
    }
}
