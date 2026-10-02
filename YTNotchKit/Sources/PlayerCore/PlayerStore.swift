import Foundation

/// The only writer of player state. Sending a command never changes state: the UI shows only
/// what the player reports, so it cannot drift out of step with the real player.
@MainActor
public final class PlayerStore {
    public let state = PlayerState()

    private let engine: PlayerEngine
    private let playlistCache: PlaylistCache?
    private let now: () -> Date
    private var artworkOrder: [URL] = []

    static let artworkKept = 64

    /// - Parameter playlistCache: lets the Playlists view work before the page loads and while
    ///   the sidebar can't be read.
    public init(engine: PlayerEngine, playlistCache: PlaylistCache? = nil, now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.playlistCache = playlistCache
        self.now = now
        if let cached = playlistCache?.load(), !cached.isEmpty {
            state.playlists = cached
            state.playlistsAreRemembered = true
        }
        engine.start { [weak self] event in
            self?.apply(event)
        }
    }

    public func play() { send(.play, needs: .playPause) }

    public func pause() { send(.pause, needs: .playPause) }

    public func togglePlayPause() { send(.toggle, needs: .playPause) }

    public func next() { send(.next, needs: .next) }

    public func previous() { send(.previous, needs: .previous) }

    public func seek(to seconds: TimeInterval) {
        guard let duration = state.track?.duration else { return }
        send(.seek(to: min(max(0, seconds), duration)), needs: .seek)
    }

    public func setLiked(_ liked: Bool) { send(.setLiked(liked), needs: .like) }

    public func toggleLike() { setLiked(!state.liked) }

    /// Needs no feature: it goes by the playlist's web address, so it still works from a
    /// remembered list while the sidebar can't be read.
    public func playPlaylist(id: String) {
        guard state.playlists.contains(where: { $0.id == id }) else { return }
        send(.playPlaylist(id: id), needs: nil)
    }

    public func playQueueItem(index: Int) {
        guard state.queue.contains(where: { $0.index == index }) else { return }
        send(.playQueueItem(index: index), needs: .queue)
    }

    public func setShuffle(_ isOn: Bool) { send(.setShuffle(isOn), needs: .shuffle) }

    public func toggleShuffle() { setShuffle(!state.shuffle) }

    public func setRepeat(_ mode: RepeatMode) { send(.setRepeat(mode), needs: .repeatMode) }

    public func cycleRepeat() { setRepeat(state.repeatMode.next) }

    private func send(_ command: PlayerCommand, needs feature: Feature?) {
        if let feature {
            guard state.isAvailable(feature) else { return }
        } else {
            guard state.health.status == .ok else { return }
        }
        engine.send(command)
    }

    func apply(_ event: PlayerEvent) {
        switch event {
        case let .ready(bridgeVersion, signedIn):
            set(\.bridgeVersion, bridgeVersion)
            set(\.health, Health(status: signedIn ? .ok : .signedOut))
        case .signedOut:
            setStatus(.signedOut)
        case .offline:
            setStatus(.offline)
        case .bridgeBroken:
            set(\.health.status, .bridgeBroken)
        case let .health(missing):
            set(\.health.missing, missing)
        case let .state(snapshot):
            // State flowing again means the connection is back.
            if state.health.status == .offline { set(\.health.status, .ok) }
            set(\.track, snapshot.track)
            set(\.isPlaying, snapshot.isPlaying)
            set(\.position, snapshot.position)
            state.positionReportedAt = now()
            set(\.canNext, snapshot.canNext)
            set(\.canPrevious, snapshot.canPrevious)
            set(\.liked, snapshot.liked)
            set(\.playlistID, snapshot.playlistID)
        case let .playlists(items):
            set(\.playlists, items)
            if !items.isEmpty {
                set(\.playlistsAreRemembered, false)
                playlistCache?.save(items)
            }
        case let .queue(items):
            set(\.queue, items)
        case let .artwork(url, data):
            artworkOrder.removeAll { $0 == url }
            artworkOrder.append(url)
            var artwork = state.artwork
            artwork[url] = data
            set(\.artwork, trimmed(artwork))
        case let .modes(shuffle, repeatMode):
            if let shuffle { set(\.shuffle, shuffle) }
            if let repeatMode { set(\.repeatMode, repeatMode) }
        }
    }

    private func trimmed(_ artwork: [URL: Data]) -> [URL: Data] {
        var excess = artworkOrder.count - Self.artworkKept
        guard excess > 0 else { return artwork }
        let inUse = Set([state.track?.artworkURL].compactMap { $0 } + state.queue.compactMap(\.artworkURL))
        var artwork = artwork
        artworkOrder.removeAll { url in
            guard excess > 0, !inUse.contains(url) else { return false }
            excess -= 1
            artwork[url] = nil
            return true
        }
        return artwork
    }

    /// A broken bridge stays broken until the page reports ready again.
    private func setStatus(_ status: Health.Status) {
        guard state.health.status != .bridgeBroken else { return }
        set(\.health.status, status)
    }

    /// Writes only real changes, so views that read a value redraw only when it changes.
    private func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PlayerState, Value>, _ value: Value) {
        if state[keyPath: keyPath] != value {
            state[keyPath: keyPath] = value
        }
    }
}
