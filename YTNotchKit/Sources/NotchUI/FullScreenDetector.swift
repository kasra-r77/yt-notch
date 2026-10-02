import AppKit

/// Another app is full screen on a display when one of its windows at level 0 is exactly the
/// size of the display (checked on macOS 26). The window list reports that without the screen
/// recording permission. Collection behaviour alone doesn't keep a panel off a full-screen
/// Space, so the panel needs this to hide itself.
enum FullScreenDetector {
    struct WindowInfo: Equatable {
        var ownerPID: pid_t
        var layer: Int
        /// In global display coordinates (origin top left), like `CGDisplayBounds`.
        var bounds: CGRect
    }

    static func isFullScreen(display bounds: CGRect, windows: [WindowInfo], ownPID: pid_t) -> Bool {
        windows.contains { window in
            window.ownerPID != ownPID && window.layer == 0
                && abs(window.bounds.minX - bounds.minX) < 1 && abs(window.bounds.minY - bounds.minY) < 1
                && abs(window.bounds.width - bounds.width) < 1 && abs(window.bounds.height - bounds.height) < 1
        }
    }

    static func onScreenWindows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            return WindowInfo(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }
}
