import Foundation
import Testing
@testable import PlayerCore

/// The playlist list survives relaunches and moments when the sidebar can't be read.
@MainActor
struct PlaylistCacheTests {
    final class MemoryCache: PlaylistCache {
        var stored: [PlaylistItem]
        private(set) var saves = 0
        init(_ stored: [PlaylistItem] = []) { self.stored = stored }
        func load() -> [PlaylistItem] { stored }
        func save(_ items: [PlaylistItem]) { stored = items; saves += 1 }
    }

    @Test func storeStartsWithTheCachedList() {
        let cache = MemoryCache(Fixture.playlists)
        let store = PlayerStore(engine: SpyEngine(), playlistCache: cache)
        #expect(store.state.playlists == Fixture.playlists)
        #expect(store.state.showsPlaylistsView)
    }

    @Test func newListIsSaved() {
        let cache = MemoryCache()
        let engine = SpyEngine()
        let store = PlayerStore(engine: engine, playlistCache: cache)
        engine.emit(.playlists(Fixture.playlists))
        #expect(cache.stored == Fixture.playlists)
        #expect(store.state.playlists == Fixture.playlists)
    }

    @Test func emptyListIsNotSaved() {
        let cache = MemoryCache(Fixture.playlists)
        let engine = SpyEngine()
        let store = PlayerStore(engine: engine, playlistCache: cache)
        engine.emit(.playlists([]))
        #expect(store.state.playlists.isEmpty)
        #expect(cache.saves == 0)
        #expect(cache.stored == Fixture.playlists)
    }

    @Test func cachedListStaysUsableWhileTheSidebarIsMissing() {
        let engine = SpyEngine()
        let store = PlayerStore(engine: engine, playlistCache: MemoryCache(Fixture.playlists))
        engine.emit(.ready(bridgeVersion: "1", signedIn: true), .health(missing: [.playlists]))
        store.playPlaylist(id: "PL1")
        #expect(engine.sent == [.playPlaylist(id: "PL1")])
    }

    @Test func userDefaultsRoundTrip() throws {
        let suite = "ytnotch-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = UserDefaultsPlaylistCache(defaults: defaults)
        #expect(cache.load().isEmpty)
        let items = [PlaylistItem(id: "LM", title: "Liked music"), PlaylistItem(id: "PL1", title: "Mix", thumbnailURL: URL(string: "https://x.test/t.jpg"))]
        cache.save(items)
        #expect(UserDefaultsPlaylistCache(defaults: defaults).load() == items)
    }
}
