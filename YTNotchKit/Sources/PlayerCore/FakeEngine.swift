import Foundation

/// A player with canned tracks, playlists and a queue, for tests and for running the whole
/// UI without the web player.
///
/// It behaves the way the spikes measured the site: commands change its own model and it
/// reports the result as events. Previous restarts a track after 3 seconds; shuffle keeps
/// the current track, and turning it off restores the original order. The `simulate…`
/// methods force the failure states for tests and the debug menu.
@MainActor
public final class FakeEngine: PlayerEngine {
    public struct Playlist: Sendable {
        public var item: PlaylistItem
        public var tracks: [Track]

        public init(item: PlaylistItem, tracks: [Track]) {
            self.item = item
            self.tracks = tracks
        }
    }

    public static let bridgeVersion = "fake-1"

    /// Every command received, in order.
    public private(set) var receivedCommands: [PlayerCommand] = []

    private let playlists: [Playlist]
    private var onEvent: (@MainActor (PlayerEvent) -> Void)?
    private var signedIn: Bool
    private let runsClock: Bool
    private var clock: Timer?

    private var originalQueue: [Track] = []
    private var queue: [Track] = []
    private var currentIndex = 0
    private var isPlaying = false
    private var position: TimeInterval = 0
    private var likedIDs: Set<String> = []
    private var shuffle = false
    private var repeatMode: RepeatMode = .off

    /// - Parameter runsClock: when true, playback time moves on by itself every half
    ///   second while playing, so a demo shows real progress. Tests use `advance(by:)`.
    public init(playlists: [Playlist] = FakeEngine.sample, signedIn: Bool = true, runsClock: Bool = false) {
        self.playlists = playlists
        self.signedIn = signedIn
        self.runsClock = runsClock
        if let first = playlists.first { load(first) }
    }

