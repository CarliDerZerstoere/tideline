import Foundation

/// Pure planner for the HealthKit menstrual-flow import flow (task #71).
///
/// Takes raw `FlowSample`s read from HealthKit + the set of civilDay-
/// normalised dates already present in Tideline's `DayEntry` table, and
/// produces a `HKImportPlan` that:
///   - groups the samples into derived cycles (same Belsey + FIGO rules
///     the store applies in `rebuildCyclesFromDayEntries`),
///   - flags per-day conflicts with existing entries (silently skipped
///     during commit — minimises surprise; documented in the design doc),
///   - dedupes multi-sample days (keeps the heaviest flow),
///   - drops future-dated samples (clock skew / edited HK entries).
///
/// Pure — no HealthKit, no SwiftUI, no SwiftData. Fully unit-testable.
///
/// **Algorithm sharing:** Belsey episode + FIGO cycle rules live in
/// `PhaseBoundaries.cycleStarts(fromBleedingDays:)` — single source of
/// truth across `CycleStore.rebuildCyclesFromDayEntries`, this planner,
/// and `HKExportPlanner`. (Extracted 2026-05-22.)
public enum HKImportPlanner {

    public static func plan(
        samples: [FlowSample],
        existingEntryDates: Set<Date>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HKImportPlan {
        // Use civilDay (UTC-midnight anchored) throughout so keys align
        // with `existingEntryDates` (which come from `CycleStore.loggedDays`,
        // also civilDay-normalised) and with the store's `rebuildCycles…`
        // algorithm. `calendar.startOfDay(for:)` would land on local-tz
        // midnight, which produces a different absolute Date in non-UTC
        // zones — see CivilDay.swift for the full story.
        let today = now.civilDay(in: calendar)

        // Count future-dated samples before dedupe so the summary is
        // accurate. The dedupe loop below silently drops them.
        var futureDroppedCount = 0
        for sample in samples where sample.date.civilDay(in: calendar) > today {
            futureDroppedCount += 1
        }

        // 1. Normalise to civilDay + dedupe (heaviest flow wins per day) +
        //    drop future-dated samples.
        var byDay: [Date: FlowLevel] = [:]
        for sample in samples {
            let day = sample.date.civilDay(in: calendar)
            guard day <= today else { continue }
            if let existing = byDay[day], existing.rawValue >= sample.flow.rawValue {
                continue   // keep heavier flow already stored
            }
            byDay[day] = sample.flow
        }

        let sortedDays = byDay.keys.sorted()
        guard !sortedDays.isEmpty else {
            return HKImportPlan(
                groups: [],
                totalSamples: samples.count,
                skippedFutureCount: futureDroppedCount
            )
        }

        // 2 + 3. Belsey episode rule + FIGO cycle floor. Shared
        // implementation in `PhaseBoundaries.cycleStarts(fromBleedingDays:)`.
        let cycleStarts = PhaseBoundaries.cycleStarts(
            fromBleedingDays: sortedDays,
            calendar: calendar
        )

        // 4. Assemble per-cycle groups. For each cycle start, collect every
        //    bleeding day in `[cycleStart, nextCycleStart)`.
        var groups: [HKImportCycleGroup] = []
        for (idx, start) in cycleStarts.enumerated() {
            let nextStart = idx + 1 < cycleStarts.count ? cycleStarts[idx + 1] : nil
            let upperExclusive = nextStart ?? Date.distantFuture
            let daysInThisCycle = sortedDays.filter { $0 >= start && $0 < upperExclusive }

            var importable: [HKImportPlan.Day] = []
            var conflicts = 0
            for day in daysInThisCycle {
                guard let flow = byDay[day] else { continue }
                if existingEntryDates.contains(day) {
                    conflicts += 1
                } else {
                    importable.append(HKImportPlan.Day(date: day, flow: flow))
                }
            }

            let lengthDays: Int? = nextStart.flatMap {
                calendar.dateComponents([.day], from: start, to: $0).day
            }

            groups.append(HKImportCycleGroup(
                id: UUID(),
                cycleStart: start,
                lengthDays: lengthDays,
                importableDays: importable,
                conflictingCount: conflicts
            ))
        }

        return HKImportPlan(
            groups: groups,
            totalSamples: samples.count,
            skippedFutureCount: futureDroppedCount
        )
    }
}

/// Result of `HKImportPlanner.plan`. Holds the grouped cycles + summary
/// counts. The view layer renders one row per group with a toggle; on
/// commit, calls `selectedDays(skipping:)` to flatten back to the days
/// the user has approved.
public struct HKImportPlan: Sendable, Equatable {
    public let groups: [HKImportCycleGroup]
    public let totalSamples: Int
    public let skippedFutureCount: Int

    public var totalImportableDays: Int {
        groups.reduce(0) { $0 + $1.importableDays.count }
    }

    public var totalConflictingDays: Int {
        groups.reduce(0) { $0 + $1.conflictingCount }
    }

    /// Per-day record after dedupe + flow normalisation. Equatable so the
    /// view layer can `\.id` it.
    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public let flow: FlowLevel
        public var id: Date { date }
    }

    /// Flatten the plan back to a day list, filtering out groups the user
    /// has toggled off. Always excludes conflicting days (silent-skip
    /// policy). Returns a stable order (sorted by date ascending).
    public func selectedDays(skipping skippedGroupIDs: Set<UUID>) -> [Day] {
        groups
            .filter { !skippedGroupIDs.contains($0.id) }
            .flatMap { $0.importableDays }
            .sorted { $0.date < $1.date }
    }
}

public struct HKImportCycleGroup: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let cycleStart: Date
    /// Length in days = next cycle's start − this cycle's start. `nil`
    /// for the most-recent cycle (we don't yet know where it ends).
    public let lengthDays: Int?
    public let importableDays: [HKImportPlan.Day]
    public let conflictingCount: Int

    public var bleedingDayCount: Int { importableDays.count + conflictingCount }
    public var hasConflicts: Bool { conflictingCount > 0 }
}
