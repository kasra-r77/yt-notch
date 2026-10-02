import AppKit

/// What the notch needs to know about one display, read from its `NSScreen` and never
/// hard-coded. In screen coordinates (points, origin at the bottom left), like
/// `NSScreen.frame`.
public struct ScreenGeometry: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var frame: CGRect
    /// The hardware notch, or nil on a display without one.
    public var notch: CGRect?
    /// The menu bar's height on this display.
    public var menuBarHeight: CGFloat

    public init(displayID: CGDirectDisplayID = 0, frame: CGRect, notch: CGRect?, menuBarHeight: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.notch = notch
        self.menuBarHeight = menuBarHeight
    }

    /// Reads the notch from the areas either side of the camera housing and the safe area at
    /// the top (design spec, "Idle on the built-in display").
    @MainActor
    public init(_ screen: NSScreen) {
        frame = screen.frame
        displayID = screen.displayID
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            let height = screen.safeAreaInsets.top
            // The left area starts at the screen's left edge, so the notch starts where it ends.
            notch = CGRect(x: frame.minX + left.width, y: frame.maxY - height, width: right.minX - left.maxX, height: height)
        } else {
            notch = nil
        }
        // The menu bar is what the visible frame leaves out at the top. With the menu bar
        // hidden there is nothing left out, so fall back to the height the menu reports.
        let reserved = frame.maxY - screen.visibleFrame.maxY
        if reserved > 0 {
            menuBarHeight = reserved
        } else if let notch {
            menuBarHeight = notch.height
        } else {
            let reported = NSApplication.shared.mainMenu?.menuBarHeight ?? 0
            menuBarHeight = reported > 0 ? reported : 24
        }
    }

    public var hasNotch: Bool { notch != nil }

    /// The strip at the top of the shape while collapsed: the notch height on a display with
    /// one, the menu bar height on any other.
    public var band: CGFloat { notch?.height ?? menuBarHeight }

    /// The x the notch is centred on.
    var centreX: CGFloat { notch?.midX ?? frame.midX }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
