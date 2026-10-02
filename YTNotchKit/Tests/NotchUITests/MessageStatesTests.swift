import AppKit
import Foundation
import PlayerCore
import SwiftUI
import Testing
@testable import NotchUI

/// The message states and the partly working page (design spec D4).
@MainActor
@Suite(.serialized)
struct MessageStatesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let pointer = PointerTracker()

    init() {
        _ = NSApplication.shared
    }

    @Test func eachStateHasOneMessageAndAtMostOneButton() {
        let signedOut = MessagePresentation(.signedOut)
        #expect(signedOut.symbol == "person.crop.circle")
        #expect(signedOut.message == "Sign in to YouTube Music")
        #expect(signedOut.detail == "YT Notch plays music from your own account.")
        #expect(signedOut.button?.label == "Sign In")
        #expect(signedOut.button?.action == .signIn)

        let offline = MessagePresentation(.offline)
        #expect(offline.symbol == "wifi.slash")
        #expect(offline.message == "No connection")
        #expect(offline.detail == "YT Notch keeps trying on its own.")
        #expect(offline.button?.label == "Try Again")
        #expect(offline.button?.action == .retry)

        let broken = MessagePresentation(.bridgeBroken)
        #expect(broken.symbol == "wrench.and.screwdriver")
        #expect(broken.message == "Player needs an update")
        #expect(broken.detail == "The page changed. Music still plays in the full window.")
        #expect(broken.button?.label == "Open Full Window")
        #expect(broken.button?.action == .openFullWindow)

        let loading = MessagePresentation(.loading)
        #expect(loading.symbol == nil, "a spinner instead")
        #expect(loading.message == "Loading YouTube Music…")
        #expect(loading.detail == "This takes a moment the first time.")
        #expect(loading.button == nil)
    }

    @Test func theMessageFollowsTheStoresHealth() {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        #expect(MessagePresentation.kind(for: store.state) == nil)
        engine.simulateOffline()
        #expect(MessagePresentation.kind(for: store.state) == .offline)
        engine.simulateReload()
        #expect(MessagePresentation.kind(for: store.state) == nil)
        engine.simulateSignedOut()
        #expect(MessagePresentation.kind(for: store.state) == .signedOut)
        engine.simulateBridgeBroken()
        #expect(MessagePresentation.kind(for: store.state) == .bridgeBroken)
    }

    @Test func beforeThePageIsReadyItIsLoading() {
        let store = PlayerStore(engine: PlayingViewTests.SilentEngine())
        #expect(MessagePresentation.kind(for: store.state) == .loading)
    }

    @Test func aPageWithEveryPartMissingIsBroken() {
        let engine = FakeEngine()
        let store = PlayerStore(engine: engine)
        engine.simulateMissing(Set(Feature.allCases))
        #expect(MessagePresentation.kind(for: store.state) == .bridgeBroken)
        engine.simulateMissing([.like])
        #expect(MessagePresentation.kind(for: store.state) == nil, "one part missing is only partly working")
    }

    @Test func aForcedStateWinsOverThePlayer() {
        let store = PlayerStore(engine: FakeEngine())
        for kind in NotchMessage.allCases {
            #expect(MessagePresentation.kind(for: store.state, forced: .message(kind)) == kind)
        }
        #expect(MessagePresentation.kind(for: store.state, forced: .missing([.like])) == nil)
    }

    @Test func missingPartsDimOrHide() {
        let store = PlayerStore(engine: FakeEngine())
        let p = PlayingPresentation(store.state, at: now, forced: .missing([.like, .seek, .shuffle, .repeatMode]))
        #expect(!p.canLike && !p.canSeek)
        #expect(!p.showsShuffle && !p.showsRepeat)
        #expect(p.canPlayPause && p.canNext, "the rest keep working")
        #expect(PlayingPresentation.help("Like", enabled: false) == "Like isn't available right now")
        #expect(PlayingPresentation.help("Like", enabled: true) == "Like")
    }

    @Test func theButtonsDoWhatTheySay() {
        var opened = 0, retried = 0, dismissed = 0
        let actions = NotchActions(store: nil, openFullWindow: { opened += 1 }, retry: { retried += 1 }, dismiss: { dismissed += 1 })
        actions.perform(.signIn)
        actions.perform(.openFullWindow)
        actions.perform(.retry)
        #expect(opened == 2)
        #expect(dismissed == 2, "opening the window closes the notch")
        #expect(retried == 1)
        #expect(actions.canPerform(.retry) && actions.canPerform(.signIn))

        let nothing = NotchActions(store: nil)
        #expect(!nothing.canPerform(.retry) && !nothing.canPerform(.openFullWindow))
    }

    @Test func dismissClosesAtOnceAndWaitsForThePointerToLeave() {
        var machine = HoverMachine()
        machine.pointer(inside: true, buttonDown: false, at: now)
        machine.tick(at: now.addingTimeInterval(Tokens.Timing.dwell))
        #expect(machine.isExpanded)

        machine.dismiss(at: now.addingTimeInterval(1))
        #expect(machine.phase == .collapsed, "no grace")
        machine.pointer(inside: true, buttonDown: false, at: now.addingTimeInterval(1.1))
        #expect(machine.phase == .collapsed, "resting on it doesn't reopen")
        machine.pointer(inside: false, buttonDown: false, at: now.addingTimeInterval(1.2))
        machine.pointer(inside: true, buttonDown: false, at: now.addingTimeInterval(1.3))
        #expect(machine.phase == .dwell(since: now.addingTimeInterval(1.3)), "back after leaving")
    }

    func panel(_ store: PlayerStore) -> NotchPanel {
        let panel = NotchPanel(screen: Displays.external, store: store, pointer: pointer)
        panel.schedulesTicks = false
        panel.now = { [now] in now }
        return panel
    }

    @Test func aForcedMessageOpensOnTheMessage() {
        let store = PlayerStore(engine: FakeEngine())
        let panel = panel(store)
        defer { panel.close() }
        panel.forcedState = .message(.offline)
        #expect(panel.model.message == .offline)
        pointer.deliver(NotchMotionPanelTests.insidePill)
        panel.tick(at: now.addingTimeInterval(Tokens.Timing.dwell))
        #expect(panel.machine.appearance == .expanded(.message))
        #expect(panel.model.expandedContent == .message)

        panel.forcedState = nil
        #expect(panel.model.message == nil)
        #expect(panel.machine.appearance == .expanded(.view(.playing)))
    }

    @Test func openingTheWindowClosesTheNotch() {
        var opened = 0
        let store = PlayerStore(engine: FakeEngine())
        let panel = panel(store)
        defer { panel.close() }
        panel.openFullWindow = { opened += 1 }
        pointer.deliver(NotchMotionPanelTests.insidePill)
        panel.tick(at: now.addingTimeInterval(Tokens.Timing.dwell))
        #expect(panel.machine.isExpanded)
        panel.model.actions.open()
        #expect(opened == 1)
        #expect(!panel.machine.isExpanded)
    }

    @Test func theManagerPassesItsHandlersAndForcedStateToEveryNotch() {
        let store = PlayerStore(engine: FakeEngine())
        let manager = NotchDisplayManager(setting: .all, store: store, screens: { [Displays.macBookPro14, Displays.external] }, pointer: pointer)
        defer { manager.stop() }
        var retried = 0
        manager.retry = { retried += 1 }
        manager.forcedState = .message(.offline)
        for notch in manager.notches {
            #expect(notch.forcedState == .message(.offline))
            notch.retry?()
            #expect(notch.openFullWindow == nil)
        }
        #expect(retried == 2)
    }

    @Test func drawsTheMessageAndItsButton() throws {
        let view = ZStack(alignment: .top) {
            Tokens.Color.surface
            MessageView(presentation: MessagePresentation(.offline), actions: NotchActions(store: nil, retry: {}), extra: 0)
        }
        .frame(width: 400, height: 148)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixels = try Pixels(image)
        // The white button sits centred low in the frame.
        let buttonRow = (150..<250).map { pixels.at(x: $0, y: 120) }
        #expect(buttonRow.filter { $0.r > 240 && $0.g > 240 }.count > 20)
        // The message's white text is above it.
        let messageRow = (120..<280).map { pixels.at(x: $0, y: 74) }
        #expect(messageRow.contains { $0.r > 200 })
    }
}
