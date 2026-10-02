import Foundation

/// What the app asks the player to do: the bridge contract's app-to-page commands.
/// The engine carries it out and reports the result as events; nothing assumes it worked.
public enum PlayerCommand: Equatable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek(to: TimeInterval)
    case setLiked(Bool)
    case playPlaylist(id: String)
    case playQueueItem(index: Int)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)
}

/// What the player reports: the bridge contract's page-to-app messages, plus the two
/// conditions the web player detects itself (`offline`, `bridgeBroken`).
public enum PlayerEvent: Equatable, Sendable {
    case ready(bridgeVersion: String, signedIn: Bool)
    case state(PlaybackSnapshot)
    case health(missing: Set<Feature>)
    case signedOut
    case playlists([PlaylistItem])
    case queue([QueueItem])
    /// A picture the page shows (the track's artwork, a queue thumbnail), handed over with
    /// its address, so the app downloads nothing itself.
    case artwork(url: URL, data: Data)
    /// Either mode is nil when the page can't read it; the store keeps its last value.
    case modes(shuffle: Bool?, repeatMode: RepeatMode?)
    case offline
    case bridgeBroken
}

/// Something that plays music: WebPlayer for the real site, FakeEngine for tests and demos.
@MainActor
public protocol PlayerEngine: AnyObject {
    /// Starts the engine. It reports every event through `onEvent`, in order.
    func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void)

    /// Carries out a command. Its result arrives as events.
    func send(_ command: PlayerCommand)
}
