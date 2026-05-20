import SwiftUI
import SwiftData

/// Horizontal scale showing the current cycle: day numbers, phase bands with
/// soft gradient transitions, bleeding-day droplet overlays, and a today-pin.
///
/// Tap a day → mini popover (no modal). Edit button in the popover →
/// `LogDaySheet`. See `docs/design/tideline-visual-language.md` § Layer 2.
struct CyclePhaseStrip: View {
    let cycleStartDate: Date
    let boundaries: PhaseBoundaries
    let bleedingDays: Set<Int>       // 1-indexed cycle days where flow >= .light
    let today: Int                   // current cycle day (1-indexed)
    let useTideNaming: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var previewDay: IdentifiableDay? = nil
    @State private var editingDay: IdentifiableDay? = nil

    private let stripHeight: CGFloat = 56
    private let cellSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let totalDays = boundaries.cycleLength
                let cellWidth = (proxy.size.width - CGFloat(totalDays - 1) * cellSpacing) / CGFloat(totalDays)

                ZStack(alignment: .topLeading) {
                    // Phase bands with soft gradient transitions.
                    phaseBandsLayer(cellWidth: cellWidth, totalDays: totalDays)

                    // Day cells (tap targets) + bleeding droplets.
                    HStack(spacing: cellSpacing) {
                        ForEach(1...totalDays, id: \.self) { day in
                            DayCell(
                                day: day,
                                isBleeding: bleedingDays.contains(day),
                                isToday: day == today,
                                cellWidth: cellWidth,
                                stripHeight: stripHeight,
                                onTap: { previewDay = IdentifiableDay(day) }
                            )
                        }
                    }
                }
                .frame(height: stripHeight)
            }
            .frame(height: stripHeight)

            // Day-number markers (every 3rd day).
            dayNumberRow

            // Three-sentence concrete-data summary.
            summaryText
        }
        .popover(item: $previewDay) { wrapped in
            DayPreviewPopover(
                day: wrapped.day,
                date: dateForDay(wrapped.day),
                isBleeding: bleedingDays.contains(wrapped.day),
                phase: boundaries.phase(forDay: wrapped.day),
                useTideNaming: useTideNaming,
                onEdit: {
                    let d = wrapped
                    previewDay = nil
                    editingDay = d
                }
            )
            .presentationCompactAdaptation(.popover)
        }
        .sheet(item: $editingDay) { wrapped in
            LogDaySheet(date: dateForDay(wrapped.day))
        }
    }

    // MARK: - Phase bands

    @ViewBuilder
    private func phaseBandsLayer(cellWidth: CGFloat, totalDays: Int) -> some View {
        let totalWidth = cellWidth * CGFloat(totalDays) + cellSpacing * CGFloat(totalDays - 1)
        let stops = phaseGradientStops(totalDays: totalDays)
        LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: totalWidth, height: stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(0.5)
    }

    /// Build gradient stops so phases blend softly across day boundaries
    /// (no crisp lines — biology is fuzzy).
    private func phaseGradientStops(totalDays: Int) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        for day in 1...totalDays {
            let frac = Double(day - 1) / Double(totalDays - 1)
            let phase = boundaries.phase(forDay: day)
            stops.append(.init(
                color: PhasePalette.color(for: phase, scheme: colorScheme),
                location: frac
            ))
        }
        return stops
    }

    // MARK: - Day-number row

    private var dayNumberRow: some View {
        GeometryReader { proxy in
            let totalDays = boundaries.cycleLength
            let cellWidth = (proxy.size.width - CGFloat(totalDays - 1) * cellSpacing) / CGFloat(totalDays)
            HStack(spacing: cellSpacing) {
                ForEach(1...totalDays, id: \.self) { day in
                    Text(day % 3 == 1 ? "\(day)" : "")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: cellWidth)
                }
            }
        }
        .frame(height: 12)
    }

    // MARK: - Summary text

    private var summaryText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Heute: Tag \(today) — \(phaseName(for: boundaries.phase(forDay: today)))")
                .font(.headline)
            if let nextPhaseSentence {
                Text(nextPhaseSentence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let lastBleedingSentence {
                Text(lastBleedingSentence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func phaseName(for phase: CyclePhase) -> String {
        useTideNaming ? phase.tideName : phase.clinicalName
    }

    private var nextPhaseSentence: String? {
        let currentPhase = boundaries.phase(forDay: today)
        guard let (nextPhase, startDay) = upcomingPhase(after: currentPhase, currentDay: today) else {
            return nil
        }
        let daysUntil = startDay - today
        let nextName = phaseName(for: nextPhase)
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

    private var lastBleedingSentence: String? {
        let sorted = bleedingDays.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let firstDate = dateForDay(first).formatted(.dateTime.day().month())
        let lastDate = dateForDay(last).formatted(.dateTime.day().month())
        if first == last {
            return "Letzter Blutungstag: \(firstDate)."
        }
        return "Blutungstage: \(firstDate) – \(lastDate)."
    }

    // MARK: - Helpers

    private func dateForDay(_ day: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day - 1, to: cycleStartDate) ?? cycleStartDate
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Int
    let isBleeding: Bool
    let isToday: Bool
    let cellWidth: CGFloat
    let stripHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isBleeding {
                    Circle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: min(cellWidth - 4, 10), height: min(cellWidth - 4, 10))
                        .accessibilityHidden(true)
                }
                if isToday {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: cellWidth, height: stripHeight - 4)
                }
            }
            .frame(width: cellWidth, height: stripHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["Tag \(day)"]
        if isBleeding { parts.append("Blutung") }
        if isToday { parts.append("heute") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Day-preview popover

private struct DayPreviewPopover: View {
    let day: Int
    let date: Date
    let isBleeding: Bool
    let phase: CyclePhase
    let useTideNaming: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.headline)
            Text("Zyklustag \(day) · \(useTideNaming ? phase.tideName : phase.clinicalName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isBleeding {
                Label("Blutungstag", systemImage: "drop.fill")
                    .foregroundStyle(.red.opacity(0.85))
                    .font(.subheadline)
            }
            Button("Bearbeiten", action: onEdit)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding()
        .frame(minWidth: 200)
    }
}

private struct IdentifiableDay: Identifiable, Hashable {
    let day: Int
    var id: Int { day }
    init(_ day: Int) { self.day = day }
}
