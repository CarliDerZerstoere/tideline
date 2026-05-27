import Foundation

/// German recognition-copy template library for the Mein Zyklus Layer 1
/// card (task #121). Static templates, no AI in v1 per CLAUDE.md Pillar 5
/// + `docs/design/app-ui-architecture.md` §3.2.
///
/// **Recognition-framing rule** (UI plan §5):
///   - Lead with "Wenn du..." / "Bemerkst du..." / "Bei vielen..." / "Tag N deiner..."
///   - Never "Du solltest..." (instruction) or "Wahrscheinlich hast du..." (diagnosis)
///   - Always pair phase context with population framing ("das ist typisch",
///     "bei vielen klingt das ab")
///
/// **Selection** is a deterministic function of (phase × zone × seed):
///   - The (phase, zone) cell selects a list of 2–5 candidate templates.
///   - The seed (cycleStart-derived) picks one candidate deterministically.
///   - Same template on the same day-in-cycle of the same cycle; rotates
///     across days within the cycle so the user doesn't see the identical
///     sentence two days running.

/// Position within the cycle, distinct from `CyclePhase`. Zones are
/// finer-grained — each phase has 1–2 zones so copy can speak to the
/// "early menses still intense" vs. "late luteal PMS-likely" distinction
/// without UI consumers needing to track day numbers themselves.
public enum CycleZone: String, Hashable, Sendable, CaseIterable {
    case mensesEarly        // cycle days 1–2
    case mensesMid          // day 3 to end of menses
    case follicularEarly    // first half of follicular phase
    case follicularLate     // second half of follicular (approaching ovulation)
    case ovulationPeak      // ovulation window
    case lutealEarly        // first half of luteal phase
    case lutealLate         // second half of luteal (PMS-likely zone)
}

public struct RecognitionTemplate: Sendable, Equatable {
    public let headline: String
    public let body: String

    public init(headline: String, body: String) {
        self.headline = headline
        self.body = body
    }
}

public enum RecognitionTemplates {

    /// Map a 1-indexed cycle day + phase boundaries to a zone.
    /// Total function — every day maps to exactly one zone.
    public static func zone(forDay day: Int, boundaries: PhaseBoundaries) -> CycleZone {
        // Menses subzones
        if day <= 2 { return .mensesEarly }
        if day <= boundaries.mensesEnd { return .mensesMid }
        // Follicular subzones: split at midpoint of follicular span
        if day < boundaries.ovulationWindowStart {
            let follicularSpan = max(1, boundaries.ovulationWindowStart - boundaries.follicularStart)
            let midpoint = boundaries.follicularStart + follicularSpan / 2
            return day <= midpoint ? .follicularEarly : .follicularLate
        }
        // Ovulation window
        if day <= boundaries.ovulationWindowEnd { return .ovulationPeak }
        // Luteal subzones
        if day <= boundaries.lutealEarlyEnd { return .lutealEarly }
        return .lutealLate
    }

    /// Deterministic-with-rotation picker. Same input always returns the
    /// same template; rotation varies across days within a cycle.
    public static func pick(
        phase: CyclePhase,
        dayInCycle: Int,
        boundaries: PhaseBoundaries,
        cycleStartHash: Int = 0
    ) -> RecognitionTemplate {
        let z = zone(forDay: dayInCycle, boundaries: boundaries)
        let candidates = templates(for: phase, zone: z)
        // Defensive fallback: a (phase, zone) cell that's empty at runtime
        // (shouldn't happen — coverage test pins all cells non-empty) falls
        // back to a phase-generic template list.
        let list = candidates.isEmpty ? phaseGenerics(for: phase) : candidates
        let seed = abs(cycleStartHash &+ dayInCycle)
        let index = list.isEmpty ? 0 : (seed % list.count)
        return list.isEmpty ? Self.universalFallback : list[index]
    }

