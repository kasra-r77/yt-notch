import AppKit
import NotchUI
import PlayerCore
import SystemMedia
import SwiftUI
import WebPlayer

/// The app target only wires the modules together. Until the web player is wired in
/// (I4.1), the store runs on FakeEngine's canned tracks.
@main
struct YTNotchApp: App {
    @State private var store: PlayerStore

    init() {
        _store = State(initialValue: PlayerStore(engine: FakeEngine(runsClock: true)))
    }

    var body: some Scene {
        MenuBarExtra("YT Notch", systemImage: "music.note") {
            PlayerMenu(store: store)
        }
    }
}

/// A stand-in for the notch until NotchUI lands: what is playing, and the basic controls.
private struct PlayerMenu: View {
    let store: PlayerStore

    var body: some View {
        let state = store.state
        if let track = state.track {
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
        Divider()
        Text("YT Notch \(Self.version) · FakeEngine")
        Button("Quit YT Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
