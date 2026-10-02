import AppKit

/// Where other apps' menu bar icons are, so a pill can keep clear of them (D8). The window
/// list gives each icon's level and bounds without any permission; titles would need screen
/// recording, so they aren't read. On macOS 26 every icon's window belongs to Control
/// Centre, before that to its own app; either way they sit at the status window level.
enum MenuBarIcons {
    static var statusLevel: Int { Int(CGWindowLevelForKey(.statusWindow)) }

    /// Where the leftmost icon on a screen starts, in screen x, or nil when there are none.
    /// `windows` are in global display coordinates, as the window list reports them.
    static func firstIconX(on screen: ScreenGeometry, windows: [FullScreenDetector.WindowInfo], primaryHeight: CGFloat) -> CGFloat? {
        let display = screen.globalBounds(primaryHeight: primaryHeight)
        let menuBar = CGRect(x: display.minX, y: display.minY, width: display.width, height: screen.menuBarHeight)
        return windows
            .filter { window in
                window.layer == statusLevel && window.bounds.width > 0
                    && window.bounds.height <= screen.menuBarHeight + 1
                    && menuBar.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY))
            }
            .map(\.bounds.minX)
            .min()
    }
}
