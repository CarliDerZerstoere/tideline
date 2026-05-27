import Foundation

/// Per-event recovery prior for the v2 mixture predictor (Phase 3 of
/// `docs/design/mixture-predictor.md`).
///
/// Replaces the uniform `softReset(forBand:)` semantics with event-specific
/// priors that capture what the literature actually tells us about
/// post-event cycle behaviour. For example, post-OCP cycle 1 has σ ≈ 11
/// days (Nassaralla 2011), whereas post-LNG-IUD cycle 1 is near baseline
/// (local-action mechanism, ~σ 6 days). The generic softReset was using
/// σ ≈ 3.79 (reproductive band) for both — actively wrong for the OCP case.
///
/// **Each profile entry has an evidence anchor.** Literature-extracted
/// values are marked `.literature(...)` with PMID/citation; analyst-
/// elicited starting points are marked `.analystElicited(...)` with the
/// reasoning chain. This honest accounting matches the design doc's
/// "what's real vs what's a starting point" convention.
///
/// Asherman risk flag (surgical abortion, late miscarriage with D&C): if
/// posterior σ stays high after the recovery window, the predictor must
/// NOT force convergence — ~17% of first-trimester D&C cases develop
/// intrauterine adhesions (HRU 2024 meta-analysis). The flag is consumed
/// by `PredictorService` to prevent premature recovery-window expiration.
public struct RecoveryProfile: Sendable, Equatable {
    /// The event kind this profile is calibrated for.
    public let eventKind: EventKind
    /// Days added to the user's pre-event μ₁ for cycle 1's prior
    /// location. Captures the typical post-event "lag" in cycle length.
    public let mu1Offset: Double
    /// Component 1 prior σ for cycle 1 (the first cycle post-event).
    /// Widened from baseline to reflect cycle-1 unpredictability.
    public let sigma1Cycle1: Double
    /// Component 1 prior σ for cycle 2. Tapers toward baseline.
    public let sigma1Cycle2: Double
    /// Prior mean of the mixing weight π for the recovery window.
    /// Lowered from the baseline 0.80 to reflect higher anovulatory
    /// probability post-event.
    public let piPriorMean: Double
    /// Number of cycles until the predictor graduates back to the
    /// standard prior. Drawn from the literature where available
    /// (e.g. post-OCP: 5–9 cycles per Gnoth 2002; post-Depo: 6–10
    /// cycles per DMPA-IM label).
    public let cyclesToBaseline: Int
    /// True for D&C-bearing events (surgical abortion, late
    /// miscarriage with D&C) where ~17% of cases develop Asherman's
    /// syndrome (HRU 2024). When true, `PredictorService` must NOT
    /// force convergence at `cyclesToBaseline` — the recovery window
    /// stays open until cleared by user.
    public let ashermanRisk: Bool
    /// Where this profile's numbers came from. Honest about
    /// literature-extracted vs analyst-elicited values.
    public let evidenceAnchor: EvidenceAnchor

    public enum EvidenceAnchor: Sendable, Equatable {
        /// Numbers extracted from primary literature.
        case literature(citation: String)
        /// Starting-point values calibrated to qualitatively match
        /// cited evidence trajectories. Subject to refinement based
        /// on user feedback per design doc § "The recovery profile
        /// table" disclaimer.
        case analystElicited(rationale: String)
    }

    public init(
        eventKind: EventKind,
        mu1Offset: Double,
        sigma1Cycle1: Double,
        sigma1Cycle2: Double,
        piPriorMean: Double,
        cyclesToBaseline: Int,
        ashermanRisk: Bool,
        evidenceAnchor: EvidenceAnchor
    ) {
        self.eventKind = eventKind
        self.mu1Offset = mu1Offset
        self.sigma1Cycle1 = sigma1Cycle1
        self.sigma1Cycle2 = sigma1Cycle2
        self.piPriorMean = piPriorMean
        self.cyclesToBaseline = cyclesToBaseline
        self.ashermanRisk = ashermanRisk
        self.evidenceAnchor = evidenceAnchor
    }

    // MARK: - Per-event profiles

