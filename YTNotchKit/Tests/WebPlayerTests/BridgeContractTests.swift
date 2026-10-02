import Foundation
import PlayerCore
import Testing
@testable import WebPlayer

/// The Swift side of the contract, without a web view: decoding messages and encoding commands.
struct BridgeContractTests {
    @Test func scriptShipsInTheBundle() {
        #expect(Bridge.script.contains("BRIDGE_VERSION = '1'"))
        #expect(Bridge.script.contains("ytNotch"))
    }

    @Test func ready() {
        #expect(Bridge.event(from: ["type": "ready", "bridgeVersion": "1", "signedIn": true]) == .ready(bridgeVersion: "1", signedIn: true))
        #expect(Bridge.event(from: ["type": "ready"]) == nil)
    }

    @Test func state() {
        let body: [String: Any] = [
            "type": "state", "trackId": "m1", "title": "T", "artist": "A", "album": NSNull(),
            "artworkURL": "https://x.test/a.jpg", "duration": 180.5, "position": 12.25,
            "isPlaying": true, "canNext": true, "canPrevious": false, "liked": true,
        ]
        let expected = PlaybackSnapshot(
            track: Track(id: "m1", title: "T", artist: "A", album: nil, artworkURL: URL(string: "https://x.test/a.jpg"), duration: 180.5),
            position: 12.25, isPlaying: true, canNext: true, canPrevious: false, liked: true
        )
        #expect(Bridge.event(from: body) == .state(expected))
    }

    @Test func stateWithoutATrack() {
        let body: [String: Any] = ["type": "state", "trackId": NSNull(), "title": NSNull(), "position": 0, "isPlaying": false]
        #expect(Bridge.event(from: body) == .state(PlaybackSnapshot(track: nil)))
    }

    @Test func healthKeepsOnlyKnownFeatures() {
        let body: [String: Any] = ["type": "health", "ok": false, "missing": ["like", "repeat", "metadata"]]
        #expect(Bridge.event(from: body) == .health(missing: [.like, .repeatMode]))
    }

    @Test func signedOut() {
        #expect(Bridge.event(from: ["type": "signedOut"]) == .signedOut)
    }

    @Test func playlists() {
        let body: [String: Any] = ["type": "playlists", "items": [
            ["id": "LM", "title": "Liked music", "thumbnailURL": NSNull()],
            ["id": "PL1", "title": "Mix", "thumbnailURL": "https://x.test/t.jpg"],
            ["title": "no id"],
        ]]
        #expect(Bridge.event(from: body) == .playlists([
            PlaylistItem(id: "LM", title: "Liked music"),
            PlaylistItem(id: "PL1", title: "Mix", thumbnailURL: URL(string: "https://x.test/t.jpg")),
        ]))
    }

    @Test func queue() {
        let body: [String: Any] = ["type": "queue", "items": [
            ["index": 0, "title": "A", "artist": "X", "isCurrent": true],
            ["index": 1, "title": "B", "artist": "Y", "isCurrent": false],
        ]]
        #expect(Bridge.event(from: body) == .queue([
            QueueItem(index: 0, title: "A", artist: "X", isCurrent: true),
            QueueItem(index: 1, title: "B", artist: "Y", isCurrent: false),
        ]))
    }

    @Test func modes() {
        #expect(Bridge.event(from: ["type": "modes", "shuffle": true, "repeat": "one"]) == .modes(shuffle: true, repeatMode: .one))
        #expect(Bridge.event(from: ["type": "modes", "shuffle": true, "repeat": "sometimes"]) == nil)
    }

    @Test func unknownOrMalformedMessages() {
        #expect(Bridge.event(from: ["type": "dance"]) == nil)
        #expect(Bridge.event(from: "not a message") == nil)
        #expect(Bridge.event(from: ["no": "type"]) == nil)
    }

    @Test func commandArguments() {
        func pair(_ command: PlayerCommand) -> String {
            let arguments = Bridge.arguments(for: command)
            return "\(arguments["name"]!) \(arguments["value"] is NSNull ? "-" : "\(arguments["value"]!)")"
        }
        #expect(pair(.play) == "play -")
        #expect(pair(.pause) == "pause -")
        #expect(pair(.toggle) == "toggle -")
        #expect(pair(.next) == "next -")
        #expect(pair(.previous) == "previous -")
        #expect(pair(.seek(to: 42.5)) == "seek 42.5")
        #expect(pair(.setLiked(true)) == "setLiked true")
        #expect(pair(.playPlaylist(id: "PL1")) == "playPlaylist PL1")
        #expect(pair(.playQueueItem(index: 3)) == "playQueueItem 3")
        #expect(pair(.setShuffle(false)) == "setShuffle false")
        #expect(pair(.setRepeat(.all)) == "setRepeat all")
    }
}
