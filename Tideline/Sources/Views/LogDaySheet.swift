import SwiftUI

/// The single logging surface — used both as Quick-Log (today) and as the
/// day editor (any past date, reached from a calendar tap in Block 2).
///
/// Required: flow level + date. Everything else is optional and lives in
/// the "Weitere Details" disclosure to keep the Quick-Log path to two taps.
struct LogDaySheet: View {
    let initialDate: Date
    let initialFlow: FlowLevel
    let initialSymptoms: Set<String>
    let initialMood: Int?
    let initialNote: String

    @Environment(\.cycleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var date: Date
    @State private var flow: FlowLevel
    @State private var symptoms: Set<String>
    @State private var mood: Int?
    @State private var note: String
    @State private var detailsExpanded: Bool = false
    @State private var isSaving: Bool = false
    @State private var sheetDetent: PresentationDetent = .medium
    @State private var isDeleting: Bool = false
    /// Task #80 — shown above the Datum section the very first time
    /// the user opens this sheet (no prior cycles AND no existing entry
    /// for the picked date). Sets expectations that early predictions
    /// are still rough. Task #159 (2026-05-26) softened the previous
    /// "2-3 cycles" claim — the Bayesian NIG posterior keeps absorbing
    /// data for many more cycles than that before stabilising, and
    /// the specific number wasn't supported by the math.
    @State private var isFirstEntry: Bool = false

    /// Slide direction for date transitions. Positive = forward, negative = backward.
    @State private var dateTransitionDirection: Int = 0
    /// Unique identifier to trigger the horizontal transition animation during date transitions.
    @State private var dateAnimationTrigger: Int = 0
    /// Stored entry for the previous day, loaded asynchronously to determine if the "Aus dem Vortag übernehmen" button should be shown.
    @State private var previousDayEntry: DayEntrySnapshot? = nil

    /// Task #92 — set true the moment the user changes any control
    /// (flow, symptoms, mood, note). The `.task(id: initialDate)`
    /// rescue check this flag and skips the store-snapshot overwrite
    /// if the user has already started typing — otherwise a slow
    /// actor hop could clobber in-flight input. Cleared on
    /// initialDate change so the rescue can run for a fresh date
    /// even after the user edited a previous one.
    @State private var userHasEdited: Bool = false

    /// True after the `.task` rescue has loaded an existing DayEntry for
    /// `initialDate` — distinguishes "editing a saved day" from "creating
    /// a new entry." Used to gate the destructive `Eintrag löschen`
    /// button so it only appears in edit mode. Audit Wave-A fix (1.7):
    /// the red delete button was previously visible on never-logged days,
    /// which scared new users.
    @State private var hasExistingEntry: Bool = false

    /// Focus tracker for the notes TextField.
    ///
    /// Two issues motivated this:
    ///   1. The field lives at the bottom of the "Weitere Details"
    ///      disclosure — at `.medium` detent it sits *behind* the keyboard
    ///      when the user taps it, so they type blind. Watching the focus
    ///      lets us force `.large` *before* the keyboard rises.
    ///   2. A plain `ScrollView` does not auto-scroll to keep a focused
    ///      `TextField` above the keyboard (only `Form` / `List` do). So
    ///      `.scrollDismissesKeyboard(.interactively)` is paired with this
    ///      focus hook to give the user an obvious recovery gesture.
    @FocusState private var noteFieldFocused: Bool

    /// Cached top safe-area inset read once at view-init. Avoids per-frame
    /// `GeometryReader` measurements during sheet detent transitions.
    private static let topInset: CGFloat = {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let v = scene?.windows.first { $0.isKeyWindow }?.safeAreaInsets.top
            ?? scene?.windows.first?.safeAreaInsets.top
            ?? 47
        return v > 0 ? v : 47
    }()

    private var isFuture: Bool {
        date.civilDay() > Date.now.civilDay()
    }

    /// Wave-B 1.6: live count of items inside the Symptome & Stimmung
    /// disclosure section. Surfaced as a badge in the disclosure label
    /// so users see "I saved 3 things in there" without expanding.
    /// Counts symptoms (one per chip), mood-set (0 or 1), and a non-
    /// empty note (0 or 1). The note is binary because text length
    /// isn't a meaningful "amount" the user would expect to track.
    private var detailsCount: Int {
        symptoms.count
            + (mood != nil ? 1 : 0)
            + (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    init(
        date: Date = .now,
        // Audit Wave-A fix (1.1): default is `.medium`, not `.light`.
        // The most common reason to open this sheet on a new day is "my
        // period started today" — and medium is the modal first-day
        // flow per the daily-driver UX review (Flo/Clue parity). The
        // previous `.light` default forced one extra tap on every
        // first-day log, the single highest-frequency action in the app.
        // Existing-entry edits override this default via the `.task`
        // snapshot rescue at line ~381.
        flow: FlowLevel = .medium,
        symptoms: Set<String> = [],
        mood: Int? = nil,
        note: String = ""
    ) {
        self.initialDate = date
        self.initialFlow = flow
        self.initialSymptoms = symptoms
        self.initialMood = mood
        self.initialNote = note
        _date = State(initialValue: date)
        _flow = State(initialValue: flow)
        _symptoms = State(initialValue: symptoms)
        _mood = State(initialValue: mood)
        _note = State(initialValue: note)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Cream/dark wash + ambient tide layer in a child view so its
            // 15fps tick doesn't invalidate the whole sheet (form fields,
            // disclosure groups, save/delete state would all churn).
            PageBackground.color(scheme: colorScheme)
                .ignoresSafeArea()
            AmbientTideBackground(primary: coral, secondary: turquoise)

            // Scrollable Content
            //
            // Wrapped in `ScrollViewReader` so the focus handler at the
            // sheet level can scroll the Notiz section above the
            // keyboard when the user taps the field. SwiftUI's default
            // `ScrollView` (unlike `Form` / `List`) does not auto-scroll
            // to a focused TextField, so the lower portion of a
            // multi-line note ended up hidden behind the keyboard until
            // we wired this up. (Task #89 follow-up bug.)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // Reserve room only for the top bar's HStack height,
                    // not for a phantom status bar. Sheets get a small drag
                    // indicator + their own implicit top inset.
                    Spacer().frame(height: 56)

                    // Task #80 — first-entry contextual hint.
                    if isFirstEntry {
                        opaqueCard {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Color(red: 0.93, green: 0.48, blue: 0.48))
                                    .font(.system(size: 18))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Dein erster Eintrag")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Tideline lernt deinen Rhythmus mit jedem geloggten Zyklus dazu — die ersten Schätzungen sind noch grob.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // Task #131 — VoiceOver reads the hint as one
                            // utterance instead of icon + headline + body
                            // as 3 separate elements.
                            .accessibilityElement(children: .combine)
                        }
                    }

                    // Section: Datum
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Datum")
                        opaqueCard {
                            VStack(alignment: .leading, spacing: 10) {
                                DatePicker(
                                    "Tag",
                                    selection: $date,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .font(.system(size: 15, weight: .semibold))
                                
                                if isFuture {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "info.circle")
                                                .accessibilityHidden(true)
                                            Text("Zukünftige Tage werden nicht in die Vorhersage einbezogen.")
                                        }
                                        // Audit Wave-A fix (4.2): the previous copy
                                        // implied the entry was BLOCKED, but the
                                        // sheet does still save the row — only the
                                        // predictor ignores it. Spelling that out
                                        // removes the "is this broken?" doubt.
                                        Text("Der Eintrag wird trotzdem gespeichert.")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }

                    // Section: Blutung
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Blutung")
                        opaqueCard {
                            FlowLevelPicker(selection: trackedBinding($flow))
                        }
                    }

                    // Section: Symptome & Stimmung.
                    //
                    // Wave-B fix (1.6): renamed from generic "Weitere
                    // Details" to the concrete contents ("Symptome &
                    // Stimmung"). The agent UX review found that "Weitere
                    // Details" + the plus-circle glyph read as "add a new
                    // section" rather than "expand hidden fields" — users
                    // who wanted to log a headache or mood didn't find
                    // their way in. Naming the contents directly + a live
                    // count badge inside the label both teach the
                    // mechanic AND confirm "yes, I saved 3 items here."
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Symptome & Stimmung")
                        opaqueCard {
                            DisclosureGroup(
                                isExpanded: disclosureBinding,
                                content: {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        // Quick Copy row
                                        if let prevEntry = previousDayEntry {
                                            Button {
                                                copyFromYesterday(prevEntry)
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "wand.and.stars")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.white)
                                                    Text("Aus dem Vortag übernehmen")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(.white)
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(coral, in: Capsule())
                                                .shadow(color: coral.opacity(0.30), radius: 6, y: 2)
                                            }
                                            .buttonStyle(.plain)
                                            .transition(.scale.combined(with: .opacity))
                                            .padding(.bottom, 6)
                                        }
                                        
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        // Symptome Sub-section
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Symptome")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            SymptomGrid(selected: trackedBinding($symptoms))
                                        }
                                        
                                        Divider()
                                        
                                        // Mood Sub-section
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Stimmung")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            MoodPicker(selection: trackedBinding($mood))
                                        }
                                        
                                        Divider()
                                        
                                        // Note Sub-section
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Notiz")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            // Notes field styled as a card sub-element
                                            // (corner radius 12 inside the parent's 20)
                                            // — matches the rest of the sheet instead of
                                            // looking like a stock iOS TextField. Bound
                                            // to `noteFieldFocused` so we can lift the
                                            // sheet to `.large` before the keyboard
                                            // covers the field.
                                            TextField("Optional hinzufügen...", text: trackedBinding($note), axis: .vertical)
                                                .lineLimit(2...5)
                                                .focused($noteFieldFocused)
                                                .id("noteField")
                                                .padding(12)
                                                .background(
                                                    (colorScheme == .dark
                                                        ? Color(red: 0.22, green: 0.22, blue: 0.24)
                                                        : Color.black.opacity(0.04)),
                                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                                )
                                        }
                                    }
                                    .padding(.top, 4)
                                },
                                label: {
                                    HStack {
                                        // Wave-B 1.6 — glyph swap from
                                        // `plus.circle.fill` (reads as
                                        // "add a new section") to a
                                        // semantic glyph for the contents
                                        // (heart.text.square = "personal
                                        // notes/details"). Conveys
                                        // "expand to edit" not "create."
                                        Image(systemName: "heart.text.square")
                                            .font(.system(size: 16))
                                            .foregroundStyle(coral)
                                            .accessibilityHidden(true)
                                        Text("Symptome & Stimmung")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(Color.primary)
                                        // Wave-B 1.6 — live count badge.
                                        // Shows the number of currently-
                                        // selected items (symptoms +
                                        // mood-set + non-empty note). Tiny
                                        // capsule next to the title so a
                                        // glance answers "did I save
                                        // those extras?" without expanding.
                                        if detailsCount > 0 {
                                            Text("\(detailsCount)")
                                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(coral))
                                                .accessibilityLabel("\(detailsCount) Einträge ausgewählt")
                                        }
                                    }
                                }
                            )
                        }
                    }

                    // Section: Delete entry.
                    //
                    // Audit Wave-A fix (1.7): gated on `hasExistingEntry`.
                    // The red destructive button used to render on every
                    // sheet — including never-logged days — which spooked
                    // first-time users tapping a fresh date from the
                    // calendar. The destructive affordance now only
                    // appears when there's actually something to delete.
                    if hasExistingEntry {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(role: .destructive) {
                                Task { await delete() }
                            } label: {
                                HStack {
                                    if isDeleting {
                                        ProgressView()
                                            .accessibilityLabel("Eintrag wird gelöscht")
                                    } else {
                                        Image(systemName: "trash")
                                            .accessibilityHidden(true)
                                    }
                                    Text("Eintrag löschen")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                // Was `.ultraThinMaterial` — backdrop blur of the
                                // ambient layer per frame during sheet resize.
                                .background(
                                    (colorScheme == .dark ? Color(red: 0.20, green: 0.10, blue: 0.10) : Color.red.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 18)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.red.opacity(0.20), lineWidth: 1.0))
                                .shadow(color: Color.red.opacity(0.05), radius: 6, y: 3)
                            }
                            .disabled(isDeleting || isSaving)
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .id(dateAnimationTrigger)
                .transition(.asymmetric(
                    insertion: .move(edge: dateTransitionDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: dateTransitionDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .scrollIndicators(.hidden)
            // Lets the user swipe the keyboard down without losing the
            // notes field. Paired with the focus → .large detent hook
            // below (see `noteFieldFocused` docstring).
            .scrollDismissesKeyboard(.interactively)
            // On focus, scroll the Notiz field into the visible area
            // above the keyboard. Without this, multi-line notes get
            // clipped at the bottom by the keyboard frame (a plain
            // ScrollView doesn't auto-scroll to a focused TextField).
            // Delayed slightly so the detent change → .large completes
            // first; otherwise we'd scroll inside the old .medium frame
            // and the destination position would be wrong.
            .onChange(of: noteFieldFocused) { _, focused in
                guard focused else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("noteField", anchor: .center)
                    }
                }
            }
            } // end ScrollViewReader

            // Frosted Custom Header Top Bar
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // No status-bar inset reserved inside a sheet — the sheet
                    // already sits below the system status bar, so adding the
                    // window's 47pt inset on top pushed the bar down and the
                    // "Datum" section header up behind the bar. A small
                    // breathing-room spacer is all that's needed.
                    Color.clear.frame(height: 8)
                    
                    HStack {
                        Button("Abbrechen") { dismiss() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                shiftDate(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(coral)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.primary.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Vorheriger Tag")

                            Text(date.formatted(.dateTime.day().month(.wide)))
                                .font(.system(size: 19, weight: .bold, design: .serif).italic())
                                .foregroundStyle(Color.primary)
                                .accessibilityAddTraits(.isHeader)
                                .id("headerDateText-" + date.formatted(.dateTime.day().month(.wide)))
                                .transition(.opacity)

                            Button {
                                shiftDate(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(coral)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.primary.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Nächster Tag")
                        }
                        Spacer()
                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .accessibilityLabel("Wird gespeichert")
                            } else {
                                Text("Speichern").bold()
                                    .font(.system(size: 15))
                            }
                        }
                        .disabled(isSaving)
                        .foregroundStyle(coral)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .background(
                    // Solid + faint translucent over ambient. Was `.ultraThinMaterial`
                    // which forces a backdrop blur of the animated ambient layer on
                    // every sheet-resize frame — measurable hit when expanding from
                    // medium to large detent.
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
        .task(id: date) {
            // Reset transient first-entry flag — if the view instance is
            // reused across date changes, a prior date's hint would otherwise linger.
            isFirstEntry = false
            hasExistingEntry = false
            userHasEdited = false
            
            guard let store else { return }
            let snapshot = await store.dayEntry(for: date)
            
            // If the user managed to type during the actor hop, keep their input instead of clobbering it.
            guard !userHasEdited else { return }
            if let snapshot {
                hasExistingEntry = true
                flow = snapshot.flow
                symptoms = snapshot.symptoms
                mood = snapshot.mood
                note = snapshot.note
                if snapshot.mood != nil || !snapshot.symptoms.isEmpty || !snapshot.note.isEmpty {
                    detailsExpanded = true
                }
            } else {
                hasExistingEntry = false
                flow = .medium // default flow level for a fresh day entry
                symptoms = []
                mood = nil
                note = ""
                detailsExpanded = false
            }
            
            // Check for first entry hint
            if snapshot == nil {
                let observedCount = await store.observedCycleCount()
                if observedCount == 0 {
                    isFirstEntry = true
                }
            }
            
            // Fetch the previous day's entry to see if we can offer a copy action
            if let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: date) {
                previousDayEntry = await store.dayEntry(for: prevDate)
            } else {
                previousDayEntry = nil
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        // When the user taps the notes field, hop the sheet to `.large`
        // *before* the keyboard rises — otherwise the field sits behind
        // the keyboard at `.medium` and the user types blind. Direct
        // assignment (not through `disclosureBinding`) so we don't also
        // toggle `detailsExpanded` redundantly.
        .onChange(of: noteFieldFocused) { _, focused in
            if focused, sheetDetent != .large {
                Task { @MainActor in
                    sheetDetent = .large
                }
            }
        }
    }

    /// Custom binding for the `DisclosureGroup`. Only the user's manual
    /// tap on the disclosure header (which writes through this setter)
    /// changes the sheet detent. Programmatic writes to `detailsExpanded`
    /// from the `.task` snapshot loader bypass the setter and therefore
    /// do NOT trigger a detent animation mid-rise.
    ///
    /// Background: the previous `.onChange(of: detailsExpanded)` couldn't
    /// distinguish auto-load from user-tap, so opening a historical day
    /// with mood/symptoms/note saved triggered a medium→large detent
    /// change while the sheet was still rising to medium — two competing
    /// animations producing the half-detent jank the user reported.
    private var disclosureBinding: Binding<Bool> {
        Binding(
            get: { detailsExpanded },
            set: { newValue in
                detailsExpanded = newValue
                // Defer the detent change one runloop tick so it doesn't
                // batch with the disclosure-expansion render pass — the
                // presentation API otherwise drives both inside the same
                // implicit animation and produces a choppy resize.
                Task { @MainActor in
                    sheetDetent = newValue ? .large : .medium
                }
            }
        )
    }

    /// Wraps a state binding so user-initiated mutations flip the
    /// `userHasEdited` flag, while programmatic writes from the
    /// `.task` rescue do NOT (they assign to the underlying @State
    /// directly). Task #92 — closes the race where a slow actor hop
    /// would overwrite in-flight typing.
    private func trackedBinding<V>(_ source: Binding<V>) -> Binding<V> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                userHasEdited = true
                source.wrappedValue = newValue
            }
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .serif).italic())
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 6)
            // Task #131 — VoiceOver navigates by header. Every section
            // header in this sheet ("Datum", "Blutung", "Weitere Details")
            // gets the trait so the user can rotor-jump between sections.
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func opaqueCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(colorScheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 8, x: 0, y: 3)
    }

    private func delete() async {
        guard let store else {
            dismiss()
            return
        }
        isDeleting = true
        await store.deleteDay(date: date)
        isDeleting = false
        dismiss()
    }

    private func save() async {
        guard let store else {
            assertionFailure("LogDaySheet was presented without a CycleStore in the environment")
            dismiss()
            return
        }
        isSaving = true
        await store.logDay(
            date: date,
            flow: flow,
            symptoms: Array(symptoms),
            mood: mood,
            note: note
        )
        isSaving = false
        dismiss()
    }

    private func shiftDate(by days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        dateTransitionDirection = days
        userHasEdited = false // Navigation resets editing state for the newly paged day
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            date = newDate
            dateAnimationTrigger += 1
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func copyFromYesterday(_ snapshot: DayEntrySnapshot) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            userHasEdited = true
            symptoms = snapshot.symptoms
            mood = snapshot.mood
            note = snapshot.note
            if snapshot.mood != nil || !snapshot.symptoms.isEmpty || !snapshot.note.isEmpty {
                detailsExpanded = true
                sheetDetent = .large
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private let coral = Color(hex: 0xE87070)
    private let turquoise = Color(hex: 0x82BDC4)
}

#Preview {
    LogDaySheet()
}
