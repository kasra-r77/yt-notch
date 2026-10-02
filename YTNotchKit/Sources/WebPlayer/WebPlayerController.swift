import AppKit
import Network
import OSLog
import PlayerCore
import WebKit

/// The one web view for the app's lifetime, playing the site in a hidden window.
///
/// It injects `bridge.js`, turns the bridge's messages into events and commands into calls
/// into the page, and implements `PlayerEngine`. It never reads the page itself; that is
/// the bridge's job. The web view lives in a real window that stays ordered in but sits far
/// off-screen, which keeps playback going (spike report, S0.2).
///
/// Brought on screen, its window is the full window (`FullWindow`) for signing in and
/// browsing. Only the site's own pages talk to the app: the bridge also runs on the pages a
/// sign-in passes through, and what it posts there is dropped.
///
/// It also recovers, as the plan's failure table says: it retries a page that failed to
/// load, reloads after a web content crash without starting playback, re-reads everything
/// after a wake from sleep, and when playback goes quiet it re-injects the bridge, then
/// reloads once, then reports the bridge broken.
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
        public var timing = RecoveryTiming()
        /// Says when the network comes back, to retry at once. Nil leaves it to the timer.
        public var networkMonitor: (any NetworkMonitor)? = PathNetworkMonitor()
        /// Links the user follows stay in the window only on these hosts: the site and the
        /// pages its sign-in uses. Everything else opens in the default browser.
        public var windowHosts: Set<String> = [
            "music.youtube.com", "accounts.google.com", "accounts.youtube.com", "consent.youtube.com", "consent.google.com",
        ]
        /// Where the full window keeps its frame and whether the first run is over.
        public var defaults: UserDefaults = .standard
        /// Opens a link outside the window.
        public var openInBrowser: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

        public init() {}
    }

    /// How far recovery from a quiet bridge has got.
    enum RecoveryStage: Equatable {
        case none
        case reinjected
        case reloading
        case broken
    }

    public let webView: WKWebView
    /// What `start` loads, and what a reload falls back to. Tests switch it.
    var page: Configuration.Page
    let fullWindow: FullWindow
    private let timing: RecoveryTiming
    private let networkMonitor: (any NetworkMonitor)?
    private let windowHosts: Set<String>
    private let openInBrowser: @MainActor (URL) -> Void
    private var onEvent: (@MainActor (PlayerEvent) -> Void)?
    private let log = Logger(subsystem: "io.github.kasra-r77.ytnotch", category: "WebPlayer")

    // Recovery. The counters are for tests and the log.
    private(set) var recoveryStage = RecoveryStage.none
    private(set) var loadAttempts = 0
    private(set) var stalls = 0
    /// How many times a page of the site has said its bridge is ready: once per load.
    private(set) var readyReports = 0
    private var isOffline = false
    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var isPlaying = false
    private var lastHeardAt = Date()
    private var lastCheckAt = Date()
    private var stageStartedAt = Date()
    private var holdsAutoplayAfterReady = false
    private var holdsAutoplayUntil: Date?

    /// For tests: drops every message from the bridge, as if it had gone quiet.
    var ignoresBridgeMessages = false
    /// Messages dropped because they came from a page other than the site.
    private(set) var foreignMessages = 0

    /// Whether the site says the user is signed in; nil until it has said.
    private(set) var isSignedIn: Bool?
    /// The window asked for the site's sign-in before the page could say it was needed.
    private var signInPending = false

    public init(configuration: Configuration = Configuration()) {
        page = configuration.page
        timing = configuration.timing
        networkMonitor = configuration.networkMonitor

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

        windowHosts = configuration.windowHosts
        openInBrowser = configuration.openInBrowser
        fullWindow = FullWindow(webView: webView, defaults: configuration.defaults)

        super.init()

        webView.configuration.userContentController.add(WeakMessageHandler(self), name: Bridge.messageHandlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        fullWindow.reload = { [weak self] in self?.retry() }
    }

    // MARK: PlayerEngine

    public func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void) {
        self.onEvent = onEvent
        load(page)
        startWatchdog()
        networkMonitor?.start { [weak self] in self?.networkReturned() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    public func send(_ command: PlayerCommand) {
        switch command {
        case .play, .toggle, .playPlaylist, .playQueueItem:
            // The user asked for playback, so a crash reload no longer holds it back.
            holdsAutoplayAfterReady = false
            holdsAutoplayUntil = nil
        default:
            break
        }
        run(Bridge.arguments(for: command))
    }

    /// Runs a bridge command in the page and logs it if it fails.
    private func run(_ arguments: [String: Any]) {
        // The name only: values such as playlist IDs come from the user's account.
        let name = arguments["name"] as? String ?? "?"
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(Bridge.commandFunctionBody, arguments: arguments, contentWorld: .page)
                if let reply = result as? [String: Any], reply["ok"] as? Bool != true {
                    log.notice("command \(name, privacy: .public) failed: \(reply["error"] as? String ?? "?", privacy: .public)")
                }
            } catch {
                log.error("command \(name, privacy: .public) could not run: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: The window

    public var isWindowVisible: Bool { fullWindow.isVisible }

    /// Brings the full window on screen and the app forward. With `signIn`, it also opens
    /// the site's own sign-in, which goes on to Google's pages, as soon as the page says it
    /// is signed out.
    public func showWindow(signIn: Bool = false) {
        fullWindow.show()
        if signIn { requestSignIn() }
    }

    /// Moves the full window back off-screen. The page and the music go on.
    public func hideWindow() {
        fullWindow.hide()
    }

    /// On the very first launch, opens the full window on the site's sign-in with the
    /// first-run bar; later launches open nothing. Says whether it opened the window.
    @discardableResult
    public func openOnFirstLaunch() -> Bool {
        guard !fullWindow.hasFinishedFirstRun else { return false }
        fullWindow.beginFirstRun()
        fullWindow.firstRunBar.stage = isSignedIn == true ? .signedIn : .signIn
        showWindow(signIn: true)
        return true
    }

    private func requestSignIn() {
        switch isSignedIn {
        case false?: openSignIn()
        case nil: signInPending = true
        case true?: break
        }
    }

    private func openSignIn() {
        signInPending = false
        run(Bridge.signInArguments)
    }

    /// What the site says about signing in: the first-run bar follows it, and a sign-in the
    /// window asked for early goes ahead.
    private func signedIn(_ signedIn: Bool) {
        isSignedIn = signedIn
        fullWindow.firstRunBar.stage = signedIn ? .signedIn : .signIn
        if signedIn {
            signInPending = false
        } else if signInPending {
            openSignIn()
        }
    }

    // MARK: Messages

    /// The site's host: only its pages talk to the app.
    private var siteHost: String? {
        switch page {
        case let .url(url): url.host
        case let .html(_, baseURL): baseURL.host
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, !ignoresBridgeMessages else { return }
        guard message.frameInfo.securityOrigin.host == siteHost else {
            // A sign-in page, or anywhere else the window went: the bridge runs there too,
            // but nothing from those pages reaches the app.
            foreignMessages += 1
            return
        }
        guard let event = Bridge.event(from: message.body) else {
            log.notice("ignored a message the bridge contract does not know")
            return
        }
        observe(event)
        onEvent?(event)
    }

    /// What recovery learns from the bridge's messages.
    private func observe(_ event: PlayerEvent) {
        let now = Date()
        switch event {
        case let .ready(_, isSignedIn):
            log.notice("the bridge is ready")
            readyReports += 1
            lastHeardAt = now
            signedIn(isSignedIn)
            pageIsBack()
            if holdsAutoplayAfterReady {
                holdsAutoplayAfterReady = false
                holdsAutoplayUntil = now.addingTimeInterval(timing.noAutoplayWindow)
            }
        case let .state(snapshot):
            lastHeardAt = now
            isPlaying = snapshot.isPlaying
            pageIsBack()
            if snapshot.isPlaying, let until = holdsAutoplayUntil, now < until {
                holdsAutoplayUntil = nil
                log.notice("pausing playback the page started by itself after a crash reload")
                send(.pause)
            }
        case let .health(missing):
            if missing.isEmpty {
                log.notice("the bridge finds every part of the page")
            } else {
                // Notice, not error: parts are often missing while the page builds.
                log.notice("the bridge cannot find: \(missing.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)")
            }
        case .signedOut:
            log.notice("the page is signed out")
            signedIn(false)
        default:
            break
        }
    }

    /// The bridge is talking, so whatever recovery was under way worked.
    private func pageIsBack() {
        if isOffline { log.notice("the page loaded; back online") }
        isOffline = false
        retryAttempt = 0
        retryTask?.cancel()
        if recoveryStage != .none { log.notice("the bridge is reporting again") }
        recoveryStage = .none
    }

    // MARK: Recovery

    /// Loads the page again now: for a Retry button, and when the network returns.
    public func retry() {
        retryTask?.cancel()
        reloadCurrentPage()
    }

    @objc private func didWake(_ notification: Notification) {
        handleWake()
    }

    /// After a wake from sleep the page may have changed, so the bridge reports everything
    /// again. A page that had failed to load is retried instead.
    func handleWake() {
        log.notice("woke from sleep")
        lastHeardAt = Date()
        if isOffline {
            retry()
        } else {
            refreshBridge()
        }
    }

    private func networkReturned() {
        guard isOffline else { return }
        log.notice("the network is back; retrying now")
        retry()
    }

    private func load(_ page: Configuration.Page) {
        loadAttempts += 1
        lastHeardAt = Date()
        switch page {
        case let .url(url): webView.load(URLRequest(url: url))
        case let .html(html, baseURL): webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    /// Reloads the page where it is (a playlist, say), or loads the start page if none
    /// ever loaded. A test page is loaded again from its string, since its address is
    /// made up.
    private func reloadCurrentPage() {
        guard case .url = page, webView.url != nil else { return load(page) }
        loadAttempts += 1
        lastHeardAt = Date()
        webView.reload()
    }

    private func loadFailed(_ error: Error) {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else {
            log.error("page failed to load: \(error.localizedDescription, privacy: .public)")
            return
        }
        // A navigation replaced by another one is not a failure.
        guard error.code != NSURLErrorCancelled else { return }
        log.error("page failed to load, offline: \(error.localizedDescription, privacy: .public)")
        isOffline = true
        recoveryStage = .none
        onEvent?(.offline)
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = timing.retryDelay(attempt: retryAttempt)
        retryAttempt += 1
        log.notice("retry \(self.retryAttempt, privacy: .public) in \(delay, privacy: .public) s")
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isOffline else { return }
            self.reloadCurrentPage()
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let interval = min(1, timing.stallTimeout / 5)
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                self.checkForStall(now: Date())
            }
        }
    }

    /// No state for a while during playback: re-inject the bridge, then reload once, then
    /// report it broken. Nothing changes for the user until the last step.
    func checkForStall(now: Date) {
        defer { lastCheckAt = now }
        // A long gap between checks means the Mac slept (or the app hung); the page gets a
        // fresh start instead of counting the gap as silence.
        if now.timeIntervalSince(lastCheckAt) > timing.stallTimeout {
            lastHeardAt = now
            stageStartedAt = now
            return
        }
        guard !isOffline else { return }
        switch recoveryStage {
        case .none:
            guard isPlaying, now.timeIntervalSince(lastHeardAt) > timing.stallTimeout else { return }
            stalls += 1
            log.error("no state for \(self.timing.stallTimeout, privacy: .public) s while playing; re-injecting the bridge")
            recoveryStage = .reinjected
            stageStartedAt = now
            reinjectBridge()
        case .reinjected:
            guard now.timeIntervalSince(stageStartedAt) > timing.stallTimeout else { return }
            log.error("still no state after re-injecting; reloading the page once")
            recoveryStage = .reloading
            stageStartedAt = now
            reloadCurrentPage()
        case .reloading:
            guard now.timeIntervalSince(stageStartedAt) > timing.reloadTimeout else { return }
            log.fault("no state \(self.timing.reloadTimeout, privacy: .public) s after the reload; the bridge is broken")
            recoveryStage = .broken
            isPlaying = false
            onEvent?(.bridgeBroken)
        case .broken:
            break
        }
    }

    /// Runs the bridge script again (it returns at once if the bridge is still attached),
    /// then asks it to report everything.
    private func reinjectBridge() {
        Task {
            _ = try? await webView.callAsyncJavaScript(Bridge.script, contentWorld: .page)
            refreshBridge()
        }
    }

    private func refreshBridge() {
        Task {
            let refreshed = try? await webView.callAsyncJavaScript(Bridge.refreshFunctionBody, contentWorld: .page) as? Bool
            if refreshed != true { log.error("could not ask the bridge to report again") }
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

extension WebPlayerController: WKNavigationDelegate, WKUIDelegate {
    /// Links the user follows out of the site and its sign-in open in the default browser.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame ?? true,
              LinkPolicy.opensInBrowser(url, followedLink: navigationAction.navigationType == .linkActivated, allowedHosts: windowHosts)
        else { return .allow }
        openInBrowser(url)
        return .cancel
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A page on its way is not a stall.
        lastHeardAt = Date()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    /// The page crashed: load it again, but don't let it start playback nobody asked for.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("the web content process ended; reloading without auto-play")
        isPlaying = false
        recoveryStage = .none
        holdsAutoplayAfterReady = true
        reloadCurrentPage()
    }

    /// Pages that open a new window (sign-in links, target=_blank) load in this one instead,
    /// unless they lead out of the site, which goes to the browser.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }
        if LinkPolicy.opensInBrowser(url, followedLink: true, allowedHosts: windowHosts) {
            openInBrowser(url)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// How long recovery waits. The defaults are the plan's; tests shorten them.
public struct RecoveryTiming: Sendable {
    /// The waits before the retries after a failed load. The last one repeats for as long
    /// as the page can't load.
    public var retryDelays: [TimeInterval] = [2, 5, 15, 60]
    /// How long playback may go without a state message before recovery starts, and how
    /// long re-injecting gets before the page is reloaded.
    public var stallTimeout: TimeInterval = 5
    /// How long a reload gets to bring the bridge back before it counts as broken.
    public var reloadTimeout: TimeInterval = 20
    /// After a crash reload, playback that starts by itself this soon after the page is
    /// ready is paused.
    public var noAutoplayWindow: TimeInterval = 10

    public init() {}

    /// The wait before retry number `attempt`, counting from 0.
    public func retryDelay(attempt: Int) -> TimeInterval {
        guard let last = retryDelays.last else { return 60 }
        return attempt < retryDelays.count ? retryDelays[attempt] : last
    }
}

/// Says when the network comes back.
@MainActor
public protocol NetworkMonitor: AnyObject {
    func start(onReachable: @escaping @MainActor () -> Void)
}

/// Watches the network with the system's path monitor.
@MainActor
public final class PathNetworkMonitor: NetworkMonitor {
    private let monitor = NWPathMonitor()
    private var wasSatisfied: Bool?

    public init() {}

    deinit {
        monitor.cancel()
    }

    public func start(onReachable: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            MainActor.assumeIsolated {
                guard let self else { return }
                if isSatisfied, self.wasSatisfied == false { onReachable() }
                self.wasSatisfied = isSatisfied
            }
        }
        monitor.start(queue: .main)
    }
}

/// Holds the controller weakly, so the web view's content controller does not keep it alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var controller: WebPlayerController?

    init(_ controller: WebPlayerController) { self.controller = controller }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.receive(message)
    }
}
