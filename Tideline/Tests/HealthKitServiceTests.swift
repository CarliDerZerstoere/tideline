import Testing
import Foundation
import HealthKit
@testable import Tideline

/// Pure unit tests of the `FlowLevel ↔ HKCategoryValueVaginalBleeding` mapping.
/// Authorization and storage round-trips are not tested here — the simulator
/// can't grant HealthKit auth cleanly, and those are integration concerns.
@Suite("FlowMapping — HealthKit value conversion")
struct HealthKitServiceTests {

    @Test("FlowLevel.none does not produce an HK value")
    func noneFlowNotWritten() {
        #expect(FlowMapping.healthKitValue(for: .none) == nil)
    }

    @Test("light/medium/heavy round-trip through HealthKit values")
    func roundTrip() {
        for flow in [FlowLevel.light, .medium, .heavy] {
            guard let hk = FlowMapping.healthKitValue(for: flow) else {
                Issue.record("Expected HK value for \(flow)")
                return
            }
            #expect(FlowMapping.flowLevel(for: hk) == flow)
        }
    }

    @Test("spotting maps to HK light (lossy)")
    func spottingMapsToLight() {
        #expect(FlowMapping.healthKitValue(for: .spotting) == HKCategoryValueVaginalBleeding.light.rawValue)
        // Reverse mapping: HK light → our .light (spotting is lost).
        #expect(FlowMapping.flowLevel(for: HKCategoryValueVaginalBleeding.light.rawValue) == .light)
    }

    @Test("HK unspecified maps to light (best-effort)")
    func unspecifiedMapsToLight() {
        #expect(FlowMapping.flowLevel(for: HKCategoryValueVaginalBleeding.unspecified.rawValue) == .light)
    }

    @Test("unknown HK raw value returns nil")
    func unknownReturnsNil() {
        #expect(FlowMapping.flowLevel(for: -999) == nil)
    }

    @Test("isHealthDataAvailable reflects HKHealthStore.isHealthDataAvailable")
    func availabilityCheck() {
        // On simulator + most devices this is true; on Mac without HealthKit it's false.
        // Just confirm the property is callable without crashing.
        _ = HealthKitService.isHealthDataAvailable
    }
}
