import AppKit
import Foundation
import PlayerCore
import SwiftUI
import Testing
@testable import NotchUI

/// The Playing view: what it shows comes only from the store, and every control drives the
/// engine through the store.
@MainActor
@Suite(.serialized)
struct PlayingViewTests {
    /// An engine that records commands and never answers them, like a page that ignores us.
    final class SilentEngine: PlayerEngine {
        var sent: [PlayerCommand] = []
        private var onEvent: (@MainActor (PlayerEvent) -> Void)?

        func start(onEvent: @escaping @MainActor (PlayerEvent) -> Void) {
            self.onEvent = onEvent
        }

        func send(_ command: PlayerCommand) { sent.append(command) }

        func report(_ event: PlayerEvent) { onEvent?(event) }
    }

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() {
        _ = NSApplication.shared
    }

    func presentation(_ store: PlayerStore) -> PlayingPresentation {
        PlayingPresentation(store.state, at: now)
    }

    @Test func timesAreMinutesAndSeconds() {
        #expect(PlayingPresentation.time(0) == "0:00")
        #expect(PlayingPresentation.time(72.9) == "1:12")
        #expect(PlayingPresentation.time(225) == "3:45")
        #expect(PlayingPresentation.time(3723) == "1:02:03")
        #expect(PlayingPresentation.time(-3) == "0:00")
    }

    @Test func aPausedTrackFromFakeEngine() {
        let store = PlayerStore(engine: FakeEngine())
        let p = presentation(store)
        #expect(p.hasTrack)
        #expect(p.title == store.state.track?.title)
        #expect(p.artist == store.state.track?.artist)
        #expect(p.help == "\(p.title) — \(p.artist)")
        #expect(p.playSymbol == Tokens.Symbol.play)
        #expect(p.playLabel == "Play")
        #expect(p.elapsed == "0:00")
        #expect(p.total == PlayingPresentation.time(store.state.track?.duration ?? 0))
        #expect(p.canPlayPause && p.canSeek && p.canLike)
        #expect(p.showsShuffle && p.showsRepeat)
    }

    @Test func beforeTheFirstTrackEverythingWaits() {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        let p = presentation(store)
        #expect(!p.hasTrack)
        #expect(p.elapsed == "0:00")
        #expect(p.total == PlayingPresentation.unknownTime)
        #expect(!p.canPlayPause && !p.canNext && !p.canPrevious && !p.canSeek && !p.canLike)
    }

    @Test func missingShuffleAndRepeatAreHiddenNotDimmed() {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        engine.simulateMissing([.shuffle, .repeatMode, .like])
        let p = presentation(store)
        #expect(!p.showsShuffle && !p.showsRepeat)
        #expect(!p.canLike, "like dims")
    }

    @Test func playAndPause() {
        let store = PlayerStore(engine: FakeEngine())
        let actions = NotchActions(store: store)
        actions.togglePlayPause()
        #expect(presentation(store).playSymbol == Tokens.Symbol.pause)
        #expect(presentation(store).playLabel == "Pause")
        actions.togglePlayPause()
        #expect(presentation(store).playSymbol == Tokens.Symbol.play)
    }

    @Test func nextAndPrevious() {
        let store = PlayerStore(engine: FakeEngine())
        let actions = NotchActions(store: store)
        let first = presentation(store).title
        actions.next()
        #expect(presentation(store).title != first)
        actions.previous()
        #expect(presentation(store).title == first)
    }

    @Test func like() {
        let store = PlayerStore(engine: FakeEngine())
        let actions = NotchActions(store: store)
        let before = presentation(store).liked
        actions.toggleLike()
        #expect(presentation(store).liked == !before)
        #expect(presentation(store).likeSymbol == (before ? Tokens.Symbol.like : Tokens.Symbol.liked))
    }

    @Test func shuffleAndRepeat() {
        let store = PlayerStore(engine: FakeEngine())
        let actions = NotchActions(store: store)
        actions.toggleShuffle()
        #expect(presentation(store).shuffleOn)
        actions.cycleRepeat()
        #expect(presentation(store).repeatOn)
        #expect(presentation(store).repeatSymbol == Tokens.Symbol.repeat)
        #expect(presentation(store).repeatLabel == "Repeat All")
        actions.cycleRepeat()
        #expect(presentation(store).repeatSymbol == Tokens.Symbol.repeatOne)
        actions.cycleRepeat()
        #expect(!presentation(store).repeatOn)
    }

    @Test func seekByFraction() throws {
        let store = PlayerStore(engine: FakeEngine())
        let actions = NotchActions(store: store)
        let duration = try #require(store.state.track?.duration)
        actions.seek(toFraction: 0.5)
        #expect(abs(store.state.position - duration / 2) < 0.5)
        #expect(abs(presentation(store).progress - 0.5) < 0.01)
        actions.seek(toFraction: 2)
        #expect(abs(store.state.position - duration) < 0.5, "clamped to the end")
    }

    @Test func nothingChangesUntilThePlayerSaysSo() {
        let engine = SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        let track = Track(id: "t", title: "Title", artist: "Artist", duration: 200)
        engine.report(.state(PlaybackSnapshot(track: track, position: 10, isPlaying: false, canNext: true, canPrevious: true, liked: false)))
        let actions = NotchActions(store: store)
        let before = presentation(store)

        actions.togglePlayPause()
        actions.toggleLike()
        actions.next()
        actions.seek(toFraction: 0.9)
        #expect(engine.sent.count == 4, "the commands went out")
        #expect(presentation(store) == before, "but nothing shows as done")

        engine.report(.state(PlaybackSnapshot(track: track, position: 10, isPlaying: true, canNext: true, canPrevious: true, liked: true)))
        #expect(presentation(store).playSymbol == Tokens.Symbol.pause)
        #expect(presentation(store).liked)
    }

    @Test func drawsTheViewOnBlack() throws {
        let store = PlayerStore(engine: FakeEngine())
        let model = NotchModel(outline: NotchLayout.outline(for: .expanded(.view(.playing)), on: Displays.macBookPro14), band: 32)
        model.actions = NotchActions(store: store)
        let view = ZStack(alignment: .topLeading) {
            Tokens.Color.surface
            PlayingView(state: store.state, model: model, actions: model.actions, extra: 0)
        }
        .frame(width: 400, height: 148)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixels = try Pixels(image)
        #expect(image.width == 400 && image.height == 148)
        // The artwork placeholder at (16, 48) to (100, 132) is white 8% on black.
        let placeholder = pixels.at(x: 20, y: 52)
        #expect(placeholder.r > 10 && placeholder.r < 40)
        // The title's line has white text somewhere along it.
        let titleRow = (116..<380).map { pixels.at(x: $0, y: 56) }
        #expect(titleRow.contains { $0.r > 200 })
    }
}
