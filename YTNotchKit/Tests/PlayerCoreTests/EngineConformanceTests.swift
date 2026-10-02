import EngineConformance
import Testing
@testable import PlayerCore

/// FakeEngine passes every engine scenario.
@MainActor
struct FakeEngineConformanceTests {
    @Test(arguments: EngineScenario.all)
    func fakeEngine(scenario: EngineScenario) async throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        try await scenario.run(EngineHarness(store: store) { seconds in engine.advance(by: seconds) })
    }
}