    /// Templates for a given (phase, zone) cell. Exposed for tests.
    public static func templates(for phase: CyclePhase, zone: CycleZone) -> [RecognitionTemplate] {
        switch (phase, zone) {

        // ─── Menses ─────────────────────────────────────────────────────
        case (.menses, .mensesEarly):
            return [
                .init(
                    headline: "Tag 1 deiner Periode",
                    body: "Heute ist oft der intensivste Tag. Bei den meisten klingt das nach 2–3 Tagen ab."
                ),
                .init(
                    headline: "Periode beginnt",
                    body: "Wenn du dich heute müde oder krampfig fühlst — das ist typisch für den Start. Sei sanft mit dir."
                ),
                .init(
                    headline: "Frühe Menstruation",
                    body: "Bei vielen ist die Energie heute niedrig. Das pendelt sich in den nächsten Tagen ein."
                ),
                .init(
                    headline: "Anfang deines Zyklus",
                    body: "Bemerkst du gerade Schwere oder Rückzug? Beides gehört zur frühen Menstruation."
                )
            ]

        case (.menses, .mensesMid):
            return [
                .init(
                    headline: "Mitte deiner Periode",
                    body: "Wenn du dich langsam besser fühlst — das ist typisch. Die Hormone fangen an, wieder anzusteigen."
                ),
                .init(
                    headline: "Periode klingt ab",
                    body: "Bei den meisten lässt die Intensität jetzt nach. In den nächsten Tagen kommt oft die Energie zurück."
                ),
                .init(
                    headline: "Späte Menstruation",
                    body: "Bemerkst du wieder mehr Tatendrang? Östrogen steigt — das macht sich oft schon spürbar."
                ),
                .init(
                    headline: "Ende der Periode rückt näher",
                    body: "Wenn die Blutung weniger wird — Tideline registriert das automatisch beim nächsten Logbuch-Eintrag."
                )
            ]

        // ─── Follicular ─────────────────────────────────────────────────
        case (.follicular, .follicularEarly):
            return [
                .init(
                    headline: "Aufsteigende Flut",
                    body: "Wenn du dich heute klarer und energiegeladener fühlst — du bist in der frühen Follikelphase, das ist typisch."
                ),
                .init(
                    headline: "Frühe Follikelphase",
                    body: "Östrogen steigt langsam an. Bei vielen ist das die produktivste Phase des Zyklus."
                ),
                .init(
                    headline: "Nach der Periode",
                    body: "Bemerkst du gerade mehr Lust auf Bewegung oder soziale Aktivitäten? Das passt zur Follikelphase."
                ),
                .init(
                    headline: "Östrogen kommt zurück",
                    body: "Wenn deine Stimmung heute spürbar besser ist als letzte Woche — du bist nicht eingebildet, das ist die Phase."
                )
            ]

        case (.follicular, .follicularLate):
            return [
                .init(
                    headline: "Späte Follikelphase",
                    body: "Du näherst dich dem Eisprung. Bei vielen ist jetzt die kommunikativste, kreativste Zeit."
                ),
                .init(
                    headline: "Vor dem Eisprung",
                    body: "Wenn du dich heute besonders fit oder gesprächig fühlst — Östrogen ist nah am Höhepunkt."
                ),
                .init(
                    headline: "Annäherung Hochwasser",
                    body: "Bei vielen ist die Stimmung jetzt offener und der Schlaf leichter. Du näherst dich der Mitte deines Zyklus."
                ),
                .init(
                    headline: "Energiehoch baut sich auf",
                    body: "Bemerkst du gerade Selbstvertrauen oder mehr Ausdauer? Das passt zur späten Follikelphase."
                )
            ]

        // ─── Ovulation ──────────────────────────────────────────────────
        case (.ovulation, .ovulationPeak):
            return [
                .init(
                    headline: "Hochwasser",
                    body: "Wenn du dich heute energiegeladen fühlst — du bist in der Ovulationsphase, das ist typisch."
                ),
                .init(
                    headline: "Eisprung",
                    body: "Bei vielen ist das die Phase mit der höchsten Energie und Stimmung. Auch der Geruchssinn ist oft schärfer."
                ),
                .init(
                    headline: "Mitte des Zyklus",
                    body: "Bemerkst du heute ein leichtes Ziehen im Unterleib? Das kann der Mittelschmerz sein — bei einigen Menschen begleitet er den Eisprung."
                ),
                .init(
                    headline: "Östrogen am Höhepunkt",
                    body: "Wenn die Libido jetzt steigt — das ist evolutionär verankert und bei vielen Menschen spürbar."
                )
            ]

        // ─── Luteal early ───────────────────────────────────────────────
        case (.lutealEarly, .lutealEarly):
            return [
                .init(
                    headline: "Frühe Lutealphase",
                    body: "Nach dem Eisprung übernimmt Progesteron. Bei vielen wird die Stimmung jetzt ruhiger, fokussierter."
                ),
                .init(
                    headline: "Fallende Flut beginnt",
                    body: "Wenn du dich heute eher introvertiert fühlst — das passt zur frühen Lutealphase."
                ),
                .init(
                    headline: "Nach Hochwasser",
                    body: "Progesteron steigt, Östrogen sinkt langsam. Bei vielen Menschen kommt jetzt mehr Bedürfnis nach Routine und Schlaf."
                ),
                .init(
                    headline: "Lutealphase beginnt",
                    body: "Bemerkst du gerade mehr Hunger oder Wärmeempfinden? Beides typische Begleiter von Progesteron."
                )
            ]

        // ─── Luteal late (PMS-likely) ───────────────────────────────────
        case (.lutealLate, .lutealLate):
            return [
                .init(
                    headline: "Späte Lutealphase",
                    body: "Bemerkst du gerade Reizbarkeit oder Müdigkeit? Bei vielen klingt das mit dem Periodenstart ab."
                ),
                .init(
                    headline: "Dämmerung",
                    body: "Wenn du dich heute empfindlicher fühlst als sonst — das ist die hormonelle Talsohle vor der Periode."
                ),
                .init(
                    headline: "Vor der Periode",
                    body: "Bei vielen sind Heißhunger, Wassereinlagerungen oder Stimmungsschwankungen jetzt typisch. Das hat einen Namen: PMS."
                ),
                .init(
                    headline: "Letzte Tage des Zyklus",
                    body: "Wenn du Brustspannen, Kopfweh oder Krämpfe bemerkst — die Periode steht oft in wenigen Tagen vor der Tür."
                ),
                .init(
                    headline: "Hormone fallen",
                    body: "Östrogen und Progesteron sinken jetzt beide. Bei manchen erklärt das, warum sich alles intensiver anfühlt."
                )
            ]

        // ─── Unreachable combinations ───────────────────────────────────
        // (e.g., .menses with .follicularEarly zone) — return empty, the
        // picker falls back to phase-generics. Coverage test asserts that
        // every (phase, zone) the `zone(forDay:)` classifier can produce
        // has a non-empty template list.
        default:
            return []
        }
    }

