import Foundation
import Observation

/// Everything the notch, Control Center and the menu show. Other modules can only read it:
/// its setters are internal to PlayerCore, and PlayerStore is the only writer.
@MainActor
@Observable
public final class PlayerState {
    public internal(set) var track: Track?
    public internal(set) var isPlaying = false
    /// Seconds into the track at the last report; use `elapsed(at:)` to show progress.
    public internal(set) var position: TimeInterval = 0
    public internal(set) var positionReportedAt: Date = .distantPast
    public internal(set) var canNext = false
    public internal(set) var canPrevious = false
    public internal(set) var liked = false
    public internal(set) var shuffle = false
    public internal(set) var repeatMode: RepeatMode = .off
    /// The last playlist list the bridge reported. It is kept when the bridge later reports
    /// playlists as missing, so the list stays usable.
    public internal(set) var playlists: [PlaylistItem] = []
    public internal(set) var queue: [QueueItem] = []
    public internal(set) var health = Health()
    public internal(set) var bridgeVersion: String?

    public init() {}

    /// The position now: it keeps moving from the last report while playing, and never
    /// passes the duration.
    public func elapsed(at now: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let moved = position + max(0, now.timeIntervalSince(positionReportedAt))
        if let duration = track?.duration { return min(moved, duration) }
        return moved
    }

    /// Whether a feature's controls work right now. Unavailable controls are dimmed.
    public func isAvailable(_ feature: Feature) -> Bool {
        guard health.status == .ok, !health.missing.contains(feature) else { return false }
        switch feature {
        case .playPause, .like: return track != nil
        case .seek: return track?.duration != nil
        case .next: return canNext
        case .previous: return canPrevious
        case .shuffle, .repeatMode, .playlists, .queue: return true
        }
    }

    /// The Playlists tab shows while there is a list, even a remembered one.
    public var showsPlaylistsView: Bool { !playlists.isEmpty }

    /// The Up next tab hides as soon as the queue can't be read.
    public var showsQueueView: Bool { !health.missing.contains(.queue) && !queue.isEmpty }
}
