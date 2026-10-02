import Testing
@testable import PlayerCore

/// Every health change the store decides.
@MainActor
struct HealthTests {
    @Test func startsAsStarting() {
        let store = PlayerStore(engine: SpyEngine())
        #expect(store.state.health == Health(status: .starting))
        #expect(store.state.bridgeVersion == nil)
    }

    @Test func readySignedInIsOK() {
        let engine = SpyEngine()
        let store = PlayerStore(engine: engine)
        engine.emit(.ready(bridgeVersion: "3", signedIn: true))
        #expect(store.state.health.status == .ok)
        #expect(store.state.bridgeVersion == "3")
    }

    @Test func readySignedOutIsSignedOut() {
        let engine = SpyEngine()
        let store = PlayerStore(engine: engine)
        engine.emit(.ready(bridgeVersion: "3", signedIn: false))
        #expect(store.state.health.status == .signedOut)
    }

    @Test func signedOutEvent() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.signedOut)
        #expect(store.state.health.status == .signedOut)
    }

    @Test func stateDoesNotSignBackIn() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.signedOut, .state(Fixture.playing))
        #expect(store.state.health.status == .signedOut)
    }

    @Test func readyAfterSignInIsOK() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.signedOut, .ready(bridgeVersion: "1", signedIn: true))
        #expect(store.state.health.status == .ok)
    }

    @Test func offlineEvent() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.offline)
        #expect(store.state.health.status == .offline)
    }

    @Test func stateAfterOfflineIsOKAgain() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.offline, .state(Fixture.playing))
        #expect(store.state.health.status == .ok)
    }

    @Test func bridgeBrokenEvent() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.bridgeBroken)
        #expect(store.state.health.status == .bridgeBroken)
    }

    @Test(arguments: [PlayerEvent.offline, .signedOut, .state(Fixture.playing), .health(missing: [])])
    func bridgeBrokenStaysBroken(event: PlayerEvent) {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.bridgeBroken, event)
        #expect(store.state.health.status == .bridgeBroken)
    }

    @Test func readyAfterBridgeBrokenIsOK() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.bridgeBroken, .ready(bridgeVersion: "2", signedIn: true))
        #expect(store.state.health.status == .ok)
        #expect(store.state.bridgeVersion == "2")
    }

    @Test func missingFeaturesAreRecordedAndCleared() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.health(missing: [.like, .queue]))
        #expect(store.state.health.missing == [.like, .queue])
        #expect(store.state.health.status == .ok)
        engine.emit(.health(missing: []))
        #expect(store.state.health.missing.isEmpty)
    }

    @Test func readyClearsMissingFeatures() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.health(missing: [.like]), .ready(bridgeVersion: "1", signedIn: true))
        #expect(store.state.health.missing.isEmpty)
    }

    @Test func bridgeNamesMatchFeatures() {
        #expect(Feature(rawValue: "repeat") == .repeatMode)
        #expect(Feature(rawValue: "playPause") == .playPause)
        #expect(Feature(rawValue: "unknown") == nil)
    }
}