    /// Returns the recovery profile for a given event kind, or nil if
    /// the event isn't in Category C (recoverable).
    public static func profile(for eventKind: EventKind) -> RecoveryProfile? {
        switch eventKind {
        case .medicalAbortion:              return medicalAbortion
        case .surgicalAbortion:             return surgicalAbortion
        case .miscarriageEarly:             return miscarriageEarly
        case .miscarriageLate:              return miscarriageLate
        case .pregnancyLoss:                return pregnancyLossGeneric
        case .birthNoBreastfeeding:         return liveBirthNonBreastfeeding
        case .stoppedHormonalContraception: return stoppedOCP
        case .stoppedIUDHormonal:           return stoppedLNGIUD
        case .acuteIllnessSevere, .majorSurgery:
            return prolongedIllnessOrSurgery
        case .significantWeightChange, .extremeStress:
            return weightOrStressShift
        default:
            return nil
        }
    }

    public static let medicalAbortion = RecoveryProfile(
        eventKind: .medicalAbortion,
        mu1Offset: 2.0,
        sigma1Cycle1: 7.0,
        sigma1Cycle2: 5.0,
        piPriorMean: 0.75,
        cyclesToBaseline: 3,
        ashermanRisk: false,
        // Schreiber 2011 anchors ovulation TIMING (σ = 5.1 d to first
        // ovulation post-mifepristone), NOT cycle-length SD. Convolving
        // with a typical luteal-phase SD ~2.5d (Crawford 2017 / Bull
        // 2019) gives cycle-length SD ≈ √(5.1² + 2.5²) ≈ 5.7 d. We
        // inflate to 7.0 to absorb first-cycle reset uncertainty
        // (HPO-axis recovery, occasional anovulatory cycle 1). The
        // analyst-elicited padding is honest in the evidenceAnchor
        // below — only the ovulation-timing portion is literature-
        // anchored.
        evidenceAnchor: .analystElicited(
            rationale: "Schreiber CA 2011 (PMID 21843685) anchors first-ovulation σ=5.1d; cycle-length σ analyst-inflated from convolved ~5.7d to 7.0 for first-cycle reset uncertainty"
        )
    )

    public static let surgicalAbortion = RecoveryProfile(
        eventKind: .surgicalAbortion,
        mu1Offset: 3.0,
        sigma1Cycle1: 8.0,
        sigma1Cycle2: 5.0,
        piPriorMean: 0.75,
        cyclesToBaseline: 3,
        // ~17% Asherman risk per HRU 2024 — recovery window doesn't
        // auto-graduate. User must clear manually if cycles normalise.
        ashermanRisk: true,
        evidenceAnchor: .literature(
            citation: "HRU 2024 intrauterine-adhesion meta-analysis (Asherman flag); σ/π values analyst-elicited"
        )
    )

    public static let miscarriageEarly = RecoveryProfile(
        eventKind: .miscarriageEarly,
        mu1Offset: 2.0,
        sigma1Cycle1: 6.0,
        sigma1Cycle2: 5.0,
        piPriorMean: 0.75,
        cyclesToBaseline: 3,
        ashermanRisk: false,
        evidenceAnchor: .analystElicited(
            rationale: "By analogy to medical abortion; sparse direct primary literature for <10wk miscarriage cycle recovery."
        )
    )

    public static let miscarriageLate = RecoveryProfile(
        eventKind: .miscarriageLate,
        mu1Offset: 6.0,
        sigma1Cycle1: 11.0,
        sigma1Cycle2: 8.0,
        piPriorMean: 0.55,
        cyclesToBaseline: 4,
        // 10–20wk miscarriage often requires D&C → Asherman risk applies.
        ashermanRisk: true,
        evidenceAnchor: .analystElicited(
            rationale: "Sparse primary literature for 10–20wk miscarriage cycle recovery; Asherman flag from HRU 2024."
        )
    )

    /// Generic profile for `.pregnancyLoss` (user-declared loss without
    /// medical category). Slightly more conservative than miscarriageEarly
    /// since gestational age is unknown.
    public static let pregnancyLossGeneric = RecoveryProfile(
        eventKind: .pregnancyLoss,
        mu1Offset: 3.0,
        sigma1Cycle1: 8.0,
        sigma1Cycle2: 6.0,
        piPriorMean: 0.70,
        cyclesToBaseline: 4,
        ashermanRisk: false,
        evidenceAnchor: .analystElicited(
            rationale: "Generic post-loss prior, sits between medicalAbortion and miscarriageLate. Gestational age unknown by design (#136 — user declines to specify category)."
        )
    )

