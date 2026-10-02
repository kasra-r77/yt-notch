import AppKit
import WebKit

/// The full window (design spec D7): the one web view, brought on screen.
///
/// Hidden, the window stays ordered in but far off-screen, which keeps the page playing
/// (spike report, S0.2). Closing it only hides it.
@MainActor
final class FullWindow: NSObject {
    static let size = NSSize(width: 1100, height: 760)
    static let minimumSize = NSSize(width: 800, height: 600)
    static let frameKey = "fullWindowFrame"
    static let firstRunDoneKey = "firstRunDone"

    let window: HostWindow
    let webView: WKWebView
    let firstRunBar = FirstRunBar()
    /// The player's own reload, not the web view's: it knows its test pages.
    var reload: () -> Void = {}

    private let defaults: UserDefaults
    private let hiddenFrame = NSRect(x: -20_000, y: -20_000, width: FullWindow.size.width, height: FullWindow.size.height)
    private let barHeight: NSLayoutConstraint
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var observations: [NSKeyValueObservation] = []

    init(webView: WKWebView, defaults: UserDefaults) {
        self.webView = webView
        self.defaults = defaults
        window = HostWindow(
            contentRect: hiddenFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        barHeight = firstRunBar.heightAnchor.constraint(equalToConstant: 0)
        super.init()

        window.title = "YouTube Music"
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = Self.hiddenBehavior
        window.contentView = content()
        window.delegate = self
        window.keyCommands = [
            "w": { [weak self] in self?.hide() },
            "[": { [weak self] in self?.webView.goBack() },
            "]": { [weak self] in self?.webView.goForward() },
            "r": { [weak self] in self?.reload() },
        ]

        let toolbar = NSToolbar(identifier: "YTNotchFullWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // Set on the content, after the toolbar: AppKit adds the title bar's height to a
        // minimum set on the frame.
        let titleBar = window.frame.height - window.contentLayoutRect.height
        window.contentMinSize = NSSize(width: Self.minimumSize.width, height: Self.minimumSize.height - titleBar)

        observations = [
            webView.observe(\.canGoBack, options: [.initial]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateItems() }
            },
            webView.observe(\.canGoForward, options: [.initial]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateItems() }
            },
        ]

        firstRunBar.isHidden = true
        firstRunBar.close = { [weak self] in self?.hide() }

        // AppKit puts a new window on screen whatever its frame, so move it off afterwards.
        window.setFrame(hiddenFrame, display: false)
        window.orderFrontRegardless()
    }

