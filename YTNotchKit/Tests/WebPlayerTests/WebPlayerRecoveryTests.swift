import AppKit
import EngineConformance
import Foundation
import PlayerCore
import Testing
import WebKit
@testable import WebPlayer

/// Each failure the player recovers from, triggered on purpose, with short timings.
@MainActor
@Suite(.serialized)
struct WebPlayerRecoveryTests {
    static let unreachable = URL(string: "https://nothing-here.invalid/")!

    init() {
        _ = NSApplication.shared
    }

    static func fixture(_ options: String..., timing: (inout RecoveryTiming) -> Void = { _ in }) throws -> WebPlayerController.Configuration {
        guard let url = Bundle.module.url(forResource: "fake-player", withExtension: "html", subdirectory: "Fixtures") else {
            throw ConformanceFailure(description: "fake-player.html is missing from the test bundle")
        }
        var configuration = WebPlayerController.Configuration()
        configuration.page = .html(
            try String(contentsOf: url, encoding: .utf8),
            // Options in the query, so loading the page again makes a new document.
            baseURL: URL(string: "https://fixture.ytnotch.test/?" + options.joined(separator: ","))!
        )
        configuration.dataStore = .nonPersistent()
        configuration.networkMonitor = nil
        timing(&configuration.timing)
        return configuration
    }

    /// A page that can't load, with the fixture ready to switch to once "the network is back".
    static func offline(retryDelays: [TimeInterval], monitor: FakeNetworkMonitor? = nil) throws -> (WebPlayerController.Configuration, fixture: WebPlayerController.Configuration.Page) {
        let fixture = try fixture()
        var configuration = fixture
        configuration.page = .url(unreachable)
        configuration.timing.retryDelays = retryDelays
        configuration.networkMonitor = monitor
        return (configuration, fixture.page)
    }

    static func playing(_ store: PlayerStore) async throws {
        try await eventually("ready with a track") { store.state.health.status == .ok && store.state.track != nil }
        store.play()
        try await eventually("playing") { store.state.isPlaying }
    }

    // MARK: Page fails to load

    @Test func retryDelaysFollowThePlanThenRepeat() {
        let timing = RecoveryTiming()
        #expect((0..<6).map(timing.retryDelay(attempt:)) == [2, 5, 15, 60, 60, 60])
    }

    @Test func aFailedLoadIsOfflineAndKeepsRetryingUntilThePageLoads() async throws {
        let (configuration, fixture) = try Self.offline(retryDelays: [0.2])
        let controller = WebPlayerController(configuration: configuration)
        let store = PlayerStore(engine: controller)
        try await eventually("offline", timeout: 15) { store.state.health.status == .offline }
        try await eventually("retried twice", timeout: 20) { controller.loadAttempts >= 3 }
        #expect(store.state.health.status == .offline)

        controller.page = fixture
        try await eventually("back online", timeout: 10) { store.state.health.status == .ok && store.state.track != nil }
        let attempts = controller.loadAttempts
        try await Task.sleep(for: .seconds(1))
        #expect(controller.loadAttempts == attempts, "retries stop once the page loads")
    }

    @Test func theNetworkComingBackRetriesAtOnce() async throws {
        let monitor = FakeNetworkMonitor()
        let (configuration, fixture) = try Self.offline(retryDelays: [60], monitor: monitor)
        let controller = WebPlayerController(configuration: configuration)
        let store = PlayerStore(engine: controller)
        try await eventually("offline", timeout: 15) { store.state.health.status == .offline }
        #expect(controller.loadAttempts == 1)

        controller.page = fixture
        monitor.becomeReachable()
        #expect(controller.loadAttempts == 2)
        try await eventually("back online") { store.state.health.status == .ok }
    }

    @Test func theRetryButtonRetriesAtOnce() async throws {
        let (configuration, fixture) = try Self.offline(retryDelays: [60])
        let controller = WebPlayerController(configuration: configuration)
        let store = PlayerStore(engine: controller)
        try await eventually("offline", timeout: 15) { store.state.health.status == .offline }

        controller.page = fixture
        controller.retry()
        try await eventually("back online") { store.state.health.status == .ok }
    }

    // MARK: Web content crash

    @Test func aCrashReloadsWithoutStartingPlayback() async throws {
        // The autoplay page starts playing whenever it loads, as the site may after a reload.
        let controller = WebPlayerController(configuration: try Self.fixture("autoplay"))
        let store = PlayerStore(engine: controller)
        try await eventually("playing by itself on first load") { store.state.isPlaying }

        controller.webViewWebContentProcessDidTerminate(controller.webView)
        #expect(controller.loadAttempts == 2)
        // The store still has the first page's state, so wait for the new page itself.
        try await eventually("the reloaded page is ready") { controller.readyReports == 2 }
        try await eventually("paused after the reload") { !store.state.isPlaying }
        try await Task.sleep(for: .seconds(1.5))
        let paused = try await controller.webView.callAsyncJavaScript("return window.fixture.status().paused", contentWorld: .page) as? Bool
        #expect(paused == true)
        #expect(!store.state.isPlaying)
        #expect(store.state.health.status == .ok)
    }

