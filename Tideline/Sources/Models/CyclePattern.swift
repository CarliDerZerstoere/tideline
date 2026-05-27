import Foundation

/// Descriptive 3-level summary of the user's cycle pattern, derived from the
/// posterior mixing weight π of the v2 mixture predictor (#83). Surfaces in
/// the Mein Zyklus Layer 2 pattern strip after the user has logged at least
/// 12 cycles (the graduation threshold).
///
/// **Doctrinal contract:** this is descriptive of *what was logged*, not
/// diagnostic. The badge says "your cycles, as logged, mostly look
/// ovulatory" — it never says "you have PCOS" or "consult your doctor."
/// CLAUDE.md hard rule: "Never display diagnostic interpretations." This
/// type is the user-visible boundary that rule lives behind.
///
/// **Why three levels and not a continuous scale:** the underlying
/// mixingWeightEstimate is a posterior mean, which has noise. A three-bucket
/// discretization with comfortable margins is the most honest representation
/// — a continuous "you are 73% ovulatory" overstates precision.
public struct CyclePattern: Sendable, Equatable {
    public let category: Category
    /// How many cycles the pattern is based on. Surfaces in the UI
    /// (`basiert auf N Zyklen`) to ground the abstraction in concrete data
    /// and let the user judge confidence themselves.
    public let observedCount: Int

    // MARK: - Tuning constants (single source of truth)

    /// Number of observed cycles before the pattern badge surfaces.
    /// Below this, the 2-component mixture is unidentifiable in
    /// practice and Gibbs estimates of π are dominated by the Beta(8,2)
    /// prior. Matches `docs/design/mixture-predictor.md` § "Cold-start
    /// and graduation" simplified threshold for v1.
    public static let graduationThreshold: Int = 12
    /// Lower bound of `mostlyOvulatory`: posterior π ≥ this value.
    public static let mostlyOvulatoryThreshold: Double = 0.85
    /// Lower bound of `occasionallyAnovulatory`: posterior π ≥ this
    /// value (strictly below `mostlyOvulatoryThreshold`).
    public static let occasionallyAnovulatoryThreshold: Double = 0.50

    public enum Category: Sendable, Equatable {
        /// π ≥ 0.85: most cycles look ovulatory.
        case mostlyOvulatory
        /// 0.50 ≤ π < 0.85: ovulatory most of the time but with regular
        /// anovulatory cycles mixed in.
        case occasionallyAnovulatory
        /// π < 0.50: more than half of cycles are anovulatory by length.
        case oftenAnovulatory
    }

    public init(category: Category, observedCount: Int) {
        self.category = category
        self.observedCount = observedCount
    }

    /// Map a posterior mixing weight to the bucketed category.
    /// Thresholds chosen with the noise of `mixingWeightEstimate` in mind:
    /// 0.85 and 0.50 leave a comfortable margin so chain noise doesn't
    /// flicker users between levels session-to-session.
    public init(mixingWeight pi: Double, observedCount: Int) {
        self.observedCount = observedCount
        if pi >= Self.mostlyOvulatoryThreshold {
            self.category = .mostlyOvulatory
        } else if pi >= Self.occasionallyAnovulatoryThreshold {
            self.category = .occasionallyAnovulatory
        } else {
            self.category = .oftenAnovulatory
        }
    }

    // MARK: - Display

    /// German display label for the badge.
    public var germanLabel: String {
        switch category {
        case .mostlyOvulatory:           return "Meist ovulatorisch"
        case .occasionallyAnovulatory:   return "Gelegentlich anovulatorisch"
        case .oftenAnovulatory:          return "Häufig anovulatorisch"
        }
    }

    /// Auto-localizing label for SwiftUI `Text(_:)`. Same pattern as
    /// `AgeBand.localizedLabel` and `EventKind.localizedLabel`.
    public var localizedLabel: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: germanLabel)
    }

    /// Compact German footer string, e.g. `basiert auf 24 Zyklen`. Plural
    /// rules are simple in German for this construction: `1 Zyklus` /
    /// `N Zyklen`.
    public var basisLabel: String {
        observedCount == 1
            ? "basiert auf 1 Zyklus"
            : "basiert auf \(observedCount) Zyklen"
    }
}
