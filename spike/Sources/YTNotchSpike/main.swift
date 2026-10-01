import AppKit
import WebKit

// Phase 0 spike. Throwaway code.
// S0.1: a visible web view on music.youtube.com with a current Safari user agent and the
//       default persistent data store.
// S0.2: the same web view in a hidden host window that stays ordered in but sits far
//       off-screen, with a playback monitor that logs whether audio keeps moving.

enum Spike {
    static let startURL = URL(string: "https://music.youtube.com")!

    /// Cookies whose presence means the YouTube Music session is signed in.
    static let signInCookies = ["LOGIN_INFO", "SAPISID", "__Secure-3PSID"]

    /// Safari's user agent, built from the Safari installed on this Mac so it stays current.
    static var safariUserAgent: String {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "26.0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }

    /// How WebKit schedules the page while the view is not visible. `--policy suspend|throttle|none`;
    /// `none` (no throttling) unless asked otherwise.
    static var schedulingPolicy: WKPreferences.InactiveSchedulingPolicy {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--policy"), i + 1 < args.count else { return .none }
        switch args[i + 1] {
        case "suspend": return .suspend
        case "throttle": return .throttle
        default: return .none
        }
    }

    static func name(of policy: WKPreferences.InactiveSchedulingPolicy) -> String {
        switch policy {
        case .suspend: return "suspend"
        case .throttle: return "throttle"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }

    static let logsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
    static let logFile = logsFolder.appendingPathComponent("YTNotchSpike.log")
    static let playbackFile = logsFolder.appendingPathComponent("YTNotchSpike-playback.csv")

    /// Logs to the system log and appends to ~/Library/Logs/YTNotchSpike.log.
    static func log(_ message: String) {
        NSLog("[spike] %@", message)
        append("\(ISO8601DateFormatter().string(from: Date())) \(message)\n", to: logFile)
    }

    static func append(_ text: String, to file: URL) {
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: file)
        }
    }

    /// Reports which sign-in cookies exist in the default data store. Never reads cookie values.
    @MainActor
    static func signInReport() async -> (signedIn: Bool, text: String) {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        var lines: [String] = []
        for name in signInCookies {
            let domains = Set(cookies.filter { $0.name == name }.map(\.domain)).sorted()
            lines.append("\(name): \(domains.isEmpty ? "missing" : domains.joined(separator: ", "))")
        }
        let onYouTube = { (name: String) in
            cookies.contains { $0.name == name && $0.domain.hasSuffix("youtube.com") }
        }
        let signedIn = onYouTube("LOGIN_INFO") && onYouTube("SAPISID")
        let text = (["Signed in: \(signedIn ? "yes" : "no")"] + lines
            + ["\(cookies.count) cookies in the default data store (values are never shown)"])
            .joined(separator: "\n")
        return (signedIn, text)
    }
}

/// A window the system never pulls back on screen, so it can sit far off-screen while
/// staying ordered in.
final class HostWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Samples the page every 5 seconds and logs whether playback keeps pace with the clock.
/// Logs counts and times only; track titles are compared in memory and never written.
final class PlaybackMonitor {
    struct Sample: Decodable {
        let hasVideo: Bool
        let t: Double
        let paused: Bool
        let track: String
        let hidden: Bool
        let waiting: Int
        let stalled: Int
        let pauses: Int
    }

    /// Counts media events on the page from the moment it starts.
    static let statsScript = """
    (() => {
      const s = window.__spikeStats = { waiting: 0, stalled: 0, pause: 0, playing: 0, ended: 0 };
      for (const name of Object.keys(s)) {
        document.addEventListener(name, (e) => { if (e.target instanceof HTMLMediaElement) s[name]++; }, true);
      }
    })();
    """

