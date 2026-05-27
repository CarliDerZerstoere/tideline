import Foundation
import SwiftUI

/// The four+1 visible cycle phases. Naming defaults to the tide metaphor per
/// `docs/design/tideline-visual-language.md`; clinical names available via
/// `clinicalName` for the settings toggle.
public enum CyclePhase: String, CaseIterable, Sendable {
    case menses             // Blutung — coral/peach (sunrise)
    case follicular         // aufsteigende Flut — turquoise (morning)
    case ovulation          // Hochwasser — gold (midday)
    case lutealEarly        // fallende Flut — amber (afternoon)
    case lutealLate         // Dämmerung — dusky purple (sunset)

    public var tideName: String {
        switch self {
        case .menses: return "Periode"
        case .follicular: return "aufsteigende Flut"
        case .ovulation: return "Hochwasser"
        case .lutealEarly: return "fallende Flut"
        case .lutealLate: return "Dämmerung"
        }
    }

    public var clinicalName: String {
        switch self {
        case .menses: return "Menstruation"
        case .follicular: return "Follikelphase"
        case .ovulation: return "Ovulation"
        case .lutealEarly: return "Lutealphase"
        case .lutealLate: return "Lutealphase"
        }
    }

    /// Short label used in the phase-strip slider where four labels share one
    /// row. Compresses `lutealEarly`/`lutealLate` into a single "Lutealphase"
    /// bucket since the strip only has space for four headings.
    public func compactLabel(useTideNaming: Bool) -> String {
        switch (self, useTideNaming) {
        case (.menses, true):       return "Periode"
        case (.menses, false):      return "Menstruation"
        case (.follicular, true):   return "Aufsteigend"
        case (.follicular, false):  return "Follikelphase"
        case (.ovulation, true):    return "Hochwasser"
        case (.ovulation, false):   return "Ovulation"
        case (.lutealEarly, true), (.lutealLate, true):     return "Dämmerung"
        case (.lutealEarly, false), (.lutealLate, false):   return "Lutealphase"
        }
    }
}

/// Computed phase boundaries for one cycle.
/// See `docs/design/tideline-visual-language.md` § Phase boundary computation.
/// Day numbers are 1-indexed (cycle day 1 = first day of menses).
public struct PhaseBoundaries: Sendable, Equatable {
    public let mensesEnd: Int           // last bleeding day (inclusive)
    public let ovulation: Int           // estimated ovulation day
    public let cycleLength: Int         // predicted length of this cycle

    public var follicularStart: Int { mensesEnd + 1 }
    public var follicularEnd: Int { ovulation - 3 }
    public var ovulationWindowStart: Int { ovulation - 2 }
    public var ovulationWindowEnd: Int { ovulation + 2 }
    public var lutealEarlyStart: Int { ovulation + 3 }
    public var lutealEarlyEnd: Int { min(cycleLength - 4, lutealEarlyStart + 7) }
    public var lutealLateStart: Int { lutealEarlyEnd + 1 }
    public var lutealLateEnd: Int { cycleLength }

    /// Map a cycle day → phase. Days before menses end (inclusive) = .menses.
    public func phase(forDay day: Int) -> CyclePhase {
        if day <= mensesEnd { return .menses }
        if day < ovulationWindowStart { return .follicular }
        if day <= ovulationWindowEnd { return .ovulation }
        if day <= lutealEarlyEnd { return .lutealEarly }
        return .lutealLate
    }

    /// Population default cycle length, in days, used for UI surfaces
    /// that need an Int (calendar phase rings, fallback when no past
    /// cycles are logged). Rounded from the canonical AWHS 2023 mean of
    /// 28.7 days (Mahalingaiah, PMC10226714). The `CyclePredictor.mu`
    /// holds the exact 28.7 as a Double; this Int is purely a display-
    /// side rounding for surfaces that compute integer cycle days.
    public static let defaultCycleLength: Int = 29

    /// Population default menses duration (days). Used as a LOWER bound
    /// on `mensesEnd` when the user has either logged no bleeding yet or
    /// only a partial run — see `mensesEnd(forCycleStart:bleedingDays:today:)`
    /// below for the full reasoning. Source: WHO/Belsey + FIGO 2018
    /// normal range ≤8 days; population median ≈4–5 days.
    public static let defaultMensesDuration: Int = 5

