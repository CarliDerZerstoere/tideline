import Foundation

/// A point prediction with a credible interval.
public struct Prediction: Sendable, Equatable {
    public let estimate: Date
    public let interval: ClosedRange<Date>
    public let isWidenedRecovery: Bool
    public let isOngoingIrregularity: Bool
}

/// Owns the predictor's mode and routes life-events to the right action.
/// See docs/design/disrupted-cycles.md § Category-to-action lookup table.
///
/// **No-op contract:** `apply(event:)` silently returns without effect when
/// the mode is incompatible with the event's category (e.g., Category C event
/// during `.paused` or `.retired`). Callers driving UI must check
/// `currentMode()` before presenting options. An unrecognized `EventKind`
/// raw value (future app version writing to older schema) is also a no-op.
public actor PredictorService {
    private var mode: PredictorMode
    /// Task #96 — single-anomaly outlier rejection. Set by
    /// `apply(eventKind: .singleAnomaly | .emergencyContraception*)` and
    /// consumed by the very next `observe(cycleLength:)` call. Cleared
    /// on `.pause` / `.complete` transitions because those terminate
    /// the cycle the anomaly applied to.
    private var skipNextObservation: Bool = false
    /// Task #162 — user's declared age band, used to route `softReset()`
    /// for Category C events to the band-appropriate prior. Without
    /// this, every soft-reset would collapse to the reproductive-band
    /// β=28.7282 — actively NARROWING the prior for menopausal users
    /// (σ=11.19, band-appropriate β=250.43) post-event. Set via
    /// `setAgeBand(_:)` from CycleStore which mirrors its own state.
    private var ageBand: AgeBand = .unspecified

    /// Task #193 / #83 Session 1 — v2 mixture predictor sidecar.
    /// Maintained in lock-step with the active CyclePredictor: every
    /// `observe(cycleLength:)` that's accepted also feeds the mixture;
    /// every soft-reset clears the mixture's observation history. The
    /// mixture is *not yet* on the prediction path — only its derived
    /// `mixingWeightEstimate` is consumed (via `cyclePattern()`) to
    /// surface the cycle-pattern badge after N ≥ 12 cycles.
    ///
    /// Why a sidecar, not a `PredictorVariant` enum replacing the mode:
    /// changing `PredictorMode` to hold `PredictorVariant` would touch
    /// every caller of `mode.activePredictor`. The sidecar lets v2 ship
    /// user-visible behaviour without disrupting the prediction
    /// surface. Full variant routing comes in a follow-up session.
    private var mixture: MixturePredictor = .populationPrior
    /// Marks whether the mixture has new observations since the last
    /// Gibbs run. Gibbs is deferred to `cyclePattern()` request time so
    /// `loadAndReplay` (which calls `observe` N times) doesn't pay
    /// N × 25ms but rather 1 × 25ms at the next pattern read.
    private var mixturePosteriorStale: Bool = true

    /// Re-export of `CyclePattern.graduationThreshold` for callers that
    /// want to reason about graduation from the service side without
    /// having to import the model type's static. Single source of truth
    /// lives on `CyclePattern`; this is just a thin re-export.
    public static var mixtureGraduationThreshold: Int {
        CyclePattern.graduationThreshold
    }

    /// Active recovery-profile state (Phase 3 / #194). Tracks the
    /// event-specific recovery window after a Category C event was
    /// applied: which event triggered it, how many cycles remain
    /// before the predictor graduates back to standard prior, and
    /// whether the Asherman risk flag is active.
    ///
    /// Set by `apply(eventKind:on:)` for `.recoverable` events that
    /// have a `RecoveryProfile`. Decremented per `observe()`. Cleared
    /// when `cyclesRemaining` reaches 0 — except when `ashermanRisk`
    /// is true, in which case the window stays open indefinitely (D&C
    /// cases need ongoing monitoring per HRU 2024).
    private var activeRecovery: ActiveRecovery? = nil

    /// Snapshot value type used to surface recovery state in
    /// `MyCycleSnapshot`. Sendable so it crosses actor boundaries.
    public struct ActiveRecovery: Sendable, Equatable {
        public let eventKind: EventKind
        public let cyclesRemaining: Int
        public let totalCycles: Int
        public let ashermanFlag: Bool
        public let germanRecoveryPhrase: String

        public init(
            eventKind: EventKind,
            cyclesRemaining: Int,
            totalCycles: Int,
            ashermanFlag: Bool,
            germanRecoveryPhrase: String
        ) {
            self.eventKind = eventKind
            self.cyclesRemaining = cyclesRemaining
            self.totalCycles = totalCycles
            self.ashermanFlag = ashermanFlag
            self.germanRecoveryPhrase = germanRecoveryPhrase
        }

        /// 1-indexed cycle position within the recovery window.
        /// "Zyklus 2 von 4" maps to currentCycle=2, totalCycles=4.
        public var currentCycle: Int {
            max(1, totalCycles - cyclesRemaining + 1)
        }
    }

    public init(mode: PredictorMode = .active(.populationPrior)) {
        self.mode = mode
    }

    public func currentMode() -> PredictorMode { mode }

    /// Task #162 — set the user's age band so subsequent `apply(.recoverable)`
    /// soft-resets route through the correct prior. CycleStore mirrors
    /// this via its own `setAgeBand(_:)` call. Idempotent.
    ///
    /// Also re-prepares the mixture sidecar with the band-appropriate
    /// prior so PCOS / perimenopausal users get a correctly-shaped
    /// component-1 σ baseline. Only takes effect if the mixture has no
    /// observations yet (changing the prior mid-stream would discard
    /// learned posterior).
    public func setAgeBand(_ band: AgeBand) {
        self.ageBand = band
        if mixture.observedCount == 0 {
            mixture = .populationPrior(for: band)
            mixturePosteriorStale = true
        }
    }

    /// Clinically plausible cycle length range. FIGO 2018 cites 24–38 days
    /// as normal; the wider [21, 45] band gives slack for adolescent /
    /// perimenopausal users while still rejecting clearly broken data
    /// (e.g. accidental 12-day or 70-day "cycles" that result from
    /// mis-logged bleeding events). Task #95.
    public static func clinicallyPlausible(_ cycleLengthDays: Double) -> Bool {
        cycleLengthDays >= 21.0 && cycleLengthDays <= 45.0
    }

    /// Apply a life-event by kind + date. Routes to retire / pause / softReset
    /// / widen / no-op. Takes primitives (not the SwiftData `@Model` class)
    /// so it can be called safely across actor boundaries.
    public func apply(eventKind kind: EventKind, on date: Date) {
        switch kind.category {
        case .complete:
            // Terminating a tracked cycle clears any pending anomaly
            // suppression — the cycle the anomaly applied to is gone.
            skipNextObservation = false
            mode = .retired(since: date, reason: kind.retirementReason)
            // Task #193 — retirement also retires the mixture sidecar:
            // wipe observations so the pattern badge doesn't surface
            // stale data after a hysterectomy etc.
            mixture = .populationPrior(for: ageBand)
            mixturePosteriorStale = true
            // Task #194 — clear any active recovery window. Retirement
            // ends the cycle-tracking regime entirely.
            activeRecovery = nil

        case .pause:
            // Same reasoning as `.complete` — the pause terminates the
            // cycle the anomaly was supposed to mask.
            skipNextObservation = false
            let archived = mode.archivedPredictor ?? .populationPrior
            mode = .paused(archived: archived, since: date, reason: kind.pauseReason)
            // Task #193 — mixture clears too. Resuming starts a fresh
            // chain; pre-pause pattern is no longer the right summary
            // for the post-pause regime (breastfeeding-affected cycles,
            // post-OCP irregularity, etc.).
            mixture = .populationPrior(for: ageBand)
            mixturePosteriorStale = true
            // Task #194 — pause clears any active recovery window too.
            activeRecovery = nil

        case .recoverable:
            // Soft-reset terminates the cycle the anomaly applied to, in
            // the same sense that .complete/.pause do — the disrupted-cycles
            // doctrine treats Category C as restarting the tracking phase.
            // β-widening (the recovery window) is the disruption-tolerance
            // mechanism here; double-up with anomaly suppression would
            // silently drop a clean post-recovery cycle. Reviewer B1.
            //
            // Task #162 — route through the band-aware soft-reset so a
            // menopausal user (σ=11.19) doesn't get reset to the
            // reproductive-band prior (σ=3.79). Without the band, a
            // post-Fehlgeburt menopausal user would see their prior
            // ACTIVELY NARROW — clinically wrong.
            skipNextObservation = false
            if case .active(var p) = mode {
                p.softReset(forBand: ageBand)
                mode = .active(p)
            }
            // Task #193 — Category C does NOT wipe the mixture sidecar.
            // CyclePredictor's softReset keeps μ as a stable location
            // hint; the analogous "stable trait" for the mixture is
            // the user's accumulated ovulatory/anovulatory pattern over
            // many cycles. A single miscarriage or short-term illness
            // doesn't fundamentally change that long-run pattern, and
            // wiping 24 cycles of history to require another 12 before
            // the pattern badge reappears would be punitive without
            // clinical justification.
            //
            // Contrast Category A (retire, mixture cleared) and
            // Category B (pause, mixture cleared) — both *terminate*
            // the cycle-tracking regime; Category C *continues* it.
            //
            // Task #194 (Phase 3) — apply the per-event recovery
            // profile to shape the next 1–3 cycles' predictions. The
            // profile shifts the prior; observations stay. After
            // `cyclesToBaseline` observations, the recovery window
            // closes and the predictor graduates back to the standard
            // prior. Asherman-flagged events stay open indefinitely.
            if let profile = RecoveryProfile.profile(for: kind) {
                mixture.applyRecoveryProfile(profile)
                activeRecovery = ActiveRecovery(
                    eventKind: kind,
                    cyclesRemaining: profile.cyclesToBaseline,
                    totalCycles: profile.cyclesToBaseline,
                    ashermanFlag: profile.ashermanRisk,
                    germanRecoveryPhrase: profile.germanRecoveryPhrase
                )
            }
            mixturePosteriorStale = true
            // Paused/retired: no-op — caller must resume() first.

        case .anomaly:
            // Outlier-reject only — flag the next observed cycle length
            // to be silently dropped. Matches the design-doc semantic
            // for Category D events (single anomaly = outlier-reject,
            // no reset, no widening). Task #96 — was previously a no-op
            // despite the doc-comment claim that suppression happened
            // at the observe() boundary; now it actually does.
            skipNextObservation = true

        case .ongoing:
            if case .active(var p) = mode {
                p.declareOngoingIrregularity()
                mode = .active(p)
            }

        case .resume:
            // Un-pause via the existing imperative resume() — applies
            // softReset to the archived posterior, preserving μ as a
            // location hint and resetting κ/α/β. Wrapping the existing
            // method keeps the .paused → .active transition rules in one
            // place (no duplicated logic to drift). Active/retired
            // modes are no-ops because there's no pause to resume from.
            //
            // Out-of-order replay hazard (for #75 Events tab): if a
            // future UI lets the user backdate a `.resumeAfterPause` to
            // *before* its corresponding pause event, the replay merge
            // will apply resume first against `.active` mode → no-op →
            // the pause then fires and stays paused forever. The right
            // defence is a causal tiebreaker in `CycleStore.loadAndReplay`
            // (sort same-day events with pause before resume). See the
            // task #74 review note in the project history.
            resume()
        }
    }

    /// Observe a completed cycle length (days). Returns true if applied,
    /// false if suppressed for any reason: out-of-clinical-range (#95),
    /// pending anomaly flag (#96), or non-active mode.
    ///
    /// Side-effect on accept: the v2 mixture sidecar (#193) also
    /// observes the same length. The mixture's Gibbs run is deferred
    /// until the next `cyclePattern()` request (the chain only needs
    /// to be up-to-date when read).
    @discardableResult
    public func observe(cycleLength days: Double) -> Bool {
        // Task #95 — reject lengths outside [21, 45]. Catches accidental
        // mis-logs before they corrupt the posterior. Lives at the
        // service boundary; the underlying NIG predictor stays pure.
        guard Self.clinicallyPlausible(days) else { return false }
        // Task #96 — consume + clear any pending anomaly suppression.
        if skipNextObservation {
            skipNextObservation = false
            return false
        }
        guard case .active(var p) = mode else { return false }
        p.observe(cycleLength: days)
        mode = .active(p)
        // Task #193 — keep the v2 mixture sidecar in lock-step. Same
        // outlier/range filters already applied above. Defer Gibbs.
        mixture.observe(cycleLength: days)
        mixturePosteriorStale = true
        // Task #194 (Phase 3) — count this observation against the
        // active recovery window. Asherman-flagged windows never
        // auto-graduate; non-flagged windows clear when
        // `cyclesRemaining` reaches 0 (HRU 2024 — 17% of D&C cases
        // develop intrauterine adhesions, so we don't force
        // convergence for those events).
        if var recovery = activeRecovery {
            let newRemaining = max(0, recovery.cyclesRemaining - 1)
            if newRemaining == 0 && !recovery.ashermanFlag {
                activeRecovery = nil
            } else {
                recovery = ActiveRecovery(
                    eventKind: recovery.eventKind,
                    cyclesRemaining: newRemaining,
                    totalCycles: recovery.totalCycles,
                    ashermanFlag: recovery.ashermanFlag,
                    germanRecoveryPhrase: recovery.germanRecoveryPhrase
                )
                activeRecovery = recovery
            }
        }
        return true
    }

    /// Active recovery-profile state, if a Category C event is being
    /// tracked. Returns nil when no recovery is active or when the
    /// recovery window has graduated (cyclesRemaining reached 0 for
    /// non-Asherman events).
    public func recoveryState() -> ActiveRecovery? {
        activeRecovery
    }

    /// Manually clear an Asherman-flagged recovery window. Called from
    /// settings UI when the user confirms their cycles have normalised
    /// (e.g., 6+ months of regular cycles post-D&C). Non-Asherman
    /// windows auto-clear via the observe() counter, so this method is
    /// a no-op for them.
    public func clearAshermanRecovery() {
        guard let recovery = activeRecovery, recovery.ashermanFlag else { return }
        activeRecovery = nil
    }

    /// Observe a sequence of cycle lengths. Returns how many were applied.
    @discardableResult
    public func observe(cycleLengths: [Double]) -> Int {
        var applied = 0
        for x in cycleLengths where observe(cycleLength: x) { applied += 1 }
        return applied
    }

    /// Next-period prediction. Returns nil if paused or retired.
    public func nextPrediction(
        after lastPeriodStart: Date,
        confidence: Double = 0.90
    ) -> Prediction? {
        guard let p = mode.activePredictor else { return nil }
        let estimate = p.nextPeriodDate(after: lastPeriodStart)
        let interval = p.nextPeriodDateInterval(after: lastPeriodStart, confidence: confidence)
        return Prediction(
            estimate: estimate,
            interval: interval,
            isWidenedRecovery: p.isInRecoveryWindow,
            isOngoingIrregularity: p.isOngoingIrregularity
        )
    }

    /// Conditional credible interval given the cycle has run `daysSinceLastPeriod`
    /// without a new period starting yet. Returns nil if paused/retired.
    public func conditionalInterval(
        daysSinceLastPeriod D: Double,
        confidence: Double = 0.90
    ) -> ClosedRange<Double>? {
        guard let p = mode.activePredictor else { return nil }
        return p.conditionalInterval(currentDay: D, confidence: confidence)
    }

    /// Resume from `.paused`. Performs a soft-reset on the archived posterior.
    ///
    /// Task #162 follow-up — routes through the band-aware soft-reset so the
    /// post-pause prior matches the user's declared age band. Without this,
    /// a menopausal user (σ=11.19) who resumes from breastfeeding would have
    /// her prior actively collapsed to the band-agnostic default (σ=5.0) —
    /// the same clinical bug #162 fixed for Category C events, now closed
    /// in the Category F resume path too.
    public func resume() {
        if case .paused(var archived, _, _) = mode {
            archived.softReset(forBand: ageBand)
            mode = .active(archived)
            // Task #193 — mixture is also "resumed" by being reset to a
            // fresh chain. Same reasoning as the original pause: post-
            // pause regime is qualitatively different.
            mixture = .populationPrior(for: ageBand)
            mixturePosteriorStale = true
        }
    }

    // MARK: - v2 mixture sidecar (#193 / #83 Session 1)

    /// Cycle-pattern indicator derived from the v2 mixture's posterior
    /// mixing weight π. Returns nil when:
    ///   - The predictor isn't active (paused/retired).
    ///   - Too few cycles observed (`< mixtureGraduationThreshold`).
    ///   - The mixture chain hasn't produced posterior samples.
    ///
    /// Uses the **mixture's own** observation count for both the
    /// graduation guard and the displayed `observedCount`, not the
    /// active CyclePredictor's count. The two diverge after a Category C
    /// event: CyclePredictor's `softReset(forBand:)` zeroes its count
    /// (recovery window semantics), but the mixture preserves its
    /// long-run history so the pattern badge survives single
    /// disruptions. Reviewer H1.
    ///
    /// Lazily runs the Gibbs sampler when stale: the first call after
    /// any number of `observe()` calls pays the ~25ms Gibbs cost; the
    /// next call returns the cached pattern immediately. This is why
    /// `loadAndReplay` (which observes N cycles back-to-back) only pays
    /// the Gibbs cost once at the next snapshot read, not N times.
    /// Mixture-based conditional credible interval for late-period
    /// prediction. Returns nil when the predictor isn't active, when
    /// the user hasn't reached the graduation threshold, or when the
    /// mixture posterior is empty.
    ///
    /// Callers (currently `CycleStore.homeSnapshot`) should prefer this
    /// over the single-component `conditionalInterval` when available —
    /// the mixture's right tail honestly reflects the user's observed
    /// anovulatory rate. For users with mostly-ovulatory cycles the two
    /// agree on the lower bound; the mixture's upper bound is allowed
    /// to extend further into the anovulatory tail (this is by design,
    /// not a bug — see `MixturePredictor.conditionalInterval` doc).
    ///
    /// Same lazy-Gibbs semantics as `cyclePattern()`: runs Gibbs only
    /// on the first call after a new observation has landed.
    public func mixtureConditionalInterval(
        daysSinceLastPeriod D: Double,
        confidence: Double = 0.90
    ) -> ClosedRange<Double>? {
        guard case .active = mode else { return nil }
        guard mixture.observedCount >= Self.mixtureGraduationThreshold else { return nil }
        if mixturePosteriorStale {
            mixture.runGibbs(iterations: 200, burnIn: 100, seed: 42)
            mixturePosteriorStale = false
        }
        // #215 — `conditionalInterval` is now Optional; the guard above
        // already ensures non-empty posterior, but the method's contract
        // is honest about empty so we forward the Optional. Equivalent
        // behaviour, cleaner type signature.
        return mixture.conditionalInterval(currentDay: D, confidence: confidence)
    }

    public func cyclePattern() -> CyclePattern? {
        guard case .active = mode else { return nil }
        guard mixture.observedCount >= Self.mixtureGraduationThreshold else { return nil }
        if mixturePosteriorStale {
            mixture.runGibbs(iterations: 200, burnIn: 100, seed: 42)
            mixturePosteriorStale = false
        }
        // #190 — `mixingWeightEstimate` is Optional; nil iff posterior
        // is empty. The graduation guard above already ensures non-empty
        // observations, but the chain could fail to produce samples in
        // a pathological case (e.g. all data deterministically routed
        // by the H-Z threshold leaving comp 1 with no obs). Treat as
        // "no pattern yet" rather than crashing.
        guard let pi = mixture.mixingWeightEstimate else { return nil }
        return CyclePattern(
            mixingWeight: pi,
            observedCount: mixture.observedCount
        )
    }
}
