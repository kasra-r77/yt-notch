import Foundation
import PlayerCore

/// What the Playlists and Up next views show (design spec D3), worked out from the store's
/// state and nothing else, so the playing marker moves only when the player reports it.
struct ListPresentation: Equatable {
    enum Content: Equatable {
        case rows([ListRow])
        case loading
        case empty(EmptyList)
    }

    struct EmptyList: Equatable {
        var symbol: String
        var title: String
        var detail: String
    }

    var view: HoverMachine.ExpandedView
    var content: Content
    var showsSavedLine: Bool
    var currentRowID: ListRow.ID?
    var isPlaying: Bool
    var showsPlaylistsTab: Bool
    var showsUpNextTab: Bool

    @MainActor
    init(_ view: HoverMachine.ExpandedView, state: PlayerState, forced: NotchForcedState? = nil) {
        self.view = view
        isPlaying = state.isPlaying
        (showsPlaylistsTab, showsUpNextTab) = Self.tabs(state, forced: forced, selected: view)
        let missing = MessagePresentation.missing(in: state, forced: forced)
        var forcedList: NotchForcedState.ListState?
        if case let .lists(list) = forced { forcedList = list }
        showsSavedLine = false

        switch view {
        case .playlists:
            if forcedList == .loading {
                content = .loading
            } else if forcedList == .empty {
                content = .empty(Self.noPlaylists)
            } else if !state.playlists.isEmpty {
                // Liked music first, the rest in the sidebar's order.
                let ordered = state.playlists.filter(\.isLikedMusic) + state.playlists.filter { !$0.isLikedMusic }
                content = .rows(ordered.map { ListRow(playlist: $0, playingID: state.playlistID) })
                showsSavedLine = state.playlistsMayBeOutOfDate || missing.contains(.playlists) || forcedList == .saved
            } else if missing.contains(.playlists) {
                content = .empty(Self.noPlaylists)
            } else {
                content = .loading
            }
        case .upNext:
            if forcedList == .loading {
                content = .loading
            } else if forcedList == .empty || missing.contains(.queue) {
                content = .empty(Self.nothingUpNext)
            } else if !state.queue.isEmpty {
                content = .rows(state.queue.map(ListRow.init(queueItem:)))
            } else {
                content = .loading
            }
        case .playing:
            content = .rows([])
        }

        if case let .rows(rows) = content {
            currentRowID = rows.first(where: \.isCurrent)?.id
        }
    }

    static let savedLine = "Saved list · may be out of date"

    static let noPlaylists = EmptyList(
        symbol: Tokens.Symbol.playlistTile,
        title: "No playlists yet",
        detail: "Playlists you make or save on YouTube Music show up here."
    )

    static let nothingUpNext = EmptyList(
        symbol: Tokens.Symbol.tabUpNext,
        title: "Nothing up next",
        detail: "Start a playlist or an album and its tracks line up here."
    )

    /// The open view keeps its tab when its data goes, and shows its empty state instead.
    @MainActor
    static func tabs(_ state: PlayerState, forced: NotchForcedState?, selected: HoverMachine.ExpandedView) -> (playlists: Bool, upNext: Bool) {
        if case .lists = forced { return (true, true) }
        let missing = MessagePresentation.missing(in: state, forced: forced)
        let playlists = !state.playlists.isEmpty
        let upNext = !state.queue.isEmpty && !missing.contains(.queue)
        return (playlists || selected == .playlists, upNext || selected == .upNext)
    }
}

struct ListRow: Equatable, Identifiable {
    enum Tile: Equatable {
        /// For playlists, which the site gives no pictures.
        case symbol(String)
        case artwork(URL?)
    }

    enum Action: Equatable {
        case playPlaylist(id: String)
        case playQueueItem(index: Int)
    }

    var id: String
    var title: String
    var subtitle: String?
    var length: String?
    var tile: Tile
    var isCurrent: Bool
    var action: Action

    var artworkURL: URL? {
        if case let .artwork(url) = tile { return url }
        return nil
    }

    var help: String {
        [title, subtitle ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    init(playlist: PlaylistItem, playingID: String?) {
        id = "playlist:" + playlist.id
        title = playlist.title
        tile = .symbol(playlist.isLikedMusic ? Tokens.Symbol.likedTile : Tokens.Symbol.playlistTile)
        isCurrent = playlist.id == playingID
        action = .playPlaylist(id: playlist.id)
    }

    init(queueItem item: QueueItem) {
        id = "queue:\(item.index)"
        title = item.title
        subtitle = item.artist
        length = item.duration.map(PlayingPresentation.time)
        tile = .artwork(item.artworkURL)
        isCurrent = item.isCurrent
        action = .playQueueItem(index: item.index)
    }
}
