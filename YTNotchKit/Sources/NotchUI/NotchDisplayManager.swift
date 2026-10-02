import AppKit
import Observation
import PlayerCore

/// Which displays show a notch (design spec, "Two or more displays").
public enum NotchDisplaySetting: Equatable, Sendable, Codable {
    case all
    case builtInOnly
    /// The displays picked by their `ScreenGeometry.key`, so a pick survives reconnecting
    /// the display and restarting the Mac.
    case picked(Set<String>)

    public func includes(_ screen: ScreenGeometry) -> Bool {
        switch self {
        case .all: true
        case .builtInOnly: screen.isBuiltIn
        case let .picked(keys): keys.contains(screen.key)
        }
    }

    static let defaultsKey = "notchDisplays"

    /// The saved setting; all displays when nothing is saved or it can't be read.
    public static func load(from defaults: UserDefaults) -> NotchDisplaySetting {
        guard let data = defaults.data(forKey: defaultsKey),
              let setting = try? JSONDecoder().decode(NotchDisplaySetting.self, from: data)
        else { return .all }
        return setting
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// Keeps exactly one notch on every chosen display.
///
/// It rebuilds the panels whenever displays are added, removed or rearranged and whenever
/// the setting changes: panels for displays that are gone or no longer chosen close, panels
/// that stay take their display's new sizes, and new displays get a panel that fades in. It
/// also hides a display's notch while another app is full screen there.
///
/// It knows nothing about the player, so display changes never reach the web view.
@MainActor
@Observable
public final class NotchDisplayManager {
    /// Saved as it changes.
    public var setting: NotchDisplaySetting {
        didSet {
            guard setting != oldValue else { return }
            if let defaults { setting.save(to: defaults) }
            rebuild()
        }
    }

    /// Every connected display, chosen or not, for the setting's picker.
    public private(set) var displays: [ScreenGeometry] = []

    @ObservationIgnored private(set) var panels: [String: NotchPanel] = [:]
    @ObservationIgnored private let readScreens: @MainActor () -> [ScreenGeometry]
    @ObservationIgnored private let readWindows: @MainActor () -> [FullScreenDetector.WindowInfo]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let pointer: PointerTracker
    @ObservationIgnored private let store: PlayerStore?
    /// What Open in the notch does: show the full window. The app sets it.
    @ObservationIgnored public var openFullWindow: (@MainActor () -> Void)?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var fullScreenRecheck: Task<Void, Never>?

    /// Reads the setting from `defaults`, shows a notch for `store` on each chosen display and
    /// starts following display, Space and app changes.
    public convenience init(store: PlayerStore?, defaults: UserDefaults = .standard) {
        self.init(
            setting: .load(from: defaults),
            defaults: defaults,
            store: store,
            screens: { NSScreen.screens.map(ScreenGeometry.init) },
            windows: FullScreenDetector.onScreenWindows
        )
        startObserving()
    }

    init(
        setting: NotchDisplaySetting,
        defaults: UserDefaults? = nil,
        store: PlayerStore? = nil,
        screens: @escaping @MainActor () -> [ScreenGeometry],
        windows: @escaping @MainActor () -> [FullScreenDetector.WindowInfo] = { [] },
        pointer: PointerTracker = .shared
    ) {
        self.setting = setting
        self.defaults = defaults
        self.store = store
        readScreens = screens
        readWindows = windows
        self.pointer = pointer
        rebuild()
    }

    /// The notch on each chosen display, in display order.
    public var notches: [NotchPanel] {
        displays.compactMap { panels[$0.key] }
    }

    /// Closes every notch and stops following the system.
    public func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        fullScreenRecheck?.cancel()
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }

    // MARK: Rebuilding

    /// Brings the panels in line with the connected displays and the setting.
    func rebuild() {
        displays = Self.uniqueKeys(readScreens())
        let chosen = displays.filter(setting.includes)
        let chosenKeys = Set(chosen.map(\.key))
        for (key, panel) in panels where !chosenKeys.contains(key) {
            panel.close()
            panels[key] = nil
        }
        for screen in chosen {
            if let panel = panels[screen.key] {
                panel.update(screen: screen)
            } else {
                panels[screen.key] = NotchPanel(screen: screen, store: store, openFullWindow: { [weak self] in self?.openFullWindow?() }, pointer: pointer)
            }
        }
        refreshFullScreen()
    }

    /// Two identical monitors without serial numbers can share a key; the second gets its
    /// display ID added so each still gets its own notch.
    static func uniqueKeys(_ screens: [ScreenGeometry]) -> [ScreenGeometry] {
        var seen = Set<String>()
        return screens.map { screen in
            var screen = screen
            if !seen.insert(screen.key).inserted { screen.key += "#\(screen.displayID)" }
            return screen
        }
    }

    /// One look at the window list for every display.
    func refreshFullScreen() {
        guard !panels.isEmpty else { return }
        let windows = readWindows()
        let primaryHeight = displays.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for panel in panels.values {
            let bounds = panel.screen.globalBounds(primaryHeight: primaryHeight)
            panel.setFullScreen(FullScreenDetector.isFullScreen(display: bounds, windows: windows, ownPID: ownPID))
        }
    }

    // MARK: Following the system

    private func startObserving() {
        let app = NotificationCenter.default
        observe(app, NSApplication.didChangeScreenParametersNotification) { $0.rebuild() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.spaceOrAppChanged() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.spaceOrAppChanged() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (NotchDisplayManager) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, observer))
    }

    private func spaceOrAppChanged() {
        refreshFullScreen()
        // The window list can lag a Space change, so look again once it has settled.
        fullScreenRecheck?.cancel()
        fullScreenRecheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.refreshFullScreen()
        }
    }
}