    @Test func playingAfterACrashIsAllowedWhenTheUserAsks() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.health.status == .ok && store.state.track != nil }

        controller.webViewWebContentProcessDidTerminate(controller.webView)
        // Wait for the reloaded page to be ready, not for a while: the store still holds the
        // first page's track, and a play sent before the new page's bridge is up is lost.
        try await eventually("the reloaded page is ready") { controller.readyReports == 2 && store.state.track != nil }
        store.play()
        try await eventually("playing") { store.state.isPlaying }
        try await Task.sleep(for: .seconds(1.5))
        #expect(store.state.isPlaying)
    }

    // MARK: Stalls
    // While playing, the bridge reports every second, so these stall timeouts stay well
    // above that.

    @Test func aStallIsFixedByReinjectingTheBridge() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture { $0.stallTimeout = 2 })
        let store = PlayerStore(engine: controller)
        try await Self.playing(store)

        // Clearing the page's timers stops the bridge's heartbeat while the track plays on.
        _ = try await controller.webView.callAsyncJavaScript("window.fixture.stopTimers()", contentWorld: .page)
        try await eventually("a stall was noticed", timeout: 10) { controller.stalls == 1 }
        try await eventually("the bridge reports again") { controller.recoveryStage == .none }
        try await Task.sleep(for: .seconds(3))
        #expect(controller.stalls == 1, "the heartbeat is back")
        #expect(controller.loadAttempts == 1, "no reload was needed")
        #expect(store.state.health.status == .ok)
    }

    @Test func aStallThatNothingFixesMarksTheBridgeBroken() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture {
            $0.stallTimeout = 2
            $0.reloadTimeout = 1
        })
        let store = PlayerStore(engine: controller)
        try await Self.playing(store)

        controller.ignoresBridgeMessages = true
        try await eventually("reloaded once", timeout: 10) { controller.loadAttempts == 2 }
        #expect(controller.recoveryStage == .reloading)
        try await eventually("broken") { store.state.health.status == .bridgeBroken }
        #expect(controller.stalls == 1)
        #expect(!store.state.isAvailable(.playPause))
        try await Task.sleep(for: .seconds(1))
        #expect(controller.loadAttempts == 2, "only one reload")

        // A page that reports ready again (a retry, a sign-in) clears it.
        controller.ignoresBridgeMessages = false
        controller.retry()
        try await eventually("ok again") { store.state.health.status == .ok }
        #expect(controller.recoveryStage == .none)
    }

    @Test func silenceWhilePausedIsNotAStall() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture { $0.stallTimeout = 0.5 })
        let store = PlayerStore(engine: controller)
        try await eventually("ready, paused") { store.state.health.status == .ok && store.state.track != nil }
        // Paused, the bridge reports every 3 seconds, far longer than the stall timeout.
        try await Task.sleep(for: .seconds(2))
        #expect(controller.stalls == 0)
        #expect(controller.loadAttempts == 1)
    }

    @Test func aLongGapBetweenChecksIsSleepNotAStall() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let store = PlayerStore(engine: controller)
        try await Self.playing(store)
        controller.checkForStall(now: Date().addingTimeInterval(120))
        #expect(controller.stalls == 0)
        #expect(controller.recoveryStage == .none)
    }

    // MARK: Wake from sleep

    @Test func wakingMakesTheBridgeReportEverythingAgain() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let log = EventLog()
        controller.start { log.events.append($0) }
        try await eventually("the first report") { log.events.contains { $0.playlists != nil } }
        try await Task.sleep(for: .milliseconds(300))

        // Playlists are posted only when they change, so seeing them again means a refresh.
        log.events.removeAll()
        controller.handleWake()
        try await eventually("playlists again") { log.events.contains { $0.playlists != nil } }
        #expect(log.events.contains { $0.snapshot != nil })
        #expect(log.events.contains { $0.missing != nil })
    }

    @Test func wakingWhileOfflineRetries() async throws {
        let (configuration, fixture) = try Self.offline(retryDelays: [60])
        let controller = WebPlayerController(configuration: configuration)
        let store = PlayerStore(engine: controller)
        try await eventually("offline", timeout: 15) { store.state.health.status == .offline }

        controller.page = fixture
        controller.handleWake()
        #expect(controller.loadAttempts == 2)
        try await eventually("back online") { store.state.health.status == .ok }
    }
}

@MainActor
final class FakeNetworkMonitor: NetworkMonitor {
    private var onReachable: (@MainActor () -> Void)?

    func start(onReachable: @escaping @MainActor () -> Void) {
        self.onReachable = onReachable
    }

    func becomeReachable() {
        onReachable?()
    }
}

@MainActor
final class EventLog {
    var events: [PlayerEvent] = []
}
