import AppKit
import PlayerCore
import SwiftUI
import WebPlayer

/// A stand-in for the notch until NotchUI lands: what is playing, and every control the
/// store offers, so the live check (`docs/live-check.md`) can be run from here. Each
/// control is disabled when the store says its feature isn't available, and every value
/// shown is what the player reported.
struct PlayerMenu: View {
    let store: PlayerStore
    let webPlayer: WebPlayerController?

    var body: some View {
        let state = store.state
        if let status = Self.statusText(state.health.status) {
            Text(status)
        } else if let track = state.track {
            Text(track.title)
            Text(track.artist)
            Text(Self.timeText(state) + (state.liked ? " · Liked" : ""))
        } else {
            Text("Nothing playing")
        }
        if !state.health.missing.isEmpty {
            Text("Can't read: " + state.health.missing.map(\.rawValue).sorted().joined(separator: ", "))
        }

        Divider()
        Button(state.isPlaying ? "Pause" : "Play") { store.togglePlayPause() }
            .disabled(!state.isAvailable(.playPause))
        Button("Previous") { store.previous() }
            .disabled(!state.isAvailable(.previous))
        Button("Next") { store.next() }
            .disabled(!state.isAvailable(.next))
        Menu("Seek") {
            Button("Back 10 Seconds") { store.seek(to: state.elapsed(at: .now) - 10) }
            Button("Forward 30 Seconds") { store.seek(to: state.elapsed(at: .now) + 30) }
            Button("To 1:00") { store.seek(to: 60) }
        }
        .disabled(!state.isAvailable(.seek))
        Button(state.liked ? "Unlike" : "Like") { store.toggleLike() }
            .disabled(!state.isAvailable(.like))

        Divider()
        Toggle("Shuffle", isOn: Binding(get: { state.shuffle }, set: { store.setShuffle($0) }))
            .disabled(!state.isAvailable(.shuffle))
        Picker("Repeat", selection: Binding(get: { state.repeatMode }, set: { store.setRepeat($0) })) {
            ForEach(RepeatMode.allCases, id: \.self) { mode in
                Text(mode.rawValue.capitalized).tag(mode)
            }
        }
        .disabled(!state.isAvailable(.repeatMode))
        Menu("Playlists") {
            ForEach(state.playlists) { playlist in
                Button(playlist.title) { store.playPlaylist(id: playlist.id) }
            }
        }
        .disabled(!state.showsPlaylistsView || state.health.status != .ok)
        Picker("Up Next", selection: Binding(
            get: { state.queue.first(where: \.isCurrent)?.index ?? -1 },
            set: { store.playQueueItem(index: $0) }
        )) {
            ForEach(state.queue) { item in
                Text("\(item.title) – \(item.artist)").tag(item.index)
            }
        }
        .disabled(!state.showsQueueView || !state.isAvailable(.queue))

        if let webPlayer {
            Divider()
            // Until the full window (W3.3) exists, this is how to sign in and browse.
            Button("Show Web Player") { webPlayer.showWindow() }
        }
        Divider()
        Text("YT Notch \(Self.version) · \(webPlayer == nil ? "FakeEngine" : "web player, bridge \(state.bridgeVersion ?? "–")")")
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

    /// "1:23 / 3:45", as of when the menu opened.
    static func timeText(_ state: PlayerState) -> String {
        let elapsed = minutesAndSeconds(state.elapsed(at: .now))
        guard let duration = state.track?.duration else { return elapsed }
        return "\(elapsed) / \(minutesAndSeconds(duration))"
    }

    static func minutesAndSeconds(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
