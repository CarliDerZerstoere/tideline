import SwiftUI

/// Compact sinusoidal sparkline of the last 6 cycles, rendered like a tide
/// table. Each peak/trough is a cycle; peak height encodes cycle length
/// relative to the user's mean. Tap a peak → expand inline into a detail
/// view. See `docs/design/tideline-visual-language.md` § Layer 3.
struct TideSparkline: View {
    /// Past cycles, oldest first. Each entry: (start date, length in days).
    /// Maximum 6 shown by default per the design.
    let cycles: [CycleSummary]
    let onCycleTap: (CycleSummary) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeDetailCycle: CycleSummary? = nil

    private let height: CGFloat = 80
    private let maxCyclesShown = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gezeitentabelle")
                    .font(.system(size: 15, weight: .bold))
                Text("Letzte 6 Zyklen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if displayed.isEmpty {
                emptyState
            } else {
                sparklineCanvas
            }
        }
        .popover(item: $activeDetailCycle) { cycle in
            VStack(alignment: .leading, spacing: 8) {
                Text("Zyklus-Details")
                    .font(.system(size: 14, weight: .bold, design: .serif).italic())
                    .foregroundStyle(curveColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "Beginn:", value: cycle.startDate.formatted(.dateTime.day().month(.wide).year()))
                    detailRow(label: "Dauer:", value: "\(cycle.lengthDays) Tage")
                }
                .font(.system(size: 12.5))
                
                Divider().padding(.vertical, 2)
                
                Button {
                    activeDetailCycle = nil
                    // Execute original callback to open "Mein Zyklus" details sheet
                    onCycleTap(cycle)
                } label: {
                    Text("Alle Details anzeigen →")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(curveColor)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: 220)
            .background(.ultraThinMaterial)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var displayed: [CycleSummary] {
        Array(cycles.suffix(maxCyclesShown))
    }

    @ViewBuilder
    private var emptyState: some View {
        Text("Noch keine vergangenen Zyklen.")
            .font(.caption)
            // Task #133 — was .tertiary; bumped to .secondary so the
            // empty-state guidance meets WCAG AA contrast.
            .foregroundStyle(.secondary)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sparklineCanvas: some View {
        GeometryReader { proxy in
            let h = max(proxy.size.height, height)
            ZStack(alignment: .topLeading) {
                // Gradient-filled background under the curve.
                ClosedTideCurve(cycles: displayed)
                    .fill(
                        LinearGradient(
                            colors: [curveColor.opacity(0.18), curveColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: proxy.size.width, height: h)
                
                // Background sinusoidal curve through cycle peaks.
                TideCurve(cycles: displayed)
                    .stroke(curveColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                // Tappable peak markers + length labels.
                ForEach(Array(displayed.enumerated()), id: \.offset) { idx, cycle in
                    peakMarker(index: idx, cycle: cycle, in: proxy.size)
                }
            }
            // Guard: GeometryReader inside a ScrollView receives zero height on
            // the first layout pass. Clamp to the declared height so the Path
            // is never drawn in a zero-height rect.
            .frame(width: proxy.size.width, height: h)
        }
        .frame(height: height)
    }

    private var curveColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.78, blue: 0.85)
            : Color(red: 0.20, green: 0.42, blue: 0.55)
    }

    @ViewBuilder
    private func peakMarker(index: Int, cycle: CycleSummary, in size: CGSize) -> some View {
        let pos = position(forIndex: index, length: cycle.lengthDays, in: size)
        Button {
            activeDetailCycle = cycle
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(curveColor)
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 1.5)
                    )
                    .shadow(color: curveColor.opacity(0.6), radius: 4, x: 0, y: 1.5)
                Text("\(cycle.lengthDays)d")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .position(x: pos.x, y: pos.y + 12)
        .accessibilityLabel("Zyklus \(index + 1), \(cycle.lengthDays) Tage. Beginn \(cycle.startDate.formatted(.dateTime.day().month()))")
    }

    private func position(forIndex index: Int, length: Int, in size: CGSize) -> CGPoint {
        let n = max(1, displayed.count)
        let xFrac = (Double(index) + 0.5) / Double(n)
        let x = size.width * CGFloat(xFrac)

        // Y position: encode cycle length around a "mean line." Shorter → higher
        // peak (closer to top), longer → lower (closer to bottom). Tide-table feel.
        let mean = displayed.map(\.lengthDays).reduce(0, +) / max(1, displayed.count)
        let deviation = Double(length - mean)
        let scale = 8.0  // points per day deviation
        let centerY = size.height * 0.45
        let y = centerY - CGFloat(deviation * scale).clamped(to: -28...28)
        return CGPoint(x: x, y: y)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

/// Smooth sinusoidal curve passing through each cycle's "tide level."
private struct TideCurve: Shape {
    let cycles: [CycleSummary]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !cycles.isEmpty else { return path }

        let n = cycles.count
        let mean = cycles.map(\.lengthDays).reduce(0, +) / max(1, n)
        let centerY = rect.midY
        let scale = 8.0

        func yFor(_ length: Int) -> CGFloat {
            let dev = Double(length - mean)
            return centerY - CGFloat(dev * scale).clamped(to: -28...28)
        }

        // Build control points at each cycle's peak position.
        var points: [CGPoint] = []
        for (idx, cycle) in cycles.enumerated() {
            let xFrac = (Double(idx) + 0.5) / Double(n)
            points.append(CGPoint(x: rect.width * CGFloat(xFrac), y: yFor(cycle.lengthDays)))
        }

        path.move(to: CGPoint(x: 0, y: points.first!.y))
        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let midX = (p0.x + p1.x) / 2
            path.addCurve(
                to: p1,
                control1: CGPoint(x: midX, y: p0.y),
                control2: CGPoint(x: midX, y: p1.y)
            )
        }
        path.addLine(to: CGPoint(x: rect.width, y: points.last!.y))
        return path
    }
}

/// A closed version of TideCurve for rendering a beautiful under-curve gradient.
private struct ClosedTideCurve: Shape {
    let cycles: [CycleSummary]
 
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !cycles.isEmpty else { return path }
 
        let n = cycles.count
        let mean = cycles.map(\.lengthDays).reduce(0, +) / max(1, n)
        let centerY = rect.midY
        let scale = 8.0
 
        func yFor(_ length: Int) -> CGFloat {
            let dev = Double(length - mean)
            return centerY - CGFloat(dev * scale).clamped(to: -28...28)
        }
 
        var points: [CGPoint] = []
        for (idx, cycle) in cycles.enumerated() {
            let xFrac = (Double(idx) + 0.5) / Double(n)
            points.append(CGPoint(x: rect.width * CGFloat(xFrac), y: yFor(cycle.lengthDays)))
        }
 
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: points.first!.y))
        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let midX = (p0.x + p1.x) / 2
            path.addCurve(
                to: p1,
                control1: CGPoint(x: midX, y: p0.y),
                control2: CGPoint(x: midX, y: p1.y)
            )
        }
        path.addLine(to: CGPoint(x: rect.width, y: points.last!.y))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct CycleSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let lengthDays: Int

    init(id: UUID = UUID(), startDate: Date, lengthDays: Int) {
        self.id = id
        self.startDate = startDate
        self.lengthDays = lengthDays
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    let now = Date()
    return TideSparkline(
        cycles: [
            .init(startDate: now.addingTimeInterval(-180 * 86400), lengthDays: 27),
            .init(startDate: now.addingTimeInterval(-150 * 86400), lengthDays: 29),
            .init(startDate: now.addingTimeInterval(-120 * 86400), lengthDays: 28),
            .init(startDate: now.addingTimeInterval(-90 * 86400), lengthDays: 30),
            .init(startDate: now.addingTimeInterval(-60 * 86400), lengthDays: 26),
            .init(startDate: now.addingTimeInterval(-30 * 86400), lengthDays: 29)
        ],
        onCycleTap: { _ in }
    )
    .padding()
}
