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
        if UserDefaults.standard.string(forKey: "engine") == "web" {
            let player = WebPlayerController()
            webPlayer = player
            store = PlayerStore(engine: player, playlistCache: UserDefaultsPlaylistCache())
        } else {
            webPlayer = nil
            store = PlayerStore(engine: FakeEngine(runsClock: true))
        }
        _store = State(initialValue: store)
        notches = NotchDisplayManager(store: store)
        if let webPlayer {
            notches.openFullWindow = { webPlayer.showWindow() }
        }
    }

    var body: some Scene {
        MenuBarExtra("YT Notch", systemImage: "music.note") {
            PlayerMenu(store: store, webPlayer: webPlayer, notches: notches)
        }
    }
}
