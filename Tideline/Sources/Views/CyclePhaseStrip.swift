import SwiftUI
import SwiftData

/// Slider-style phase strip showing the current cycle on a single horizontal
/// gradient bar. Layers, top to bottom:
///
///   1. Phase labels (4: Menstruation / Follikelphase / Ovulation / Lutealphase)
///      positioned dynamically from `PhaseBoundaries`.
///   2. Tick dots — 29 small circles, one per day, today highlighted.
///   3. Gradient bar (8pt) + thumb (22pt) — thumb anchored to today.
///   4. Connector line from thumb down into the day-numbers row.
///   5. Day numbers — only days 1, 5, 10, today, 20, 25, cycleLength.
///   6. Bleeding-drop row — `BloodDrop` shape on each bleeding day.
///   7. Divider + summary text with bold inline labels.
///
/// Drag along the bar selects a day → popover preview → Bearbeiten →
/// `LogDaySheet` (edit mode). `onDataChanged` fires on sheet dismiss so the
/// parent can refresh.
struct CyclePhaseStrip: View {
    let cycleStartDate: Date
    let boundaries: PhaseBoundaries
    let bleedingDays: Set<Int>       // 1-indexed cycle days where flow >= .light
    let today: Int                   // current cycle day (1-indexed)
    let useTideNaming: Bool
    /// Audit Wave-A fix (1.4): the next-period prediction string from the
    /// hero, echoed in the strip summary so it stays visible after the
    /// user scrolls past the atmospheric layer. Nil when the predictor
    /// has no opinion (paused / retired / pre-3-cycles low-data state).
    var predictionText: String? = nil
    var onDataChanged: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var previewDay: IdentifiableDay? = nil
    @State private var editingDay: IdentifiableDay? = nil
    @State private var activePopoverPhase: CyclePhase? = nil

    // Layout constants (per design handoff README).
    private let labelsHeight: CGFloat = 16
    private let tickDotsHeight: CGFloat = 8
    private let barHeight: CGFloat = 8
    private let thumbDiameter: CGFloat = 22
    private let connectorHeight: CGFloat = 6
    private let dayNumberHeight: CGFloat = 14
    private let dropsHeight: CGFloat = 11

