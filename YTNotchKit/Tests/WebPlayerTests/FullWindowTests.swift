import AppKit
import EngineConformance
import Foundation
import PlayerCore
import Testing
import WebKit
@testable import WebPlayer

/// The full window (W3.3): the one web view on screen, its title bar, what it remembers,
/// where links go, and the first run.
@MainActor
@Suite(.serialized)
final class FullWindowTests {
    final class Browser {
        var opened: [URL] = []
    }

    let suiteName = "io.github.kasra-r77.ytnotch.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let browser = Browser()

    init() {
        _ = NSApplication.shared
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func controller(_ options: String...) throws -> WebPlayerController {
        var configuration = try WebPlayerControllerTests.fixture(options, defaults: defaults)
        configuration.windowHosts = ["fixture.ytnotch.test", "signin.ytnotch.test"]
        configuration.openInBrowser = { [browser] in browser.opened.append($0) }
        return WebPlayerController(configuration: configuration)
    }

    func js(_ controller: WebPlayerController, _ source: String) async throws -> Any? {
        try await controller.webView.callAsyncJavaScript(source, contentWorld: .page)
    }

    func waitForSignInClicks(_ count: Int, in controller: WebPlayerController) async throws {
        let deadline = Date().addingTimeInterval(5)
        while try await js(controller, "return window.fixture.signInClicks") as? Int != count {
            if Date() > deadline { throw ConformanceFailure(description: "Timed out waiting for \(count) sign-in clicks") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func press(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command, in window: NSWindow) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
        )!
        return window.performKeyEquivalent(with: event)
    }

    // MARK: The window

    @Test func opensAtItsSizeCentredOnThePointersScreen() throws {
        let controller = try controller()
        let window = controller.fullWindow.window
        controller.showWindow()
        #expect(controller.isWindowVisible)
        #expect(window.frame == FullWindow.defaultFrame(on: FullWindow.pointerScreen))
        if let area = FullWindow.pointerScreen?.visibleFrame, area.width >= 1100, area.height >= 760 {
            #expect(window.frame.size == NSSize(width: 1100, height: 760))
        }
        #expect(window.minSize == NSSize(width: 800, height: 600))
        #expect(window.collectionBehavior.contains(.fullScreenNone))
        #expect(window.title == "YouTube Music")
        #expect(window.toolbarStyle == .unified)
        #expect(window.toolbar?.items.map(\.itemIdentifier) == [FullWindow.back, FullWindow.forward, FullWindow.reloadItem])
        #expect(window.toolbar?.items.allSatisfy { $0.isNavigational && !$0.isBordered } == true)
        #expect(controller.webView.window === window, "the same web view, not a second one")
        #expect(!controller.fullWindow.showsFirstRunBar)
        controller.hideWindow()
        #expect(!controller.isWindowVisible)
    }

    @Test func remembersWhereItWas() throws {
        let first = try controller()
        first.showWindow()
        let area = try #require(first.fullWindow.window.screen?.visibleFrame)
        let moved = NSRect(x: area.minX + 40, y: area.minY + 40, width: 900, height: 650)
        first.fullWindow.window.setFrame(moved, display: false)
        first.hideWindow()

        let second = try controller()
        second.showWindow()
        #expect(second.fullWindow.window.frame == moved)
        second.hideWindow()
    }

    @Test func closingKeepsTheMusicAndThePage() async throws {
        let controller = try controller()
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.health.status == .ok && store.state.track != nil }
        controller.showWindow()
        store.play()
        try await eventually("playing") { store.state.isPlaying }
        _ = try await js(controller, "window.marker = 'kept'")

        let window = controller.fullWindow.window
        #expect(controller.fullWindow.windowShouldClose(window) == false)
        #expect(!controller.isWindowVisible)
        _ = try await js(controller, "window.fixture.advance(2)")
        try await eventually("still playing, further on") { store.state.isPlaying && store.state.position >= 2 }

        controller.showWindow()
        #expect(controller.webView.window === window)
        #expect(try await js(controller, "return window.marker") as? String == "kept", "the same page, not a reload")
        #expect(controller.loadAttempts == 1)
        controller.hideWindow()
    }

    @Test func keyboardShortcutsAndTheTitleBarButtons() async throws {
        let controller = try controller()
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.health.status == .ok }
        controller.showWindow()
        let window = controller.fullWindow.window
        let back = try #require(controller.fullWindow.item(FullWindow.back))
        let forward = try #require(controller.fullWindow.item(FullWindow.forward))
        #expect(!back.isEnabled && !forward.isEnabled, "nowhere to go yet")

        // Two pages with history. WebKit keeps none for pages loaded from a string, like the
        // fixture, so these are files.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.html")
        let second = folder.appendingPathComponent("second.html")
        try "<p>first</p>".write(to: first, atomically: true, encoding: .utf8)
        try "<p>second</p>".write(to: second, atomically: true, encoding: .utf8)
        controller.webView.loadFileURL(first, allowingReadAccessTo: folder)
        try await eventually("first page") { controller.webView.url == first && !controller.webView.isLoading }
        controller.webView.loadFileURL(second, allowingReadAccessTo: folder)
        try await eventually("history") { controller.webView.canGoBack }
        #expect(back.isEnabled && !forward.isEnabled)

        #expect(press("[", in: window))
        try await eventually("back") { controller.webView.url == first }
        try await eventually("forward enabled") { forward.isEnabled && !back.isEnabled }
        #expect(press("]", in: window))
        try await eventually("forward") { controller.webView.url == second }

        let loads = controller.loadAttempts
        #expect(press("r", in: window))
        #expect(controller.loadAttempts == loads + 1, "the player's own reload")

        #expect(press("w", in: window))
        #expect(!controller.isWindowVisible)
    }

