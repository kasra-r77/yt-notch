import AppKit
import EngineConformance
import Foundation
import PlayerCore
import Testing
import WebKit
@testable import WebPlayer

/// WebPlayerController on the fixture page: the same engine scenarios FakeEngine passes,
/// plus what is particular to the controller.
@MainActor
@Suite(.serialized)
struct WebPlayerControllerTests {
    static func fixture(_ options: String...) throws -> WebPlayerController.Configuration {
        try fixture(options)
    }

    /// The fixture page, with defaults of the test's own and no browser to open links in.
    static func fixture(_ options: [String], defaults: UserDefaults? = nil) throws -> WebPlayerController.Configuration {
        guard let url = Bundle.module.url(forResource: "fake-player", withExtension: "html", subdirectory: "Fixtures") else {
            throw ConformanceFailure(description: "fake-player.html is missing from the test bundle")
        }
        var configuration = WebPlayerController.Configuration()
        configuration.page = .html(
            try String(contentsOf: url, encoding: .utf8),
            baseURL: URL(string: "https://fixture.ytnotch.test/#" + options.joined(separator: ","))!
        )
        configuration.dataStore = .nonPersistent()
        configuration.defaults = defaults ?? Self.scratchDefaults
        configuration.openInBrowser = { _ in }
        return configuration
    }

    /// Shared by tests that don't look at what the window remembers.
    static let scratchDefaults = UserDefaults(suiteName: "io.github.kasra-r77.ytnotch.tests.scratch")!

    init() {
        _ = NSApplication.shared
    }

    @Test(arguments: EngineScenario.all)
    func passesTheEngineScenarios(scenario: EngineScenario) async throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let store = PlayerStore(engine: controller)
        try await scenario.run(EngineHarness(store: store) { seconds in
            _ = try await controller.webView.callAsyncJavaScript(
                "window.fixture.advance(seconds)", arguments: ["seconds": seconds], contentWorld: .page
            )
        })
    }

    @Test func reportsSignedOut() async throws {
        let store = PlayerStore(engine: WebPlayerController(configuration: try Self.fixture("signed-out")))
        try await eventually("signed out") { store.state.health.status == .signedOut }
    }

    @Test func reportsMissingParts() async throws {
        let store = PlayerStore(engine: WebPlayerController(configuration: try Self.fixture("no-like")))
        try await eventually("like missing") { store.state.health.missing == [.like] }
        #expect(!store.state.isAvailable(.like))
    }

    /// The pictures arrive in the store from the page: the app downloads none itself.
    @Test func picturesReachTheStoreFromThePage() async throws {
        let store = PlayerStore(engine: WebPlayerController(configuration: try Self.fixture()))
        try await eventually("the track's artwork") {
            store.state.track?.artworkURL.flatMap { store.state.artwork[$0] } != nil
        }
        try await eventually("the queue's thumbnails") {
            let thumbnails = store.state.queue.compactMap(\.artworkURL)
            return !thumbnails.isEmpty && thumbnails.allSatisfy { store.state.artwork[$0] != nil }
        }
    }

    @Test func usesSafarisUserAgentAndTheBridge() throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        #expect(controller.webView.customUserAgent?.contains("Safari/") == true)
        #expect(controller.webView.configuration.userContentController.userScripts.contains { $0.source == Bridge.script })
        #expect(controller.webView.configuration.preferences.inactiveSchedulingPolicy == .none)
    }

    @Test func defaultsToTheSiteAndThePersistentStore() {
        let configuration = WebPlayerController.Configuration()
        #expect(configuration.dataStore.isPersistent)
        guard case let .url(url) = configuration.page else {
            Issue.record("default page is not a URL")
            return
        }
        #expect(url.host == "music.youtube.com")
    }

    @Test func windowIsOrderedInButOffScreen() throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let window = try #require(controller.webView.window)
        #expect(window.isVisible)
        #expect(!controller.isWindowVisible)
        #expect(window.collectionBehavior.contains(.transient))
    }

    @Test func showAndHideTheWindow() throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        controller.showWindow()
        #expect(controller.isWindowVisible)
        controller.hideWindow()
        #expect(!controller.isWindowVisible)
        #expect(controller.webView.window?.isVisible == true)
    }

    // Calls the close handler directly: AppKit's own close path (performClose) in a test
    // process with no running app ends the process. The app's close button is checked by hand.
    @Test func closingTheWindowOnlyHidesIt() throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        controller.showWindow()
        let window = try #require(controller.webView.window)
        #expect(controller.fullWindow.windowShouldClose(window) == false)
        #expect(!controller.isWindowVisible)
        #expect(window.isVisible)
    }

    /// Display changes rebuild the notches (NotchDisplayManager) but must never reach the
    /// player: macOS can't pull its window back on screen, and nothing reloads or pauses.
    @Test func displayChangesLeaveThePlayerAlone() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.health.status == .ok && store.state.track != nil }
        store.play()
        try await eventually("playing") { store.state.isPlaying }
        let window = try #require(controller.webView.window)
        let frame = window.frame
        for screen in NSScreen.screens {
            #expect(window.constrainFrameRect(frame, to: screen) == frame)
        }

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApplication.shared)
        try await Task.sleep(for: .milliseconds(500))
        #expect(window.frame == frame)
        #expect(controller.loadAttempts == 1)
        #expect(store.state.isPlaying)
    }

    @Test func loadFailureIsOffline() async throws {
        var configuration = WebPlayerController.Configuration()
        configuration.page = .url(URL(string: "https://nothing-here.invalid/")!)
        configuration.dataStore = .nonPersistent()
        let store = PlayerStore(engine: WebPlayerController(configuration: configuration))
        try await eventually("offline", timeout: 15) { store.state.health.status == .offline }
    }
}
