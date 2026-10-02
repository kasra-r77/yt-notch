import AppKit
import Observation
import SwiftUI

/// The notch on one display.
///
/// A borderless panel above the menu bar, on every Space, that never takes keyboard focus
/// and never activates the app, so typing elsewhere is never interrupted. It stays the same
/// size and draws each shape top-centred. Only the shape takes clicks: the panel ignores
/// mouse events except while the pointer is inside the target shape, so everywhere else
/// clicks reach the app underneath. It fades in when it is built, and fades out while another
/// app is full screen on its display.
///
/// Panels don't watch the system themselves: `NotchDisplayManager` creates and removes
/// them, and tells them about display changes and full screen.
///
/// Built on our own panel rather than DynamicNotchKit; see `docs/decisions.md`.
@MainActor
public final class NotchPanel {
    public private(set) var screen: ScreenGeometry
    public private(set) var isFullScreen = false

    let model: NotchModel
    let window: NotchWindow
    private let pointer: PointerTracker
    private var pointerObservation: Int?
    private var cachedHitPath: (outline: NotchOutline, size: CGSize, path: CGPath)?

    public init(screen: ScreenGeometry, pointer: PointerTracker = .shared) {
        self.screen = screen
        self.pointer = pointer
        model = NotchModel(outline: .idle(on: screen))
        window = NotchWindow(frame: PanelLayout.frame(on: screen))

        let host = NSHostingView(rootView: NotchRootView(model: model))
        // The panel's size is fixed by PanelLayout; the content must not resize it.
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()

        pointerObservation = pointer.observe { [weak self] location in self?.pointerMoved(to: location) }
        pointerMoved(to: pointer.location)
    }

    /// Takes new sizes and position after the display changed (resolution, arrangement,
    /// menu bar).
    public func update(screen: ScreenGeometry) {
        guard screen != self.screen else { return }
        self.screen = screen
        model.outline = .idle(on: screen)
        window.setFrame(PanelLayout.frame(on: screen), display: true)
        pointerMoved(to: pointer.location)
    }

    /// Hides the notch while another app is full screen on this display, and shows it again
    /// after. It fades over 0.15 s and takes no clicks while hidden.
    public func setFullScreen(_ isFullScreen: Bool) {
        guard isFullScreen != self.isFullScreen else { return }
        self.isFullScreen = isFullScreen
        model.isHidden = isFullScreen
        pointerMoved(to: pointer.location)
    }

    public private(set) var isClosed = false

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        if let pointerObservation { pointer.stopObserving(pointerObservation) }
        pointerObservation = nil
        window.close()
    }

    // MARK: Hit testing

    /// Whether a point in screen coordinates is inside the shape the notch is heading for.
    /// While a shape animates, this is its target, as the spec asks.
    public func contains(_ point: CGPoint) -> Bool {
        let frame = window.frame
        // Most pointer moves are nowhere near the panel. Its top edge counts as inside.
        guard !isFullScreen, !isClosed, (frame.minX...frame.maxX).contains(point.x), (frame.minY...frame.maxY).contains(point.y) else {
            return false
        }
        // Into the panel's y-down space. The top row of pixels counts as inside, so throwing
        // the pointer against the top edge hits the notch.
        let local = CGPoint(x: point.x - frame.minX, y: max(frame.maxY - point.y, 0.5))
        return hitPath(in: frame.size).contains(local)
    }

    /// The target shape's path, kept until the shape or the panel changes. CGPath's test,
    /// not SwiftUI's: SwiftUI's `Path.contains` misreads the joined outline.
    private func hitPath(in size: CGSize) -> CGPath {
        if let cached = cachedHitPath, cached.outline == model.outline, cached.size == size { return cached.path }
        let path = NotchShape.path(model.outline, topCentre: CGPoint(x: size.width / 2, y: 0)).cgPath
        cachedHitPath = (model.outline, size, path)
        return path
    }

    func pointerMoved(to location: CGPoint) {
        let ignores = !contains(location)
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }
}

/// What the notch's view draws. The outline is always the target; SwiftUI animates to it.
@MainActor
@Observable
final class NotchModel {
    var outline: NotchOutline
    var isHidden = false

    init(outline: NotchOutline) {
        self.outline = outline
    }
}

struct NotchRootView: View {
    let model: NotchModel
    /// False for the first frame, so a new notch fades in.
    @State private var hasAppeared: Bool

    init(model: NotchModel, fadesIn: Bool = true) {
        self.model = model
        _hasAppeared = State(initialValue: !fadesIn)
    }

    var body: some View {
        NotchShape(model.outline)
            .fill(Color.black)
            .opacity(model.isHidden || !hasAppeared ? 0 : 1)
            .animation(.linear(duration: Metrics.fade), value: model.isHidden || !hasAppeared)
            .onAppear { hasAppeared = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

/// The panel itself: borderless, non-activating, never key or main.
final class NotchWindow: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar and its status items (statusBar is mainMenu + 1), below menus.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit keeps windows clear of the menu bar; the notch sits over it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