    public func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void) {
        self.onEvent = onEvent
        reportPageLoad()
    }

    public func send(_ command: PlayerCommand) {
        receivedCommands.append(command)
        switch command {
        case .play:
            isPlaying = currentTrack != nil
        case .pause:
            isPlaying = false
        case .toggle:
            isPlaying = !isPlaying && currentTrack != nil
        case .next:
            skipForward()
        case .previous:
            skipBack()
        case let .seek(seconds):
            position = min(max(0, seconds), currentTrack?.duration ?? 0)
        case let .setLiked(liked):
            guard let id = currentTrack?.id else { break }
            if liked { likedIDs.insert(id) } else { likedIDs.remove(id) }
        case let .playPlaylist(id):
            guard let playlist = playlists.first(where: { $0.item.id == id }) else { break }
            load(playlist)
            isPlaying = true
            report(.queue(queueItems))
            report(.modes(shuffle: shuffle, repeatMode: repeatMode))
        case let .playQueueItem(index):
            guard queue.indices.contains(index) else { break }
            currentIndex = index
            position = 0
            isPlaying = true
            report(.queue(queueItems))
        case let .setShuffle(isOn):
            setShuffle(isOn)
            report(.queue(queueItems))
            report(.modes(shuffle: shuffle, repeatMode: repeatMode))
        case let .setRepeat(mode):
            repeatMode = mode
            report(.modes(shuffle: shuffle, repeatMode: repeatMode))
        }
        report(.state(snapshot))
        updateClock()
    }

    /// Moves playback time on, as the real player does while playing. At the end of a track
    /// it repeats it, goes to the next one, or stops at the end of the queue.
    public func advance(by seconds: TimeInterval) {
        guard isPlaying, let track = currentTrack else { return }
        position += seconds
        if let duration = track.duration, position >= duration {
            switch repeatMode {
            case .one:
                position = 0
            case .all:
                currentIndex = (currentIndex + 1) % queue.count
                position = 0
                report(.queue(queueItems))
            case .off:
                if currentIndex + 1 < queue.count {
                    currentIndex += 1
                    position = 0
                    report(.queue(queueItems))
                } else {
                    position = duration
                    isPlaying = false
                }
            }
        }
        report(.state(snapshot))
        updateClock()
    }

    // MARK: Failures, for tests and the debug menu

    /// The page shows its sign-in prompt.
    public func simulateSignedOut() {
        signedIn = false
        report(.signedOut)
    }

    public func simulateOffline() { report(.offline) }

    public func simulateBridgeBroken() { report(.bridgeBroken) }

    /// The bridge can't find these parts of the page.
    public func simulateMissing(_ features: Set<Feature>) { report(.health(missing: features)) }

    /// A page reload: the bridge attaches again and reports everything from scratch.
    public func simulateReload(signedIn: Bool = true) {
        self.signedIn = signedIn
        reportPageLoad()
    }

    // MARK: Model

    private var currentTrack: Track? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }

    private var snapshot: PlaybackSnapshot {
        PlaybackSnapshot(
            track: currentTrack,
            position: position,
            isPlaying: isPlaying,
            canNext: currentIndex + 1 < queue.count || (repeatMode == .all && !queue.isEmpty),
            canPrevious: currentTrack != nil,
            liked: currentTrack.map { likedIDs.contains($0.id) } ?? false
        )
    }

    private var queueItems: [QueueItem] {
        queue.enumerated().map { index, track in
            QueueItem(index: index, title: track.title, artist: track.artist, isCurrent: index == currentIndex)
        }
    }

    private func load(_ playlist: Playlist) {
        originalQueue = playlist.tracks
        queue = shuffle ? shuffled(playlist.tracks, keepingFirst: playlist.tracks.first) : playlist.tracks
        currentIndex = 0
        position = 0
    }

    private func skipForward() {
        if currentIndex + 1 < queue.count {
            currentIndex += 1
        } else if repeatMode == .all, !queue.isEmpty {
            currentIndex = 0
        } else {
            return
        }
        position = 0
        report(.queue(queueItems))
    }

    /// Like the site: after 3 seconds previous restarts the track; before that it goes back.
    private func skipBack() {
        if position <= 3, currentIndex > 0 {
            currentIndex -= 1
            report(.queue(queueItems))
        } else if position <= 3, repeatMode == .all, queue.count > 1 {
            currentIndex = queue.count - 1
            report(.queue(queueItems))
        }
        position = 0
    }

    private func setShuffle(_ isOn: Bool) {
        guard isOn != shuffle else { return }
        shuffle = isOn
        let current = currentTrack
        queue = isOn ? shuffled(originalQueue, keepingFirst: current) : originalQueue
        currentIndex = current.flatMap { track in queue.firstIndex(of: track) } ?? 0
    }

    /// The current track first, then the rest in a fixed scrambled order, so tests are
    /// repeatable.
    private func shuffled(_ tracks: [Track], keepingFirst first: Track?) -> [Track] {
        var rest = tracks.filter { $0 != first }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in stride(from: rest.count - 1, to: 0, by: -1) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            rest.swapAt(i, Int(seed >> 33) % (i + 1))
        }
        return (first.map { [$0] } ?? []) + rest
    }

    // MARK: Reporting

    private func reportPageLoad() {
        report(.ready(bridgeVersion: Self.bridgeVersion, signedIn: signedIn))
        guard signedIn else {
            report(.signedOut)
            return
        }
        report(.health(missing: []))
        report(.playlists(playlists.map(\.item)))
        report(.queue(queueItems))
        report(.modes(shuffle: shuffle, repeatMode: repeatMode))
        report(.state(snapshot))
    }

    private func report(_ event: PlayerEvent) {
        onEvent?(event)
    }

    private func updateClock() {
        guard runsClock else { return }
        if isPlaying, clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance(by: 0.5) }
            }
        } else if !isPlaying {
            clock?.invalidate()
            clock = nil
        }
    }
}

extension FakeEngine {
    /// Three playlists with invented tracks, one with a title long enough to truncate.
    public static let sample: [Playlist] = [
        Playlist(
            item: PlaylistItem(id: "LM", title: "Liked music"),
            tracks: [
                Track(id: "fake-01", title: "Morning Static", artist: "Paper Planes Collective", album: "Low Light", duration: 222),
                Track(id: "fake-02", title: "A Very Long Track Title That Has To Be Cut Short In The Notch", artist: "The Ensemble With A Long Name", album: "Overflow", duration: 307),
                Track(id: "fake-03", title: "Lanterns", artist: "Mira Holt", album: "Harbour", duration: 178),
                Track(id: "fake-04", title: "Glass Rivers", artist: "Northbound", album: "Glass Rivers", duration: 241),
                Track(id: "fake-05", title: "Quiet Engines", artist: "Paper Planes Collective", album: "Low Light", duration: 199),
            ]
        ),
        Playlist(
            item: PlaylistItem(id: "PLfake-focus", title: "Focus"),
            tracks: [
                Track(id: "fake-06", title: "Long Division", artist: "Ada Vance", duration: 260),
                Track(id: "fake-07", title: "Tidewater", artist: "Mira Holt", album: "Harbour", duration: 214),
                Track(id: "fake-08", title: "Graphite", artist: "Northbound", duration: 187),
            ]
        ),
        Playlist(
            item: PlaylistItem(id: "PLfake-evening", title: "Evening"),
            tracks: [
                Track(id: "fake-09", title: "Slow Return", artist: "Ada Vance", duration: 233),
                Track(id: "fake-10", title: "Embers", artist: "The Ensemble With A Long Name", duration: 276),
            ]
        ),
    ]
}