    /// Population-mean luteal-phase duration in days. Used as the offset
    /// from predicted cycle end back to predicted ovulation day.
    ///
    /// Source: Bull JR, Rowland SP, Scherwitzl EB, et al. "Real-world
    /// menstrual cycle characteristics of more than 600,000 menstrual cycles."
    /// npj Digital Medicine 2:83 (2019). PMC6710244. Population mean
    /// luteal = 12.4 ± 2.4 d; 18% of cycles < 11 d. BBT-based, n=612,613.
    ///
    /// Int rounded from 12.4 → 12. For a 28-day cycle, `28 − 12 = 16`
    /// matches `round(28 − 12.4) = 16`. The 0.4 d rounding bias is
    /// absorbed by the soft phase-band gradient.
    ///
    /// Supersedes the textbook `−14` folk rule (off by ~2 d on average).
    /// Sensitivity confirmation against Fehring 2013 NFP dataset (1,508
    /// cycles, mean luteal 13.24 d) verifies direction; the 0.8 d gap
    /// reflects LH-peak vs BBT measurement convention, not biology.
    /// Tideline aligns with BBT methodology (Apple Watch wrist-temp
    /// Phase 4 roadmap) — Bull 2019 is the right anchor.
    ///
    /// Task NEW-169. See docs/research/2026-05-25-empirical-validation-results.md.
    public static let defaultLutealDuration: Int = 12

    /// Default boundaries when we have no per-user data yet — uses the
    /// population-prior cycle length and median menses.
    public static let populationDefault = PhaseBoundaries(
        mensesEnd: defaultMensesDuration,
        ovulation: defaultCycleLength - defaultLutealDuration,
        cycleLength: defaultCycleLength
    )

    /// Build from a predicted cycle length and observed menses end.
    public static func from(cycleLength: Int, mensesEnd: Int) -> PhaseBoundaries {
        PhaseBoundaries(
            mensesEnd: max(1, mensesEnd),
            ovulation: max(mensesEnd + 2, cycleLength - defaultLutealDuration),
            cycleLength: max(cycleLength, mensesEnd + 7)
        )
    }

    /// Derive `mensesEnd` for one cycle from the user's logged bleeding
    /// days. Used by both the home-view phase strip and the calendar grid
    /// — extracted here so both surfaces share one source of truth (prior
    /// to this refactor they had diverged; see task #98 for the bug).
    ///
    /// Algorithm (Belsey-aligned, task #156):
    ///   1. Walk cycle days 1, 2, 3, … tracking the last bleeding day seen
    ///      and a running count of consecutive dry days since the last
    ///      bleeding day. The Belsey rule (PMID 3048871) says ≤2 dry days
    ///      between bleeding days = same episode; ≥3 dry days closes it.
    ///   2. Cap the walk at today (passed in) so future-dated entries
    ///      can't push the end past where the user actually is.
    ///   3. `defaultMenses` acts as a LOWER bound. If the user has logged
    ///      0–4 days that resolve under Belsey to a short episode, pad to
    ///      default (typically 5) because we cannot distinguish "period
    ///      was short" from "user forgot to log day 2-5". If the
    ///      Belsey-resolved end exceeds the default, trust the data.
    ///   4. If day 1 itself is not a bleeding day, return the default —
    ///      we don't have a real episode start to anchor the walk to.
    ///
    /// The Belsey alignment closes the divergence (task #156) between
    /// this function and `CycleStore.rebuildCyclesFromDayEntries`'s
    /// cycle-grouping algorithm, which also uses the ≤2-day rule. Before
    /// the fix, a user logging `{1,2,3,5,6,7}` would see the Cycle table
    /// treat it as one 7-day episode while the phase strip / calendar
    /// painted day 6 as follicular — internally inconsistent.
    ///
    /// - Parameters:
    ///   - bleedingDays: set of 1-indexed cycle days that have a
    ///     bleeding DayEntry (flow >= .light) for this cycle.
    ///   - todayDayInCycle: which cycle day "today" falls on (1-indexed,
    ///     clamped to cycle length by caller).
    ///   - personalMedianMenses: optional per-user median menses duration
    ///     (NEW-171), derived from her last N closed cycles' Belsey-grouped
    ///     bleeding-day counts. When supplied, the floor RATCHETS UP — we
    ///     use `max(personalMedianMenses, defaultMenses)` so the floor
    ///     never drops below the population default. Defensive against
    ///     under-logging: a personal median below defaultMenses is
    ///     suspicious (could be short periods OR missed logs), so we
    ///     keep the population default. Validation: V5 of Fehring n=132
    ///     showed 40% of women have personal median > 5 d → real impact.
    ///   - defaultMenses: lower bound. Pass `defaultMensesDuration`
    ///     unless overriding for tests.
    ///
    /// Tests in `MensesHeuristicTests.swift` pin this behavior — change
    /// requires updating both views and the tests in lockstep.
    public static func mensesEnd(
        bleedingDays: Set<Int>,
        todayDayInCycle: Int,
        personalMedianMenses: Int? = nil,
        defaultMenses: Int = PhaseBoundaries.defaultMensesDuration
    ) -> Int {
        // NEW-171 — floor is the max of personal median (when available)
        // and population default. We ratchet UP from default but never
        // below — a user whose evidence shows shorter-than-default
        // periods could be either genuinely short OR under-logging, and
        // we can't distinguish without additional signal.
        let floor = max(personalMedianMenses ?? defaultMenses, defaultMenses)
        guard todayDayInCycle >= 1 else { return floor }
        var lastBleeding = 0
        var dryRun = 0
        for d in 1...todayDayInCycle {
            if bleedingDays.contains(d) {
                lastBleeding = d
                dryRun = 0
            } else {
                dryRun += 1
                if dryRun >= 3 { break }   // Belsey: ≥3 dry days closes the episode
            }
        }
        if lastBleeding == 0 { return floor }   // day 1 not a bleeding day
        return max(lastBleeding, floor)         // partial-log padding floor
    }