    static let sampleScript = """
    (() => {
      const v = document.querySelector('video');
      const m = navigator.mediaSession && navigator.mediaSession.metadata;
      const s = window.__spikeStats || {};
      return JSON.stringify({
        hasVideo: !!v, t: v ? v.currentTime : -1, paused: v ? v.paused : true,
        track: m ? (m.title + '\\u0001' + m.artist) : '', hidden: document.hidden,
        waiting: s.waiting || 0, stalled: s.stalled || 0, pauses: s.pause || 0
      });
    })()
    """

    private weak var webView: WKWebView?
    private let policy: String
    private var timer: Timer?
    private var last: (sample: Sample, at: Date)?
    private var trackIndex = 0
    private let startedAt = Date()

    var isHidden = false
    var isDisplayAsleep = false
    var userToggledAt = Date.distantPast

    private(set) var hiddenSeconds = 0.0
    private(set) var playingSeconds = 0.0
    private(set) var playedSeconds = 0.0
    private(set) var stalls = 0
    private(set) var unexpectedPauses = 0
    private(set) var trackChanges = 0
    private(set) var longestGap = 0.0
    private(set) var displaySleeps = 0
    private(set) var spaceChanges = 0
    private var firstEvents: Sample?

    init(webView: WKWebView, policy: String) {
        self.webView = webView
        self.policy = policy
    }

    func start() {
        Spike.append("time,elapsed,window,policy,appActive,displayAsleep,pageHidden,hasVideo,paused,position,wallDelta,playDelta,track,waiting,stalled,pauseEvents,note\n", to: Spike.playbackFile)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.5
        Spike.log("playback monitor started, policy \(policy), writing \(Spike.playbackFile.path)")
    }

    func note(_ event: String) {
        if event == "display-sleep" { displaySleeps += 1 }
        if event == "space-change" { spaceChanges += 1 }
        Spike.append("\(ISO8601DateFormatter().string(from: Date())),\(Int(Date().timeIntervalSince(startedAt))),,,,,,,,,,,,,,,\(event)\n", to: Spike.playbackFile)
        Spike.log(event)
    }

    private func tick() {
        webView?.evaluateJavaScript(Self.sampleScript) { [weak self] result, _ in
            guard let self, let json = result as? String,
                  let sample = try? JSONDecoder().decode(Sample.self, from: Data(json.utf8)) else { return }
            self.record(sample, at: Date())
        }
    }

    private func record(_ sample: Sample, at now: Date) {
        if firstEvents == nil { firstEvents = sample }
        var wallDelta = 0.0
        var playDelta = 0.0
        var note = ""
        if let (previous, previousAt) = last {
            wallDelta = now.timeIntervalSince(previousAt)
            longestGap = max(longestGap, wallDelta)
            if isHidden { hiddenSeconds += wallDelta }
            let sameTrack = previous.track == sample.track
            if !sameTrack, !sample.track.isEmpty {
                trackIndex += 1
                trackChanges += 1
                note = "track-change"
            } else if !previous.paused, !sample.paused {
                playDelta = sample.t - previous.t
                playingSeconds += wallDelta
                playedSeconds += max(0, playDelta)
                if playDelta < wallDelta * 0.8 {
                    stalls += 1
                    note = "stall"
                }
            }
            if !previous.paused, sample.paused {
                if now.timeIntervalSince(userToggledAt) < 10 {
                    note = "user-pause"
                } else {
                    unexpectedPauses += 1
                    note = "unexpected-pause"
                }
            }
        }
        last = (sample, now)
        let fields: [String] = [
            ISO8601DateFormatter().string(from: now),
            String(Int(now.timeIntervalSince(startedAt))),
            isHidden ? "hidden" : "visible",
            policy,
            NSApp.isActive ? "1" : "0",
            isDisplayAsleep ? "1" : "0",
            sample.hidden ? "1" : "0",
            sample.hasVideo ? "1" : "0",
            sample.paused ? "1" : "0",
            String(format: "%.1f", sample.t),
            String(format: "%.1f", wallDelta),
            String(format: "%.1f", playDelta),
            String(trackIndex),
            String(sample.waiting),
            String(sample.stalled),
            String(sample.pauses),
            note,
        ]
        Spike.append(fields.joined(separator: ",") + "\n", to: Spike.playbackFile)
        if !note.isEmpty { Spike.log("playback: \(note)") }
    }

