import Foundation

/// The only writer of player state.
///
/// The store turns user intents into commands for the engine and the engine's events into
/// state. It never changes state when it sends a command: the UI shows only what the player
/// reports, so the notch cannot drift out of step with the real player.
///
/// It also decides health. Commands are dropped while health isn't OK, while the feature
/// they need is missing, or when they can't apply (no next track, an unknown queue index).
@MainActor
public final class PlayerStore {
    public let state = PlayerState()

    private let engine: PlayerEngine
    private let now: () -> Date

    public init(engine: PlayerEngine, now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.now = now
        engine.start { [weak self] event in
            self?.apply(event)
        }
    }

    // MARK: Intents

    public func play() { send(.play, needs: .playPause) }

    public func pause() { send(.pause, needs: .playPause) }

    public func togglePlayPause() { send(.toggle, needs: .playPause) }

    public func next() { send(.next, needs: .next) }

    public func previous() { send(.previous, needs: .previous) }

    /// Seeks within the current track; the position is clamped to the track.
    public func seek(to seconds: TimeInterval) {
        guard let duration = state.track?.duration else { return }
        send(.seek(to: min(max(0, seconds), duration)), needs: .seek)
    }

    public func setLiked(_ liked: Bool) { send(.setLiked(liked), needs: .like) }

    public func toggleLike() { setLiked(!state.liked) }

    /// Starts a playlist from the list. Starting one goes by its web address, so it still
    /// works from a remembered list while the sidebar can't be read.
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

    /// Moves repeat to the next mode, as the repeat button does: off, all, one, off.
    public func cycleRepeat() { setRepeat(state.repeatMode.next) }

    private func send(_ command: PlayerCommand, needs feature: Feature?) {
        if let feature {
            guard state.isAvailable(feature) else { return }
        } else {
            guard state.health.status == .ok else { return }
        }
        engine.send(command)
    }

    // MARK: Events

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
        case let .playlists(items):
            set(\.playlists, items)
        case let .queue(items):
            set(\.queue, items)
        case let .modes(shuffle, repeatMode):
            set(\.shuffle, shuffle)
            set(\.repeatMode, repeatMode)
        }
    }

    /// Changes the status, except that a broken bridge stays broken until the page
    /// reports ready again.
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
