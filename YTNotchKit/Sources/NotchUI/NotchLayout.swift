import AppKit
import SwiftUI

/// The shape for each thing the notch can show on a display (design spec, "Shapes").
enum NotchLayout {
    /// The collapsed width before wings: the hardware notch, or the pill.
    static func baseWidth(on screen: ScreenGeometry) -> CGFloat {
        screen.notch?.width ?? Tokens.Size.pillWidth
    }

    static func playingWidth(on screen: ScreenGeometry) -> CGFloat {
        baseWidth(on: screen) + 2 * Tokens.Size.wing
    }

    /// How much taller the expanded shapes are when the band is taller than 32.
    static func expandedExtra(on screen: ScreenGeometry) -> CGFloat {
        max(0, screen.band - Tokens.Size.expandedBand)
    }

    /// The target outline for an appearance. `peekTextWidth` is the width of the peek's
    /// line of text, from `peekTextWidth(title:artist:)`.
    static func outline(for appearance: HoverMachine.Appearance, on screen: ScreenGeometry, peekTextWidth: CGFloat = 0) -> NotchOutline {
        let collapsed = { (width: CGFloat, height: CGFloat) in
            NotchOutline(width: width, height: height, bottomRadius: Tokens.Size.collapsedRadius, flare: Tokens.Size.collapsedFlare)
        }
        let expanded = { (height: CGFloat) in
            NotchOutline(width: Tokens.Size.expandedWidth, height: height + expandedExtra(on: screen),
                         bottomRadius: Tokens.Size.expandedRadius, flare: Tokens.Size.expandedFlare)
        }
        switch appearance {
        case .hidden, .collapsed(.idle):
            return .idle(on: screen)
        case .collapsed(.playing):
            return collapsed(playingWidth(on: screen), screen.band)
        case .collapsed(.peek):
            let width = min(Tokens.Size.peekMaxWidth, max(playingWidth(on: screen), peekTextWidth + 2 * Tokens.Size.peekPadding))
            return collapsed(width, screen.band + Tokens.Size.peekRow)
        case .expanded(.view(.playlists)), .expanded(.view(.upNext)):
            return expanded(Tokens.Size.expandedListHeight)
        case .expanded:
            return expanded(Tokens.Size.expandedPlayingHeight)
        }
    }

    static var peekTitleFont: NSFont { NSFont.systemFont(ofSize: Tokens.Size.titleText, weight: .semibold) }
    static var peekArtistFont: NSFont { NSFont.systemFont(ofSize: Tokens.Size.secondaryText, weight: .regular) }

