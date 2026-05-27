import Foundation

/// Pure state derivation for the home-view hero. Splitting this out of
/// `TidelineHomeView` makes the precedence rules — which message wins
/// when multiple conditions apply — testable in isolation, and keeps
/// `refresh()` a thin orchestration shell over actor reads.
///
/// **Precedence (tasks #77, #78, #101, #102):**
/// The hero's interval text has three independent flags that can all
/// fire at once — low-data (<3 cycles), widened-recovery (post-soft-reset
/// recovery window), ongoing-irregularity (PCOS self-declared) — plus a
/// late-mode override when the conditional CI exceeds 14 days. They
/// compose in `predictionIntervalText` according to this table:
///
///     observedCount<3 ?           → low-data fallback wins; everything else suppressed.
///     isWideLate (late mode) ?    → headline = "Keine klare Schätzung"
///     else if interval != nil ?   → headline = "Periode etwa <lo> – <hi>"
///     else                        → return nil (nothing to show)
///
///     if headline is a real interval:
///       append " · " + suffix(es), in stable order:
///         - isWidenedRecovery → "Die Schätzung wird mit neuen Zyklen schärfer."
///         - isOngoingIrregularity → "Deine Zyklen sind natürlich variabel."
///
/// **Recovery window activation** (audit fix #101): `isInRecoveryWindow` is
/// now defined as `recoveryRemaining > 0` — a counter set to 5 on
/// `softReset(...)` and decremented per `observe(...)`. This decouples
/// the suffix from the low-data condition: a post-soft-reset predictor
/// with `observedCount == 0` still has a known μ from prior history and
/// publishes an interval, so the calibrated headline + recovery suffix
/// fire together. A brand-new predictor has `recoveryRemaining == 0` and
/// falls through to the low-data message. The previous wording (defined
/// as `observedCount < 3`) made the recovery suffix structurally
/// unreachable — flagged in the 2026-05-24 audit.
/// Aggregate of every input `deriveHeroState` needs. Introduced because
/// the function had 12 positional args, all `Bool`/`Int`/`Date?` — the
/// kind of signature where a future call-site refactor could silently
/// swap `isWidenedRecovery` with `isOngoingIrregularity` (both `Bool`)
/// and pass the build. Wrapping in a struct turns those swap-bugs into
/// compile errors, and makes the call site at `TidelineHomeView.refresh()`
/// readable as "build the inputs once, then derive".
struct HeroInputs {
    let mode: PredictorMode
    let lastStart: Date?
    let todayDayInCycle: Int
    let cycleBoundaries: PhaseBoundaries
    let observedCount: Int
    let calibratedInterval: ClosedRange<Date>?
    let conditionalInterval: ClosedRange<Date>?
    let conditionalWidthDays: Double?
    let isWidenedRecovery: Bool
    let isOngoingIrregularity: Bool
    let pausedLabel: String?
    let retiredLabel: String?
}

enum HeroStateBuilder {

    // MARK: - State derivation

    /// State-machine that picks the right `HeroState` case for the home
    /// view. Pure — no SwiftData, no actor, no Date.now reads outside
    /// what the caller supplies. All time-dependent inputs are passed in
    /// explicitly so tests can pin behaviour deterministically.
    ///
    /// Ordering matters:
    ///   1. paused / retired short-circuit — these mode states preclude
    ///      late-mode (no active predictor, no conditional CI).
    ///   2. lastStart == nil → .empty (no cycle observed at all).
    ///   3. todayDayInCycle <= cycleLength → .active (still inside the
    ///      expected cycle window).
    ///   4. else → .late (today has passed the expected length).
    ///
    /// The boundary at step 3/4 follows the design doc edge case
    /// `late-mode-implementation.md` line 177: "Day 29 of 29 = active,
    /// not late". So we transition at `todayDayInCycle == cycleLength + 1`.
    static func deriveHeroState(_ inputs: HeroInputs) -> HeroState {
        // Step 1 — terminal modes
        if case .paused = inputs.mode {
            return .paused(reasonLabel: inputs.pausedLabel ?? "")
        }
        if case .retired = inputs.mode {
            return .retired(reasonLabel: inputs.retiredLabel ?? "")
        }

        // Step 2 — no cycle observed yet
        guard inputs.lastStart != nil else { return .empty }

        let cycleLength = inputs.cycleBoundaries.cycleLength

        // Step 3 — inside expected window
        if inputs.todayDayInCycle <= cycleLength {
            let intervalText = predictionIntervalText(
                interval: inputs.calibratedInterval,
                observedCount: inputs.observedCount,
                isWidenedRecovery: inputs.isWidenedRecovery,
                isOngoingIrregularity: inputs.isOngoingIrregularity,
                isWideLate: false
            )
            let phase = inputs.cycleBoundaries.phase(forDay: inputs.todayDayInCycle)
            let lower = predictedDay(from: inputs.calibratedInterval?.lowerBound,
                                     lastStart: inputs.lastStart, fallback: cycleLength)
            let upper = predictedDay(from: inputs.calibratedInterval?.upperBound,
                                     lastStart: inputs.lastStart, fallback: cycleLength)
            return .active(ActiveHeroModel(
                todayDay: inputs.todayDayInCycle,
                cycleLength: cycleLength,
                phase: phase,
                predictedLowerDay: lower,
                predictedUpperDay: upper,
                predictionIntervalText: intervalText
            ))
        }

        // Step 4 — late mode
        let daysLate = inputs.todayDayInCycle - cycleLength
        let isWide = (inputs.conditionalWidthDays ?? Double.infinity) > 14.0
        let intervalText = predictionIntervalText(
            interval: inputs.conditionalInterval,
            observedCount: inputs.observedCount,
            isWidenedRecovery: inputs.isWidenedRecovery,
            isOngoingIrregularity: inputs.isOngoingIrregularity,
            isWideLate: isWide
        )
        let lastKnownPhase = inputs.cycleBoundaries.phase(forDay: cycleLength)
        return .late(LatePeriodHeroModel(
            todayDay: inputs.todayDayInCycle,
            cycleLength: cycleLength,
            daysLate: daysLate,
            intervalText: intervalText,
            isWide: isWide,
            lastKnownPhase: lastKnownPhase
        ))
    }

