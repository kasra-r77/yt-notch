import CoreGraphics
import Foundation
import SwiftUI

/// The design tokens from `docs/design/tokens.md` (D5), in one place, under the names that
/// file gives them. Code reads sizes, colours and timings from here, never from literals.
/// Values the spec marks as read from the screen (notch and menu bar sizes) come from
/// `ScreenGeometry` instead. The Playing view (N2.5) adds the rest of D5's colours, fonts
/// and symbols.
public enum Tokens {
    /// Sizes in points.
    public enum Size {
        public static let grid: CGFloat = 8
        public static let expandedPadding: CGFloat = 16
        public static let pillWidth: CGFloat = 190
        public static let collapsedRadius: CGFloat = 10
        public static let expandedRadius: CGFloat = 24
        public static let collapsedFlare: CGFloat = 6
        public static let expandedFlare: CGFloat = 12
        public static let wing: CGFloat = 44
        public static let expandedWidth: CGFloat = 400
        public static let expandedPlayingHeight: CGFloat = 148
        public static let expandedListHeight: CGFloat = 300
        /// The band the expanded heights are designed around.
        public static let expandedBand: CGFloat = 32
        public static let peekRow: CGFloat = 26
        public static let peekMaxWidth: CGFloat = 360
        public static let minimumHitTarget: CGFloat = 28
        public static let shadowRadius: CGFloat = 24
        public static let shadowOffsetY: CGFloat = 8
        public static let shadowOpacity: Double = 0.3

        /// Wing artwork: `min(wingArtwork, band − wingArtworkClearance)` square.
        public static let wingArtwork: CGFloat = 20
        public static let wingArtworkClearance: CGFloat = 8
        /// Artwork and bars sit this far in from the wing's outer edge.
        public static let wingInset: CGFloat = 12
        public static let barWidth: CGFloat = 3
        public static let barGap: CGFloat = 2
        /// The tallest a bar gets: on a band of `barTallBand` or more, and on a smaller one.
        public static let barMaxHeight: CGFloat = 14
        public static let barMaxHeightSmall: CGFloat = 12
        public static let barTallBand: CGFloat = 28
        /// Where the bars rest while paused or under Reduce Motion, for a 14 tall maximum.
        public static let barRestHeights: [CGFloat] = [8, 14, 10, 5]
        /// The lowest point of a bar's swing, as a share of the maximum.
        public static let barLow: CGFloat = 0.35
        /// Peek row: text inset at the sides, space above the line, gap between title and
        /// artist.
        public static let peekPadding: CGFloat = 16
        public static let peekTextTop: CGFloat = 4
        public static let peekTextGap: CGFloat = 6
    }

    /// Radii in points that aren't the notch's own (those are in `Size`).
    public enum Radius {
        /// Wing artwork: 5 at 20, 4 at 16.
        public static let wingArtwork: CGFloat = 5
        public static let wingArtworkSmall: CGFloat = 4
        public static let bar: CGFloat = 1.5
    }

    /// Colours. The surface is black in light and dark mode; everything on it is white at
    /// an opacity.
    public enum Color {
        public static let surface = SwiftUI.Color.black
        public static let textPrimary = SwiftUI.Color.white
        public static let textSecondary = SwiftUI.Color.white.opacity(0.6)
        public static let placeholder = SwiftUI.Color.white.opacity(0.08)
        public static let shadow = SwiftUI.Color.black.opacity(Size.shadowOpacity)
    }

    /// The accent rule (D5): the artwork's dominant colour, lifted to this contrast on black,
    /// or white for near-grey artwork and none.
    public enum Accent {
        public static let minimumContrast: Double = 3
        public static let greyChroma: Double = 0.03
    }

    /// Durations in seconds.
    public enum Timing {
        /// How long the pointer rests inside the shape before it opens.
        public static let dwell: TimeInterval = 0.15
        /// How long the shape stays open after the pointer leaves.
        public static let grace: TimeInterval = 0.4
        /// How long a peek stays out, from the moment it is fully out.
        public static let peekHold: TimeInterval = 2.5
        /// Reopening within this long of closing returns to the view it closed on.
        public static let reopenMemory: TimeInterval = 10
        public static let contentFadeIn: TimeInterval = 0.15
        public static let contentFadeOut: TimeInterval = 0.1
        /// When the spring is about 60% of the way, content starts to fade in.
        public static let contentFadeInDelay: TimeInterval = 0.1
        public static let wingsIn: TimeInterval = 0.25
        public static let wingsOut: TimeInterval = 0.2
        /// Wings fade out over the first 0.1 s of opening, and back in over the last 0.15 s
        /// of closing, which starts about 0.3 s in.
        public static let wingsFadeOut: TimeInterval = 0.1
        public static let wingsFadeIn: TimeInterval = 0.15
        public static let wingsFadeInDelay: TimeInterval = 0.3
        /// Artwork and bars fade in over the last 0.1 s of the wings growing.
        public static let wingContentFadeIn: TimeInterval = 0.1
        public static let reduceMotionCrossfade: TimeInterval = 0.15
        /// A notch fades in when it is built, and out and in for full screen.
        public static let fade: TimeInterval = 0.15
        /// The one spring for opening, closing, peeking and resizing.
        public static let springResponse: Double = 0.35
        public static let springDamping: Double = 0.8
        /// One swing of each bar, low to high, in seconds; the phases are offset by
        /// `barPhases` of a full cycle.
        public static let barSwings: [TimeInterval] = [0.55, 0.8, 0.65, 0.72]
        public static let barPhases: [Double] = [0, 0.35, 0.7, 0.15]
    }

    /// Animations built from the timings above.
    public enum Motion {
        public static let spring = Animation.spring(response: Timing.springResponse, dampingFraction: Timing.springDamping)
        public static let wingsIn = Animation.timingCurve(0.2, 0, 0, 1, duration: Timing.wingsIn)
        public static let wingsOut = Animation.timingCurve(0.2, 0, 0, 1, duration: Timing.wingsOut)
        public static let crossfade = Animation.linear(duration: Timing.reduceMotionCrossfade)
        public static let fade = Animation.linear(duration: Timing.fade)
    }
}
