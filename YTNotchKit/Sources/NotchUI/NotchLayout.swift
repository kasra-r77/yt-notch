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

    static var peekTitleFont: NSFont { NSFont.systemFont(ofSize: 13, weight: .semibold) }
    static var peekArtistFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .regular) }

    /// The peek's one line: the title, 6, the artist.
    static func peekTextWidth(title: String, artist: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: peekTitleFont]).width
        let artistWidth = (artist as NSString).size(withAttributes: [.font: peekArtistFont]).width
        return ceil(titleWidth + (artist.isEmpty ? 0 : Tokens.Size.peekTextGap + artistWidth))
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