    /// Phase-only fallback list, used when a specific zone is empty.
    /// Defensive — coverage test pins reachable cells non-empty.
    static func phaseGenerics(for phase: CyclePhase) -> [RecognitionTemplate] {
        switch phase {
        case .menses:
            return [.init(headline: "Periode", body: "Sei sanft mit dir. Tideline ist hier, wenn du etwas loggen möchtest.")]
        case .follicular:
            return [.init(headline: "Follikelphase", body: "Energie steigt. Bei vielen ist das die produktivste Zeit im Zyklus.")]
        case .ovulation:
            return [.init(headline: "Hochwasser", body: "Du bist in der Ovulationsphase. Bei vielen ist das die energiereichste Zeit.")]
        case .lutealEarly:
            return [.init(headline: "Lutealphase", body: "Progesteron übernimmt. Bei vielen wird die Stimmung jetzt ruhiger.")]
        case .lutealLate:
            return [.init(headline: "Späte Lutealphase", body: "Du näherst dich der Periode. Sei sanft mit dir, falls heute alles intensiver wirkt.")]
        }
    }

    /// Last-resort fallback if even phaseGenerics is empty (should never
    /// trigger; the picker's signature is total).
    static let universalFallback = RecognitionTemplate(
        headline: "Dein Zyklus",
        body: "Tideline ist hier. Wenn du etwas loggen möchtest, geht das jederzeit."
    )
}
