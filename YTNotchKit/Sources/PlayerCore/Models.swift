import Foundation

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

/// The site exposes no thumbnail for most playlists (spike report, S0.4), so `thumbnailURL`
/// is usually nil.
public struct PlaylistItem: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var thumbnailURL: URL?
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

public struct QueueItem: Equatable, Sendable, Identifiable {
    public var index: Int
    public var title: String
    public var artist: String
    public var isCurrent: Bool
    public var artworkURL: URL?
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

    /// In the order the site's repeat button cycles.
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// A part of the page the bridge can report as missing. Raw values are the bridge's names.
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
        case starting
        case ok
        case signedOut
        case offline
        /// Recovery gave up. No commands are sent until the page reports ready again.
        case bridgeBroken

        /// Something only the user can sort out: the menu bar icon shows its dot (design spec D7).
        public var needsAttention: Bool {
            switch self {
            case .signedOut, .offline, .bridgeBroken: true
            case .starting, .ok: false
            }
        }
    }

    public var status: Status
    public var missing: Set<Feature>

    public init(status: Status = .starting, missing: Set<Feature> = []) {
        self.status = status
        self.missing = missing
    }
}

public struct PlaybackSnapshot: Equatable, Sendable {
    public var track: Track?
    public var position: TimeInterval
    public var isPlaying: Bool
    public var canNext: Bool
    public var canPrevious: Bool
    public var liked: Bool
    /// Nil unless a library playlist is playing and the page says which.
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
