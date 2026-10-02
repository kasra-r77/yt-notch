import Foundation
@testable import PlayerCore

/// Records the commands the store sends and lets a test push events.
@MainActor
final class SpyEngine: PlayerEngine {
    private(set) var sent: [PlayerCommand] = []
    private var onEvent: (@MainActor (PlayerEvent) -> Void)?

    func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void) { self.onEvent = onEvent }

    func send(_ command: PlayerCommand) { sent.append(command) }

    func emit(_ events: PlayerEvent...) { events.forEach { onEvent?($0) } }
}

/// A clock a test can move by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
}

enum Fixture {
    static let track = Track(id: "t1", title: "Title", artist: "Artist", album: "Album", duration: 200)
    static let otherTrack = Track(id: "t2", title: "Other", artist: "Someone", duration: 100)

    static let playlists = [
        PlaylistItem(id: "LM", title: "Liked music"),
        PlaylistItem(id: "PL1", title: "Mix"),
    ]

    static let queue = [
        QueueItem(index: 0, title: "Title", artist: "Artist", isCurrent: true),
        QueueItem(index: 1, title: "Other", artist: "Someone", isCurrent: false),
    ]

    static let playing = PlaybackSnapshot(
        track: track, position: 40, isPlaying: true, canNext: true, canPrevious: true, liked: false
    )

    /// A store whose engine has reported a signed-in page with everything available.
    @MainActor
    static func readyStore(clock: TestClock = TestClock()) -> (PlayerStore, SpyEngine) {
        let engine = SpyEngine()
        let store = PlayerStore(engine: engine, now: { clock.now })
        engine.emit(
            .ready(bridgeVersion: "1", signedIn: true),
            .playlists(playlists),
            .queue(queue),
            .modes(shuffle: false, repeatMode: .off),
            .state(playing)
        )
        return (store, engine)
    }
}

/// Lets an observation callback, which must be Sendable, report that it ran.
final class Flag: @unchecked Sendable {
    var isSet = false
}
