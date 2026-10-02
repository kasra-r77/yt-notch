import AppKit
import NotchUI
import PlayerCore
import SystemMedia
import SwiftUI
import WebPlayer

/// To run on FakeEngine's canned tracks instead of the web player, launch with `-engine fake`
/// or `defaults write io.github.kasra-r77.ytnotch engine fake`.
@main
struct YTNotchApp: App {
    @State private var store: PlayerStore
    private let notches: NotchDisplayManager
    /// `true` opens on the site's sign-in. Nil on FakeEngine.
    private let openWindow: (@MainActor (Bool) -> Void)?
    private let retry: @MainActor () -> Void
    private let engineName: String
    private let updater = Updater()

    init() {
        let store: PlayerStore
        let notches: NotchDisplayManager
        if UserDefaults.standard.string(forKey: "engine") == "fake" {
            let engine = FakeEngine(runsClock: true)
            store = PlayerStore(engine: engine)
            notches = NotchDisplayManager(store: store)
            openWindow = nil
            retry = { engine.simulateReload() }
            engineName = "FakeEngine"
        } else {
            let player = WebPlayerController()
            store = PlayerStore(engine: player, playlistCache: UserDefaultsPlaylistCache())
            notches = NotchDisplayManager(store: store)
            openWindow = { player.showWindow(signIn: $0) }
            retry = { player.retry() }
            engineName = "web player"
            notches.openFullWindow = { player.showWindow(signIn: store.state.health.status == .signedOut) }
            // In a Task, so it runs once the app has finished launching.
            Task { @MainActor in player.openOnFirstLaunch() }
        }
        notches.retry = retry
        _store = State(initialValue: store)
        self.notches = notches
    }

    var body: some Scene {
        MenuBarExtra {
            AppMenu(store: store, notches: notches, openWindow: openWindow, retry: retry, engineName: engineName, updater: updater)
        } label: {
            // D6's template icon, with its dot while something needs the user.
            Image(store.state.health.status.needsAttention ? "MenuBarIconAttention" : "MenuBarIcon")
                .accessibilityLabel("YT Notch")
        }
        Settings {
            SettingsView(notches: notches, updater: updater)
        }
    }
}