    // MARK: Links

    @Test func followedLinksOutOfTheSiteOpenInTheBrowser() async throws {
        let controller = try controller()
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.health.status == .ok }
        let before = controller.webView.url
        _ = try await js(controller, """
            const link = document.createElement('a');
            link.href = 'https://elsewhere.test/help';
            document.body.appendChild(link);
            link.click();
            """)
        try await eventually("opened in the browser") { !self.browser.opened.isEmpty }
        #expect(browser.opened == [URL(string: "https://elsewhere.test/help")!])
        #expect(controller.webView.url == before, "the window stays on the site")
    }

    @Test func whichLinksLeave() {
        let hosts: Set<String> = ["music.youtube.com", "accounts.google.com"]
        let leaves = { (address: String, followed: Bool) in
            LinkPolicy.opensInBrowser(URL(string: address)!, followedLink: followed, allowedHosts: hosts)
        }
        #expect(leaves("https://www.example.com/", true))
        #expect(leaves("https://support.google.com/youtubemusic", true))
        #expect(leaves("mailto:someone@example.com", true))
        #expect(!leaves("https://music.youtube.com/library", true))
        #expect(!leaves("https://ACCOUNTS.google.com/signin", true), "hosts are matched without case")
        #expect(!leaves("https://sso.example.com/saml", false), "a sign-in redirect stays in the window")
        #expect(!leaves("about:blank", true))
    }

    // MARK: First run

    @Test func firstRunOpensOnSignInAndEndsWhenTheWindowCloses() async throws {
        let controller = try controller("signed-out")
        #expect(controller.openOnFirstLaunch())
        #expect(controller.isWindowVisible)
        let bar = controller.fullWindow.firstRunBar
        #expect(controller.fullWindow.showsFirstRunBar)
        #expect(bar.stage == .signIn)
        #expect(bar.label.stringValue == "Sign in to YouTube Music to start. You'll stay signed in on this Mac.")
        #expect(bar.closeButton.isHidden)

        let store = PlayerStore(engine: controller)
        try await eventually("signed out") { store.state.health.status == .signedOut }
        try await waitForSignInClicks(1, in: controller)

        // Signing in ends on the site again, which reports it. (A new address: a load that
        // changes only the fragment doesn't reload.)
        let html = try #require(try WebPlayerControllerTests.fixture([]).page.html)
        controller.page = .html(html, baseURL: URL(string: "https://fixture.ytnotch.test/?after-sign-in")!)
        controller.retry()
        try await eventually("signed in") { store.state.health.status == .ok }
        #expect(bar.stage == .signedIn)
        #expect(bar.label.stringValue == "You're signed in. Music you play now shows in the notch.")
        #expect(!bar.closeButton.isHidden)
        #expect(bar.closeButton.keyEquivalent == "\r", "the default button")

        // The button's action, without AppKit's click tracking, which needs a running app.
        #expect(bar.closeButton.sendAction(bar.closeButton.action, to: bar.closeButton.target))
        #expect(!controller.isWindowVisible)
        #expect(!controller.fullWindow.showsFirstRunBar)
        #expect(!controller.openOnFirstLaunch(), "later launches open nothing")
        #expect(!controller.isWindowVisible)
        #expect(!(try self.controller()).openOnFirstLaunch())
    }

    @Test func signingInLaterHasNoFirstRunBar() async throws {
        defaults.set(true, forKey: FullWindow.firstRunDoneKey)
        let controller = try controller("signed-out")
        let store = PlayerStore(engine: controller)
        try await eventually("signed out") { store.state.health.status == .signedOut }
        controller.showWindow(signIn: true)
        try await waitForSignInClicks(1, in: controller)
        #expect(!controller.fullWindow.showsFirstRunBar)
        controller.hideWindow()
    }

    // MARK: The password

    /// Sign-in happens on Google's pages, where the bridge also runs. Nothing from a page
    /// other than the site reaches the app.
    @Test func pagesOtherThanTheSiteNeverReachTheApp() async throws {
        let controller = try controller()
        let store = PlayerStore(engine: controller)
        try await eventually("ready") { store.state.health.status == .ok && store.state.track != nil }
        let html = try #require(try WebPlayerControllerTests.fixture([]).page.html)
        controller.webView.loadHTMLString(html, baseURL: URL(string: "https://signin.ytnotch.test/")!)
        try await eventually("the bridge posts from the other page") { controller.foreignMessages > 0 }
        _ = try await js(controller, "window.fixture.signOut()")
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.state.health.status == .ok, "nothing it posted arrived")
    }
}

extension WebPlayerController.Configuration.Page {
    var html: String? {
        if case let .html(html, _) = self { return html }
        return nil
    }
}
