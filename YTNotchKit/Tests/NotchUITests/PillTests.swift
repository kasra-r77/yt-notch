import AppKit
import Foundation
import PlayerCore
import SwiftUI
import Testing
@testable import NotchUI

/// The pill on a screen without a notch (D8): its middle, and keeping clear of the menu bar
/// icons.
@MainActor
@Suite(.serialized)
struct PillTests {
    typealias S = Tokens.Size
    typealias Placement = NotchLayout.PillPlacement

    let pointer = PointerTracker()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() {
        _ = NSApplication.shared
    }

    // MARK: Placement

    /// A 278 pill centred at 1000 with 6 flares spans 855 to 1145 and has 236 of room.
    func place(_ firstIconX: CGFloat?, width: CGFloat = 278) -> Placement {
        NotchLayout.pillPlacement(width: width, flare: 6, centreX: 1000, firstIconX: firstIconX, room: 236)
    }

    func rightEdge(_ placement: Placement) -> CGFloat {
        1000 + placement.offset + placement.width / 2 + 6
    }

    @Test func centredWhileItFits() {
        #expect(place(nil) == Placement(width: 278, offset: 0, isHidden: false))
        #expect(place(1153) == Placement(width: 278, offset: 0, isHidden: false), "8 clear of the first icon is enough")
    }

    @Test func crowdedItShrinksFromTheRightAndKeepsItsLeftEdge() {
        let placement = place(1100)
        #expect(!placement.isHidden)
        let expected: CGFloat = 278 - (1145 - 1092)
        #expect(placement.width == expected)
        #expect(rightEdge(placement) == 1092, "ends 8 before the icon")
        #expect(1000 + placement.offset - placement.width / 2 - 6 == 855, "the left edge stays")
    }

    @Test func veryCrowdedTheSmallestPillSlidesLeft() {
        let placement = place(940)
        #expect(placement.width == S.pillMinimum)
        #expect(rightEdge(placement) == 932)
        #expect(!placement.isHidden)
    }

    @Test func pastTheNotchsRoomItHides() {
        // The smallest pill fits while its left edge is within the room: 1000 - 236.
        let roomEdge: CGFloat = 1000 - 236
        let lastFit: CGFloat = roomEdge + S.pillIconClearance + 12 + S.pillMinimum
        #expect(place(lastFit - 1).isHidden)
        #expect(!place(lastFit).isHidden, "exactly at the room's edge still fits")
    }

    @Test func theIdlePillFollowsTheSameRule() {
        #expect(place(1200, width: 190) == Placement(width: 190, offset: 0, isHidden: false))
        let crowded = place(1050, width: 190)
        let left: CGFloat = 1000 - 95 - 6
        #expect(crowded.width == 1042 - left - 12)
        #expect(1000 + crowded.offset + crowded.width / 2 + 6 == 1042)
    }

    @Test func theMiddleHasWhatTheWingsLeave() {
        // 278 less 12 either side, the 16 artwork on a 24 band, the 18 of bars, 10 either side.
        #expect(NotchLayout.pillMiddleWidth(pillWidth: 278, band: 24) == 200)
        #expect(NotchLayout.pillMiddleWidth(pillWidth: S.pillMinimum, band: 24) < S.pillMiddleMinimum)
    }

    // MARK: Scrolling

    @Test func aLongTitleRestsScrollsRestsAndComesBack() {
        let overflow: CGFloat = 60
        let speed = CGFloat(Tokens.Timing.pillScrollSpeed)
        let travel = Double(overflow / speed)
        let rest = Tokens.Timing.pillScrollRest
        let endRest = Tokens.Timing.pillScrollEndRest
        #expect(NotchLayout.pillScrollOffset(overflow: overflow, elapsed: 0) == 0)
        #expect(NotchLayout.pillScrollOffset(overflow: overflow, elapsed: rest - 0.1) == 0, "rests at the start")
        #expect(abs(NotchLayout.pillScrollOffset(overflow: overflow, elapsed: rest + 1) - speed) < 0.001)
        #expect(NotchLayout.pillScrollOffset(overflow: overflow, elapsed: rest + travel + endRest / 2) == overflow, "rests at the end")
        #expect(abs(NotchLayout.pillScrollOffset(overflow: overflow, elapsed: rest + travel + endRest + 1) - (overflow - speed)) < 0.001)
        let cycle = rest + travel + endRest + travel
        #expect(NotchLayout.pillScrollOffset(overflow: overflow, elapsed: cycle + 0.5) == 0, "and again")
        #expect(NotchLayout.pillScrollOffset(overflow: 0, elapsed: rest + 1) == 0, "a title that fits stays put")
    }

    // MARK: Reading the icons

    /// The external display in window-list coordinates: x 1512, top at 982 - 1120.
    static let top: CGFloat = 982 - 1120

    func icon(_ x: CGFloat, width: CGFloat = 30, top: CGFloat = Self.top, height: CGFloat = 30, layer: Int = MenuBarIcons.statusLevel) -> FullScreenDetector.WindowInfo {
        .init(ownerPID: 9, layer: layer, bounds: CGRect(x: x, y: top, width: width, height: height))
    }

    @Test func theFirstIconIsTheLeftmostStatusWindowInTheMenuBar() {
        let windows = [
            icon(3000), icon(2600), icon(2800),
            icon(2300, layer: 0),                                // an ordinary window
            icon(2200, height: 400),                             // something taller than the menu bar
            icon(2100, top: Self.top + 500),                     // further down the screen
            icon(900, top: 0),                                   // on the other display
        ]
        #expect(MenuBarIcons.firstIconX(on: Displays.external, windows: windows, primaryHeight: 982) == 2600)
        #expect(MenuBarIcons.firstIconX(on: Displays.external, windows: [icon(2300, layer: 0)], primaryHeight: 982) == nil)
    }

