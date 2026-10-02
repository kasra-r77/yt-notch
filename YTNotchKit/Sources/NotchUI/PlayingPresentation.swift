import Foundation
import PlayerCore

/// What the Playing view shows (design spec D2), worked out from the store's state and
/// nothing else, so the view never shows a command as done before the player reports it.
struct PlayingPresentation: Equatable {
    var hasTrack: Bool
    var title: String
    var artist: String
    /// The help tag over the title and artist: both in full.
    var help: String
    var elapsed: String
    var total: String
    /// How far through the track, 0 to 1.
    var progress: Double
    var duration: TimeInterval?
    var isPlaying: Bool
    var playSymbol: String
    var playLabel: String
    var liked: Bool
    var likeSymbol: String
    var likeLabel: String
    var shuffleOn: Bool
    var repeatOn: Bool
    var repeatSymbol: String
    var repeatLabel: String
    /// Shuffle and repeat are hidden, not dimmed, when the page can't read them.
    var showsShuffle: Bool
    var showsRepeat: Bool
    var showsPlaylistsTab: Bool
    var showsUpNextTab: Bool
    var canPlayPause: Bool
    var canPrevious: Bool
    var canNext: Bool
    var canSeek: Bool
    var canLike: Bool
    var canShuffle: Bool
    var canRepeat: Bool

    @MainActor
    init(_ state: PlayerState, at now: Date) {
        let track = state.track
        hasTrack = track != nil
        title = track?.title ?? ""
        artist = track?.artist ?? ""
        help = [title, artist].filter { !$0.isEmpty }.joined(separator: " — ")
        duration = track?.duration
        let position = state.elapsed(at: now)
        if hasTrack {
            elapsed = Self.time(position)
            total = duration.map(Self.time) ?? Self.unknownTime
        } else {
            elapsed = Self.time(0)
            total = Self.unknownTime
        }
        if let duration, duration > 0 {
            progress = min(1, max(0, position / duration))
        } else {
            progress = 0
        }
        isPlaying = state.isPlaying
        playSymbol = state.isPlaying ? Tokens.Symbol.pause : Tokens.Symbol.play
        playLabel = state.isPlaying ? "Pause" : "Play"
        liked = state.liked
        likeSymbol = state.liked ? Tokens.Symbol.liked : Tokens.Symbol.like
        likeLabel = state.liked ? "Remove Like" : "Like"
        shuffleOn = state.shuffle
        repeatOn = state.repeatMode != .off
        repeatSymbol = state.repeatMode == .one ? Tokens.Symbol.repeatOne : Tokens.Symbol.repeat
        repeatLabel = switch state.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
        let missing = state.health.missing
        showsShuffle = !missing.contains(.shuffle)
        showsRepeat = !missing.contains(.repeatMode)
        showsPlaylistsTab = state.showsPlaylistsView
        showsUpNextTab = state.showsQueueView
        canPlayPause = state.isAvailable(.playPause)
        canPrevious = state.isAvailable(.previous)
        canNext = state.isAvailable(.next)
        canSeek = state.isAvailable(.seek)
        canLike = state.isAvailable(.like)
        canShuffle = state.isAvailable(.shuffle)
        canRepeat = state.isAvailable(.repeatMode)
    }

    static let unknownTime = "–:––"

    /// "1:12", or "1:02:03" past an hour.
    static func time(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let rest = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// What the notch's controls do: the store's intents, plus the two things only the app can
/// do (open the full window) or only the panel can (switch views).
@MainActor
struct NotchActions {
    let store: PlayerStore?
    var openFullWindow: (@MainActor () -> Void)?
    var select: @MainActor (HoverMachine.ExpandedView) -> Void = { _ in }

    func togglePlayPause() { store?.togglePlayPause() }
    func previous() { store?.previous() }
    func next() { store?.next() }
    func toggleLike() { store?.toggleLike() }
    func toggleShuffle() { store?.toggleShuffle() }
    func cycleRepeat() { store?.cycleRepeat() }

    /// Seeks to a point given as a share of the track, 0 to 1.
    func seek(toFraction fraction: Double) {
        guard let store, let duration = store.state.track?.duration else { return }
        store.seek(to: min(1, max(0, fraction)) * duration)
    }
}