    // MARK: - Cycle-grouping (Belsey + FIGO)

    /// Group sorted bleeding-quality days into episode starts using the
    /// Belsey rule: ≥3 dry days between bleeding days closes an episode.
    /// (Belsey 1988 / WHO bleeding-pattern convention, PMID 3048871.)
    ///
    /// Input is expected to be civilDay-normalised and sorted ascending —
    /// callers already do both. Empty input → empty output.
    ///
    /// Extracted (2026-05-22) from the previous in-place implementations
    /// in `CycleStore.rebuildCyclesFromDayEntries`, `HKImportPlanner`,
    /// and `HKExportPlanner`. The three previously had identical copies
    /// of this algorithm; this is the single source of truth.
    public static func episodeStarts(
        from bleedingDays: [Date],
        calendar: Calendar = .current
    ) -> [Date] {
        guard !bleedingDays.isEmpty else { return [] }
        var episodes: [Date] = [bleedingDays[0]]
        for i in 1..<bleedingDays.count {
            let prev = bleedingDays[i - 1]
            let curr = bleedingDays[i]
            let dryDays = (calendar.dateComponents([.day], from: prev, to: curr).day ?? 0) - 1
            if dryDays >= 3 { episodes.append(curr) }
        }
        return episodes
    }

    /// Group episode starts into cycle starts using the FIGO-derived
    /// floor: a new cycle starts only when the next bleeding episode
    /// begins ≥21 days after the prior cycle's day-1. Anything shorter
    /// is intermenstrual bleeding within the same cycle (FIGO 2018
    /// frequent-menstruation cutoff <24 days, minus reasonable variance
    /// — engineering convention, no single textbook number exists).
    ///
    /// Empty input → empty output.
    public static func cycleStarts(
        fromEpisodeStarts episodes: [Date],
        calendar: Calendar = .current
    ) -> [Date] {
        guard !episodes.isEmpty else { return [] }
        var cycles: [Date] = [episodes[0]]
        for ep in episodes.dropFirst() {
            guard let lastCycle = cycles.last else { continue }
            let gap = calendar.dateComponents([.day], from: lastCycle, to: ep).day ?? 0
            if gap >= 21 { cycles.append(ep) }
        }
        return cycles
    }

