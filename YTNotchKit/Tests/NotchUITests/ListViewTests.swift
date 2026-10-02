import AppKit
import Foundation
import PlayerCore
import SwiftUI
import Testing
@testable import NotchUI

/// The Playlists and Up next views: what they show comes only from the store, rows drive
/// the engine through the store, and tabs hide when their view has nothing to show.
@MainActor
@Suite(.serialized)
struct ListViewTests {
    typealias SilentEngine = PlayingViewTests.SilentEngine

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let pointer = PointerTracker()

    init() {
        _ = NSApplication.shared
    }

    func rows(_ p: ListPresentation) -> [ListRow] {
        if case let .rows(rows) = p.content { return rows }
        return []
    }

    // MARK: Playlists

    @Test func playlistsPinLikedMusicFirstAndMarkWhatPlays() {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        engine.report(.playlists([
            PlaylistItem(id: "PL1", title: "Mix"),
            PlaylistItem(id: "LM", title: "Liked music", isLikedMusic: true),
            PlaylistItem(id: "PL2", title: "Focus"),
        ]))
        engine.report(.state(PlaybackSnapshot(track: nil, playlistID: "PL2")))
        let p = ListPresentation(.playlists, state: store.state)
        #expect(rows(p).map(\.title) == ["Liked music", "Mix", "Focus"])
        #expect(rows(p).map(\.tile) == [.symbol(Tokens.Symbol.likedTile), .symbol(Tokens.Symbol.playlistTile), .symbol(Tokens.Symbol.playlistTile)])
        #expect(rows(p).map(\.isCurrent) == [false, false, true])
        #expect(p.currentRowID == "playlist:PL2")
        #expect(!p.showsSavedLine)
        #expect(rows(p).allSatisfy { $0.length == nil && $0.subtitle == nil }, "the marker is all that trails a playlist")
    }

