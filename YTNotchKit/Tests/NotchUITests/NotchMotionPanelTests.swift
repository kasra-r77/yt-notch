import AppKit
import Foundation
import PlayerCore
import Testing
@testable import NotchUI

/// A panel driven by a real store on FakeEngine, its pointer and a clock the test owns.
@MainActor
@Suite(.serialized)
struct NotchMotionPanelTests {
    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    let pointer = PointerTracker()
    let clock = Clock()
    let engine = FakeEngine()
    let store: PlayerStore

    // On the external display the pill's centre is at x 2408 and the top edge at y 1120.
    static let insidePill = CGPoint(x: 2408, y: 1110)
    static let belowEverything = CGPoint(x: 2408, y: 700)

    init() {
        _ = NSApplication.shared
        store = PlayerStore(engine: engine)
    }

    func panel() -> NotchPanel {
        let panel = NotchPanel(screen: Displays.external, store: store, pointer: pointer)
        panel.schedulesTicks = false
        panel.now = { [clock] in clock.now }
        return panel
    }

    static func eventually(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting until \(what)")
    }

    @Test func playbackBringsOutTheWings() async throws {
        let panel = panel()
        defer { panel.close() }
        #expect(panel.machine.appearance == .collapsed(.idle))
        store.play()
        try await Self.eventually("playing") { panel.machine.appearance == .collapsed(.playing) }
        #expect(panel.model.outline == NotchLayout.outline(for: .collapsed(.playing), on: Displays.external))
        #expect(panel.model.wingsShown)
        #expect(panel.model.isPlaying)
    }

    @Test func restingInsideOpensAfterTheDwellAndLeavingClosesAfterTheGrace() async throws {
        let panel = panel()
        defer { panel.close() }
        store.play()
        try await Self.eventually("playing") { panel.machine.appearance == .collapsed(.playing) }

        pointer.deliver(Self.insidePill)
        #expect(panel.machine.phase == .dwell(since: clock.now))
        clock.advance(Tokens.Timing.dwell)
        panel.tick(at: clock.now)
        #expect(panel.machine.appearance == .expanded(.view(.playing)))
        #expect(panel.model.outline.height == Tokens.Size.expandedPlayingHeight)
        #expect(panel.model.contentShown)
        #expect(!panel.model.wingsShown)
        #expect(!panel.window.ignoresMouseEvents)

        pointer.deliver(Self.belowEverything)
        #expect(panel.window.ignoresMouseEvents)
        clock.advance(Tokens.Timing.grace)
        panel.tick(at: clock.now)
        #expect(panel.machine.appearance == .collapsed(.playing))
        #expect(panel.model.outline == NotchLayout.outline(for: .collapsed(.playing), on: Displays.external))
    }

    @Test func aTrackChangePeeksWithTheNewTitle() async throws {
        let panel = panel()
        defer { panel.close() }
        store.play()
        try await Self.eventually("playing") { panel.machine.appearance == .collapsed(.playing) }
        let first = store.state.track?.title
        store.next()
        try await Self.eventually("peeking") { panel.machine.appearance == .collapsed(.peek) }
        #expect(panel.model.title != first)
        #expect(panel.model.outline.height == Displays.external.band + Tokens.Size.peekRow)
        #expect(panel.model.peekShown)
    }

    @Test func signedOutOpensOnTheMessage() async throws {
        let panel = panel()
        defer { panel.close() }
        engine.simulateSignedOut()
        try await Self.eventually("needs attention") { panel.machine.needsAttention }
        pointer.deliver(Self.insidePill)
        clock.advance(Tokens.Timing.dwell)
        panel.tick(at: clock.now)
        #expect(panel.machine.appearance == .expanded(.message))
        #expect(panel.model.outline.height == Tokens.Size.expandedPlayingHeight)
    }

    @Test func fullScreenClosesAtOnceAndHides() async throws {
        let panel = panel()
        defer { panel.close() }
        store.play()
        try await Self.eventually("playing") { panel.machine.appearance == .collapsed(.playing) }
        pointer.deliver(Self.insidePill)
        clock.advance(Tokens.Timing.dwell)
        panel.tick(at: clock.now)
        #expect(panel.machine.isExpanded)

        panel.setFullScreen(true)
        #expect(panel.machine.appearance == .hidden)
        #expect(panel.model.isHidden)
        #expect(!panel.model.contentShown)
        #expect(panel.window.ignoresMouseEvents)
    }

    @Test func switchingToAListResizes() async throws {
        let panel = panel()
        defer { panel.close() }
        pointer.deliver(Self.insidePill)
        clock.advance(Tokens.Timing.dwell)
        panel.tick(at: clock.now)
        panel.select(.upNext)
        #expect(panel.machine.appearance == .expanded(.view(.upNext)))
        #expect(panel.model.outline.height == Tokens.Size.expandedListHeight)
    }

    @Test func withoutArtworkTheAccentIsWhite() async throws {
        let panel = panel()
        defer { panel.close() }
        store.play()
        try await Self.eventually("playing") { panel.model.isPlaying }
        #expect(store.state.track?.artworkURL == nil)
        #expect(panel.model.artwork == nil)
        #expect(panel.model.accent == .white)
    }
}
