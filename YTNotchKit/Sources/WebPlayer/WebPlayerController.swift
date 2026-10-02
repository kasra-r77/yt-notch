import AppKit
import OSLog
import PlayerCore
import WebKit

/// The one web view for the app's lifetime, playing the site in a hidden window.
///
/// It injects `bridge.js`, turns the bridge's messages into events and commands into calls
/// into the page, and implements `PlayerEngine`. It never reads the page itself; that is
/// the bridge's job. The web view lives in a real window that stays ordered in but sits far
/// off-screen, which keeps playback going (spike report, S0.2).
@MainActor
public final class WebPlayerController: NSObject, PlayerEngine {
    @MainActor
    public struct Configuration {
        /// What to load: the site, or a page for tests.
        public enum Page {
            case url(URL)
            case html(String, baseURL: URL)
        }

        public var page: Page = .url(URL(string: "https://music.youtube.com/")!)
        /// The persistent store keeps the login across relaunches.
        public var dataStore: WKWebsiteDataStore = .default()
        public var userAgent: String? = WebPlayerController.safariUserAgent()

        public init() {}
    }

    public let webView: WKWebView
    private let window: HostWindow
    private let page: Configuration.Page
    private var onEvent: (@MainActor (PlayerEvent) -> Void)?
    private var hiddenFrame: NSRect
    private let log = Logger(subsystem: "io.github.kasra-r77.ytnotch", category: "WebPlayer")

    public init(configuration: Configuration = Configuration()) {
        page = configuration.page

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = configuration.dataStore
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        // Keep the page running at full speed while its window is hidden.
        webConfiguration.preferences.inactiveSchedulingPolicy = .none
        webConfiguration.userContentController.addUserScript(
            WKUserScript(source: Bridge.script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760), configuration: webConfiguration)
        webView.customUserAgent = configuration.userAgent
        webView.isInspectable = true

        hiddenFrame = NSRect(x: -20_000, y: -20_000, width: 1100, height: 760)
        window = HostWindow(
            contentRect: hiddenFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YouTube Music"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.isExcludedFromWindowsMenu = true
        window.contentView = webView

        super.init()

        webView.configuration.userContentController.add(WeakMessageHandler(self), name: Bridge.messageHandlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.delegate = self
        // Ordered in but off-screen: invisible, yet the page keeps playing. AppKit puts a new
        // window on screen whatever frame it is given, so move it off afterwards.
        window.setFrame(hiddenFrame, display: false)
        window.orderFrontRegardless()
    }

    // MARK: PlayerEngine

    public func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void) {
        self.onEvent = onEvent
        switch page {
        case let .url(url): webView.load(URLRequest(url: url))
        case let .html(html, baseURL): webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    public func send(_ command: PlayerCommand) {
        let arguments = Bridge.arguments(for: command)
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(Bridge.commandFunctionBody, arguments: arguments, contentWorld: .page)
                if let reply = result as? [String: Any], reply["ok"] as? Bool != true {
                    log.notice("command \(String(describing: command), privacy: .public) failed: \(reply["error"] as? String ?? "?", privacy: .public)")
                }
            } catch {
                log.error("command \(String(describing: command), privacy: .public) could not run: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: The window

    public var isWindowVisible: Bool { window.frame.intersects(NSScreen.screens.map(\.frame).reduce(.null) { $0.union($1) }) }

    /// Brings the web view on screen, for signing in and browsing. Until the full window
    /// (W3.3) exists, this is the only way to see the page.
    public func showWindow() {
        guard !isWindowVisible else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.center()
        window.collectionBehavior = []
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Moves the web view back off-screen. Playback continues.
    public func hideWindow() {
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.setFrame(hiddenFrame, display: false)
        window.orderFrontRegardless()
    }

    // MARK: Messages

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if let event = Bridge.event(from: message.body) {
            onEvent?(event)
        } else {
            log.notice("ignored a message the bridge contract does not know")
        }
    }

    // MARK: User agent

    /// Safari's user agent, built from the Safari installed on this Mac so it stays current.
    public nonisolated static func safariUserAgent() -> String {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "26.0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }
}

extension WebPlayerController: WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("page failed to load: \(error.localizedDescription, privacy: .public)")
        if (error as NSError).domain == NSURLErrorDomain { onEvent?(.offline) }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("web content process terminated")
    }

    /// Pages that open a new window (sign-in links, target=_blank) load in this one instead.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    /// Closing the window hides it; the web view and the music keep going.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }
}

/// A window macOS never pulls back on screen, so it can sit far off-screen while ordered in.
final class HostWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Holds the controller weakly, so the web view's content controller does not keep it alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var controller: WebPlayerController?

    init(_ controller: WebPlayerController) { self.controller = controller }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.receive(message)
    }
}
