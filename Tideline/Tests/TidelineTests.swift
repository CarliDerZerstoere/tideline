import Testing
@testable import Tideline

@Suite("Tideline smoke tests")
struct TidelineTests {
    @Test("FlowLevel covers expected cases")
    func flowLevelCases() {
        #expect(FlowLevel.allCases.count == 5)
        #expect(FlowLevel.none.rawValue == 0)
        #expect(FlowLevel.heavy.rawValue == 4)
    }
}
