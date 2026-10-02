import Foundation

/// A track as the bridge reports it.
public struct Track: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    public var artworkURL: URL?
    /// In seconds; nil while the site does not know it yet.
    public var duration: TimeInterval?

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
    }
}

/// A playlist from the user's library. The site exposes no thumbnail for most playlists
/// (spike report, S0.4), so `thumbnailURL` is usually nil.
public struct PlaylistItem: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var thumbnailURL: URL?
    /// The user's liked songs, which the Playlists view pins first with its own tile.
    public var isLikedMusic: Bool

    public init(id: String, title: String, thumbnailURL: URL? = nil, isLikedMusic: Bool = false) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.isLikedMusic = isLikedMusic
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, thumbnailURL, isLikedMusic
    }

    /// Lists saved before `isLikedMusic` existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        isLikedMusic = try container.decodeIfPresent(Bool.self, forKey: .isLikedMusic) ?? false
    }
}

/// One entry in the queue, in queue order.
public struct QueueItem: Equatable, Sendable, Identifiable {
    public var index: Int
    public var title: String
    public var artist: String
    public var isCurrent: Bool
    /// The track's picture, when the page shows one.
    public var artworkURL: URL?
    /// In seconds, when the page shows the length.
    public var duration: TimeInterval?

    public var id: Int { index }

    public init(index: Int, title: String, artist: String, isCurrent: Bool, artworkURL: URL? = nil, duration: TimeInterval? = nil) {
        self.index = index
        self.title = title
        self.artist = artist
        self.isCurrent = isCurrent
        self.artworkURL = artworkURL
        self.duration = duration
    }
}

public enum RepeatMode: String, Equatable, Sendable, CaseIterable {
    case off, all, one

    /// The mode after this one, in the order the site's repeat button cycles.
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// A part of the player the bridge can report as missing. A missing feature's controls are
/// dimmed and its commands are not sent. Raw values are the names the bridge uses.
public enum Feature: String, Hashable, Sendable, CaseIterable {
    case playPause
    case next
    case previous
    case seek
    case like
    case shuffle
    case repeatMode = "repeat"
    case playlists
    case queue
}

public struct Health: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The page has not reported ready yet.
        case starting
        case ok
        /// The page shows its sign-in prompt.
        case signedOut
        /// The page failed to load, or the network is gone.
        case offline
        /// Recovery gave up. No commands are sent until the page reports ready again.
        case bridgeBroken

        /// Signed out, offline or broken: something only the user can sort out, so the menu
        /// bar icon shows its dot and the menu a line saying what (design spec D7).
        public var needsAttention: Bool {
            switch self {
            case .signedOut, .offline, .bridgeBroken: true
            case .starting, .ok: false
            }
        }
    }

    public var status: Status
    /// Parts of the page the bridge could not find. Their controls are dimmed.
    public var missing: Set<Feature>

    public init(status: Status = .starting, missing: Set<Feature> = []) {
        self.status = status
        self.missing = missing
    }
}

/// The bridge's `state` message: what is playing and where.
public struct PlaybackSnapshot: Equatable, Sendable {
    public var track: Track?
    /// Seconds into the track.
    public var position: TimeInterval
    public var isPlaying: Bool
    public var canNext: Bool
    public var canPrevious: Bool
    public var liked: Bool
    /// The library playlist playing now, if the page says; nil for anything else.
    public var playlistID: String?

    public init(
        track: Track?,
        position: TimeInterval = 0,
        isPlaying: Bool = false,
        canNext: Bool = false,
        canPrevious: Bool = false,
        liked: Bool = false,
        playlistID: String? = nil
    ) {
        self.track = track
        self.position = position
        self.isPlaying = isPlaying
        self.canNext = canNext
        self.canPrevious = canPrevious
        self.liked = liked
        self.playlistID = playlistID
    }
}
