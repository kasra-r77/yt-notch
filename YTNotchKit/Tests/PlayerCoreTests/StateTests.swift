import Foundation
import Observation
import Testing
@testable import PlayerCore

@MainActor
struct StateTests {
    @Test func stateEventFillsPlayback() {
        let clock = TestClock()
        let (store, _) = Fixture.readyStore(clock: clock)
        let state = store.state
        #expect(state.track == Fixture.track)
        #expect(state.isPlaying)
        #expect(state.position == 40)
        #expect(state.positionReportedAt == clock.now)
        #expect(state.canNext && state.canPrevious)
        #expect(!state.liked)
    }

    @Test func picturesFromThePageAreKeptByAddress() throws {
        let (store, engine) = Fixture.readyStore()
        let url = try #require(URL(string: "https://x.test/a.jpg"))
        engine.emit(.artwork(url: url, data: Data([1, 2, 3])))
        #expect(store.state.artwork[url] == Data([1, 2, 3]))
        engine.emit(.artwork(url: url, data: Data([4])))
        #expect(store.state.artwork[url] == Data([4]), "a new picture for the address replaces it")
    }

    @Test func oldPicturesGoButNeverOnesInUse() throws {
        let (store, engine) = Fixture.readyStore()
        let inUse = try #require(URL(string: "https://x.test/track.jpg"))
        engine.emit(.state(PlaybackSnapshot(track: Track(id: "t", title: "T", artist: "A", artworkURL: inUse))))
        engine.emit(.artwork(url: inUse, data: Data([1])))
        let others = (0..<PlayerStore.artworkKept + 5).map { URL(string: "https://x.test/\($0).jpg")! }
        for url in others { engine.emit(.artwork(url: url, data: Data([2]))) }
        #expect(store.state.artwork[inUse] != nil, "the track's artwork stays, though it is the oldest")
        #expect(store.state.artwork.count == PlayerStore.artworkKept)
        #expect(store.state.artwork[others[0]] == nil, "the oldest others go")
        #expect(store.state.artwork[others.last!] != nil)
    }

    @Test func listsAndModesFollowTheirEvents() {
        let (store, engine) = Fixture.readyStore()
        #expect(store.state.playlists == Fixture.playlists)
        #expect(store.state.queue == Fixture.queue)
        engine.emit(.modes(shuffle: true, repeatMode: .one), .queue([]), .playlists([]))
        #expect(store.state.shuffle)
        #expect(store.state.repeatMode == .one)
        #expect(store.state.queue.isEmpty)
        #expect(store.state.playlists.isEmpty)
    }

    @Test func modesUpdateOnlyWhatWasRead() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.modes(shuffle: true, repeatMode: .one))
        engine.emit(.modes(shuffle: nil, repeatMode: .all))
        #expect(store.state.shuffle)
        #expect(store.state.repeatMode == .all)
        engine.emit(.modes(shuffle: false, repeatMode: nil))
        #expect(!store.state.shuffle)
        #expect(store.state.repeatMode == .all)
    }

    @Test func noTrackClearsTheTrack() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.state(PlaybackSnapshot(track: nil)))
        #expect(store.state.track == nil)
        #expect(!store.state.isPlaying)
    }

    @Test func elapsedMovesOnWhilePlaying() {
        let clock = TestClock()
        let (store, _) = Fixture.readyStore(clock: clock)
        #expect(store.state.elapsed(at: clock.now.addingTimeInterval(1.5)) == 41.5)
    }

    @Test func elapsedStopsAtTheDuration() {
        let clock = TestClock()
        let (store, _) = Fixture.readyStore(clock: clock)
        #expect(store.state.elapsed(at: clock.now.addingTimeInterval(500)) == 200)
    }

    @Test func elapsedHoldsWhilePaused() {
        let clock = TestClock()
        let (store, engine) = Fixture.readyStore(clock: clock)
        var snapshot = Fixture.playing
        snapshot.isPlaying = false
        engine.emit(.state(snapshot))
        #expect(store.state.elapsed(at: clock.now.addingTimeInterval(30)) == 40)
    }

    @Test func playlistsAreKeptWhenTheSidebarCantBeRead() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.health(missing: [.playlists]))
        #expect(store.state.playlists == Fixture.playlists)
        #expect(store.state.showsPlaylistsView)
    }

    @Test func playlistsViewHidesWithNoList() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.playlists([]))
        #expect(!store.state.showsPlaylistsView)
    }

    @Test func queueViewHidesWhenTheQueueCantBeRead() {
        let (store, engine) = Fixture.readyStore()
        #expect(store.state.showsQueueView)
        engine.emit(.health(missing: [.queue]))
        #expect(!store.state.showsQueueView)
    }

    @Test func queueViewHidesWhenEmpty() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.queue([]))
        #expect(!store.state.showsQueueView)
    }

    @Test func everyFeatureIsAvailableWhenHealthy() {
        let (store, _) = Fixture.readyStore()
        for feature in Feature.allCases {
            #expect(store.state.isAvailable(feature), "\(feature)")
        }
    }

    @Test(arguments: Feature.allCases)
    func missingFeatureIsUnavailable(feature: Feature) {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.health(missing: [feature]))
        #expect(!store.state.isAvailable(feature))
    }

    @Test func nothingIsAvailableWhileOffline() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.offline)
        for feature in Feature.allCases {
            #expect(!store.state.isAvailable(feature), "\(feature)")
        }
    }

    @Test func repeatedSnapshotDoesNotRedrawTheTrack() {
        let (store, engine) = Fixture.readyStore()
        let changed = Flag()
        withObservationTracking {
            _ = store.state.track
            _ = store.state.isPlaying
        } onChange: {
            changed.isSet = true
        }
        engine.emit(.state(Fixture.playing))
        #expect(!changed.isSet)
    }

    @Test func newTrackRedraws() {
        let (store, engine) = Fixture.readyStore()
        let changed = Flag()
        withObservationTracking {
            _ = store.state.track
        } onChange: {
            changed.isSet = true
        }
        var snapshot = Fixture.playing
        snapshot.track = Fixture.otherTrack
        engine.emit(.state(snapshot))
        #expect(changed.isSet)
    }
}