    public static let liveBirthNonBreastfeeding = RecoveryProfile(
        eventKind: .birthNoBreastfeeding,
        mu1Offset: 8.0,
        sigma1Cycle1: 12.0,
        sigma1Cycle2: 8.0,
        piPriorMean: 0.45,
        cyclesToBaseline: 5,
        ashermanRisk: false,
        // First-ovulation 45–94d range and 20–71% anovulatory fraction
        // anchored in Jackson & Glasier 2011.
        evidenceAnchor: .literature(
            citation: "Jackson E, Glasier A 2011 (PMID 21343770) — first-ovulation 45–94d, 20–71% anovulatory"
        )
    )

    public static let stoppedOCP = RecoveryProfile(
        eventKind: .stoppedHormonalContraception,
        mu1Offset: 2.0,
        sigma1Cycle1: 11.0,
        sigma1Cycle2: 7.0,
        piPriorMean: 0.65,
        cyclesToBaseline: 9,
        ashermanRisk: false,
        // Cycle 1 σ from Nassaralla 2011 (cycle 1 mean 31.5±11.1, n=70).
        // Cycles-to-baseline of 9 from Gnoth 2002 (post-OCP disturbance
        // through cycle 9; 10.24% strict anovulatory cycle 1).
        evidenceAnchor: .literature(
            citation: "Nassaralla CL 2011 (PMC7643763) σ; Gnoth C 2002 (PMID 12396560) cycles-to-baseline"
        )
    )

    public static let stoppedLNGIUD = RecoveryProfile(
        eventKind: .stoppedIUDHormonal,
        mu1Offset: 1.0,
        sigma1Cycle1: 6.0,
        sigma1Cycle2: 5.0,
        piPriorMean: 0.80,
        cyclesToBaseline: 3,
        ashermanRisk: false,
        evidenceAnchor: .analystElicited(
            rationale: "LNG-IUD is local-action progestin; once removed, systemic recovery is fast. Cycle 1 σ near baseline by design."
        )
    )

    public static let prolongedIllnessOrSurgery = RecoveryProfile(
        eventKind: .acuteIllnessSevere,
        mu1Offset: 4.0,
        sigma1Cycle1: 10.0,
        sigma1Cycle2: 7.0,
        piPriorMean: 0.65,
        cyclesToBaseline: 3,
        ashermanRisk: false,
        // Meczekalski 2014 anchors functional hypothalamic amenorrhea
        // spectrum framing; specific σ/π values analyst-elicited from
        // the FHA recovery trajectory range.
        evidenceAnchor: .literature(
            citation: "Meczekalski B 2014 (FHA spectrum framing); σ/π analyst-elicited from FHA recovery range"
        )
    )

    public static let weightOrStressShift = RecoveryProfile(
        eventKind: .significantWeightChange,
        mu1Offset: 3.0,
        sigma1Cycle1: 8.0,
        sigma1Cycle2: 6.0,
        piPriorMean: 0.70,
        cyclesToBaseline: 3,
        ashermanRisk: false,
        evidenceAnchor: .analystElicited(
            rationale: "Conservative generic prior for HPO-axis disruption from weight/stress shifts. Wider than illness because the shift may be ongoing."
        )
    )

    // MARK: - German display label

    /// Short German phrase for the recovery-mode badge in `MyCycleSheet`,
    /// e.g. "nach medizinischem Schwangerschaftsabbruch" — composes
    /// into "Im Erholungsprozess <phrase> (Zyklus N von M)".
    public var germanRecoveryPhrase: String {
        switch eventKind {
        case .medicalAbortion:              return "nach medizinischem Abbruch"
        case .surgicalAbortion:             return "nach operativem Abbruch"
        case .miscarriageEarly:             return "nach frühem Verlust"
        case .miscarriageLate:              return "nach spätem Verlust"
        case .pregnancyLoss:                return "nach Verlust"
        case .birthNoBreastfeeding:         return "nach Geburt"
        case .stoppedHormonalContraception: return "nach Absetzen der Pille"
        case .stoppedIUDHormonal:           return "nach Entfernung der Hormonspirale"
        case .acuteIllnessSevere:           return "nach Krankheit"
        case .majorSurgery:                 return "nach Operation"
        case .significantWeightChange:      return "nach Gewichtsveränderung"
        case .extremeStress:                return "nach Belastung"
        default:                            return "nach Ereignis"
        }
    }
}
