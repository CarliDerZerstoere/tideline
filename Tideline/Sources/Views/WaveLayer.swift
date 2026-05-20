import SwiftUI

/// Three overlapping sine waves forming the ambient sea at the bottom of the
/// `TidelineHero`. Breath-paced (~4-second primary cycle), automatically
/// paused when the app is not in `.active` scene phase, when iOS Low Power
/// Mode is enabled, or when the user has Reduce Motion turned on.
///
/// Per the fact-checked animation research: uses `TimelineView(.animation(...))`
/// + `Shape` with `animatableData`. No third-party deps, no remote assets.
struct WaveLayer: View {
    /// Tint of the primary wave. Secondary/tertiary waves derive from this
    /// at reduced opacity.
    let tint: Color

    /// Wave amplitude in points. Increase modestly during active menses to
    /// suggest a rougher sea.
    let amplitudeScale: CGFloat

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var shouldPause: Bool {
        scenePhase != .active || reduceMotion || isLowPower
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: shouldPause)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            ZStack {
                SineWave(
                    phase: elapsed * 1.0,
                    amplitude: 14 * amplitudeScale,
                    frequency: 1.0
                )
                .fill(tint.opacity(0.85))

                SineWave(
                    phase: elapsed * 0.7,
                    amplitude: 8 * amplitudeScale,
                    frequency: 1.3
                )
                .fill(tint.opacity(0.55))

                SineWave(
                    phase: elapsed * 1.4,
                    amplitude: 5 * amplitudeScale,
                    frequency: 1.7
                )
                .fill(tint.opacity(0.30))
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: .NSProcessInfoPowerStateDidChange
            ) {
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single phase-driven sine wave filled down to the bottom of its frame.
struct SineWave: Shape {
    var phase: Double
    var amplitude: Double
    var frequency: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let mid = rect.midY
        path.move(to: CGPoint(x: 0, y: mid))
        // Stride of 3 points: smooth enough for ambient motion, half the
        // path-point cost of stride 1.
        stride(from: 0.0, through: Double(width), by: 3.0).forEach { x in
            let angle = (x / Double(width)) * .pi * 2 * frequency + phase
            let y = mid + amplitude * sin(angle)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: width, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    WaveLayer(tint: .teal, amplitudeScale: 1.0)
        .frame(height: 80)
        .background(Color.blue.opacity(0.1))
}
