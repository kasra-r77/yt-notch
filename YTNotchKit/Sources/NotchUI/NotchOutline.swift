import CoreGraphics

/// The four values every notch shape is drawn from (design spec, "Corner geometry"): the
/// body's width and height, its bottom corner radius, and the flare at the top on each side.
public struct NotchOutline: Hashable, Sendable {
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
            NotchOutline(width: notch.width, height: notch.height, bottomRadius: Tokens.Size.collapsedRadius, flare: 0)
        } else {
            NotchOutline(width: Tokens.Size.pillWidth, height: screen.menuBarHeight, bottomRadius: Tokens.Size.collapsedRadius, flare: Tokens.Size.collapsedFlare)
        }
    }
}

/// Where a display's panel goes. The panel never moves or resizes: it is large enough for
/// the largest shape, and every shape is drawn top-centred inside it.
enum PanelLayout {
    /// The expanded list view's footprint (424 × 300), taller by however much the band is
    /// taller than 32, plus room for the shadow. Top-centred on the notch.
    static func frame(on screen: ScreenGeometry) -> CGRect {
        let width = Tokens.Size.expandedWidth + 2 * Tokens.Size.expandedFlare + 2 * Tokens.Size.shadowRadius
        let height = Tokens.Size.expandedListHeight + max(0, screen.band - Tokens.Size.expandedBand)
            + Tokens.Size.shadowRadius + Tokens.Size.shadowOffsetY
        return CGRect(x: screen.centreX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}