    // MARK: - Interval text composition

    /// Compose the hero's interval text from the four orthogonal flags.
    /// See the file-level docstring for the precedence table.
    static func predictionIntervalText(
        interval: ClosedRange<Date>?,
        observedCount: Int,
        isWidenedRecovery: Bool,
        isOngoingIrregularity: Bool,
        isWideLate: Bool
    ) -> String? {
        // 1. Low-data fallback dominates everything.
        let remaining = max(0, 3 - observedCount)
        if remaining > 0 {
            switch remaining {
            case 1: return "Wir lernen deinen Rhythmus kennen — erste Schätzung nach 1 weiteren Zyklus."
            case 2: return "Wir lernen deinen Rhythmus kennen — erste Schätzung nach 2 weiteren Zyklen."
            default: return "Wir lernen deinen Rhythmus kennen — erste Schätzung nach 3 weiteren Zyklen."
            }
        }

        // 2. Headline
        let headline: String
        if isWideLate {
            headline = "Keine klare Schätzung"
        } else if let interval {
            let lo = interval.lowerBound.formatted(.dateTime.day().month())
            let hi = interval.upperBound.formatted(.dateTime.day().month())
            // Audit Wave-A fix (Option A from owner-flagged inconsistency
            // 2026-05-25): the previous wording "Periode etwa \(lo) – \(hi)"
            // read as "the period runs from <lo> to <hi>" — a DURATION.
            // But `interval` is actually the credible interval on the
            // period's START DATE (lo = P5, hi = P95). Meanwhile the
            // calendar's red rings show the point-estimate menses days
            // (e.g. June 16–20 = predicted start + 5-day median menses).
            // Result: hero said "11.–20. Juni", calendar said "16.–20.
            // Juni", user reasonably thought the app was broken.
            //
            // New wording signals "start window" instead of "duration".
            // The calendar's hard 5-day block now reads consistently as
            // "best guess of when within that window the period actually
            // starts + its typical length." Wave D #2 is the principled
            // fix (graduated-opacity calendar rings encoding the same
            // CI); this is the cheap text patch until that lands.
            headline = "Beginnt etwa zwischen \(lo) und \(hi)"
        } else {
            return nil  // no interval to show, no headline to compose
        }

        // 3. Disclaimer suffixes — stable order, joined with " · "
        var suffixes: [String] = []
        if isWidenedRecovery {
            // Audit fix #101 — now reachable: `isInRecoveryWindow` is
            // backed by the `recoveryRemaining` counter, not the
            // low-data observedCount<3 condition. After a soft-reset
            // (Category C or F event) the user has a known μ but
            // recoveryRemaining > 0, so the calibrated headline shows
            // alongside this suffix for 5 post-reset observations.
            suffixes.append("Die Schätzung wird mit neuen Zyklen schärfer.")
        }
        if isOngoingIrregularity {
            suffixes.append("Deine Zyklen sind natürlich variabel.")
        }

        if suffixes.isEmpty {
            return headline
        }
        return headline + " · " + suffixes.joined(separator: " · ")
    }

    // MARK: - Helpers

    /// Convert a calibrated-interval endpoint Date into a 1-indexed
    /// day-in-cycle integer relative to `lastStart`. Used by the
    /// `ActiveHeroModel`'s `predictedLowerDay` / `predictedUpperDay`.
    ///
    /// Returns `fallback` if either endpoint is nil or if `date` lands
    /// strictly before `lastStart`. The pre-fallback variant clamped
    /// negative deltas to day 1, which would silently hide a stale
    /// posterior emitting an interval that ends before the current
    /// cycle started — better to fall back to the strip's natural
    /// length so the bug is at least visually distinguishable from a
    /// legitimate day-1 case.
    static func predictedDay(from date: Date?, lastStart: Date?, fallback: Int) -> Int {
        guard let date, let lastStart else { return fallback }
        let days = Calendar.current.dateComponents(
            [.day],
            from: lastStart.civilDay(),
            to: date.civilDay()
        ).day ?? fallback
        if days < 0 { return fallback }
        // `days >= 0` so `days + 1 >= 1` — no clamp needed.
        return days + 1
    }
}
