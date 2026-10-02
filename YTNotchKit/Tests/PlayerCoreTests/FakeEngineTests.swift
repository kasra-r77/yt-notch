import Testing
@testable import PlayerCore

@MainActor
struct FakeEngineTests {
    let engine = FakeEngine()
    let store: PlayerStore

    init() {
        store = PlayerStore(engine: engine)
    }

    var liked: [Track] { FakeEngine.sample[0].tracks }

    @Test func startsLikeALoadedPage() {
        let state = store.state
        #expect(state.health == Health(status: .ok))
        #expect(state.bridgeVersion == FakeEngine.bridgeVersion)
        #expect(state.playlists.map(\.id) == FakeEngine.sample.map(\.item.id))
        #expect(state.playlists.first?.isLikedMusic == true)
        #expect(state.playlistID == "LM")
        #expect(state.queue.count == liked.count)
        #expect(state.queue.first?.isCurrent == true)
        #expect(state.track == liked[0])
        #expect(!state.isPlaying)
        #expect(state.shuffle == false && state.repeatMode == .off)
    }

    @Test func signedOutPage() {
        let store = PlayerStore(engine: FakeEngine(signedIn: false))
        #expect(store.state.health.status == .signedOut)
        #expect(store.state.track == nil)
    }

    @Test func nextMovesThroughTheQueue() {
        store.next()
        #expect(store.state.track == liked[1])
        #expect(store.state.queue[1].isCurrent && !store.state.queue[0].isCurrent)
        #expect(store.state.position == 0)
    }

    @Test func nextStopsAtTheEndUnlessRepeatAll() {
        store.playQueueItem(index: liked.count - 1)
        #expect(!store.state.canNext)
        store.next()
        #expect(engine.receivedCommands.last == .playQueueItem(index: liked.count - 1))
        store.setRepeat(.all)
        #expect(store.state.canNext)
        store.next()
        #expect(store.state.track == liked[0])
    }

    @Test func previousGoesBackEarlyInATrack() {
        store.next()
        engine.send(.seek(to: 2))
        store.previous()
        #expect(store.state.track == liked[0])
    }

    @Test func previousRestartsLaterInATrack() {
        store.next()
        store.seek(to: 60)
        store.previous()
        #expect(store.state.track == liked[1])
        #expect(store.state.position == 0)
    }

    @Test func queueItemsCarryTheirLengthAndArtwork() {
        #expect(store.state.queue.map(\.duration) == liked.map(\.duration))
        #expect(store.state.queue.map(\.artworkURL) == liked.map(\.artworkURL))
    }

    @Test func thePlaylistPlayingNowIsReported() {
        #expect(store.state.playlistID == "LM")
        store.playPlaylist(id: "PLfake-focus")
        #expect(store.state.playlistID == "PLfake-focus")
    }

    @Test func playPlaylist() {
        store.playPlaylist(id: "PLfake-focus")
        #expect(store.state.track == FakeEngine.sample[1].tracks[0])
        #expect(store.state.isPlaying)
        #expect(store.state.queue.map(\.title) == FakeEngine.sample[1].tracks.map(\.title))
    }

    @Test func playQueueItem() {
        store.playQueueItem(index: 3)
        #expect(store.state.track == liked[3])
        #expect(store.state.isPlaying)
        #expect(store.state.queue.filter(\.isCurrent).map(\.index) == [3])
    }

    @Test func shuffleKeepsTheCurrentTrackAndRestoresTheOrder() {
        store.playQueueItem(index: 2)
        let original = store.state.queue.map(\.title)

        store.setShuffle(true)
        #expect(store.state.shuffle)
        #expect(store.state.track == liked[2])
        #expect(store.state.queue.map(\.title) != original)
        #expect(Set(store.state.queue.map(\.title)) == Set(original))
        #expect(store.state.queue.first?.isCurrent == true)

        store.setShuffle(false)
        #expect(!store.state.shuffle)
        #expect(store.state.queue.map(\.title) == original)
        #expect(store.state.track == liked[2])
        #expect(store.state.queue[2].isCurrent)
    }

    @Test func repeatCycles() {
        store.cycleRepeat()
        #expect(store.state.repeatMode == .all)
        store.cycleRepeat()
        #expect(store.state.repeatMode == .one)
        store.cycleRepeat()
        #expect(store.state.repeatMode == .off)
    }

    @Test func timeMovesOnWhilePlaying() {
        engine.advance(by: 10)
        #expect(store.state.position == 0)
        store.play()
        engine.advance(by: 10)
        #expect(store.state.position == 10)
    }

    @Test func trackEndGoesToTheNextTrack() {
        store.play()
        engine.advance(by: liked[0].duration! + 1)
        #expect(store.state.track == liked[1])
        #expect(store.state.isPlaying)
    }

    @Test func repeatOneReplaysTheTrack() {
        store.setRepeat(.one)
        store.play()
        engine.advance(by: liked[0].duration! + 1)
        #expect(store.state.track == liked[0])
        #expect(store.state.position == 0)
    }

    @Test func queueEndStops() {
        store.playQueueItem(index: liked.count - 1)
        engine.advance(by: liked.last!.duration! + 1)
        #expect(!store.state.isPlaying)
        #expect(store.state.track == liked.last)
    }

    @Test func simulatedFailures() {
        engine.simulateMissing([.like])
        #expect(store.state.health.missing == [.like])
        engine.simulateOffline()
        #expect(store.state.health.status == .offline)
        engine.simulateBridgeBroken()
        #expect(store.state.health.status == .bridgeBroken)
        engine.simulateReload()
        #expect(store.state.health == Health(status: .ok))
        engine.simulateSignedOut()
        #expect(store.state.health.status == .signedOut)
        engine.simulateReload(signedIn: true)
        #expect(store.state.health.status == .ok)
    }
}
