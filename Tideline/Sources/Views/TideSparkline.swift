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

    private let height: CGFloat = 80
    private let maxCyclesShown = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gezeitentabelle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if displayed.isEmpty {
                emptyState
            } else {
                sparklineCanvas
            }
        }
    }

    private var displayed: [CycleSummary] {
        Array(cycles.suffix(maxCyclesShown))
    }

    @ViewBuilder
    private var emptyState: some View {
        Text("Noch keine vergangenen Zyklen.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sparklineCanvas: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Background sinusoidal curve through cycle peaks.
                TideCurve(cycles: displayed)
                    .stroke(curveColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Tappable peak markers + length labels.
                ForEach(Array(displayed.enumerated()), id: \.offset) { idx, cycle in
                    peakMarker(index: idx, cycle: cycle, in: proxy.size)
                }
            }
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
            onCycleTap(cycle)
        } label: {
            VStack(spacing: 2) {
                Circle()
                    .fill(curveColor)
                    .frame(width: 8, height: 8)
                Text("\(cycle.lengthDays)d")
                    .font(.system(size: 9))
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