    @Test func clickingAPlaylistStartsItAndTheMarkerMovesWhenThePlayerSaysSo() throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        let actions = NotchActions(store: store)
        let focus = try #require(rows(ListPresentation(.playlists, state: store.state)).first { $0.title == "Focus" })
        #expect(!focus.isCurrent)
        actions.play(focus.action)
        #expect(engine.receivedCommands.last == .playPlaylist(id: "PLfake-focus"))
        let after = ListPresentation(.playlists, state: store.state)
        #expect(after.currentRowID == "playlist:PLfake-focus")
        #expect(rows(after).filter(\.isCurrent).count == 1)
    }

    // MARK: Up next

    @Test func upNextShowsTheQueueWithLengths() {
        let store = PlayerStore(engine: FakeEngine())
        let p = ListPresentation(.upNext, state: store.state)
        let liked = FakeEngine.sample[0].tracks
        #expect(rows(p).map(\.title) == liked.map(\.title))
        #expect(rows(p).map(\.subtitle) == liked.map(\.artist))
        #expect(rows(p).first?.length == "3:42")
        #expect(rows(p).first?.isCurrent == true)
        #expect(rows(p).allSatisfy { $0.tile == .artwork(nil) })
        #expect(p.currentRowID == "queue:0")
        #expect(rows(p)[1].help == "\(liked[1].title) — \(liked[1].artist)", "the help tag has the full text")
    }

    @Test func clickingATrackJumpsToIt() {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        let actions = NotchActions(store: store)
        actions.play(rows(ListPresentation(.upNext, state: store.state))[7].action)
        #expect(engine.receivedCommands.last == .playQueueItem(index: 7))
        #expect(store.state.track == FakeEngine.sample[0].tracks[7])
        #expect(ListPresentation(.upNext, state: store.state).currentRowID == "queue:7")
    }

    @Test func nothingMovesUntilThePlayerReportsIt() {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        engine.report(.queue([
            QueueItem(index: 0, title: "A", artist: "X", isCurrent: true, duration: 200),
            QueueItem(index: 1, title: "B", artist: "Y", isCurrent: false),
        ]))
        engine.report(.playlists([PlaylistItem(id: "PL1", title: "Mix")]))
        let actions = NotchActions(store: store)
        let before = (ListPresentation(.upNext, state: store.state), ListPresentation(.playlists, state: store.state))
        actions.play(.playQueueItem(index: 1))
        actions.play(.playPlaylist(id: "PL1"))
        #expect(engine.sent == [.playQueueItem(index: 1), .playPlaylist(id: "PL1")])
        #expect(ListPresentation(.upNext, state: store.state) == before.0)
        #expect(ListPresentation(.playlists, state: store.state) == before.1)
        #expect(rows(before.0)[1].length == nil, "no length when the page shows none")
    }

    // MARK: Tabs

    @Test func aViewWithNoDataHidesItsTab() {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        var tabs = ListPresentation.tabs(store.state, forced: nil, selected: .playing)
        #expect(!tabs.playlists && !tabs.upNext, "nothing read, nothing saved")

        engine.report(.playlists([PlaylistItem(id: "PL1", title: "Mix")]))
        engine.report(.queue([QueueItem(index: 0, title: "A", artist: "X", isCurrent: true)]))
        tabs = ListPresentation.tabs(store.state, forced: nil, selected: .playing)
        #expect(tabs.playlists && tabs.upNext)

        engine.report(.health(missing: [.queue, .playlists]))
        tabs = ListPresentation.tabs(store.state, forced: nil, selected: .playing)
        #expect(!tabs.upNext, "the queue can't be read")
        #expect(tabs.playlists, "the list read earlier still plays")
        #expect(PlayingPresentation(store.state, at: now).showsUpNextTab == false)
    }

    @Test func theOpenViewKeepsItsTabAndShowsItsEmptyState() {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        engine.simulateMissing([.queue])
        let p = ListPresentation(.upNext, state: store.state)
        #expect(p.showsUpNextTab)
        #expect(p.content == .empty(ListPresentation.nothingUpNext))
        #expect(!ListPresentation(.playlists, state: store.state).showsUpNextTab)
    }

    // MARK: States

    @Test func aListBeingReadForTheFirstTimeIsLoading() {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        #expect(ListPresentation(.playlists, state: store.state).content == .loading)
        #expect(ListPresentation(.upNext, state: store.state).content == .loading)
    }

    @Test func aRememberedListShowsUnderTheSavedLine() {
        let cache = PlaylistCacheStub([PlaylistItem(id: "LM", title: "Liked music", isLikedMusic: true)])
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine, playlistCache: cache)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        var p = ListPresentation(.playlists, state: store.state)
        #expect(p.showsSavedLine)
        #expect(rows(p).map(\.title) == ["Liked music"], "the rows still play")
        engine.report(.playlists([PlaylistItem(id: "LM", title: "Liked music", isLikedMusic: true)]))
        p = ListPresentation(.playlists, state: store.state)
        #expect(!p.showsSavedLine, "gone once the sidebar is read")
        engine.report(.health(missing: [.playlists]))
        #expect(ListPresentation(.playlists, state: store.state).showsSavedLine, "and back while it can't be read")
    }

    @Test func emptyStatesHaveTheApprovedWording() {
        #expect(ListPresentation.noPlaylists == .init(symbol: "music.note.list", title: "No playlists yet",
                                                      detail: "Playlists you make or save on YouTube Music show up here."))
        #expect(ListPresentation.nothingUpNext == .init(symbol: "list.bullet", title: "Nothing up next",
                                                        detail: "Start a playlist or an album and its tracks line up here."))
        #expect(ListPresentation.savedLine == "Saved list · may be out of date")
    }

    @Test func eachListStateCanBeForced() {
        let store = PlayerStore(engine: FakeEngine())
        for view in [HoverMachine.ExpandedView.playlists, .upNext] {
            #expect(ListPresentation(view, state: store.state, forced: .lists(.loading)).content == .loading)
            let empty = ListPresentation(view, state: store.state, forced: .lists(.empty))
            #expect(empty.content == .empty(view == .playlists ? ListPresentation.noPlaylists : ListPresentation.nothingUpNext))
            #expect(empty.showsPlaylistsTab && empty.showsUpNextTab)
        }
        #expect(ListPresentation(.playlists, state: store.state, forced: .lists(.saved)).showsSavedLine)
        #expect(MessagePresentation.kind(for: store.state, forced: .lists(.empty)) == nil)
    }

    // MARK: The panel

    func panel(_ store: PlayerStore) -> NotchPanel {
        let panel = NotchPanel(screen: Displays.external, store: store, pointer: pointer)
        panel.schedulesTicks = false
        panel.now = { [now] in now }
        return panel
    }

    func open(_ panel: NotchPanel, at time: Date) {
        panel.now = { time }
        pointer.deliver(NotchMotionPanelTests.insidePill)
        panel.tick(at: time.addingTimeInterval(Tokens.Timing.dwell))
    }

    func close(_ panel: NotchPanel, at time: Date) {
        panel.now = { time }
        pointer.deliver(CGPoint(x: 100, y: 100))
        panel.tick(at: time.addingTimeInterval(Tokens.Timing.grace))
    }

    @Test func switchingToAListResizesToThreeHundred() {
        let store = PlayerStore(engine: FakeEngine())
        let panel = panel(store)
        defer { panel.close() }
        open(panel, at: now)
        #expect(panel.model.outline.height == Tokens.Size.expandedPlayingHeight)
        panel.model.actions.select(.upNext)
        #expect(panel.model.expandedContent == .view(.upNext))
        #expect(panel.model.outline.height == Tokens.Size.expandedListHeight)
        panel.model.actions.select(.playlists)
        #expect(panel.model.outline.height == Tokens.Size.expandedListHeight, "the lists share a size")
    }

    @Test func reopensOnPlayingUnlessClosedLessThanTenSecondsAgo() {
        let store = PlayerStore(engine: FakeEngine())
        let panel = panel(store)
        defer { panel.close() }
        open(panel, at: now)
        panel.model.actions.select(.upNext)
        panel.settled()
        close(panel, at: now.addingTimeInterval(1))

        open(panel, at: now.addingTimeInterval(5))
        #expect(panel.machine.appearance == .expanded(.view(.upNext)), "back within 10 s")
        close(panel, at: now.addingTimeInterval(6))

        open(panel, at: now.addingTimeInterval(6 + Tokens.Timing.grace + Tokens.Timing.reopenMemory + 1))
        #expect(panel.machine.appearance == .expanded(.view(.playing)), "later, on Playing")
    }

    @Test func neverReopensOnAListThatHasEmptied() async throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        let panel = panel(store)
        defer { panel.close() }
        open(panel, at: now)
        panel.model.actions.select(.upNext)
        panel.settled()
        close(panel, at: now.addingTimeInterval(1))
        #expect(!panel.machine.isExpanded)
        engine.simulateMissing([.queue])
        // The panel reads the store on its next turn.
        try await Task.sleep(for: .milliseconds(20))
        open(panel, at: now.addingTimeInterval(3))
        #expect(panel.machine.appearance == .expanded(.view(.playing)))
    }

    // MARK: Drawing

    @Test func drawsARowWithItsMarkerAndLength() throws {
        let row = ListRow(queueItem: QueueItem(index: 0, title: "Title", artist: "Artist", isCurrent: true, duration: 222))
        let view = ZStack {
            Tokens.Color.surface
            ListRowView(row: row, isPlaying: false, accent: .red, reduceMotion: false) {}
        }
        .frame(width: 384, height: 48)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let pixels = try Pixels(try #require(renderer.cgImage))
        // White 10% behind the playing row, and the placeholder tile at (8, 8) over it.
        let background = pixels.at(x: 200, y: 4)
        #expect(background.r > 15 && background.r < 40)
        let tile = pixels.at(x: 12, y: 24)
        #expect(tile.r > background.r + 5 && tile.r < 70)
        // Red bars near the right end, before the length.
        let trailing = (300..<376).flatMap { x in (14..<34).map { pixels.at(x: x, y: $0) } }
        #expect(trailing.contains { $0.r > 200 && $0.g < 80 })
    }

    @Test func opensScrolledToWhatPlaysNow() async throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        store.playQueueItem(index: 8)
        let model = NotchModel(outline: NotchLayout.outline(for: .expanded(.view(.upNext)), on: Displays.macBookPro14), band: 32)
        model.actions = NotchActions(store: store)
        let hosted = Hosted(ListView(state: store.state, view: .upNext, model: model, actions: model.actions, extra: 0))
        defer { hosted.close() }
        let scroller = try await hosted.scrollView()
        try await eventually("scrolled") { scroller.documentVisibleRect.minY > 0 }
        let top = scroller.documentVisibleRect.minY
        // Row 8 is at the top, or as near as the list allows.
        let rows = FakeEngine.sample[0].tracks.count
        let contentHeight = CGFloat(rows) * Tokens.Size.row + Tokens.Size.listBottom
        let expected = min(8 * Tokens.Size.row, contentHeight - scroller.documentVisibleRect.height)
        #expect(abs(top - expected) < 1)
        hosted.dump("up-next-scrolled")
    }

    @Test func aShortListDoesNotScroll() async throws {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        store.playPlaylist(id: "PLfake-focus")
        let model = NotchModel(outline: NotchLayout.outline(for: .expanded(.view(.upNext)), on: Displays.macBookPro14), band: 32)
        model.actions = NotchActions(store: store)
        let hosted = Hosted(ListView(state: store.state, view: .upNext, model: model, actions: model.actions, extra: 0))
        defer { hosted.close() }
        let scroller = try await hosted.scrollView()
        #expect(scroller.documentVisibleRect.minY == 0)
        #expect(scroller.documentView.map { $0.frame.height <= scroller.documentVisibleRect.height + 0.5 } ?? true)
        hosted.dump("up-next-short")
    }

    @Test func drawsEveryState() async throws {
        let store = PlayerStore(engine: FakeEngine())
        for (name, view, forced) in [
            ("playlists", HoverMachine.ExpandedView.playlists, NotchForcedState?.none),
            ("playlists-saved", .playlists, .lists(.saved)),
            ("playlists-loading", .playlists, .lists(.loading)),
            ("playlists-empty", .playlists, .lists(.empty)),
            ("up-next", .upNext, nil),
            ("up-next-loading", .upNext, .lists(.loading)),
            ("up-next-empty", .upNext, .lists(.empty)),
        ] {
            let model = NotchModel(outline: NotchLayout.outline(for: .expanded(.view(view)), on: Displays.macBookPro14), band: 32)
            model.actions = NotchActions(store: store)
            model.forcedState = forced
            let hosted = Hosted(ListView(state: store.state, view: view, model: model, actions: model.actions, extra: 0))
            try await Task.sleep(for: .milliseconds(100))
            hosted.dump(name)
            hosted.close()
        }
    }
}

