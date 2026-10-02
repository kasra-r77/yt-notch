import CoreGraphics

/// The four values every notch shape is drawn from (design spec, "Corner geometry"): the
/// body's width and height, its bottom corner radius, and the flare at the top on each side.
public struct NotchOutline: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var bottomRadius: CGFloat
    public var flare: CGFloat

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, flare: CGFloat) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.flare = flare
    }

    /// The body and both flares.
    public var footprint: CGSize { CGSize(width: width + 2 * flare, height: height) }

    /// Idle: exactly the hardware notch on a display with one, with no flare so nothing
    /// shows past the hardware; the pill on any other display.
    public static func idle(on screen: ScreenGeometry) -> NotchOutline {
        if let notch = screen.notch {
            NotchOutline(width: notch.width, height: notch.height, bottomRadius: Metrics.collapsedRadius, flare: 0)
        } else {
            NotchOutline(width: Metrics.pillWidth, height: screen.menuBarHeight, bottomRadius: Metrics.collapsedRadius, flare: Metrics.collapsedFlare)
        }
    }
}

/// Sizes from the design spec (`docs/design/notch-shapes.md`), in points. Anything the spec
/// marks as read from the screen comes from `ScreenGeometry` instead.
enum Metrics {
    static let pillWidth: CGFloat = 190
    static let collapsedRadius: CGFloat = 10
    static let collapsedFlare: CGFloat = 6
    static let expandedWidth: CGFloat = 400
    static let expandedFlare: CGFloat = 12
    static let expandedListHeight: CGFloat = 300
    /// The band the expanded heights are designed around.
    static let expandedBand: CGFloat = 32
    static let shadowRadius: CGFloat = 24
    static let shadowOffsetY: CGFloat = 8
    /// A notch fades in when built and in or out for full screen.
    static let fade: Double = 0.15
}

/// Where a display's panel goes. The panel never moves or resizes: it is large enough for
/// the largest shape, and every shape is drawn top-centred inside it.
enum PanelLayout {
    /// The expanded list view's footprint (424 × 300), taller by however much the band is
    /// taller than 32, plus room for the shadow. Top-centred on the notch.
    static func frame(on screen: ScreenGeometry) -> CGRect {
        let width = Metrics.expandedWidth + 2 * Metrics.expandedFlare + 2 * Metrics.shadowRadius
        let height = Metrics.expandedListHeight + max(0, screen.band - Metrics.expandedBand)
            + Metrics.shadowRadius + Metrics.shadowOffsetY
        return CGRect(x: screen.centreX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}
