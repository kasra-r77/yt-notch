import CoreGraphics
import Foundation
import Testing
@testable import NotchUI

/// Every shape in the D1 table, and how the notch moves between them.
struct NotchLayoutTests {
    typealias S = Tokens.Size

    static func outline(_ appearance: HoverMachine.Appearance, _ screen: ScreenGeometry = Displays.macBookPro14, text: CGFloat = 0) -> NotchOutline {
        NotchLayout.outline(for: appearance, on: screen, peekTextWidth: text)
    }

    @Test func idleIsTheNotchOrThePill() {
        #expect(Self.outline(.collapsed(.idle)) == .idle(on: Displays.macBookPro14))
        #expect(Self.outline(.collapsed(.idle), Displays.external) == .idle(on: Displays.external))
        #expect(Self.outline(.hidden) == .idle(on: Displays.macBookPro14))
    }

    @Test func playingAddsAWingEachSide() {
        #expect(Self.outline(.collapsed(.playing)) == NotchOutline(width: 185 + 2 * S.wing, height: 32, bottomRadius: S.collapsedRadius, flare: S.collapsedFlare))
        #expect(Self.outline(.collapsed(.playing), Displays.external) == NotchOutline(width: S.pillWidth + 2 * S.wing, height: 30, bottomRadius: S.collapsedRadius, flare: S.collapsedFlare))
    }

    @Test func peekGrowsDownAndFitsItsText() {
        let playing = NotchLayout.playingWidth(on: Displays.macBookPro14)
        #expect(Self.outline(.collapsed(.peek), text: 100) == NotchOutline(width: playing, height: 32 + S.peekRow, bottomRadius: S.collapsedRadius, flare: S.collapsedFlare))
        #expect(Self.outline(.collapsed(.peek), text: 280).width == 280 + 2 * S.peekPadding)
        #expect(Self.outline(.collapsed(.peek), text: 900).width == S.peekMaxWidth)
    }

    @Test func expandedSizes() {
        #expect(Self.outline(.expanded(.view(.playing))) == NotchOutline(width: 400, height: 148, bottomRadius: S.expandedRadius, flare: S.expandedFlare))
        #expect(Self.outline(.expanded(.message)) == NotchOutline(width: 400, height: 148, bottomRadius: S.expandedRadius, flare: S.expandedFlare))
        #expect(Self.outline(.expanded(.view(.playlists))).height == 300)
        #expect(Self.outline(.expanded(.view(.upNext))).height == 300)
        // The external display's 30 pt menu bar is under 32, so nothing is added.
        #expect(Self.outline(.expanded(.view(.playing)), Displays.external).height == 148)
    }

    @Test func aTallerNotchMakesTheExpandedShapesTaller() {
        #expect(Self.outline(.expanded(.view(.playing)), Displays.tallNotch).height == CGFloat(148 + 6))
        #expect(Self.outline(.expanded(.view(.upNext)), Displays.tallNotch).height == CGFloat(300 + 6))
    }

    @Test func peekTextIsTitleGapArtist() {
        #expect(NotchLayout.peekTextWidth(title: "", artist: "") == 0)
        let title = NotchLayout.peekTextWidth(title: "Track title", artist: "")
        let both = NotchLayout.peekTextWidth(title: "Track title", artist: "Artist")
        #expect(title > 0)
        #expect(both > title + S.peekTextGap)
    }

    @Test func wingContentFitsTheBand() {
        #expect(NotchLayout.wingArtworkSize(band: 32) == 20)
        #expect(NotchLayout.wingArtworkSize(band: 24) == 16)
        #expect(NotchLayout.barMaxHeight(band: 32) == 14)
        #expect(NotchLayout.barMaxHeight(band: 30) == 14)
        #expect(NotchLayout.barMaxHeight(band: 24) == 12)
    }

    @Test func motionBetweenShapes() {
        #expect(NotchMotion.between(.collapsed(.idle), .collapsed(.playing), reduceMotion: false) == .wingsIn)
        #expect(NotchMotion.between(.collapsed(.playing), .collapsed(.idle), reduceMotion: false) == .wingsOut)
        #expect(NotchMotion.between(.collapsed(.playing), .expanded(.view(.playing)), reduceMotion: false) == .spring)
        #expect(NotchMotion.between(.expanded(.view(.playing)), .collapsed(.idle), reduceMotion: false) == .spring)
        #expect(NotchMotion.between(.collapsed(.playing), .collapsed(.peek), reduceMotion: false) == .spring)
        #expect(NotchMotion.between(.expanded(.view(.playing)), .expanded(.view(.upNext)), reduceMotion: false) == .spring)
        #expect(NotchMotion.between(.expanded(.view(.playing)), .hidden, reduceMotion: false) == NotchMotion.none)
        #expect(NotchMotion.between(.collapsed(.playing), .collapsed(.playing), reduceMotion: false) == NotchMotion.none)
        #expect(NotchMotion.between(.collapsed(.playing), .expanded(.view(.playing)), reduceMotion: true) == .crossfade)
        #expect(NotchMotion.between(.collapsed(.idle), .collapsed(.playing), reduceMotion: true) == .crossfade)
    }

    @Test func barsRestWhenNotPlaying() {
        let rest = (0..<4).map { BarMotion.height(bar: $0, at: 123, isAnimating: false, maxHeight: 14) }
        #expect(rest == [8, 14, 10, 5])
        let small = (0..<4).map { BarMotion.height(bar: $0, at: 123, isAnimating: false, maxHeight: 12) }
        #expect(small == [8, 14, 10, 5].map { $0 * 12 / 14 })
    }

    @Test func barsSwingBetweenTheirLowAndTheirHeight() {
        var seen: Set<Int> = []
        for step in 0..<400 {
            let time = Double(step) * 0.01
            for bar in 0..<4 {
                let height = BarMotion.height(bar: bar, at: time, isAnimating: true, maxHeight: 14)
                #expect(height >= S.barLow * 14 - 0.001 && height <= 14.001)
                seen.insert(Int(height.rounded()))
            }
        }
        #expect(seen.count > 6, "the bars move through many heights")
        let heights = (0..<4).map { BarMotion.height(bar: $0, at: 1, isAnimating: true, maxHeight: 14) }
        #expect(Set(heights.map { Int($0 * 10) }).count > 1, "the phases are offset")
    }
}
