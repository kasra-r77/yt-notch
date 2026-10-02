import AppKit
import NotchUI
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
    let notches: NotchDisplayManager

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

        Divider()
        NotchDisplaysMenu(notches: notches)
        DebugMenu(notches: notches)

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

/// The display setting until the Settings window exists: all displays, the built-in one, or
/// a picked list. Each display is checked while it shows a notch; changing one turns the
/// setting into a picked list, starting from the displays that show one now.
private struct NotchDisplaysMenu: View {
    let notches: NotchDisplayManager

    var body: some View {
        Menu("Show Notch On") {
            Toggle("All Displays", isOn: Binding(
                get: { notches.setting == .all },
                set: { if $0 { notches.setting = .all } }
            ))
            Toggle("Built-in Display Only", isOn: Binding(
                get: { notches.setting == .builtInOnly },
                set: { if $0 { notches.setting = .builtInOnly } }
            ))
            Divider()
            ForEach(notches.displays, id: \.key) { display in
                Toggle(display.name, isOn: Binding(
                    get: { notches.setting.includes(display) },
                    set: { pick(display, $0) }
                ))
            }
        }
    }

    private func pick(_ display: ScreenGeometry, _ isOn: Bool) {
        var keys: Set<String>
        if case let .picked(current) = notches.setting {
            keys = current
        } else {
            keys = Set(notches.displays.filter(notches.setting.includes).map(\.key))
        }
        if isOn { keys.insert(display.key) } else { keys.remove(display.key) }
        notches.setting = .picked(keys)
    }
}

/// Forces each notch state without breaking anything (N2.6): the messages, and a page that
/// only partly works. Normal shows what the player really reports.
private struct DebugMenu: View {
    let notches: NotchDisplayManager

    var body: some View {
        Menu("Debug") {
            Picker("Notch State", selection: Binding(get: { Choice(notches.forcedState) }, set: { notches.forcedState = $0.forced })) {
                ForEach(Choice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.inline)
        }
    }

    enum Choice: CaseIterable, Hashable {
        case normal, signedOut, offline, bridgeBroken, loading, partlyWorking

        init(_ forced: NotchForcedState?) {
            switch forced {
            case .message(.signedOut): self = .signedOut
            case .message(.offline): self = .offline
            case .message(.bridgeBroken): self = .bridgeBroken
            case .message(.loading): self = .loading
            case .missing: self = .partlyWorking
            case nil: self = .normal
            }
        }

        var forced: NotchForcedState? {
            switch self {
            case .normal: nil
            case .signedOut: .message(.signedOut)
            case .offline: .message(.offline)
            case .bridgeBroken: .message(.bridgeBroken)
            case .loading: .message(.loading)
            case .partlyWorking: .missing([.like, .seek, .shuffle, .repeatMode])
            }
        }

        var title: String {
            switch self {
            case .normal: "Normal"
            case .signedOut: "Signed Out"
            case .offline: "No Connection"
            case .bridgeBroken: "Player Needs an Update"
            case .loading: "Loading"
            case .partlyWorking: "Partly Working"
            }
        }
    }
}