    // Colors from spec.
    private let coral = Color(hex: 0xE87070)
    private let turquoise = Color(hex: 0x82BDC4)
    private let teal = Color(hex: 0x3E8890)
    private let purple = Color(hex: 0x7A6098)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            phaseLabelsRow
            thumbLabelRow
            tickDotsRow
            barWithThumb
            connectorLine
            loggedDaysRow
            Divider().padding(.top, 8)
            summaryText
        }
        .sheet(item: $editingDay, onDismiss: { onDataChanged?() }) { wrapped in
            LogDaySheet(date: dateForDay(wrapped.day))
        }
    }

    // MARK: - Layer 1: phase labels

    private var highlightedPhase: CyclePhase {
        if let preview = previewDay {
            return boundaries.phase(forDay: preview.day)
        }
        return boundaries.phase(forDay: today)
    }

    private func isPhaseActive(_ entryPhase: CyclePhase) -> Bool {
        let active = highlightedPhase
        if entryPhase == .lutealEarly {
            return active == .lutealEarly || active == .lutealLate
        }
        return entryPhase == active
    }

    private var phaseLabelsRow: some View {
        HStack(spacing: 0) {
            ForEach(phaseLabelEntries, id: \.id) { entry in
                let isActive = isPhaseActive(entry.phase)
                Button {
                    activePopoverPhase = entry.phase
                } label: {
                    Text(entry.text)
                        // Task #132 — semantic TextStyle scales with Dynamic
                        // Type; the previous 11pt fixed size truncated at AX5.
                        .font(.caption.weight(isActive ? .bold : .medium))
                        .foregroundColor(isActive ? entry.color : .secondary.opacity(0.65))
                        .scaleEffect(isActive ? 1.05 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.text), Tippe für Details")
            }
        }
        .frame(height: labelsHeight)
        .popover(item: Binding<IdentifiablePhase?>(
            get: { activePopoverPhase.map { IdentifiablePhase(phase: $0) } },
            set: { activePopoverPhase = $0?.phase }
        )) { wrapped in
            VStack(alignment: .leading, spacing: 10) {
                Text(wrapped.phase.compactLabel(useTideNaming: useTideNaming))
                    // Task #132 — scales with Dynamic Type.
                    .tidelineSerifHeadline(size: 16, relativeTo: .headline)
                    .foregroundStyle(phaseColor(wrapped.phase))

                Text(wellnessText(for: wrapped.phase))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 280)
            .background(.ultraThinMaterial)
            .presentationCompactAdaptation(.popover)
        }
    }

    private struct PhaseLabelEntry: Identifiable {
        let id: String
        let text: String
        let phase: CyclePhase
        let color: Color
    }

    private var phaseLabelEntries: [PhaseLabelEntry] {
        [
            .init(
                id: "menses",
                text: CyclePhase.menses.compactLabel(useTideNaming: useTideNaming),
                phase: .menses,
                color: coral
            ),
            .init(
                id: "follicular",
                text: CyclePhase.follicular.compactLabel(useTideNaming: useTideNaming),
                phase: .follicular,
                color: turquoise
            ),
            .init(
                id: "ovulation",
                text: CyclePhase.ovulation.compactLabel(useTideNaming: useTideNaming),
                phase: .ovulation,
                color: teal
            ),
            .init(
                id: "luteal",
                text: CyclePhase.lutealEarly.compactLabel(useTideNaming: useTideNaming),
                phase: .lutealEarly,
                color: purple
            )
        ]
    }

    private func clamp(_ f: CGFloat) -> CGFloat { max(0.08, min(0.92, f)) }

    // MARK: - Layer 2: tick dots

    /// Day the thumb + highlights currently point at — follows the user's drag
     /// when active, otherwise rests on `today`.
    private var selectedDay: Int { previewDay?.day ?? today }

    private var tickDotsRow: some View {
        HStack(spacing: 0) {
            ForEach(1...boundaries.cycleLength, id: \.self) { day in
                let isSelected = day == selectedDay
                let isToday = day == today
                Circle()
                    .fill(isSelected ? thumbColor : Color.secondary)
                    .frame(width: isSelected ? 4.5 : (isToday ? 3.5 : 2.5),
                           height: isSelected ? 4.5 : (isToday ? 3.5 : 2.5))
                    .opacity(isSelected ? 1.0 : (isToday ? 0.55 : 0.28))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: tickDotsHeight)
    }

    // MARK: - Layer 3: gradient bar + thumb

    private var barWithThumb: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(barGradient)
                    .frame(height: barHeight)
                    .position(x: proxy.size.width / 2, y: thumbDiameter / 2)

                // Task #161 — static "today" tick. The thumb follows the
                // drag (`selectedDay = previewDay?.day ?? today`), which
                // means when the user previews another day the today
                // anchor disappears entirely. This 1.5pt vertical bar
                // stays at today's x position regardless of drag, so the
                // user always has a visual answer to "where am I now?"
                //
                // Visibility rule (reviewer follow-up): show only when
                // `previewDay` is set AND points to a day other than
                // today. Without the day-aware check the tick stays on
                // forever once dragged (previewDay isn't auto-cleared)
                // and worst-case duplicates the thumb's center line when
                // the user drags back to today.
                if let preview = previewDay, preview.day != today {
                    Rectangle()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.55 : 0.45))
                        .frame(width: 1.5, height: thumbDiameter + 6)
                        .position(x: xForDayInBar(today, width: proxy.size.width),
                                  y: thumbDiameter / 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                Circle()
                    .fill(thumbColor)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle().stroke(thumbRingColor, lineWidth: 2.0)
                    )
                    .shadow(color: thumbColor.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 6, x: 0, y: 3)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 4, x: 0, y: 2)
                    .position(x: thumbX(in: proxy.size.width), y: thumbDiameter / 2)
            }
            // Hit target spans the entire bar height plus the thumb so taps
            // adjacent to the bar still land on a day.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let day = dayFromX(value.location.x, width: proxy.size.width)
                        if previewDay?.day != day {
                            previewDay = IdentifiableDay(day)
                        }
                    }
            )
            .sensoryFeedback(.selection, trigger: previewDay?.day)
            // Task #131 — VoiceOver can't drag. Expose the slider as
            // an adjustable element: VoiceOver users swipe up/down to
            // increment/decrement the selected day. The value is
            // announced as "Tag N of M".
            .accessibilityElement()
            .accessibilityLabel("Zyklustag-Auswahl")
            .accessibilityValue("Tag \(selectedDay) von \(boundaries.cycleLength)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if selectedDay < boundaries.cycleLength {
                        previewDay = IdentifiableDay(selectedDay + 1)
                    }
                case .decrement:
                    if selectedDay > 1 {
                        previewDay = IdentifiableDay(selectedDay - 1)
                    }
                @unknown default:
                    break
                }
            }
        }
        .frame(height: thumbDiameter)
    }

    /// Gradient stops computed from `PhaseBoundaries` — coral at the start,
    /// turquoise at the menses/follicular boundary, teal at ovulation, purple
    /// from luteal start to the end.
    private var barGradient: LinearGradient {
        let cl = CGFloat(max(boundaries.cycleLength, 1))
        // Map cycle days to fractions using cell-centered math so the gradient
        // aligns with the tick-dot + thumb positions (which use (day-0.5)/cl).
        // Each phase is given a solid plateau followed by a narrow blend zone
        // into the next phase — this prevents the bar from looking "already
        // follicular" on day 2 when the menses plateau used to be tiny.
        let blendHalf: CGFloat = 0.025  // half-width of the blend zone between two phases
        let mensesEnd = CGFloat(boundaries.mensesEnd) / cl           // end of menses (inclusive)
        let follicEnd = CGFloat(boundaries.ovulationWindowStart - 1) / cl
        let ovuEnd = CGFloat(boundaries.ovulationWindowEnd) / cl
        let lutEarlyEnd = CGFloat(boundaries.lutealEarlyEnd) / cl
        return LinearGradient(
            stops: [
                .init(color: coral,     location: 0),
                .init(color: coral,     location: clamp(mensesEnd - blendHalf)),
                .init(color: turquoise, location: clamp(mensesEnd + blendHalf)),
                .init(color: turquoise, location: clamp(follicEnd - blendHalf)),
                .init(color: teal,      location: clamp(follicEnd + blendHalf)),
                .init(color: teal,      location: clamp(ovuEnd - blendHalf)),
                .init(color: purple,    location: clamp(ovuEnd + blendHalf)),
                .init(color: purple,    location: clamp(lutEarlyEnd)),
                .init(color: purple,    location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var thumbColor: Color {
        colorScheme == .dark ? Color(hex: 0x9CC8CC) : Color(hex: 0x1C3B41)
    }

    private var thumbRingColor: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.16) : Color.white
    }

    private func thumbX(in width: CGFloat) -> CGFloat {
        let frac = (CGFloat(selectedDay) - 0.5) / CGFloat(max(boundaries.cycleLength, 1))
        return width * max(0, min(1, frac))
    }

    /// Task #161 — same cell-centred math as `thumbX(in:)` but for an
    /// arbitrary day. Used to position the static today-tick that stays
    /// put while the user drags the thumb.
    private func xForDayInBar(_ day: Int, width: CGFloat) -> CGFloat {
        let frac = (CGFloat(day) - 0.5) / CGFloat(max(boundaries.cycleLength, 1))
        return width * max(0, min(1, frac))
    }

    private func dayFromX(_ x: CGFloat, width: CGFloat) -> Int {
        let clampedX = max(0, min(width - 0.001, x))
        let day = Int((clampedX / width) * CGFloat(boundaries.cycleLength)) + 1
        return max(1, min(boundaries.cycleLength, day))
    }

    // MARK: - Layer 4: connector

    private var connectorLine: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(thumbColor)
                .frame(width: 1.0, height: connectorHeight)
                .opacity(0.32)
                .position(x: thumbX(in: proxy.size.width), y: connectorHeight / 2)
        }
        .frame(height: connectorHeight)
    }

    // MARK: - Layer 5: day numbers

    /// Floating "Tag X · Datum" pill above the bar at the thumb position.
    /// Replaces the previous row of all 29 day numbers — only the selected
    /// day is labeled, plus per-day pills under bleeding days in `loggedDaysRow`.
    private var thumbLabelRow: some View {
        GeometryReader { proxy in
            let dateStr = dateForDay(selectedDay).formatted(.dateTime.day().month())
            Text("Tag \(selectedDay) · \(dateStr)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(thumbColor))
                .fixedSize()
                .position(x: pinnedX(thumbX(in: proxy.size.width), pillWidth: pillEstimatedWidth, totalWidth: proxy.size.width),
                          y: 9)
        }
        .frame(height: 18)
    }

    private var pillEstimatedWidth: CGFloat { 92 }

    private func pinnedX(_ x: CGFloat, pillWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let half = pillWidth / 2
        return min(max(x, half), totalWidth - half)
    }

    /// Replaces the old dayNumbersRow + dropsRow. Shows:
    ///   - BloodDrop + day number on every bleeding day (coral)
    ///   - tiny "1" and "cycleLength" anchors at the edges (dim)
    ///   - nothing on other days
    private var loggedDaysRow: some View {
        HStack(spacing: 0) {
            ForEach(1...boundaries.cycleLength, id: \.self) { day in
                let isBleeding = bleedingDays.contains(day)
                let isAnchor = day == 1 || day == boundaries.cycleLength
                VStack(spacing: 2) {
                    if isBleeding {
                        BloodDrop()
                            .fill(coral)
                            .frame(width: 6, height: 8)
                        Text("\(day)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundColor(coral)
                    } else if isAnchor {
                        Color.clear.frame(width: 1, height: 8)
                        Text("\(day)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(.secondary.opacity(0.55))
                    } else {
                        Color.clear.frame(width: 1, height: 8)
                        Color.clear.frame(height: 11)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Layer 7: summary text

    private var isDragging: Bool {
        previewDay != nil
    }

    private var summaryTitle: String {
        if isDragging {
            let phase = boundaries.phase(forDay: selectedDay)
            let name = useTideNaming ? phase.tideName : phase.clinicalName
            return "Tag \(selectedDay) — \(name) (Vorschau)"
        } else {
            return "Erkenntnisse"
        }
    }

    private var summaryText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summaryTitle)
                    // Task #132 — scales with Dynamic Type.
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 4)
                Button {
                    editingDay = IdentifiableDay(selectedDay)
                } label: {
                    Text("Bearbeiten →")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(thumbColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tag \(selectedDay) bearbeiten")
            }
            if let next = makeNextPhaseSentence() {
                Text(next)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let bleed = makeBleedingSentence() {
                Text(bleed)
                    .font(.subheadline)
            }
            // Audit Wave-A fix (1.8): Tideline derives the end of menses
            // silently via the Belsey ≤2-day rule. Without a visible
            // hint, a user who stopped bleeding yesterday sees "Tag 6 —
            // Menstruation" today and thinks the app is broken. Surface
            // a one-line nudge during the 1–2-day suspended window when
            // we plausibly think the period just ended.
            if let ended = makePeriodEndedHint() {
                Text(ended)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    /// "Kein Eintrag heute? Tideline schließt auf Ende der Blutung."
    ///
    /// Audit Wave-A fix (1.8). Shows during a 1–2-day window after the
    /// most recent logged bleeding day, when today is NOT itself a
    /// bleeding day. Outside that window the inference is either
    /// uncertain (long gap → user may have logged spotting after a
    /// gap → not actually period end) or moot (still bleeding).
    private func makePeriodEndedHint() -> String? {
        guard let lastBleed = bleedingDays.max() else { return nil }
        guard !bleedingDays.contains(today) else { return nil }
        let daysSinceLast = today - lastBleed
        guard (1...2).contains(daysSinceLast) else { return nil }
        return "Kein Eintrag heute? Tideline schließt auf Ende der Blutung."
    }

    private func makeSelectedDaySentence() -> AttributedString {
        let phase = boundaries.phase(forDay: selectedDay)
        let name = useTideNaming ? phase.tideName : phase.clinicalName
        let prefix: String
        if selectedDay == today {
            prefix = "Heute: "
        } else {
            let dateStr = dateForDay(selectedDay).formatted(.dateTime.day().month())
            prefix = "\(dateStr): "
        }
        var s = AttributedString(prefix)
        s.font = .system(size: 15, weight: .bold)
        var rest = AttributedString("Tag \(selectedDay) — \(name)")
        rest.font = .system(size: 15)
        s.append(rest)
        return s
    }

    private func makeNextPhaseSentence() -> String? {
        let currentPhase = boundaries.phase(forDay: today)
        guard let (nextPhase, startDay) = upcomingPhase(after: currentPhase, currentDay: today) else {
            return nil
        }
        let daysUntil = startDay - today
        let nextName = useTideNaming ? nextPhase.tideName : nextPhase.clinicalName
        switch daysUntil {
        case 0: return "\(nextName) beginnt heute."
        case 1: return "\(nextName) beginnt morgen."
        case 2: return "\(nextName) beginnt übermorgen."
        default: return "\(nextName) beginnt in \(daysUntil) Tagen."
        }
    }

    private func upcomingPhase(after current: CyclePhase, currentDay: Int) -> (CyclePhase, Int)? {
        let phases: [(CyclePhase, Int)] = [
            (.menses, 1),
            (.follicular, boundaries.follicularStart),
            (.ovulation, boundaries.ovulationWindowStart),
            (.lutealEarly, boundaries.lutealEarlyStart),
            (.lutealLate, boundaries.lutealLateStart)
        ]
        return phases.first { phase, startDay in
            phase != current && startDay > currentDay
        }
    }

    private func makeBleedingSentence() -> AttributedString? {
        let sorted = bleedingDays.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let firstDate = dateForDay(first).formatted(.dateTime.day().month())
        let lastDate = dateForDay(last).formatted(.dateTime.day().month())
        var s = AttributedString("Blutungstage: ")
        s.font = .system(size: 13, weight: .bold)
        let tail = first == last ? "\(firstDate)." : "\(firstDate) – \(lastDate)."
        var rest = AttributedString(tail)
        rest.font = .system(size: 13)
        s.append(rest)
        return s
    }

    // MARK: - Helpers

    private func dateForDay(_ day: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day - 1, to: cycleStartDate) ?? cycleStartDate
    }
}

// MARK: - BloodDrop shape

/// Coral teardrop matching the JSX `TLDrop` reference shape.
struct BloodDrop: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        p.move(to: CGPoint(x: cx, y: 0))
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.67),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.35),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.55)
        )
        p.addArc(
            center: CGPoint(x: cx, y: rect.height * 0.67),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addCurve(
            to: CGPoint(x: cx, y: 0),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.55),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.35)
        )
        p.closeSubpath()
        return p
    }
}

