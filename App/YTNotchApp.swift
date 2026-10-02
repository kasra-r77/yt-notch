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

    init() {
        if UserDefaults.standard.string(forKey: "engine") == "web" {
            let player = WebPlayerController()
            webPlayer = player
            _store = State(initialValue: PlayerStore(engine: player))
        } else {
            webPlayer = nil
            _store = State(initialValue: PlayerStore(engine: FakeEngine(runsClock: true)))
        }
    }

    var body: some Scene {
        MenuBarExtra("YT Notch", systemImage: "music.note") {
            PlayerMenu(store: store, webPlayer: webPlayer)
        }
    }
}

/// A stand-in for the notch until NotchUI lands: what is playing, and the basic controls.
private struct PlayerMenu: View {
    let store: PlayerStore
    let webPlayer: WebPlayerController?

    var body: some View {
        let state = store.state
        if let status = Self.statusText(state.health.status) {
            Text(status)
        } else if let track = state.track {
            Text(track.title)
            Text(track.artist)
        } else {
            Text("Nothing playing")
        }
        Divider()
        Button(state.isPlaying ? "Pause" : "Play") { store.togglePlayPause() }
            .disabled(!state.isAvailable(.playPause))
        Button("Previous") { store.previous() }
            .disabled(!state.isAvailable(.previous))
        Button("Next") { store.next() }
            .disabled(!state.isAvailable(.next))
        if let webPlayer {
            Divider()
            // Until the full window (W3.3) exists, this is how to sign in and browse.
            Button("Show Web Player") { webPlayer.showWindow() }
        }
        Divider()
        Text("YT Notch \(Self.version) · \(webPlayer == nil ? "FakeEngine" : "web player")")
        Button("Quit YT Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    static func statusText(_ status: Health.Status) -> String? {
        switch status {
        case .ok: nil
        case .starting: "Loading YouTube Music…"
        case .signedOut: "Signed out: show the web player to sign in"
        case .offline: "No connection"
        case .bridgeBroken: "Player needs an update"
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
