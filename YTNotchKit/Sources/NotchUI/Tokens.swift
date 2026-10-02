import CoreGraphics
import Foundation

/// The design tokens from `docs/design/notch-shapes.md` (D1), in one place. Code reads
/// sizes and timings from here, never from literals. Values the spec marks as read from the
/// screen (notch and menu bar sizes) come from `ScreenGeometry` instead. Colours and fonts
/// join with the Playing view (N2.5).
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
        public static let wingsIn: TimeInterval = 0.25
        public static let wingsOut: TimeInterval = 0.2
        public static let reduceMotionCrossfade: TimeInterval = 0.15
        /// A notch fades in when it is built, and out and in for full screen.
        public static let fade: TimeInterval = 0.15
        /// The one spring for opening, closing, peeking and resizing.
        public static let springResponse: Double = 0.35
        public static let springDamping: Double = 0.8
    }
}