    /// Combined Belsey + FIGO: takes sorted civilDay-normalised bleeding
    /// days and returns the derived cycle start dates.
    public static func cycleStarts(
        fromBleedingDays bleedingDays: [Date],
        calendar: Calendar = .current
    ) -> [Date] {
        cycleStarts(
            fromEpisodeStarts: episodeStarts(from: bleedingDays, calendar: calendar),
            calendar: calendar
        )
    }

    /// Pure projection function: for a given calendar `day`, given the list of
    /// logged `cycleStarts` (oldest → newest), the population/observed
    /// `cycleLength`, and the per-cycle `mensesEndByCycle` lookup, return the
    /// `CyclePhase` to render.
    ///
    /// **Why this exists:** the calendar's per-day rendering was
    /// previously inlined inside `CalendarSheet.recomputePhasesImpl` and
    /// applied `(days % cycleLen) + 1` unconditionally. When a closed
    /// cycle was longer than `cycleLen` (e.g., the user's actual Feb 12 →
    /// Mar 19 cycle = 35 days while `cycleLen = 29`), the modulo wrapped
    /// days 30–34 back to days 1–5 and rendered them as a phantom
    /// menstrual phase that contradicted the user's logged next cycle.
    /// See `CalendarPhaseProjectionTests` for the regression scenario.
    ///
    /// **Algorithm:**
    /// 1. Find the most recent cycle start `s` with `s <= day`.
    /// 2. If a *later* cycle start exists, the day sits inside a closed
    ///    cycle — `dayInCycle = days + 1` (no modulo). Past the cycle's
    ///    expected length, `PhaseBoundaries.phase(forDay:)` clamps to
    ///    `.lutealLate`, which is the right "still-waiting" semantic.
    /// 3. If `s` is the latest start, the day is in or past the current
    ///    cycle. Apply `(days % cycleLen) + 1` — this is the *projection*
    ///    behaviour, drawing future days using the cycle's expected
    ///    rhythm. This is only meaningful when the user hasn't yet logged
    ///    a next cycle to contradict it.
    /// 4. Days before the first logged cycle start return `nil` (the
    ///    calendar leaves them blank).
    ///
    /// - Precondition: `cycleStarts` must be sorted oldest → newest and
    ///   each entry should be `civilDay()`-normalised. The calendar passes
    ///   `cycleStarts.map { $0.civilDay() }` from `CycleStore` (which sorts
    ///   by `startDate` ascending); other callers must match.
    public static func projectedPhase(
        for day: Date,
        cycleStarts: [Date],
        cycleLength: Int,
        mensesEndByCycle: [Date: Int],
        defaultMensesEnd: Int = PhaseBoundaries.defaultMensesDuration,
        calendar: Calendar = .current
    ) -> CyclePhase? {
        let dayStart = day.civilDay()
        guard let s = cycleStarts.last(where: { $0 <= dayStart }) else { return nil }
        let cycleLen = max(cycleLength, 1)
        let days = calendar.dateComponents([.day], from: s, to: dayStart).day ?? 0
        let hasLaterStart = cycleStarts.contains(where: { $0 > s })
        let dayInCycle = hasLaterStart ? (days + 1) : ((days % cycleLen) + 1)
        let mensesEnd = mensesEndByCycle[s] ?? defaultMensesEnd
        let bounds = PhaseBoundaries.from(cycleLength: cycleLen, mensesEnd: mensesEnd)
        return bounds.phase(forDay: dayInCycle)
    }
}

/// Phase colors. Each phase has a day-mode and dark-mode anchor.
/// Soft transitions between adjacent phases are handled at render time
/// via gradient stops, not as separate enum cases.
public struct PhasePalette {
    public static func color(for phase: CyclePhase, scheme: ColorScheme) -> Color {
        switch (phase, scheme) {
        // Day mode — sunrise → midday → sunset palette
        case (.menses, .light):       return Color(red: 0.93, green: 0.46, blue: 0.45)  // deep coral
        case (.follicular, .light):   return Color(red: 0.56, green: 0.82, blue: 0.88)  // pale turquoise
        case (.ovulation, .light):    return Color(red: 0.98, green: 0.78, blue: 0.36)  // bright gold
        case (.lutealEarly, .light):  return Color(red: 0.93, green: 0.65, blue: 0.45)  // amber
        case (.lutealLate, .light):   return Color(red: 0.55, green: 0.42, blue: 0.62)  // dusky purple

        // Dark mode — night palette
        case (.menses, .dark):        return Color(red: 0.62, green: 0.18, blue: 0.22)  // deep ember
        case (.follicular, .dark):    return Color(red: 0.18, green: 0.42, blue: 0.58)  // phosphor turquoise
        case (.ovulation, .dark):     return Color(red: 0.72, green: 0.55, blue: 0.20)  // moonlit gold
        case (.lutealEarly, .dark):   return Color(red: 0.58, green: 0.35, blue: 0.30)  // aurora amber
        case (.lutealLate, .dark):    return Color(red: 0.28, green: 0.20, blue: 0.42)  // twilight violet

        @unknown default:
            return Color.gray
        }
    }

