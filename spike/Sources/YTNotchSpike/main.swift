import AppKit
import WebKit

// S0.1 spike: a visible web view on music.youtube.com with a current Safari user agent
// and the default persistent data store. Throwaway code.

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

    static let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/YTNotchSpike.log")

    /// Logs to the system log and appends to ~/Library/Logs/YTNotchSpike.log.
    static func log(_ message: String) {
        NSLog("[spike] %@", message)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logFile)
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var isCheckingOnly = false

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

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Spike.safariUserAgent
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YT Notch spike"
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("SpikeWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Spike.log("launched, user agent: \(Spike.safariUserAgent)")
        webView.load(URLRequest(url: Spike.startURL))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Menu

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
        Spike.log("web content process terminated, reloading")
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
