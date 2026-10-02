import AppKit
import Foundation
import PlayerCore
import WebKit
@testable import WebPlayer

/// A real web view with bridge.js injected at document start, as the app does it, on the
/// fixture page instead of the site.
@MainActor
final class BridgeHarness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var messages: [[String: Any]] = []
    /// The message count when the test last acted on the page. `next` looks at everything
    /// from here, so a reply that arrives before the test starts waiting is not missed.
    private var actionMark = 0

    var events: [PlayerEvent] { messages.compactMap(Bridge.event(from:)) }

    override init() {
        // A web view in a test process needs the shared application, as in an app.
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // As in the app: no timer throttling for a page that isn't on screen.
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.userContentController.addUserScript(
            WKUserScript(source: Bridge.script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        webView.configuration.userContentController.add(self, name: Bridge.messageHandlerName)
        webView.navigationDelegate = self
    }

    /// Loads the fixture page with options (see fake-player.html) and waits for `ready`.
    /// `path` is the address's path and query, as the site's player page has them.
    func load(_ options: String..., path: String = "/") async throws {
        guard let url = Bundle.module.url(forResource: "fake-player", withExtension: "html", subdirectory: "Fixtures") else {
            throw HarnessError.missingFixture
        }
        let html = try String(contentsOf: url, encoding: .utf8)
        let base = URL(string: "https://fixture.ytnotch.test" + path + "#" + options.joined(separator: ","))!
        loadedPath = path
        webView.loadHTMLString(html, baseURL: base)
        try await wait("ready") { $0.contains { $0["type"] as? String == "ready" } }
    }

    /// Waits until `condition` holds. The wait gives the main actor back, so WebKit can
    /// deliver its callbacks.
    func wait(_ what: String, timeout: TimeInterval = 5, until condition: ([[String: Any]]) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(messages) {
            if Date() > deadline { throw HarnessError.timedOut(what) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Waits for an event, since the test last acted on the page, that matches.
    @discardableResult
    func next<T>(_ what: String, timeout: TimeInterval = 5, _ match: (PlayerEvent) -> T?) async throws -> T {
        let start = actionMark
        var found: T?
        try await wait(what, timeout: timeout) { messages in
            found = messages.dropFirst(start).compactMap(Bridge.event(from:)).lazy.compactMap(match).first
            return found != nil
        }
        return found!
    }

    /// Waits until any message so far, newest first, matches. For what the bridge reports
    /// together with `ready`.
    @discardableResult
    func any<T>(_ what: String, timeout: TimeInterval = 5, _ match: (PlayerEvent) -> T?) async throws -> T {
        var found: T?
        try await wait(what, timeout: timeout) { messages in
            found = messages.compactMap(Bridge.event(from:)).reversed().lazy.compactMap(match).first
            return found != nil
        }
        return found!
    }

    var latestSnapshot: PlaybackSnapshot? { events.lazy.reversed().compactMap(\.snapshot).first }

    @discardableResult
    func send(_ command: PlayerCommand) async throws -> [String: Any] {
        actionMark = messages.count
        let result = try await webView.callAsyncJavaScript(
            Bridge.commandFunctionBody,
            arguments: Bridge.arguments(for: command),
            contentWorld: .page
        )
        return result as? [String: Any] ?? [:]
    }

    @discardableResult
    func js(_ source: String) async throws -> Any? {
        actionMark = messages.count
        return try await webView.callAsyncJavaScript(source, contentWorld: .page)
    }

    /// Errors the page caught: uncaught exceptions and unhandled rejections.
    func pageErrors() async throws -> [String] {
        try await js("return window.fixture.errors") as? [String] ?? []
    }

    /// Addresses the page tried to leave for. Only the fixture itself may load; anything
    /// else (starting a playlist by its address) is recorded and stopped, so tests never
    /// leave the fixture.
    private(set) var blockedNavigations: [URL] = []
    private var loadedPath = "/"

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.host == "fixture.ytnotch.test", Self.pathAndQuery(url) == loadedPath { return .allow }
        blockedNavigations.append(url)
        return .cancel
    }

    private static func pathAndQuery(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return url.query.map { path + "?" + $0 } ?? path
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { messages.append(body) }
    }

    enum HarnessError: Error, CustomStringConvertible {
        case timedOut(String)
        case missingFixture
        var description: String {
            switch self {
            case let .timedOut(what): "Timed out waiting for \(what)"
            case .missingFixture: "fake-player.html is missing from the test bundle"
            }
        }
    }
}

extension PlayerEvent {
    var snapshot: PlaybackSnapshot? {
        if case let .state(snapshot) = self { return snapshot }
        return nil
    }

    var missing: Set<Feature>? {
        if case let .health(missing) = self { return missing }
        return nil
    }

    var playlists: [PlaylistItem]? {
        if case let .playlists(items) = self { return items }
        return nil
    }

    var queue: [QueueItem]? {
        if case let .queue(items) = self { return items }
        return nil
    }

    var modes: (shuffle: Bool?, repeatMode: RepeatMode?)? {
        if case let .modes(shuffle, repeatMode) = self { return (shuffle, repeatMode) }
        return nil
    }
}