    var summary: String {
        let minutes = { (s: Double) in String(format: "%.1f min", s / 60) }
        let pace = playingSeconds > 0 ? String(format: "%.1f%%", playedSeconds / playingSeconds * 100) : "n/a"
        let events = { (key: KeyPath<Sample, Int>) -> Int in
            guard let first = self.firstEvents, let latest = self.last?.sample else { return 0 }
            return latest[keyPath: key] - first[keyPath: key]
        }
        return [
            "Monitored: \(minutes(Date().timeIntervalSince(startedAt))), hidden for \(minutes(hiddenSeconds))",
            "Inactive scheduling policy: \(policy)",
            "Playing: \(minutes(playingSeconds)) of wall time, audio advanced \(minutes(playedSeconds)) (\(pace))",
            "Stalls (audio under 80% of the clock in a 5 s window): \(stalls)",
            "Unexpected pauses: \(unexpectedPauses)",
            "Media events since start: waiting \(events(\.waiting)), stalled \(events(\.stalled))",
            "Track changes: \(trackChanges)",
            "Display sleeps: \(displaySleeps), Space changes (full screen): \(spaceChanges)",
            String(format: "Longest gap between samples: %.1f s", longestGap),
        ].joined(separator: "\n")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSMenuDelegate {
    private var window: HostWindow!
    private var webView: WKWebView!
    private var monitor: PlaybackMonitor?
    private var statusItem: NSStatusItem?
    private var visibleFrame: NSRect?
    private var isCheckingOnly = false

    private var isPlayerHidden: Bool { visibleFrame != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--check-sign-in`: print the cookie report and quit, without showing a window.
        // WebKit only loads saved cookies once a web view uses the store, so load a blank
        // page in a hidden web view first and report when it finishes.
        if CommandLine.arguments.contains("--check-sign-in") {
            NSApp.setActivationPolicy(.prohibited)
            isCheckingOnly = true
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.loadHTMLString("", baseURL: URL(string: "https://music.youtube.com"))
            return
        }

        buildMenu()
        buildStatusItem()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.inactiveSchedulingPolicy = Spike.schedulingPolicy
        configuration.userContentController.addUserScript(
            WKUserScript(source: PlaybackMonitor.statsScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Spike.safariUserAgent
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        window = HostWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YT Notch spike"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let policy = Spike.name(of: Spike.schedulingPolicy)
        Spike.log("launched, policy \(policy), user agent: \(Spike.safariUserAgent)")
        webView.load(URLRequest(url: Spike.startURL))

        let monitor = PlaybackMonitor(webView: webView, policy: policy)
        monitor.start()
        self.monitor = monitor

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor?.isDisplayAsleep = true
            self?.monitor?.note("display-sleep")
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor?.isDisplayAsleep = false
            self?.monitor?.note("display-wake")
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor?.note("space-change")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor { Spike.log("summary | " + monitor.summary.replacingOccurrences(of: "\n", with: " | ")) }
    }

    // MARK: Hiding the player

    /// Moves the host window far off-screen (still ordered in) and turns the app into a
    /// menu bar app, as the real app will be.
    private func hidePlayer() {
        guard !isPlayerHidden else { return }
        visibleFrame = window.frame
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        NSApp.setActivationPolicy(.accessory)
        monitor?.isHidden = true
        monitor?.note("hidden")
    }

    private func showPlayer() {
        guard let frame = visibleFrame else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        visibleFrame = nil
        NSApp.setActivationPolicy(.regular)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor?.isHidden = false
        monitor?.note("shown")
    }

    @objc private func togglePlayerWindow(_ sender: Any?) {
        isPlayerHidden ? showPlayer() : hidePlayer()
    }

    @objc private func playPause(_ sender: Any?) {
        monitor?.userToggledAt = Date()
        webView.evaluateJavaScript("(() => { const v = document.querySelector('video'); if (!v) return 'none'; if (v.paused) { v.play(); return 'play'; } v.pause(); return 'pause'; })()") { result, _ in
            Spike.log("user play/pause: \(result as? String ?? "?")")
        }
    }

    @objc private func showSummary(_ sender: Any?) {
        guard let monitor else { return }
        Spike.log("summary | " + monitor.summary.replacingOccurrences(of: "\n", with: " | "))
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Playback summary"
        alert.informativeText = monitor.summary
        alert.runModal()
    }

    // MARK: Menus

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YT Notch spike")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusItem?.menu else { return }
        menu.removeAllItems()
        menu.addItem(withTitle: isPlayerHidden ? "Show Player Window" : "Hide Player Window", action: #selector(togglePlayerWindow(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Play or Pause", action: #selector(playPause(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Playback Summary…", action: #selector(showSummary(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit YT Notch spike", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit YT Notch spike", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenu: appMenu, title: "YT Notch spike")

        // Without an Edit menu, paste does not work in Google's sign-in fields.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenu: editMenu, title: "Edit")

        let spikeMenu = NSMenu(title: "Spike")
        spikeMenu.addItem(withTitle: "Check Sign-in", action: #selector(checkSignIn(_:)), keyEquivalent: "i").target = self
        spikeMenu.addItem(withTitle: "Reload", action: #selector(reload(_:)), keyEquivalent: "r").target = self
        spikeMenu.addItem(withTitle: "Go to YouTube Music", action: #selector(goHome(_:)), keyEquivalent: "h").target = self
        spikeMenu.addItem(.separator())
        spikeMenu.addItem(withTitle: "Hide Player Window", action: #selector(togglePlayerWindow(_:)), keyEquivalent: "H").target = self
        spikeMenu.addItem(withTitle: "Playback Summary…", action: #selector(showSummary(_:)), keyEquivalent: "").target = self
        spikeMenu.addItem(.separator())
        spikeMenu.addItem(withTitle: "Delete Website Data…", action: #selector(deleteWebsiteData(_:)), keyEquivalent: "").target = self
        mainMenu.addItem(submenu: spikeMenu, title: "Spike")

        NSApp.mainMenu = mainMenu
    }

    @objc private func checkSignIn(_ sender: Any?) {
        Task { @MainActor in
            let report = await Spike.signInReport()
            Spike.log(report.text.replacingOccurrences(of: "\n", with: " | "))
            let alert = NSAlert()
            alert.messageText = report.signedIn ? "Signed in" : "Not signed in"
            alert.informativeText = report.text
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    @objc private func reload(_ sender: Any?) { webView.reload() }

    @objc private func goHome(_ sender: Any?) { webView.load(URLRequest(url: Spike.startURL)) }

    @objc private func deleteWebsiteData(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Delete this spike's website data?"
        alert.informativeText = "Signs the spike out by removing its cookies and storage. Safari and other apps are not affected."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let store = WKWebsiteDataStore.default()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                Spike.log("website data deleted")
                self.goHome(nil)
            }
        }
    }

    // MARK: Web view

    // Pages that open a new window (target=_blank, window.open) load in this one instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isCheckingOnly {
            Task { @MainActor in
                let report = await Spike.signInReport()
                print(report.text)
                exit(report.signedIn ? 0 : 1)
            }
            return
        }
        let host = webView.url?.host ?? "?"
        window.title = "YT Notch spike · \(host)"
        Spike.log("loaded \(host)\(webView.url?.path ?? "")")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Spike.log("navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Spike.log("load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        monitor?.note("web-content-terminated")
        webView.reload()
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
