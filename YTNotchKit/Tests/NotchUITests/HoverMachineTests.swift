import Foundation
import Testing
@testable import NotchUI

/// Every row of the transitions table and every rule in the spec's "Motion → Hover"
/// section. Times come from the tokens; only `theTimingsAreTheSpecs` names the numbers.
struct HoverMachineTests {
    typealias T = Tokens.Timing
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// `seconds` after the start.
    static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Just short of a timing.
    static let justBefore: TimeInterval = 0.001

    /// A notch showing Playing, collapsed.
    static func playing() -> HoverMachine {
        var machine = HoverMachine()
        machine.playback(hasTrack: true, isPlaying: true)
        return machine
    }

    /// Open at `opensAt`, with the pointer inside.
    static func expanded(from machine: HoverMachine = playing(), opensAt time: TimeInterval = T.dwell) -> HoverMachine {
        var machine = machine
        machine.pointer(inside: true, buttonDown: false, at: at(time - T.dwell))
        machine.tick(at: at(time))
        return machine
    }

    /// Peeking, fully out at `outAt`.
    static func peeking(outAt time: TimeInterval = 0) -> HoverMachine {
        var machine = playing()
        machine.trackChanged(at: at(time - 0.3))
        machine.peekFullyOut(at: at(time))
        return machine
    }

    // MARK: Timings

    @Test func theTimingsAreTheSpecs() {
        #expect(HoverMachine().timing == .tokens)
        #expect(HoverMachine.Timing.tokens == HoverMachine.Timing(dwell: 0.15, grace: 0.4, peekHold: 2.5, reopenMemory: 10))
    }

    // MARK: Transitions table

    @Test func idleBecomesPlayingWhenPlaybackStarts() {
        var machine = HoverMachine()
        #expect(machine.appearance == .collapsed(.idle))
        machine.playback(hasTrack: true, isPlaying: false)
        #expect(machine.appearance == .collapsed(.idle), "a loaded, paused track is not playback starting")
        machine.playback(hasTrack: true, isPlaying: true)
        #expect(machine.appearance == .collapsed(.playing))
    }

    @Test func playingBecomesIdleOnlyWhenNoTrackIsLoaded() {
        var machine = Self.playing()
        machine.playback(hasTrack: true, isPlaying: false)
        #expect(machine.appearance == .collapsed(.playing), "pausing keeps Playing")
        machine.playback(hasTrack: false, isPlaying: false)
        #expect(machine.appearance == .collapsed(.idle))
    }

    @Test(arguments: [HoverMachine.Collapsed.idle, .playing, .peek])
    func restingInsideStartsTheDwell(from collapsed: HoverMachine.Collapsed) {
        var machine = switch collapsed {
        case .idle: HoverMachine()
        case .playing: Self.playing()
        case .peek: Self.peeking()
        }
        machine.pointer(inside: true, buttonDown: false, at: Self.at(1))
        #expect(machine.phase == .dwell(since: Self.at(1)))
        #expect(machine.appearance == .collapsed(collapsed), "nothing moves during the dwell")
        #expect(machine.nextDeadline == Self.at(1 + T.dwell))
    }

    @Test func theDwellOpensTheNotchWhenItHasPassed() {
        var machine = Self.playing()
        machine.pointer(inside: true, buttonDown: false, at: Self.at(0))
        machine.tick(at: Self.at(T.dwell - Self.justBefore))
        #expect(!machine.isExpanded)
        machine.tick(at: Self.at(T.dwell))
        #expect(machine.phase == .expanded)
        #expect(machine.appearance == .expanded(.view(.playing)))
        #expect(machine.nextDeadline == nil)
    }

    @Test(arguments: [HoverMachine.Collapsed.idle, .playing, .peek])
    func leavingBeforeTheDwellGoesBackWithNothingMoving(from collapsed: HoverMachine.Collapsed) {
        var machine = switch collapsed {
        case .idle: HoverMachine()
        case .playing: Self.playing()
        case .peek: Self.peeking()
        }
        machine.pointer(inside: true, buttonDown: false, at: Self.at(0.5))
        machine.pointer(inside: false, buttonDown: false, at: Self.at(0.5 + T.dwell - Self.justBefore))
        machine.tick(at: Self.at(0.5 + T.dwell))
        #expect(machine.phase == .collapsed)
        #expect(machine.appearance == .collapsed(collapsed))
    }

