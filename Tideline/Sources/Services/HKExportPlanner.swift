import Foundation

/// Pure planner for the HealthKit menstrual-flow **export** flow (task
/// #91). Inverse of `HKImportPlanner`: takes Tideline's logged days +
/// the set of civilDay-normalised dates already present in HealthKit, and
/// produces an `HKExportPlan` describing what to write.
///
///   - Drops `.none` (won't write — matches `FlowMapping` semantics).
///   - Drops future-dated entries (clock skew / edited entries).
///   - Dedupes to one entry per civilDay (heaviest flow wins).
///   - Conflict policy: silently skip days that already exist in HK
///     (don't overwrite — minimises surprise).
///   - Groups remaining days into cycles using the same Belsey (≤2 dry
///     days = same episode) + FIGO (≥21 days = new cycle) rules the
///     store applies in `rebuildCyclesFromDayEntries`.
///
/// Pure — no HealthKit, no SwiftUI, no SwiftData. Fully unit-testable.
///
/// **Algorithm sharing:** Belsey episode + FIGO cycle rules live in
/// `PhaseBoundaries.cycleStarts(fromBleedingDays:)` — single source of
/// truth across `CycleStore.rebuildCyclesFromDayEntries`,
/// `HKImportPlanner`, and this planner. (Extracted 2026-05-22.)
public enum HKExportPlanner {

    public static func plan(
        tidelineEntries: [(date: Date, flow: FlowLevel)],
        existingHKDates: Set<Date>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HKExportPlan {
        let today = now.civilDay(in: calendar)
        let total = tidelineEntries.count

        // 1. Drop `.none`, drop future-dated, dedupe to civilDay (keep
        //    heaviest flow per day).
        var futureDropped = 0
        var byDay: [Date: FlowLevel] = [:]
        for entry in tidelineEntries where entry.flow != .none {
            let day = entry.date.civilDay(in: calendar)
            if day > today { futureDropped += 1; continue }
            if let existing = byDay[day], existing.rawValue >= entry.flow.rawValue {
                continue
            }
            byDay[day] = entry.flow
        }

        // 2. Partition: writable (not in HK) vs alreadyInHK.
        var writableDays: [Date: FlowLevel] = [:]
        var alreadyInHKDays: Set<Date> = []
        for (day, flow) in byDay {
            if existingHKDates.contains(day) {
                alreadyInHKDays.insert(day)
            } else {
                writableDays[day] = flow
            }
        }

        // Days the planner needs to group = union of writable + alreadyInHK,
        // because cycle boundaries must be derived from the full picture,
        // not just the writable subset.
        //
        // **Limitation**: only Tideline-known days inform the partition;
        // HK-only days (logged directly into Apple Health and never
        // touching Tideline) are invisible to grouping here. Belsey could
        // therefore merge two episodes that HK's own picture would split.
        // Acceptable for v1 — the planner can only act on Tideline data.
        // If symmetric history accuracy becomes important, pass a fuller
        // `existingHKDates` set that includes HK-only days.
        let allDays = Set(writableDays.keys).union(alreadyInHKDays)
        let sortedDays = allDays.sorted()

        guard !sortedDays.isEmpty else {
            return HKExportPlan(
                groups: [],
                totalTidelineDays: total,
                skippedAlreadyInHK: alreadyInHKDays.count,
                skippedFutureCount: futureDropped
            )
        }

        // 3 + 4. Belsey episode rule + FIGO cycle floor. Shared
        // implementation in `PhaseBoundaries.cycleStarts(fromBleedingDays:)`.
        let cycleStarts = PhaseBoundaries.cycleStarts(
            fromBleedingDays: sortedDays,
            calendar: calendar
        )

        // 5. Assemble groups. Each group spans [cycleStart, nextCycleStart).
        var groups: [HKExportCycleGroup] = []
        for (idx, start) in cycleStarts.enumerated() {
            let nextStart: Date? = idx + 1 < cycleStarts.count ? cycleStarts[idx + 1] : nil
            let upperExclusive = nextStart ?? Date.distantFuture
            let daysInThisCycle = sortedDays.filter { $0 >= start && $0 < upperExclusive }

            var writable: [HKExportPlan.Day] = []
            var inHK = 0
            for day in daysInThisCycle {
                if let flow = writableDays[day] {
                    // Mark day-1 of each cycle as `isCycleStart=true` per
                    // HK spec — Apple Health's Cycle Tracking UI uses this
                    // flag to render cycle start markers. If the user's
                    // day-1 of the cycle is already in HK (conflict-skip),
                    // no writable day in this group will carry the flag,
                    // which is correct: we never re-tag HK's existing day-1.
                    let isStart = (day == start)
                    writable.append(HKExportPlan.Day(date: day, flow: flow, isCycleStart: isStart))
                } else if alreadyInHKDays.contains(day) {
                    inHK += 1
                }
            }

            let lengthDays: Int? = nextStart.flatMap {
                calendar.dateComponents([.day], from: start, to: $0).day
            }

            groups.append(HKExportCycleGroup(
                id: UUID(),
                cycleStart: start,
                lengthDays: lengthDays,
                writableDays: writable,
                alreadyInHKCount: inHK
            ))
        }

        return HKExportPlan(
            groups: groups,
            totalTidelineDays: total,
            skippedAlreadyInHK: alreadyInHKDays.count,
            skippedFutureCount: futureDropped
        )
    }
}

public struct HKExportPlan: Sendable, Equatable {
    public let groups: [HKExportCycleGroup]
    public let totalTidelineDays: Int
    public let skippedAlreadyInHK: Int
    public let skippedFutureCount: Int

    public var totalWritableDays: Int {
        groups.reduce(0) { $0 + $1.writableDays.count }
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public let flow: FlowLevel
        /// True iff this day is day-1 of its cycle. Drives the
        /// `HKMetadataKeyMenstrualCycleStart` metadata key on HK write —
        /// Apple Health's Cycle Tracking UI expects exactly one `true`
        /// per cycle (day-1) and `false` for the rest.
        public let isCycleStart: Bool

        public init(date: Date, flow: FlowLevel, isCycleStart: Bool) {
            self.date = date
            self.flow = flow
            self.isCycleStart = isCycleStart
        }

        public var id: Date { date }
    }

    /// Days to write, filtering out groups the user has toggled off.
    public func selectedDays(skipping skippedGroupIDs: Set<UUID>) -> [Day] {
        groups
            .filter { !skippedGroupIDs.contains($0.id) }
            .flatMap { $0.writableDays }
            .sorted { $0.date < $1.date }
    }
}

public struct HKExportCycleGroup: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let cycleStart: Date
    /// `nil` for the most-recent (open) cycle — no length known yet.
    public let lengthDays: Int?
    public let writableDays: [HKExportPlan.Day]
    public let alreadyInHKCount: Int

    public var totalDayCount: Int { writableDays.count + alreadyInHKCount }
    public var hasConflicts: Bool { alreadyInHKCount > 0 }
}