    /// Neutral palette for paused / retired modes — "ruhige See".
    public static func neutralColor(scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color(red: 0.20, green: 0.28, blue: 0.34)
        case .light: return Color(red: 0.72, green: 0.80, blue: 0.82)
        @unknown default: return Color.gray
        }
    }

    /// Photorealistic sunset/sunrise atmospheric gradient per phase.
    /// 4–5 color stops blending from sky to horizon, then fading to the
    /// page's cream background at the bottom. Replaces the earlier
    /// single-phase-color gradient with a richer sunset-style atmosphere.
    public static func skyHexes(for phase: CyclePhase, scheme: ColorScheme) -> [UInt32] {
        switch (phase, scheme) {
        // Light (day) sky palettes — multi-stop "sunset" feel.
        case (.menses, .light):
            return [0x1a1020, 0x4a1830, 0x8a3040, 0xc05038, 0xe07060]
        case (.follicular, .light):
            return [0xc8ddf0, 0xe8d4b8, 0xd8b888, 0xc8a068]
        case (.ovulation, .light):
            return [0xb0c4d4, 0xd8b898, 0xc89060, 0xa87050, 0x907055]
        case (.lutealEarly, .light):
            return [0xe0ccc0, 0xd0a870, 0xb88050, 0xa07050]
        case (.lutealLate, .light):
            return [0x180828, 0x3a1848, 0x6a3868, 0x8a5870]

        // Dark (night) sky palettes — deeper blacks, night skies.
        case (.menses, .dark):
            return [0x0a0410, 0x2a0c1c, 0x3a1220, 0x501828]
        case (.follicular, .dark):
            return [0x060c16, 0x0e1828, 0x162440, 0x1e3058]
        case (.ovulation, .dark):
            return [0x08080c, 0x141008, 0x201808, 0x2c2008]
        case (.lutealEarly, .dark):
            return [0x0c0808, 0x180c08, 0x241408, 0x301c10]
        case (.lutealLate, .dark):
            return [0x030108, 0x0a0418, 0x140828, 0x1e0e38]

        @unknown default:
            return [0x808080]
        }
    }

    /// Sky gradient stops including the cream-page fade at the bottom.
    /// Sky colors fill 0–82% of the height, the remaining 18% blends into
    /// the page background so the wave + cards anchor visually.
    public static func skyGradientStops(
        for phase: CyclePhase,
        scheme: ColorScheme
    ) -> [Gradient.Stop] {
        let hexes = skyHexes(for: phase, scheme: scheme)
        let pageColor = PageBackground.color(scheme: scheme)
        guard hexes.count > 1 else {
            return [.init(color: Color(hex: hexes[0]), location: 0),
                    .init(color: pageColor, location: 1)]
        }
        let topFraction = 0.82 / Double(hexes.count - 1)
        var stops = hexes.enumerated().map { i, hex in
            Gradient.Stop(color: Color(hex: hex), location: Double(i) * topFraction)
        }
        stops.append(.init(color: pageColor, location: 1.0))
        return stops
    }
}

// MARK: - Page background

/// The warm "cream" sheet color that the whole home view sits on.
/// `#F5F0EC` light / `#1C1C1E` dark — chosen for warmth + low contrast against
/// the photo-realistic phase sky gradients.
public enum PageBackground {
    public static func color(scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .light: return Color(red: 0.96, green: 0.94, blue: 0.92)
        @unknown default: return Color(white: 0.94)
        }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