/// A view in a real window, so scroll views work as they do in the notch.
@MainActor
final class Hosted<Content: View> {
    let window: NSWindow
    let host: NSHostingView<AnyView>

    init(_ content: Content, size: CGSize = CGSize(width: Tokens.Size.expandedWidth, height: Tokens.Size.expandedListHeight)) {
        host = NSHostingView(rootView: AnyView(ZStack(alignment: .top) {
            Tokens.Color.surface
            content
        }))
        host.appearance = NSAppearance(named: .darkAqua)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
    }

    func scrollView() async throws -> NSScrollView {
        var found: NSScrollView?
        try await eventually("a scroll view") {
            host.layoutSubtreeIfNeeded()
            found = Self.first(NSScrollView.self, in: host)
            return found != nil
        }
        return found!
    }

    /// Writes the window's image as a PNG when YTNOTCH_SNAPSHOTS names a folder, for review.
    func dump(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["YTNOTCH_SNAPSHOTS"],
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }

    func close() { window.close() }

    private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = first(type, in: subview) { return match }
        }
        return nil
    }
}

/// Waits until `condition` holds, giving the main actor back in between.
@MainActor
func eventually(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw TimedOut(what: what) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

struct TimedOut: Error, CustomStringConvertible {
    let what: String
    var description: String { "Timed out waiting for \(what)" }
}

/// A playlist cache that starts with a list.
final class PlaylistCacheStub: PlaylistCache {
    var items: [PlaylistItem]
    init(_ items: [PlaylistItem]) { self.items = items }
    func load() -> [PlaylistItem] { items }
    func save(_ items: [PlaylistItem]) { self.items = items }
}
