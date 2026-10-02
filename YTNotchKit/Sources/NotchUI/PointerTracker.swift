import AppKit

/// Watching mouse movement needs no permission; only keyboard monitoring would.
@MainActor
public final class PointerTracker {
    public static let shared = PointerTracker()

    /// In screen coordinates, like `NSEvent.mouseLocation`.
    public private(set) var location: CGPoint = NSEvent.mouseLocation
    private var handlers: [Int: @MainActor (CGPoint) -> Void] = [:]
    private var nextID = 0
    private var monitors: [Any] = []

    /// Presses and releases too: letting go of a held button can start a dwell.
    private static let movement: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    ]

    init() {}

    /// Calls `handler` with every pointer move until `stopObserving` is called with the
    /// returned ID. The tracker runs only while someone is observing.
    func observe(_ handler: @escaping @MainActor (CGPoint) -> Void) -> Int {
        nextID += 1
        handlers[nextID] = handler
        if monitors.isEmpty { startMonitoring() }
        return nextID
    }

    func stopObserving(_ id: Int) {
        handlers[id] = nil
        if handlers.isEmpty { stopMonitoring() }
    }

    /// Moves over other apps arrive through the global monitor; moves over this app's own
    /// windows (a notch taking clicks) through the local one.
    private func startMonitoring() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.movement, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.movement, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func moved() {
        deliver(NSEvent.mouseLocation)
    }

    /// Tests call it directly.
    func deliver(_ location: CGPoint) {
        self.location = location
        for handler in handlers.values { handler(location) }
    }
}
