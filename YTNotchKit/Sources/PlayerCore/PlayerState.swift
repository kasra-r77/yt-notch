import Foundation
import Observation

/// Read-only outside PlayerCore; PlayerStore is its only writer.
@MainActor
@Observable
public final class PlayerState {
    public internal(set) var track: Track?
    public internal(set) var isPlaying = false
    /// As of the last report; show progress with `elapsed(at:)`.
    public internal(set) var position: TimeInterval = 0
    public internal(set) var positionReportedAt: Date = .distantPast
    public internal(set) var canNext = false
    public internal(set) var canPrevious = false
    public internal(set) var liked = false
    public internal(set) var shuffle = false
    public internal(set) var repeatMode: RepeatMode = .off
    /// Kept when the bridge later reports playlists missing, so the list stays usable.
    public internal(set) var playlists: [PlaylistItem] = []
    /// `playlists` came from an earlier launch and the page hasn't read the sidebar yet.
    public internal(set) var playlistsAreRemembered = false
    public internal(set) var playlistID: String?
    public internal(set) var queue: [QueueItem] = []
    /// Pictures the page handed over, by address. Nothing in the app downloads pictures itself.
    public internal(set) var artwork: [URL: Data] = [:]
    public internal(set) var health = Health()
    public internal(set) var bridgeVersion: String?

    public init() {}

    public func elapsed(at now: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let moved = position + max(0, now.timeIntervalSince(positionReportedAt))
        if let duration = track?.duration { return min(moved, duration) }
        return moved
    }

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

    public var showsPlaylistsView: Bool { !playlists.isEmpty }

    public var playlistsMayBeOutOfDate: Bool {
        !playlists.isEmpty && (playlistsAreRemembered || health.missing.contains(.playlists))
    }

    public var showsQueueView: Bool { !health.missing.contains(.queue) && !queue.isEmpty }
}
