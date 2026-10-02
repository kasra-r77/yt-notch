import AppKit
import NotchUI
import PlayerCore
import SystemMedia
import SwiftUI
import WebPlayer

/// The app target only wires the modules together.
///
/// The store runs on the web player: the one web view, on YouTube Music. For development and
/// demos it can run on FakeEngine's canned tracks instead, with the `engine` setting:
/// `defaults write io.github.kasra-r77.ytnotch engine fake`, or launch with `-engine fake`.
@main
struct YTNotchApp: App {
    @State private var store: PlayerStore
    /// A notch on every display the "Show the notch on" setting chooses.
    private let notches: NotchDisplayManager
    /// Shows the full window, on the site's sign-in with `true`. Nil on FakeEngine.
    private let openWindow: (@MainActor (Bool) -> Void)?
    private let retry: @MainActor () -> Void
    private let engineName: String
    /// The update check, once the update keys exist (R5.2).
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
            // Open, and Sign In while signed out, which goes to the site's sign-in.
            notches.openFullWindow = { player.showWindow(signIn: store.state.health.status == .signedOut) }
            // Once the app has finished launching: the first launch opens on sign-in.
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
