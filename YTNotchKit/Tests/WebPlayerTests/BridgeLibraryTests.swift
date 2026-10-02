import Foundation
import PlayerCore
import Testing
@testable import WebPlayer

/// The bridge's playlists, queue and modes against the fixture page (W3.6).
@MainActor
@Suite(.serialized)
struct BridgeLibraryTests {
    let page = BridgeHarness()

    // MARK: Messages

    @Test func playlistsComeFromTheSidebar() async throws {
        try await page.load()
        let items = try await page.any("playlists") { $0.playlists }
        #expect(items.map(\.id) == ["LM", "PLfixture-mix", "PLfixture-focus", "SE"], "Liked music pinned first")
        #expect(items.map(\.title) == ["Liked music", "Fixture Mix", "Focus", "Episodes for later"])
        #expect(items.map(\.isLikedMusic) == [true, false, false, false])
        #expect(items.allSatisfy { $0.thumbnailURL == nil })
    }

    @Test func queueItemsHaveTheirLengthAndThumbnail() async throws {
        try await page.load()
        let items = try await page.any("queue") { $0.queue }
        #expect(items.map(\.duration) == [200, 150, 90])
        #expect(items.map(\.artworkURL?.absoluteString) == [
            "https://fixture.ytnotch.test/art/a-120.jpg",
            "https://fixture.ytnotch.test/art/b-120.jpg",
            "https://fixture.ytnotch.test/art/c-120.jpg",
        ], "from each item's data, the smallest at least 64 wide, loaded or not")
    }

    @Test func withoutItsDataAQueueItemFallsBackToItsLoadedImage() async throws {
        try await page.load("no-queue-data")
        let items = try await page.any("queue") { $0.queue }
        #expect(items.map(\.artworkURL?.absoluteString) == [
            "https://fixture.ytnotch.test/art/a-60.jpg",
            nil,
            nil,
        ], "an image that hasn't loaded is left out")
    }

    @Test func thePlaylistPlayingNowComesFromTheAddress() async throws {
        try await page.load(path: "/watch?list=PLfixture-focus")
        let id = try await page.any("state") { event -> String? in
            if case let .state(snapshot) = event { return snapshot.playlistID ?? "none" }
            return nil
        }
        #expect(id == "PLfixture-focus")
    }

    @Test func noPlaylistOutsideOne() async throws {
        try await page.load()
        let id = try await page.any("state") { event -> String? in
            if case let .state(snapshot) = event { return snapshot.playlistID ?? "none" }
            return nil
        }
        #expect(id == "none")
    }

    @Test func queueLeavesOutCounterpartsAndAutoplay() async throws {
        try await page.load()
        let items = try await page.any("queue") { $0.queue }
        #expect(items.map(\.title) == ["First Song", "Second Song", "Third Song"])
        #expect(items.map(\.index) == [0, 1, 2])
        #expect(items.map(\.artist) == ["The Fixtures", "The Fixtures", "Someone Else"])
        #expect(items.map(\.isCurrent) == [true, false, false])
    }

    @Test func currentQueueItemFollowsPlayback() async throws {
        try await page.load()
        try await page.send(.play)
        try await page.send(.next)
        try await page.next("queue on the second track") { $0.queue.flatMap { $0[1].isCurrent && !$0[0].isCurrent ? true : nil } }
        try await page.send(.pause)
        try await page.js("window.fixture.advance(1)")
        let paused = try await page.any("queue") { $0.queue }
        #expect(paused.map(\.isCurrent) == [false, true, false])
    }

    @Test func modesAreRead() async throws {
        try await page.load()
        let modes = try await page.any("modes") { $0.modes }
        #expect(modes.shuffle == false)
        #expect(modes.repeatMode == .off)
    }

    // MARK: Commands

    @Test func playPlaylistGoesToItsAddress() async throws {
        try await page.load()
        #expect(try await page.send(.playPlaylist(id: "PLfixture-mix"))["ok"] as? Bool == true)
        try await page.wait("navigation") { _ in !page.blockedNavigations.isEmpty }
        let url = try #require(page.blockedNavigations.first)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "fixture.ytnotch.test")
        #expect(components.path == "/watch")
        #expect(components.queryItems == [URLQueryItem(name: "list", value: "PLfixture-mix")])
    }

    @Test func playQueueItem() async throws {
        try await page.load()
        try await page.send(.playQueueItem(index: 2))
        try await page.next("third track") { $0.snapshot?.track?.title == "Third Song" ? true : nil }
        let queue = try await page.any("queue") { $0.queue.flatMap { $0[2].isCurrent ? $0 : nil } }
        #expect(queue.filter(\.isCurrent).map(\.index) == [2])
    }

    @Test func unknownQueueItemFails() async throws {
        try await page.load()
        #expect(try await page.send(.playQueueItem(index: 9))["ok"] as? Bool == false)
        #expect(try await page.pageErrors().isEmpty)
    }

    @Test func setShuffle() async throws {
        try await page.load()
        try await page.send(.setShuffle(true))
        try await page.next("shuffle on") { $0.modes?.shuffle == true ? true : nil }
        try await page.send(.setShuffle(true))
        #expect(try await page.js("return window.fixture.status().shuffle") as? Bool == true)
        try await page.send(.setShuffle(false))
        try await page.next("shuffle off") { $0.modes?.shuffle == false ? true : nil }
    }

    @Test func setRepeat() async throws {
        try await page.load()
        for mode in [RepeatMode.one, .all, .off, .all] {
            try await page.send(.setRepeat(mode))
            try await page.next("repeat \(mode)") { $0.modes?.repeatMode == mode ? true : nil }
            #expect(try await page.js("return window.fixture.status().repeat") as? String == mode.rawValue)
        }
    }

    // MARK: Broken pieces

    @Test(arguments: [("no-sidebar", Feature.playlists), ("no-queue", .queue), ("no-shuffle", .shuffle), ("no-repeat", .repeatMode)])
    func brokenSelectorHidesOnlyItsFeature(option: String, feature: Feature) async throws {
        try await page.load(option)
        #expect(try await page.any("health") { $0.missing } == [feature])
        try await page.send(.play)
        try await page.next("playing") { $0.snapshot.flatMap { $0.isPlaying ? true : nil } }
        try await page.send(.pause)
        try await page.next("paused") { $0.snapshot.flatMap { $0.isPlaying ? nil : true } }
        try await page.send(.next)
        try await page.next("next track") { $0.snapshot?.track?.title == "Second Song" ? true : nil }
        #expect(try await page.pageErrors().isEmpty)
    }

    @Test func repeatInAnotherLanguageReadsOffAndStopsWhenUnsure() async throws {
        try await page.load("other-language")
        let modes = try await page.any("modes") { $0.modes }
        #expect(modes.repeatMode == .off)
        #expect(try await page.any("health") { $0.missing } == [])

        try await page.send(.setRepeat(.one))
        try await page.next("repeat missing") { $0.missing.flatMap { $0.contains(.repeatMode) ? $0 : nil } }
        // It turned repeat on once, then stopped instead of clicking on blindly.
        #expect(try await page.js("return window.fixture.status().repeat") as? String == "all")
        try await page.send(.setShuffle(true))
        try await page.next("shuffle still works") { $0.modes?.shuffle == true ? true : nil }
    }

    @Test func shuffleRemovedLaterShowsInHealth() async throws {
        try await page.load()
        try await page.js("window.fixture.removeShuffle()")
        try await page.next("shuffle missing", timeout: 6) { $0.missing == [.shuffle] ? true : nil }
        #expect(try await page.send(.setShuffle(true))["ok"] as? Bool == false)
    }
}