    @Test func leavingTheOpenNotchStartsTheGrace() {
        var machine = Self.expanded()
        machine.pointer(inside: false, buttonDown: false, at: Self.at(2))
        #expect(machine.phase == .grace(since: Self.at(2)))
        #expect(machine.appearance == .expanded(.view(.playing)), "still open during the grace")
        #expect(machine.nextDeadline == Self.at(2 + T.grace))
    }

    @Test func comingBackDuringTheGraceCancelsIt() {
        var machine = Self.expanded()
        machine.pointer(inside: false, buttonDown: false, at: Self.at(2))
        machine.pointer(inside: true, buttonDown: false, at: Self.at(2 + T.grace - Self.justBefore))
        #expect(machine.phase == .expanded)
        machine.tick(at: Self.at(2 + T.grace))
        #expect(machine.phase == .expanded)
    }

    @Test func theGraceClosesTheNotchToPlayingOrIdle() {
        var playing = Self.expanded()
        playing.pointer(inside: false, buttonDown: false, at: Self.at(2))
        playing.tick(at: Self.at(2 + T.grace - Self.justBefore))
        #expect(playing.isExpanded)
        playing.tick(at: Self.at(2 + T.grace))
        #expect(playing.appearance == .collapsed(.playing))

        var idle = Self.expanded(from: HoverMachine())
        idle.pointer(inside: false, buttonDown: false, at: Self.at(2))
        idle.tick(at: Self.at(2 + T.grace))
        #expect(idle.appearance == .collapsed(.idle))
    }

    @Test func aTrackChangeWhilePlayingCollapsedPeeksAndHoldsFromFullyOut() {
        var machine = Self.playing()
        machine.trackChanged(at: Self.at(0))
        #expect(machine.appearance == .collapsed(.peek))
        #expect(machine.nextDeadline == nil, "the hold starts once the peek is fully out")
        machine.peekFullyOut(at: Self.at(0.4))
        machine.tick(at: Self.at(0.4 + T.peekHold - Self.justBefore))
        #expect(machine.appearance == .collapsed(.peek))
        machine.tick(at: Self.at(0.4 + T.peekHold))
        #expect(machine.appearance == .collapsed(.playing))
    }

    @Test func anotherTrackChangeDuringAPeekRestartsTheHold() {
        var machine = Self.peeking(outAt: 0)
        machine.trackChanged(at: Self.at(2))
        #expect(machine.appearance == .collapsed(.peek))
        #expect(machine.nextDeadline == Self.at(2 + T.peekHold))
        machine.tick(at: Self.at(T.peekHold))
        #expect(machine.appearance == .collapsed(.peek), "the first hold no longer counts")
    }

    @Test func restingOnAPeekOpensFromItAndDropsItsTimer() {
        var machine = Self.peeking(outAt: 0)
        machine.pointer(inside: true, buttonDown: false, at: Self.at(2.45))
        // The peek's hold would have ended at 2.5; the dwell's deadline is what counts now.
        #expect(machine.nextDeadline == Self.at(2.45 + T.dwell))
        machine.tick(at: Self.at(T.peekHold))
        #expect(machine.appearance == .collapsed(.peek))
        machine.tick(at: Self.at(2.45 + T.dwell))
        #expect(machine.appearance == .expanded(.view(.playing)))
        #expect(machine.collapsed == .playing, "it closes back to Playing, not the peek")
    }

    @Test func signedOutOrBridgeBrokenShowsTheMessageOnTheNextHover() {
        var machine = Self.playing()
        machine.attention(true)
        #expect(machine.appearance == .collapsed(.playing), "it doesn't open by itself")
        machine = Self.expanded(from: machine)
        #expect(machine.appearance == .expanded(.message))
        machine.attention(false)
        #expect(machine.appearance == .expanded(.view(.playing)))
    }

    @Test func fullScreenClosesAtOnceWithNoGrace() {
        var machine = Self.expanded()
        machine.fullScreen(true, at: Self.at(3))
        #expect(machine.appearance == .hidden)
        #expect(machine.phase == .collapsed)
        #expect(machine.nextDeadline == nil)

        machine.pointer(inside: true, buttonDown: false, at: Self.at(4))
        #expect(machine.phase == .collapsed, "hovering does nothing while full screen")

        machine.fullScreen(false, at: Self.at(5))
        #expect(machine.appearance == .collapsed(.playing))
    }

