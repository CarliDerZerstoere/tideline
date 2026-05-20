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

    /// Write a menstrual-flow sample for the given date. The date is treated
    /// as start-of-day; HealthKit stores menstrual flow as a category sample
    /// spanning a single day.
    public func writeMenstrualFlow(date: Date, flow: FlowLevel) async throws {
        guard let hkValue = FlowMapping.healthKitValue(for: flow) else {
            // FlowLevel.none means "no flow today"; do not insert anything.
            // (HealthKit's .none category value exists but represents "period
            // day with absent flow" — semantically different and rarely useful.)
            return
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86_400 - 1)
        let metadata = [HKMetadataKeyMenstrualCycleStart: false]
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
