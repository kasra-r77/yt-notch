import AppKit
import NotchUI
import PlayerCore
import SystemMedia
import SwiftUI
import WebPlayer

/// The app target only wires the modules together.
///
/// The store runs on FakeEngine's canned tracks unless the `engine` setting is `web`. Until
/// I4.1 wires the web player in for good, that is a debug switch:
/// `defaults write io.github.kasra-r77.ytnotch engine web`, or launch with `-engine web`.
@main
struct YTNotchApp: App {
    @State private var store: PlayerStore
    private let webPlayer: WebPlayerController?
    /// A notch on every display the "Show Notch On" setting chooses.
    private let notches: NotchDisplayManager

    init() {
        let store: PlayerStore
        let notches: NotchDisplayManager
        if UserDefaults.standard.string(forKey: "engine") == "web" {
            let player = WebPlayerController()
            webPlayer = player
            store = PlayerStore(engine: player, playlistCache: UserDefaultsPlaylistCache())
            notches = NotchDisplayManager(store: store)
            // Open, and Sign In while signed out, which goes to the site's sign-in.
            notches.openFullWindow = { player.showWindow(signIn: store.state.health.status == .signedOut) }
            notches.retry = { player.retry() }
            // Once the app has finished launching: the first launch opens on sign-in.
            Task { @MainActor in player.openOnFirstLaunch() }
        } else {
            let engine = FakeEngine(runsClock: true)
            webPlayer = nil
            store = PlayerStore(engine: engine)
            notches = NotchDisplayManager(store: store)
            notches.retry = { engine.simulateReload() }
        }
        _store = State(initialValue: store)
        self.notches = notches
    }

    var body: some Scene {
        MenuBarExtra("YT Notch", systemImage: "music.note") {
            PlayerMenu(store: store, webPlayer: webPlayer, notches: notches)
        }
    }
}
