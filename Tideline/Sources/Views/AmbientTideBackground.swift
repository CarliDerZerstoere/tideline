import SwiftUI

/// Ambient background used by CalendarSheet, LogDaySheet (and any future sheet)
/// — soft phase-tinted radial washes plus a few drifting tide lines.
///
/// Why this is a separate view rather than inline in each sheet:
///
///   1. The animation drives a phase variable at frame rate. If the gradients
///      and TideLinesShape are inlined in the sheet's `body`, the sheet's
///      *entire* body re-evaluates on every tick — including the calendar
///      grid, the form fields, the SwiftData-backed records dict, etc.
///      Pulling the ambient layer into its own view scopes the invalidation
///      to just this view's body. Calendar grid + form rows stay quiet.
///
///   2. Throttled via `TimelineView(.animation(minimumInterval: 1/15))` so
///      the ambient wash updates at ~15 fps instead of 60 fps. Visually
///      indistinguishable for a slow drift; ~4× less CPU.
///
///   3. Honours Reduce Motion + Low Power Mode by holding `phase` static.
struct AmbientTideBackground: View {
    let primary: Color
    let secondary: Color
    /// When `false`, the tide-line animation freezes — the static
    /// gradient washes still render, but the 10-fps TimelineView snaps
    /// to a fixed phase. Use this on parent views while a child sheet
    /// is presenting (the parent is blurred by iOS during sheet rise
    /// and re-rasterizes every frame with the moving tide as input,
    /// which produces visible jank at half-detent presentation).
    var animate: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycleSeconds: Double = 18

    var body: some View {
        ZStack {
            // STATIC radial washes — pulled OUT of the TimelineView so the GPU
            // can cache them. Previously their `center` was animated, which
            // forced full-screen radial-gradient rasterization on every tick
            // (dominant cost during sheet resize). Static = effectively free
            // after first render. Visual "alive" feel comes from the curves
            // drifting on top.
            RadialGradient(
                colors: [primary.opacity(colorScheme == .dark ? 0.20 : 0.08), .clear],
                center: .init(x: 0.10, y: 0.20),
                startRadius: 50,
                endRadius: 400
            )
            RadialGradient(
                colors: [secondary.opacity(colorScheme == .dark ? 0.16 : 0.06), .clear],
                center: .init(x: 0.90, y: 0.80),
                startRadius: 50,
                endRadius: 420
            )

            // Only the tide lines animate. Hard-throttled to 10 fps via
            // `.periodic` (real cap, unlike `.animation(minimumInterval:)`
            // which is just a floor). At 10 fps a 5-curve stroke is trivial.
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let phase = shouldPause ? 0 : currentPhase(context.date)
                // Point-in-time signpost so an Instruments capture reveals
                // the *actual* tick rate. If you see more than ~10 events
                // per second, the TimelineView is being driven faster than
                // claimed and culprit #1 from the perf review is real.
                let _ = { PerfSignpost.event("tideTick") }()
                TideLinesShape(phase: phase)
                    .stroke(
                        Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025),
                        style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                    )
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private var shouldPause: Bool {
        !animate || reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func currentPhase(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds
        return CGFloat(t * 2 * .pi)
    }
}
