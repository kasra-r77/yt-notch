import Testing
@testable import PlayerCore

@MainActor
struct StoreCommandTests {
    enum Intent: CaseIterable, CustomTestStringConvertible {
        case play, pause, togglePlayPause, next, previous, seek, setLiked, toggleLike
        case playPlaylist, playQueueItem, setShuffle, toggleShuffle, setRepeat, cycleRepeat

        var testDescription: String { "\(self)" }

        @MainActor
        func perform(on store: PlayerStore) {
            switch self {
            case .play: store.play()
            case .pause: store.pause()
            case .togglePlayPause: store.togglePlayPause()
            case .next: store.next()
            case .previous: store.previous()
            case .seek: store.seek(to: 90)
            case .setLiked: store.setLiked(true)
            case .toggleLike: store.toggleLike()
            case .playPlaylist: store.playPlaylist(id: "PL1")
            case .playQueueItem: store.playQueueItem(index: 1)
            case .setShuffle: store.setShuffle(true)
            case .toggleShuffle: store.toggleShuffle()
            case .setRepeat: store.setRepeat(.one)
            case .cycleRepeat: store.cycleRepeat()
            }
        }

        /// The command each intent sends from `Fixture.readyStore()`.
        var expected: PlayerCommand {
            switch self {
            case .play: .play
            case .pause: .pause
            case .togglePlayPause: .toggle
            case .next: .next
            case .previous: .previous
            case .seek: .seek(to: 90)
            case .setLiked: .setLiked(true)
            case .toggleLike: .setLiked(true)
            case .playPlaylist: .playPlaylist(id: "PL1")
            case .playQueueItem: .playQueueItem(index: 1)
            case .setShuffle: .setShuffle(true)
            case .toggleShuffle: .setShuffle(true)
            case .setRepeat: .setRepeat(.one)
            case .cycleRepeat: .setRepeat(.all)
            }
        }
    }

    @Test(arguments: Intent.allCases)
    func intentSendsItsCommand(intent: Intent) {
        let (store, engine) = Fixture.readyStore()
        intent.perform(on: store)
        #expect(engine.sent == [intent.expected])
    }

    @Test(arguments: Intent.allCases)
    func intentNeverChangesStateByItself(intent: Intent) {
        let (store, _) = Fixture.readyStore()
        let before = (store.state.isPlaying, store.state.liked, store.state.shuffle, store.state.repeatMode, store.state.position, store.state.track)
        intent.perform(on: store)
        let after = (store.state.isPlaying, store.state.liked, store.state.shuffle, store.state.repeatMode, store.state.position, store.state.track)
        #expect(before == after)
    }

    @Test(arguments: [Health.Status.starting, .signedOut, .offline, .bridgeBroken])
    func nothingIsSentUnlessHealthIsOK(status: Health.Status) {
        let (store, engine) = Fixture.readyStore()
        switch status {
        case .starting: engine.emit(.ready(bridgeVersion: "1", signedIn: true)); store.state.health.status = .starting
        case .signedOut: engine.emit(.signedOut)
        case .offline: engine.emit(.offline)
        case .bridgeBroken: engine.emit(.bridgeBroken)
        case .ok: break
        }
        for intent in Intent.allCases { intent.perform(on: store) }
        #expect(engine.sent.isEmpty)
    }

    @Test(arguments: [
        (Feature.playPause, Intent.play), (.playPause, .pause), (.playPause, .togglePlayPause),
        (.next, .next), (.previous, .previous), (.seek, .seek),
        (.like, .setLiked), (.like, .toggleLike),
        (.shuffle, .setShuffle), (.shuffle, .toggleShuffle),
        (.repeatMode, .setRepeat), (.repeatMode, .cycleRepeat),
        (.queue, .playQueueItem),
    ])
    func missingFeatureDropsItsCommand(feature: Feature, intent: Intent) {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.health(missing: [feature]))
        intent.perform(on: store)
        #expect(engine.sent.isEmpty)
    }

    @Test func playlistsStillStartWhileTheSidebarCantBeRead() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.health(missing: [.playlists]))
        store.playPlaylist(id: "LM")
        #expect(engine.sent == [.playPlaylist(id: "LM")])
    }

    @Test func unknownPlaylistIsDropped() {
        let (store, engine) = Fixture.readyStore()
        store.playPlaylist(id: "nope")
        #expect(engine.sent.isEmpty)
    }

    @Test(arguments: [-1, 2, 99])
    func unknownQueueIndexIsDropped(index: Int) {
        let (store, engine) = Fixture.readyStore()
        store.playQueueItem(index: index)
        #expect(engine.sent.isEmpty)
    }

    @Test func nextNeedsANextTrack() {
        let (store, engine) = Fixture.readyStore()
        var snapshot = Fixture.playing
        snapshot.canNext = false
        engine.emit(.state(snapshot))
        store.next()
        #expect(engine.sent.isEmpty)
    }

    @Test func previousNeedsAPreviousTrack() {
        let (store, engine) = Fixture.readyStore()
        var snapshot = Fixture.playing
        snapshot.canPrevious = false
        engine.emit(.state(snapshot))
        store.previous()
        #expect(engine.sent.isEmpty)
    }

    @Test(arguments: [Intent.play, .pause, .togglePlayPause, .seek, .setLiked, .toggleLike])
    func trackCommandsNeedATrack(intent: Intent) {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.state(PlaybackSnapshot(track: nil)))
        intent.perform(on: store)
        #expect(engine.sent.isEmpty)
    }

    @Test func seekNeedsADuration() {
        let (store, engine) = Fixture.readyStore()
        var snapshot = Fixture.playing
        snapshot.track?.duration = nil
        engine.emit(.state(snapshot))
        store.seek(to: 10)
        #expect(engine.sent.isEmpty)
    }

    @Test(arguments: [(-5.0, 0.0), (0, 0), (120, 120), (200, 200), (999, 200)])
    func seekIsClampedToTheTrack(target: Double, sent: Double) {
        let (store, engine) = Fixture.readyStore()
        store.seek(to: target)
        #expect(engine.sent == [.seek(to: sent)])
    }

    @Test func toggleLikeUnlikesALikedTrack() {
        let (store, engine) = Fixture.readyStore()
        var snapshot = Fixture.playing
        snapshot.liked = true
        engine.emit(.state(snapshot))
        store.toggleLike()
        #expect(engine.sent == [.setLiked(false)])
    }

    @Test func toggleShuffleTurnsItOff() {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.modes(shuffle: true, repeatMode: .off))
        store.toggleShuffle()
        #expect(engine.sent == [.setShuffle(false)])
    }

    @Test(arguments: [(RepeatMode.off, RepeatMode.all), (.all, .one), (.one, .off)])
    func cycleRepeatFollowsTheButton(from: RepeatMode, to: RepeatMode) {
        let (store, engine) = Fixture.readyStore()
        engine.emit(.modes(shuffle: false, repeatMode: from))
        store.cycleRepeat()
        #expect(engine.sent == [.setRepeat(to)])
    }
}