    @Test func fullScreenEndsADwellAndAPeek() {
        var dwelling = Self.playing()
        dwelling.pointer(inside: true, buttonDown: false, at: Self.at(0))
        dwelling.fullScreen(true, at: Self.at(0.1))
        dwelling.tick(at: Self.at(1))
        #expect(dwelling.phase == .collapsed)

        var peeking = Self.peeking()
        peeking.fullScreen(true, at: Self.at(1))
        peeking.fullScreen(false, at: Self.at(2))
        #expect(peeking.appearance == .collapsed(.playing))
    }

    // MARK: Rules

    @Test func movingWithinTheShapeDoesNotRestartTheDwell() {
        var machine = Self.playing()
        machine.pointer(inside: true, buttonDown: false, at: Self.at(0))
        machine.pointer(inside: true, buttonDown: false, at: Self.at(T.dwell / 2))
        #expect(machine.phase == .dwell(since: Self.at(0)))
        machine.tick(at: Self.at(T.dwell))
        #expect(machine.isExpanded)
    }

    @Test func itReopensOnPlayingUnlessItClosedRecently() {
        var machine = Self.expanded()
        machine.select(.upNext)
        machine.resizeSettled(at: Self.at(1))
        machine.pointer(inside: false, buttonDown: false, at: Self.at(2))
        machine.tick(at: Self.at(2 + T.grace))
        let closedAt = 2 + T.grace

        // Back within the memory: the view it closed on.
        machine = Self.expanded(from: machine, opensAt: closedAt + T.reopenMemory - 1)
        #expect(machine.appearance == .expanded(.view(.upNext)))

        // Closed again, and back after the memory has run out: Playing.
        machine.pointer(inside: false, buttonDown: false, at: Self.at(20))
        machine.tick(at: Self.at(20 + T.grace))
        machine = Self.expanded(from: machine, opensAt: 20 + T.grace + T.reopenMemory)
        #expect(machine.appearance == .expanded(.view(.playing)))
    }

    @Test func switchingViewsNeverClosesAndTheGraceWaitsForTheResize() {
        var machine = Self.expanded()
        machine.select(.playlists)
        // Playing (148) to a list (300) and back: the shrink can leave the pointer outside.
        machine.select(.upNext)
        #expect(machine.appearance == .expanded(.view(.upNext)), "Playlists to Up next doesn't close it")
        machine.resizeSettled(at: Self.at(1))
        machine.select(.playing)
        machine.pointer(inside: false, buttonDown: false, at: Self.at(1.1))
        machine.tick(at: Self.at(5))
        #expect(machine.phase == .expanded, "no grace while the shape resizes")
        machine.resizeSettled(at: Self.at(5.2))
        #expect(machine.phase == .grace(since: Self.at(5.2)))

        // If the pointer is still inside when the resize settles, nothing starts.
        var inside = Self.expanded()
        inside.select(.playlists)
        inside.resizeSettled(at: Self.at(1))
        #expect(inside.phase == .expanded)
    }

    @Test func aHeldMouseButtonDoesNotStartTheDwell() {
        var machine = Self.playing()
        machine.pointer(inside: true, buttonDown: true, at: Self.at(0))
        machine.tick(at: Self.at(1))
        #expect(machine.phase == .collapsed)
        // Let go inside the shape: now it rests there.
        machine.pointer(inside: true, buttonDown: false, at: Self.at(1))
        #expect(machine.phase == .dwell(since: Self.at(1)))
    }

    @Test func aPeekNeverStartsWhileOpenFullScreenOrIdle() {
        var open = Self.expanded()
        open.trackChanged(at: Self.at(1))
        #expect(open.collapsed == .playing)

        var fullScreen = Self.playing()
        fullScreen.fullScreen(true, at: Self.at(0))
        fullScreen.trackChanged(at: Self.at(1))
        #expect(fullScreen.collapsed == .playing)

        var idle = HoverMachine()
        idle.trackChanged(at: Self.at(1))
        #expect(idle.collapsed == .idle)
    }

    @Test func eachDisplaysMachineIsItsOwn() {
        var builtIn = Self.playing()
        let external = builtIn
        builtIn = Self.expanded(from: builtIn)
        #expect(builtIn.isExpanded)
        #expect(!external.isExpanded)
    }

    @Test func losingTheTrackWhileOpenClosesToIdle() {
        var machine = Self.expanded()
        machine.playback(hasTrack: false, isPlaying: false)
        #expect(machine.isExpanded, "the open notch stays open")
        machine.pointer(inside: false, buttonDown: false, at: Self.at(1))
        machine.tick(at: Self.at(1 + T.grace))
        #expect(machine.appearance == .collapsed(.idle))
    }
}
