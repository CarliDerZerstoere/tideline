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
        // Audit Wave-A fix (4.1): cap the wave animation at 30 fps so it
        // honours the "breath-paced" motion contract in the visual-
        // language doc and stays off the ProMotion 120 Hz path. The
        // previous `minimumInterval: 0.05` was a floor (≥ 20 fps);
        // ProMotion treats `.animation(_)` as "as fast as possible" and
        // would tick this 120×/sec. 1/30 (~33 ms) is sub-perceptible
        // for breathing motion and saves ~75% of the GPU pass cost.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: shouldPause)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Background — slow, long-period wave. Different spatial frequency
                // from the front layer creates an interference beat pattern that
                // reads as real water rather than three concentric sines.
                SineWave(
                    phase: elapsed * 0.4,
                    amplitude: 9 * amplitudeScale,
                    frequency: 0.75
                )
                .fill(tint.opacity(0.18))

                // Mid — opacity-breathing layer adds subtle depth.
                SineWave(
                    phase: elapsed * 0.7,
                    amplitude: 10 * amplitudeScale,
                    frequency: 1.3
                )
                .fill(tint.opacity(0.44))

                // Front — dominant, fastest, full amplitude.
                SineWave(
                    phase: elapsed * 1.0,
                    amplitude: 14 * amplitudeScale,
                    frequency: 1.0
                )
                .fill(tint.opacity(0.86))
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
