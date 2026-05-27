import Foundation
import HealthKit

/// Thin actor wrapping HealthKit menstrual-flow read/write.
///
/// `HKHealthStore` is non-Sendable in Swift 6 strict concurrency, so it lives
/// entirely inside this actor and never crosses concurrency domains. Errors
/// surface as `HealthKitError` so the caller can route them to UI without
/// inspecting `NSError` codes.
///
/// Scope: only `menstrualFlow` for v0.1. Wrist temperature / RHR / sleep are
/// deliberately deferred to v3 — see `docs/research/2026-05-20-v2-improvement-techniques-verified.md`.
public actor HealthKitService {
    private let store: HKHealthStore
    private let menstrualFlowType: HKCategoryType

    public init() {
        self.store = HKHealthStore()
        self.menstrualFlowType = HKCategoryType(.menstrualFlow)
    }

    // MARK: - Authorization

    public static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request read + write authorization for menstrual flow. Idempotent; the
    /// system shows the dialog only on the first call.
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.unavailable
        }
        let types: Set<HKSampleType> = [menstrualFlowType]
        try await store.requestAuthorization(toShare: types, read: types)
    }

    /// The user's *write* permission status. Apple does not expose read
    /// permission status by design (privacy: prevents apps from probing what
    /// the user has logged elsewhere). To detect read availability, attempt a
    /// query and handle the resulting empty/denied result.
    public func writeAuthorizationStatus() -> HKAuthorizationStatus {
        store.authorizationStatus(for: menstrualFlowType)
    }

    // MARK: - Read

    /// Read menstrual-flow samples on or after the given date, sorted oldest
    /// first. Returns an empty array if the user has denied read access or
    /// has logged nothing.
    public func readMenstrualFlow(since startDate: Date) async throws -> [FlowSample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )
        let sortByDate = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: menstrualFlowType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortByDate]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.query(error))
                    return
                }
                let categorySamples = samples?.compactMap { $0 as? HKCategorySample } ?? []
                let mapped = categorySamples.compactMap(FlowSample.init(sample:))
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    // MARK: - Write

    /// Write a batch of menstrual-flow samples sequentially (task #91).
    /// Returns a `BatchWriteResult` carrying both the success count and
    /// the first error encountered (if any). Never throws on partial
    /// success — the caller decides how to surface partial outcomes.
    /// Apple Health doesn't dedupe on re-write, so if we threw mid-batch
    /// the user would see "failed" while N samples succeeded, then
    /// retry-and-duplicate. (Reviewer rec.)
    ///
    /// `.none` samples are silently skipped (matches `writeMenstrualFlow`
    /// per-day behaviour and `FlowMapping.healthKitValue`'s nil case).
    ///
    /// `isCycleStart` on each sample maps to `HKMetadataKeyMenstrualCycleStart`
    /// in the HK metadata — per Apple's spec, the first day of each cycle
    /// MUST be `true` so Apple Health's Cycle Tracking UI can mark cycle
    /// starts correctly. Caller (typically `HKExportPlanner` via
    /// `HealthKitExportSheet`) is responsible for flagging day-1.
    ///
    /// Writes run sequentially — conservatively serialised; Apple does
    /// not publish a thread-safety contract for `HKHealthStore.save`.
    public func writeMenstrualFlowBatch(
        _ samples: [(date: Date, flow: FlowLevel, isCycleStart: Bool)]
    ) async -> BatchWriteResult {
        var written = 0
        var firstError: Error?
        for sample in samples {
            guard sample.flow != .none else { continue }
            do {
                try await writeMenstrualFlow(
                    date: sample.date,
                    flow: sample.flow,
                    isCycleStart: sample.isCycleStart
                )
                written += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return BatchWriteResult(written: written, firstError: firstError)
    }

    /// Write a menstrual-flow sample for the given date. The date is treated
    /// as start-of-day; HealthKit stores menstrual flow as a category sample
    /// spanning a single day.
    ///
    /// `isCycleStart` controls the `HKMetadataKeyMenstrualCycleStart` flag
    /// per Apple's spec: the day-1 of each cycle MUST be `true`; subsequent
    /// bleeding days of the same cycle MUST be `false`. Default `false`
    /// preserves backward-compat for callers that don't know cycle structure
    /// (single ad-hoc writes), but the batch path through
    /// `writeMenstrualFlowBatch` knows cycle starts and passes them through.
    public func writeMenstrualFlow(
        date: Date,
        flow: FlowLevel,
        isCycleStart: Bool = false
    ) async throws {
        guard let hkValue = FlowMapping.healthKitValue(for: flow) else {
            // FlowLevel.none means "no flow today"; do not insert anything.
            // (HealthKit's .none category value exists but represents "period
            // day with absent flow" — semantically different and rarely useful.)
            return
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let endOfDay = nextDay.addingTimeInterval(-1)
        let metadata: [String: Any] = [HKMetadataKeyMenstrualCycleStart: isCycleStart]
        let sample = HKCategorySample(
            type: menstrualFlowType,
            value: hkValue,
            start: startOfDay,
            end: endOfDay,
            metadata: metadata
        )
        try await store.save(sample)
    }

}

/// Pure mapping between Tideline's `FlowLevel` and HealthKit's
/// `HKCategoryValueVaginalBleeding`. Free namespace so callers don't need to
/// allocate an `HKHealthStore` just to translate values — and so the
/// `HealthKitService` actor stays focused on stateful HK calls.
public enum FlowMapping {
    /// Map our `FlowLevel` to HealthKit's raw value. Returns nil for `.none`
    /// (we don't write empty entries to HealthKit).
    /// `.spotting` is mapped to `.light` because HealthKit's menstrualFlow
    /// type doesn't have a spotting bucket. Users tracking spotting with finer
    /// granularity should use HealthKit's separate `intermenstrualBleeding`
    /// type (deferred to a later work block).
    public static func healthKitValue(for flow: FlowLevel) -> Int? {
        switch flow {
        case .none: return nil
        case .spotting: return HKCategoryValueVaginalBleeding.light.rawValue
        case .light: return HKCategoryValueVaginalBleeding.light.rawValue
        case .medium: return HKCategoryValueVaginalBleeding.medium.rawValue
        case .heavy: return HKCategoryValueVaginalBleeding.heavy.rawValue
        }
    }

    /// Inverse of `healthKitValue(for:)`. Returns nil if the HK value is
    /// unrecognized.
    public static func flowLevel(for hkValue: Int) -> FlowLevel? {
        switch hkValue {
        case HKCategoryValueVaginalBleeding.unspecified.rawValue: return .light
        case HKCategoryValueVaginalBleeding.light.rawValue: return .light
        case HKCategoryValueVaginalBleeding.medium.rawValue: return .medium
        case HKCategoryValueVaginalBleeding.heavy.rawValue: return .heavy
        default: return nil
        }
    }
}

/// A menstrual-flow sample read from HealthKit.
public struct FlowSample: Sendable, Equatable {
    public let date: Date
    public let flow: FlowLevel
    public let healthKitUUID: UUID

    init?(sample: HKCategorySample) {
        guard let level = FlowMapping.flowLevel(for: sample.value) else { return nil }
        self.date = sample.startDate
        self.flow = level
        self.healthKitUUID = sample.uuid
    }

    public init(date: Date, flow: FlowLevel, healthKitUUID: UUID = UUID()) {
        self.date = date
        self.flow = flow
        self.healthKitUUID = healthKitUUID
    }
}

public enum HealthKitError: Error, Sendable {
    case unavailable
    case authorizationDenied
    case query(Error)
}

/// Outcome of `writeMenstrualFlowBatch` (task #91). Carries both the
/// number of samples successfully written and the first error
/// encountered (if any). Lets the caller render a partial-success state
/// without losing the count to a thrown error.
public struct BatchWriteResult: Sendable {
    public let written: Int
    public let firstError: Error?

    public init(written: Int, firstError: Error?) {
        self.written = written
        self.firstError = firstError
    }

    public var allSucceeded: Bool { firstError == nil }
}
