import EngineConformance
import Testing
@testable import PlayerCore

@MainActor
struct FakeEngineConformanceTests {
    @Test(arguments: EngineScenario.all)
    func fakeEngine(scenario: EngineScenario) async throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        try await scenario.run(EngineHarness(store: store) { seconds in engine.advance(by: seconds) })
    }
}