    private func content() -> NSView {
        let container = NSView()
        for view in [firstRunBar, webView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            firstRunBar.topAnchor.constraint(equalTo: container.topAnchor),
            firstRunBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            firstRunBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            barHeight,
            webView.topAnchor.constraint(equalTo: firstRunBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: Showing and hiding

    private static let hiddenBehavior: NSWindow.CollectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]

    var isVisible: Bool {
        window.frame.intersects(NSScreen.screens.map(\.frame).reduce(.null) { $0.union($1) })
    }

    /// Also activates the app, so the page can take typing.
    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !isVisible {
            window.collectionBehavior = [.fullScreenNone]
            window.setFrame(savedFrame() ?? Self.defaultFrame(on: Self.pointerScreen), display: true)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the first-run window ends the first run for good.
    func hide() {
        if isVisible { saveFrame() }
        if !firstRunBar.isHidden { finishFirstRun() }
        window.collectionBehavior = Self.hiddenBehavior
        window.setFrame(hiddenFrame, display: false)
        window.orderFrontRegardless()
    }

    static var pointerScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    }

    static func defaultFrame(on screen: NSScreen?) -> NSRect {
        let area = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        return NSRect(x: (area.midX - width / 2).rounded(), y: (area.midY - height / 2).rounded(), width: width, height: height)
    }

    private func savedFrame() -> NSRect? {
        guard let text = defaults.string(forKey: Self.frameKey) else { return nil }
        let frame = NSRectFromString(text)
        guard frame.width >= Self.minimumSize.width, frame.height >= Self.minimumSize.height else { return nil }
        let onScreen = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width * overlap.height >= frame.width * frame.height / 2
        }
        return onScreen ? frame : nil
    }

    private func saveFrame() {
        defaults.set(NSStringFromRect(window.frame), forKey: Self.frameKey)
    }

    // MARK: First run

    var hasFinishedFirstRun: Bool { defaults.bool(forKey: Self.firstRunDoneKey) }

    var showsFirstRunBar: Bool { !firstRunBar.isHidden }

    func beginFirstRun() {
        firstRunBar.isHidden = false
        barHeight.constant = FirstRunBar.height
    }

    private func finishFirstRun() {
        firstRunBar.isHidden = true
        barHeight.constant = 0
        defaults.set(true, forKey: Self.firstRunDoneKey)
    }

    // MARK: Back, Forward, Reload

    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let reloadItem = NSToolbarItem.Identifier("reload")

    func item(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? { items[identifier] }

    private func updateItems() {
        items[Self.back]?.isEnabled = webView.canGoBack
        items[Self.forward]?.isEnabled = webView.canGoForward
    }

    @objc func goBack() { webView.goBack() }
    @objc func goForward() { webView.goForward() }
    @objc func reloadPage() { reload() }
}

extension FullWindow: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.back, Self.forward, Self.reloadItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let (symbol, label, action): (String, String, Selector) = switch identifier {
        case Self.back: ("chevron.left", "Back", #selector(goBack))
        case Self.forward: ("chevron.right", "Forward", #selector(goForward))
        default: ("arrow.clockwise", "Reload", #selector(reloadPage))
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.isNavigational = true
        item.isBordered = false
        item.autovalidates = false
        item.target = self
        item.action = action
        items[identifier] = item
        updateItems()
        return item
    }
}

extension FullWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        if isVisible, !window.isMiniaturized { saveFrame() }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if isVisible { saveFrame() }
    }
}

final class FirstRunBar: NSView {
    enum Stage: Equatable {
        case signIn
        case signedIn
    }

    static let height: CGFloat = 40
    static let signInText = "Sign in to YouTube Music to start. You'll stay signed in on this Mac."
    static let signedInText = "You're signed in. Music you play now shows in the notch."

    var stage = Stage.signIn {
        didSet { update() }
    }

    var close: () -> Void = {}

    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    let closeButton = NSButton(title: "Close Window", target: nil, action: nil)

    private static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255, alpha: 1)
    }

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        closeButton.bezelStyle = .push
        closeButton.controlSize = .small
        closeButton.keyEquivalent = "\r"
        closeButton.target = self
        closeButton.action = #selector(closeWindow)

        let row = NSStackView(views: [icon, label, NSView(), closeButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        dirtyRect.fill()
    }

    private func update() {
        switch stage {
        case .signIn:
            icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            label.stringValue = Self.signInText
            closeButton.isHidden = true
        case .signedIn:
            icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemGreen
            label.stringValue = Self.signedInText
            closeButton.isHidden = false
        }
    }

    @objc private func closeWindow() { close() }
}

/// Which links leave the window for the default browser (D7, "Links out").
enum LinkPolicy {
    /// Redirects and form posts stay in the window, so a sign-in that passes through other
    /// addresses (a work account's own sign-in) works.
    static func opensInBrowser(_ url: URL, followedLink: Bool, allowedHosts: Set<String>) -> Bool {
        guard followedLink, let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https":
            guard let host = url.host?.lowercased() else { return false }
            return !allowedHosts.contains(host)
        case "about", "data", "blob", "javascript":
            return false
        default:
            // mailto:, tel: and the like are for other apps.
            return true
        }
    }
}

/// A window macOS never pulls back on screen, so it can sit far off-screen while ordered in.
/// The app has no menu bar of its own, so the window handles its shortcuts and editing keys.
final class HostWindow: NSWindow {
    var keyCommands: [String: () -> Void] = [:]

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == .command, let command = keyCommands[key] {
            command()
            return true
        }
        if super.performKeyEquivalent(with: event) { return true }
        let editing: Selector? = switch (key, modifiers) {
        case ("x", .command): #selector(NSText.cut(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("a", .command): #selector(NSText.selectAll(_:))
        case ("z", .command): Selector(("undo:"))
        case ("z", [.command, .shift]): Selector(("redo:"))
        default: nil
        }
        guard let editing else { return false }
        return NSApp.sendAction(editing, to: nil, from: self)
    }
}
