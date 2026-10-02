import AppKit
import EngineConformance
import Foundation
import PlayerCore
import Testing
import WebKit
@testable import WebPlayer

@MainActor
@Suite(.serialized)
struct WebPlayerControllerTests {
    static func fixture(_ options: String...) throws -> WebPlayerController.Configuration {
        try fixture(options)
    }

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

    /// The full window shows the page, and the notch shows the store: whatever changes in the
    /// page itself, as a person would change it in the full window, reaches the store.
    @Test func whatChangesInThePageReachesTheStore() async throws {
        let controller = WebPlayerController(configuration: try Self.fixture())
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.track != nil }
        _ = try await controller.webView.callAsyncJavaScript("""
            window.fixture.setTrack(2);
            document.querySelector('like-button-view-model button').click();
            """, contentWorld: .page)
        let page = try #require(try await controller.webView.callAsyncJavaScript("return window.fixture.status()", contentWorld: .page) as? [String: Any])
        let title = try #require(page["title"] as? String)
        #expect(page["liked"] as? Bool == true)
        try await eventually("the store shows what the page shows") {
            store.state.track?.title == title && store.state.liked && store.state.queue.first(where: \.isCurrent)?.index == 2
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
}