private struct IdentifiableDay: Identifiable, Hashable {
    let day: Int
    var id: Int { day }
    init(_ day: Int) { self.day = day }
}

struct IdentifiablePhase: Identifiable, Hashable {
    let phase: CyclePhase
    var id: CyclePhase { phase }
}

extension CyclePhaseStrip {
    private func phaseColor(_ phase: CyclePhase) -> Color {
        switch phase {
        case .menses: return coral
        case .follicular: return turquoise
        case .ovulation: return teal
        case .lutealEarly, .lutealLate: return purple
        }
    }
    
    private func wellnessText(for phase: CyclePhase) -> String {
        switch phase {
        case .menses:
            return "Menstruation (Ebbe): Zeit der Erneuerung und inneren Ruhe. Nutze diese Tage, um dich auszuruhen und neue Kräfte für den kommenden Zyklus zu sammeln."
        case .follicular:
            return "Follikelphase (Aufbau): Zeit der Zuversicht und Energie. Dein Östrogenspiegel steigt an und schenkt dir mentale Klarheit. Ideal für neue Projekte!"
        case .ovulation:
            return "Ovulation (Flut): Zeit der Fülle und Ausstrahlung. Deine Energie ist am höchsten. Du fühlst dich meist besonders kommunikativ und kraftvoll."
        case .lutealEarly, .lutealLate:
            return "Lutealphase (Dämmerung): Zeit des Rückzugs und der Einkehr. Nutze diese Phase für gemütliche Stunden und um sanft mit dir selbst umzugehen."
        }
    }
}