    /// The peek's one line: the title, 6, the artist.
    static func peekTextWidth(title: String, artist: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: peekTitleFont]).width
        let artistWidth = (artist as NSString).size(withAttributes: [.font: peekArtistFont]).width
        return ceil(titleWidth + (artist.isEmpty ? 0 : Tokens.Size.peekTextGap + artistWidth))
    }

    // MARK: The pill without a notch (D8)

    static var pillTitleFont: NSFont { NSFont.systemFont(ofSize: Tokens.Size.pillText, weight: .semibold) }
    static var pillArtistFont: NSFont { NSFont.systemFont(ofSize: Tokens.Size.pillText, weight: .regular) }

    /// The pill's middle line: the title, 6, the artist.
    static func pillTextWidth(title: String, artist: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: pillTitleFont]).width
        let artistWidth = (artist as NSString).size(withAttributes: [.font: pillArtistFont]).width
        return ceil(titleWidth + (artist.isEmpty ? 0 : Tokens.Size.pillTextGap + artistWidth))
    }

    /// The width left for the middle in a playing pill this wide: between the artwork and the
    /// bars, 10 clear of each.
    static func pillMiddleWidth(pillWidth: CGFloat, band: CGFloat) -> CGFloat {
        let bars = CGFloat(Tokens.Size.barRestHeights.count) * Tokens.Size.barWidth
            + CGFloat(Tokens.Size.barRestHeights.count - 1) * Tokens.Size.barGap
        return pillWidth - 2 * Tokens.Size.wingInset - wingArtworkSize(band: band) - bars - 2 * Tokens.Size.pillMiddleGap
    }

    /// Where a collapsed pill goes so it never covers a menu bar icon (D8, "Crowded menu
    /// bar"): centred while it fits; otherwise its left edge stays and it narrows to end 8
    /// before the first icon; below the smallest pill (artwork and bars) it slides left from
    /// there. A pill that would leave the notch's own room (`room` either side of the centre)
    /// is hidden instead.
    struct PillPlacement: Equatable {
        var width: CGFloat
        /// The body's centre from the screen's notch centre; negative is to the left.
        var offset: CGFloat
        var isHidden: Bool
    }

    static func pillPlacement(width: CGFloat, flare: CGFloat, centreX: CGFloat, firstIconX: CGFloat?, room: CGFloat) -> PillPlacement {
        let centred = PillPlacement(width: width, offset: 0, isHidden: false)
        guard let firstIconX else { return centred }
        let limit = firstIconX - Tokens.Size.pillIconClearance
        if centreX + width / 2 + flare <= limit { return centred }
        let left = centreX - width / 2 - flare
        let shrunk = limit - left - 2 * flare
        let smallest = min(width, Tokens.Size.pillMinimum)
        if shrunk >= smallest {
            return PillPlacement(width: shrunk, offset: (shrunk - width) / 2, isHidden: false)
        }
        let centre = limit - flare - smallest / 2
        return PillPlacement(width: smallest, offset: centre - centreX, isHidden: centre - smallest / 2 - flare < centreX - room)
    }

    /// How far a title too long for the pill's middle has scrolled, `elapsed` seconds after it
    /// started: it rests at the start, scrolls to the end, rests there, scrolls back.
    static func pillScrollOffset(overflow: CGFloat, elapsed: TimeInterval) -> CGFloat {
        guard overflow > 0 else { return 0 }
        let speed = Tokens.Timing.pillScrollSpeed
        let travel = Double(overflow) / speed
        let rest = Tokens.Timing.pillScrollRest
        let endRest = Tokens.Timing.pillScrollEndRest
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: rest + travel + endRest + travel)
        if phase < rest { return 0 }
        if phase < rest + travel { return CGFloat((phase - rest) * speed) }
        if phase < rest + travel + endRest { return overflow }
        return max(0, overflow - CGFloat((phase - rest - travel - endRest) * speed))
    }

    /// The square wing artwork for a band: 20, or smaller on a short band.
    static func wingArtworkSize(band: CGFloat) -> CGFloat {
        min(Tokens.Size.wingArtwork, band - Tokens.Size.wingArtworkClearance)
    }

    static func barMaxHeight(band: CGFloat) -> CGFloat {
        band >= Tokens.Size.barTallBand ? Tokens.Size.barMaxHeight : Tokens.Size.barMaxHeightSmall
    }
}

/// How the shape moves from one appearance to the next (design spec, "Motion").
enum NotchMotion: Equatable {
    case none
    /// Open, close, peek and resize.
    case spring
    /// Idle to Playing and back: the wings grow out of the notch or draw back into it.
    case wingsIn
    case wingsOut
    /// Reduce Motion: the two shapes crossfade in place.
    case crossfade

    static func between(_ old: HoverMachine.Appearance, _ new: HoverMachine.Appearance, reduceMotion: Bool) -> NotchMotion {
        guard old != new else { return .none }
        // Hiding for full screen is a fade of the whole notch, not a change of shape.
        if case .hidden = new { return .none }
        if case .hidden = old { return .none }
        if reduceMotion { return .crossfade }
        switch (old, new) {
        case (.collapsed(.idle), .collapsed(.playing)): return .wingsIn
        case (.collapsed(.playing), .collapsed(.idle)): return .wingsOut
        default: return .spring
        }
    }

    var animation: Animation? {
        switch self {
        case .none: nil
        case .spring: Tokens.Motion.spring
        case .wingsIn: Tokens.Motion.wingsIn
        case .wingsOut: Tokens.Motion.wingsOut
        case .crossfade: Tokens.Motion.crossfade
        }
    }
}
