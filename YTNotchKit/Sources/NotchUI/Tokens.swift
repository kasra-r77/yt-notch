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

        // The Playing view (D2), positions from the expanded body's top left.
        public static let artwork: CGFloat = 84
        public static let artworkPlaceholderIcon: CGFloat = 28
        public static let control: CGFloat = 28
        public static let icon: CGFloat = 14
        public static let playIcon: CGFloat = 18
        public static let controlGap: CGFloat = 16
        public static let earGap: CGFloat = 4
        /// The text column: from x 116, 268 wide.
        public static let textColumnX: CGFloat = 116
        public static let textColumnWidth: CGFloat = 268
        public static let titleY: CGFloat = 48
        public static let artistY: CGFloat = 66
        public static let lineGap: CGFloat = 2
        public static let progressY: CGFloat = 88
        public static let progressRow: CGFloat = 12
        public static let timeGap: CGFloat = 8
        public static let controlsY: CGFloat = 104
        public static let track: CGFloat = 4
        public static let knob: CGFloat = 10
        public static let dragKnob: CGFloat = 12
        public static let halo: CGFloat = 4
        public static let toggleDot: CGFloat = 4
        /// Where the toggle dot sits above the control's bottom edge.
        public static let toggleDotInset: CGFloat = 1
        /// Click areas: the progress band, and each transport control's column.
        public static let progressHitHeight: CGFloat = 28
        public static let transportHitWidth: CGFloat = 44
        /// Loading placeholders for the title and the artist.
        public static let skeletonTitle = CGSize(width: 132, height: 10)
        public static let skeletonArtist = CGSize(width: 80, height: 8)
        /// The title's loading bar sits this far below the title's line.
        public static let skeletonTitleTop: CGFloat = 3
        public static let knobShadowRadius: CGFloat = 1
        public static let knobShadowY: CGFloat = 1
        /// Type sizes, for the fonts below and for measuring text.
        public static let titleText: CGFloat = 13
        public static let secondaryText: CGFloat = 11
        public static let timeText: CGFloat = 10
        public static let buttonText: CGFloat = 12
    }

    /// Radii in points that aren't the notch's own (those are in `Size`).
    public enum Radius {
        /// Wing artwork: 5 at 20, 4 at 16.
        public static let wingArtwork: CGFloat = 5
        public static let wingArtworkSmall: CGFloat = 4
        public static let bar: CGFloat = 1.5
        public static let artwork: CGFloat = 10
        public static let thumbnail: CGFloat = 6
        public static let row: CGFloat = 8
        public static let control: CGFloat = 8
        public static let pill: CGFloat = 14
        public static let track: CGFloat = 2
        public static let skeleton: CGFloat = 3
    }

    /// Colours. The surface is black in light and dark mode; everything on it is white at
    /// an opacity.
    public enum Color {
        public static let surface = SwiftUI.Color.black
        public static let textPrimary = SwiftUI.Color.white
        public static let textSecondary = SwiftUI.Color.white.opacity(0.6)
        public static let textDisabled = SwiftUI.Color.white.opacity(0.25)
        public static let divider = SwiftUI.Color.white.opacity(0.12)
        public static let hover = SwiftUI.Color.white.opacity(0.1)
        public static let pressed = SwiftUI.Color.white.opacity(0.16)
        public static let selected = SwiftUI.Color.white.opacity(0.16)
        public static let rowHover = SwiftUI.Color.white.opacity(0.06)
        public static let rowCurrent = SwiftUI.Color.white.opacity(0.1)
        public static let rowPressed = SwiftUI.Color.white.opacity(0.14)
        public static let placeholder = SwiftUI.Color.white.opacity(0.08)
        /// The title's loading bar; the artist's uses `placeholder`.
        public static let skeletonStrong = SwiftUI.Color.white.opacity(0.1)
        public static let artworkPlaceholderIcon = SwiftUI.Color.white.opacity(0.3)
        public static let track = SwiftUI.Color.white.opacity(0.2)
        public static let halo = SwiftUI.Color.white.opacity(0.2)
        public static let scroller = SwiftUI.Color.white.opacity(0.4)
        public static let buttonBackground = SwiftUI.Color.white
        public static let buttonBackgroundHover = SwiftUI.Color.white.opacity(0.85)
        public static let buttonBackgroundPressed = SwiftUI.Color.white.opacity(0.7)
        public static let buttonText = SwiftUI.Color.black
        public static let shadow = SwiftUI.Color.black.opacity(Size.shadowOpacity)
        /// Under the knob, so it reads on any accent.
        public static let knobShadow = SwiftUI.Color.black.opacity(0.4)
    }

    /// Opacities for whole groups.
    public enum Opacity {
        /// The progress row when seeking is unavailable (D4).
        public static let unavailableProgress: Double = 0.4
    }

    /// Type: SF Pro, the system font.
    public enum Font {
        public static let title = SwiftUI.Font.system(size: Size.titleText, weight: .semibold)
        public static let row = SwiftUI.Font.system(size: Size.titleText, weight: .regular)
        public static let secondary = SwiftUI.Font.system(size: Size.secondaryText, weight: .regular)
        public static let time = SwiftUI.Font.system(size: Size.timeText, weight: .regular).monospacedDigit()
        public static let button = SwiftUI.Font.system(size: Size.buttonText, weight: .semibold)
        public static let icon = SwiftUI.Font.system(size: Size.icon, weight: .medium)
        public static let playIcon = SwiftUI.Font.system(size: Size.playIcon, weight: .medium)
        public static let artworkPlaceholderIcon = SwiftUI.Font.system(size: Size.artworkPlaceholderIcon, weight: .regular)
    }

    /// SF Symbol names for every control (D5, "Icons").
    public enum Symbol {
        public static let tabPlaying = "music.note"
        public static let tabPlaylists = "music.note.list"
        public static let tabUpNext = "list.bullet"
        public static let like = "hand.thumbsup"
        public static let liked = "hand.thumbsup.fill"
        public static let open = "arrow.up.forward.app"
        public static let shuffle = "shuffle"
        public static let previous = "backward.fill"
        public static let play = "play.fill"
        public static let pause = "pause.fill"
        public static let next = "forward.fill"
        public static let `repeat` = "repeat"
        public static let repeatOne = "repeat.1"
        public static let noArtwork = "music.note"
        public static let playlistTile = "music.note.list"
        public static let likedTile = "hand.thumbsup.fill"
        public static let savedList = "clock.arrow.circlepath"
        public static let signedOut = "person.crop.circle"
        public static let offline = "wifi.slash"
        public static let bridgeBroken = "wrench.and.screwdriver"
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
        /// How often the elapsed time redraws while playing.
        public static let progressRefresh: TimeInterval = 0.25
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
