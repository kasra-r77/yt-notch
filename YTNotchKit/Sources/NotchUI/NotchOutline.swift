import CoreGraphics

/// The values every notch shape is drawn from (design spec, "Corner geometry").
public struct NotchOutline: Hashable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var bottomRadius: CGFloat
    public var flare: CGFloat
    /// The body's centre, from the screen's notch centre; negative is to the left.
    public var offset: CGFloat

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, flare: CGFloat, offset: CGFloat = 0) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.flare = flare
        self.offset = offset
    }

    public var footprint: CGSize { CGSize(width: width + 2 * flare, height: height) }

    /// No flare on a hardware notch, so nothing shows past the hardware.
    public static func idle(on screen: ScreenGeometry) -> NotchOutline {
        if let notch = screen.notch {
            NotchOutline(width: notch.width, height: notch.height, bottomRadius: Tokens.Size.collapsedRadius, flare: 0)
        } else {
            NotchOutline(width: Tokens.Size.pillWidth, height: screen.menuBarHeight, bottomRadius: Tokens.Size.collapsedRadius, flare: Tokens.Size.collapsedFlare)
        }
    }
}

/// The panel never moves or resizes: it is large enough for the largest shape, and every
/// shape is drawn top-centred inside it.
enum PanelLayout {
    static func frame(on screen: ScreenGeometry) -> CGRect {
        let width = Tokens.Size.expandedWidth + 2 * Tokens.Size.expandedFlare + 2 * Tokens.Size.shadowRadius
        let height = Tokens.Size.expandedListHeight + max(0, screen.band - Tokens.Size.expandedBand)
            + Tokens.Size.shadowRadius + Tokens.Size.shadowOffsetY
        return CGRect(x: screen.centreX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}