    @Test func theManagerTellsOnlyPillsWhereTheIconsStart() {
        final class Desk {
            var windows: [FullScreenDetector.WindowInfo] = []
        }
        let desk = Desk()
        desk.windows = [icon(2600), .init(ownerPID: 9, layer: MenuBarIcons.statusLevel, bounds: CGRect(x: 1300, y: 0, width: 30, height: 32))]
        let manager = NotchDisplayManager(setting: .all, screens: { [Displays.macBookPro14, Displays.external] },
                                          windows: { desk.windows }, pointer: pointer)
        defer { manager.stop() }
        #expect(manager.notches[0].firstIconX == nil, "a notch stays where the hardware is")
        #expect(manager.notches[1].firstIconX == 2600)
        desk.windows = []
        manager.refreshWindows()
        #expect(manager.notches[1].firstIconX == nil)
    }

    // MARK: The panel

    func playingPanel(on screen: ScreenGeometry = Displays.external) async throws -> (NotchPanel, PlayerStore) {
        let store = PlayerStore(engine: FakeEngine())
        let panel = NotchPanel(screen: screen, store: store, pointer: pointer)
        panel.schedulesTicks = false
        panel.now = { [now] in now }
        store.play()
        try await eventually("playing") { panel.machine.appearance == .collapsed(.playing) }
        return (panel, store)
    }

    @Test func aPlayingPillShowsItsMiddle() async throws {
        let (panel, _) = try await playingPanel()
        defer { panel.close() }
        #expect(panel.model.middleShown)
        #expect(panel.model.outline.offset == 0)
    }

    @Test func aNotchShowsNoMiddleAndIgnoresIcons() async throws {
        let (panel, _) = try await playingPanel(on: Displays.macBookPro14)
        defer { panel.close() }
        let outline = panel.model.outline
        #expect(!panel.model.middleShown)
        panel.setMenuBarIcons(firstX: 700)
        #expect(panel.model.outline == outline)
        #expect(!panel.isCrowdedOut)
    }

    @Test func thePillKeepsClearOfTheIcons() async throws {
        let (panel, _) = try await playingPanel()
        defer { panel.close() }
        let centre = Displays.external.frame.midX

        panel.setMenuBarIcons(firstX: centre + 100)
        var outline = panel.model.outline
        #expect(outline.width < S.pillWidth + 2 * S.wing)
        #expect(centre + outline.offset + outline.width / 2 + outline.flare == centre + 100 - S.pillIconClearance)
        #expect(panel.model.middleShown, "still room for the title")

        panel.setMenuBarIcons(firstX: centre - 60)
        outline = panel.model.outline
        #expect(outline.width == S.pillMinimum)
        #expect(outline.offset < 0)
        #expect(!panel.model.middleShown)
        // The shape takes the pointer where it now is, not where it was.
        let top = Displays.external.frame.maxY - 1
        #expect(panel.contains(CGPoint(x: centre + outline.offset, y: top)))
        #expect(!panel.contains(CGPoint(x: centre + 100, y: top)))

        panel.setMenuBarIcons(firstX: centre - 200)
        #expect(panel.isCrowdedOut)
        #expect(panel.model.isHidden)
        #expect(!panel.contains(CGPoint(x: centre + panel.model.outline.offset, y: top)))

        panel.setMenuBarIcons(firstX: nil)
        #expect(!panel.isCrowdedOut)
        #expect(!panel.model.isHidden)
        #expect(panel.model.outline == NotchLayout.outline(for: .collapsed(.playing), on: Displays.external))
    }

    @Test func openingIsCentredWhereverThePillWas() async throws {
        let (panel, _) = try await playingPanel()
        defer { panel.close() }
        let centre = Displays.external.frame.midX
        panel.setMenuBarIcons(firstX: centre - 60)
        pointer.deliver(CGPoint(x: centre + panel.model.outline.offset, y: Displays.external.frame.maxY - 1))
        panel.tick(at: now.addingTimeInterval(Tokens.Timing.dwell))
        #expect(panel.machine.isExpanded)
        #expect(panel.model.outline.offset == 0)
        #expect(panel.model.outline.width == S.expandedWidth)
    }

    // MARK: Drawing

    @Test func theProgressLineFollowsThePlayer() throws {
        let engine = PlayingViewTests.SilentEngine()
        let store = PlayerStore(engine: engine)
        engine.report(.ready(bridgeVersion: "1", signedIn: true))
        engine.report(.state(PlaybackSnapshot(track: Track(id: "t", title: "T", artist: "A", duration: 200), position: 50)))
        #expect(PillProgressLine.fraction(store.state, at: now) == 0.25)
        let view = PillProgressLine(state: store.state, accent: .red).frame(width: 200, height: 2)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let pixels = try Pixels(try #require(renderer.cgImage))
        #expect(pixels.at(x: 25, y: 1).r > 200, "the accent up to a quarter")
        #expect(pixels.at(x: 150, y: 1).r < 100, "white 15% after")
    }

    @Test func theTitleSitsInTheMiddle() throws {
        let view = ZStack {
            Tokens.Color.surface
            PillTitle(title: "Lanterns", artist: "Mira Holt", isPlaying: false, reduceMotion: false)
        }
        .frame(width: 200, height: 24)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let pixels = try Pixels(try #require(renderer.cgImage))
        let row = (0..<200).map { pixels.at(x: $0, y: 12) }
        let lit = row.indices.filter { row[$0].r > 120 }
        let first = try #require(lit.first)
        let last = try #require(lit.last)
        #expect(abs((first + last) / 2 - 100) < 6, "centred")
    }
}
