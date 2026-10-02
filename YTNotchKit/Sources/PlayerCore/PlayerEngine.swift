import Foundation

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

/// The bridge's page-to-app messages, plus `offline` and `bridgeBroken`, which the web player
/// detects itself.
public enum PlayerEvent: Equatable, Sendable {
    case ready(bridgeVersion: String, signedIn: Bool)
    case state(PlaybackSnapshot)
    case health(missing: Set<Feature>)
    case signedOut
    case playlists([PlaylistItem])
    case queue([QueueItem])
    /// A picture the page already loaded, handed over so the app downloads nothing itself.
    case artwork(url: URL, data: Data)
    /// Either mode is nil when the page can't read it; the store keeps its last value.
    case modes(shuffle: Bool?, repeatMode: RepeatMode?)
    case offline
    case bridgeBroken
}

@MainActor
public protocol PlayerEngine: AnyObject {
    /// Reports every event through `onEvent`, in order.
    func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void)

    /// The result arrives only as events; nothing may assume the command worked.
    func send(_ command: PlayerCommand)
}
