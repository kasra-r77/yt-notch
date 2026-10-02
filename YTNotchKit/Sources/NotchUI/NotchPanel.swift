import AppKit
import Observation
import PlayerCore
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
/// Each panel runs its own `HoverMachine`, fed by the pointer, the store and a timer for the
/// machine's deadlines, and animates to the shape the machine's appearance calls for (design
/// spec, "Motion"). `NotchDisplayManager` creates and removes panels and tells them about
/// display changes and full screen.
///
/// Built on our own panel rather than DynamicNotchKit; see `docs/decisions.md`.
@MainActor
public final class NotchPanel {
    public private(set) var screen: ScreenGeometry
    public private(set) var isFullScreen = false
    public private(set) var isClosed = false

    let model: NotchModel
    let window: NotchWindow
    private(set) var machine = HoverMachine()
    private let store: PlayerStore?
    private let pointer: PointerTracker
    private let artwork: ArtworkLoader
    private var pointerObservation: Int?
    private var cachedHitPath: (outline: NotchOutline, size: CGSize, path: CGPath)?
    private var tickTask: Task<Void, Never>?
    private var lastTrackID: String?
    private var artworkURL: URL?
    private var reduceMotionObserver: NSObjectProtocol?

    /// The clock the machine runs on. Tests replace it and turn `schedulesTicks` off to
    /// drive `tick(at:)` themselves.
    var now: () -> Date = Date.init
    var schedulesTicks = true

    public init(
        screen: ScreenGeometry,
        store: PlayerStore? = nil,
        openFullWindow: (@MainActor () -> Void)? = nil,
        retry: (@MainActor () -> Void)? = nil,
        pointer: PointerTracker = .shared
    ) {
        self.screen = screen
        self.store = store
        self.pointer = pointer
        artwork = .shared
        model = NotchModel(outline: .idle(on: screen), band: screen.band)
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.expandedExtra = NotchLayout.expandedExtra(on: screen)
        window = NotchWindow(frame: PanelLayout.frame(on: screen))
        model.actions = NotchActions(
            store: store, openFullWindow: openFullWindow, retry: retry,
            select: { [weak self] view in self?.select(view) },
            dismiss: { [weak self] in self?.dismiss() }
        )

        let host = NotchHostingView(rootView: NotchRootView(model: model))
        // The panel's size is fixed by PanelLayout; the content must not resize it.
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()

        pointerObservation = pointer.observe { [weak self] location in self?.pointerMoved(to: location) }
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
        observeStore()
        refreshHitTesting()
    }

    /// Takes new sizes and position after the display changed (resolution, arrangement,
    /// menu bar).
    public func update(screen: ScreenGeometry) {
        guard screen != self.screen else { return }
        self.screen = screen
        model.band = screen.band
        model.expandedExtra = NotchLayout.expandedExtra(on: screen)
        model.outline = NotchLayout.outline(for: machine.appearance, on: screen, peekTextWidth: peekTextWidth)
        window.setFrame(PanelLayout.frame(on: screen), display: true)
        refreshHitTesting()
    }

    /// Hides the notch while another app is full screen on this display, and shows it again
    /// after. It fades over 0.15 s, closes at once if it was open, and takes no clicks.
    public func setFullScreen(_ isFullScreen: Bool) {
        guard isFullScreen != self.isFullScreen else { return }
        self.isFullScreen = isFullScreen
        model.isHidden = isFullScreen
        machine.fullScreen(isFullScreen, at: now())
        apply()
    }

    /// What Open, Sign In and Open Full Window do. Nil disables them.
    public var openFullWindow: (@MainActor () -> Void)? {
        get { model.actions.openFullWindow }
        set { model.actions.openFullWindow = newValue }
    }

    /// What Try Again does. Nil disables it.
    public var retry: (@MainActor () -> Void)? {
        get { model.actions.retry }
        set { model.actions.retry = newValue }
    }

    /// Forces a message or missing parts over what the player reports (the debug menu).
    public var forcedState: NotchForcedState? {
        get { model.forcedState }
        set {
            guard newValue != model.forcedState else { return }
            model.forcedState = newValue
            if let store { read(store.state) }
        }
    }

    /// Closes the notch at once (Open, Sign In, Open Full Window).
    func dismiss() {
        machine.dismiss(at: now())
        apply()
    }

    /// Switches the open notch to another view (N2.7).
    public func select(_ view: HoverMachine.ExpandedView) {
        machine.select(view)
        apply()
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        if let pointerObservation { pointer.stopObserving(pointerObservation) }
        pointerObservation = nil
        if let reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
        reduceMotionObserver = nil
        tickTask?.cancel()
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
        let inside = contains(location)
        let ignores = !inside
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
        machine.pointer(inside: inside, buttonDown: NSEvent.pressedMouseButtons != 0, at: now())
        apply()
    }

    private func refreshHitTesting() {
        let ignores = !contains(pointer.location)
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }

    // MARK: The machine

    /// Moves the machine's clock on, then shows what it says.
    func tick(at time: Date) {
        machine.tick(at: time)
        apply()
    }

    /// Brings the model, and so the view, in line with the machine.
    private func apply() {
        guard !isClosed else { return }
        let appearance = machine.appearance
        let previous = model.appearance
        let outline = NotchLayout.outline(for: appearance, on: screen, peekTextWidth: peekTextWidth)
        if appearance != previous || outline != model.outline {
            applyFades(from: previous, to: appearance)
            let motion = NotchMotion.between(previous, appearance, reduceMotion: model.reduceMotion)
            let animation = motion.animation ?? (outline != model.outline && appearance == previous ? Tokens.Motion.spring : nil)
            if let animation {
                withAnimation(animation, completionCriteria: .logicallyComplete) {
                    model.appearance = appearance
                    model.outline = outline
                } completion: { [weak self] in
                    self?.settled()
                }
            } else {
                model.appearance = appearance
                model.outline = outline
                settled()
            }
        }
        refreshHitTesting()
        scheduleTick()
    }

    /// Wings, peek text and expanded content each fade on their own clock (design spec,
    /// "Motion"): content in from 60% open, wings out at once and back near the end.
    private func applyFades(from previous: HoverMachine.Appearance, to appearance: HoverMachine.Appearance) {
        let reduce = model.reduceMotion
        let wings = appearance.showsWings
        if wings != model.wingsShown {
            let animation: Animation
            if reduce {
                animation = Tokens.Motion.crossfade
            } else if !wings {
                animation = .linear(duration: Tokens.Timing.wingsFadeOut)
            } else if previous.isExpanded {
                animation = .linear(duration: Tokens.Timing.wingsFadeIn).delay(Tokens.Timing.wingsFadeInDelay)
            } else {
                animation = .linear(duration: Tokens.Timing.wingContentFadeIn).delay(Tokens.Timing.wingsIn - Tokens.Timing.wingContentFadeIn)
            }
            withAnimation(animation) { model.wingsShown = wings }
        }
        let peek = appearance == .collapsed(.peek)
        if peek != model.peekShown {
            withAnimation(fade(in: peek, reduce: reduce)) { model.peekShown = peek }
        }
        if case let .expanded(expandedContent) = appearance { model.expandedContent = expandedContent }
        let content = appearance.isExpanded
        if content != model.contentShown {
            withAnimation(fade(in: content, reduce: reduce)) { model.contentShown = content }
        }
    }

    private func fade(in isIn: Bool, reduce: Bool) -> Animation {
        if reduce { return Tokens.Motion.crossfade }
        return isIn
            ? .easeOut(duration: Tokens.Timing.contentFadeIn).delay(Tokens.Timing.contentFadeInDelay)
            : .linear(duration: Tokens.Timing.contentFadeOut)
    }

    /// The shape has arrived. A peek starts its hold now; a resize lets the grace start if
    /// it left the pointer outside.
    private func settled() {
        guard !isClosed else { return }
        let time = now()
        machine.peekFullyOut(at: time)
        machine.pointer(inside: contains(pointer.location), buttonDown: NSEvent.pressedMouseButtons != 0, at: time)
        machine.resizeSettled(at: time)
        if machine.appearance != model.appearance { apply() } else { scheduleTick() }
    }

    private func scheduleTick() {
        tickTask?.cancel()
        guard schedulesTicks, let deadline = machine.nextDeadline else { return }
        tickTask = Task { [weak self] in
            let delay = deadline.timeIntervalSince(Date())
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.tick(at: self.now())
        }
    }

    // MARK: The store

    private var peekTextWidth: CGFloat {
        NotchLayout.peekTextWidth(title: model.title, artist: model.artist)
    }

    /// Reads the store now, and again after each change to what the notch shows.
    private func observeStore() {
        guard let store, !isClosed else { return }
        withObservationTracking {
            read(store.state)
        } onChange: { [weak self] in
            // Called before the change lands; read it on the next turn.
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func read(_ state: PlayerState) {
        let time = now()
        let track = state.track
        model.isPlaying = state.isPlaying
        model.title = track?.title ?? ""
        model.artist = track?.artist ?? ""
        machine.playback(hasTrack: track != nil, isPlaying: state.isPlaying)
        if let id = track?.id, let last = lastTrackID, id != last { machine.trackChanged(at: time) }
        lastTrackID = track?.id
        model.message = MessagePresentation.kind(for: state, forced: model.forcedState)
        machine.attention(model.message != nil)
        loadArtwork(track?.artworkURL)
        apply()
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        guard let url else {
            model.artwork = nil
            model.accent = .white
            return
        }
        if let cached = artwork.cached(url) {
            model.artwork = cached.image
            model.accent = cached.accent
            return
        }
        Task { [weak self] in
            guard let self, let loaded = await self.artwork.artwork(for: url), self.artworkURL == url else { return }
            self.model.artwork = loaded.image
            self.model.accent = loaded.accent
        }
    }
}

extension HoverMachine.Appearance {
    var isExpanded: Bool {
        if case .expanded = self { true } else { false }
    }

    /// Artwork and bars show in the wings while collapsed and playing or peeking.
    var showsWings: Bool {
        self == .collapsed(.playing) || self == .collapsed(.peek)
    }
}

/// What the notch's views draw. The outline is always the target; SwiftUI animates to it.
@MainActor
@Observable
final class NotchModel {
    var outline: NotchOutline
    var appearance: HoverMachine.Appearance = .collapsed(.idle)
    /// The collapsed band: notch height, or menu bar height.
    var band: CGFloat
    var isHidden = false
    var reduceMotion = false
    var wingsShown = false
    var peekShown = false
    var contentShown = false
    var isPlaying = false
    var title = ""
    var artist = ""
    var artwork: NSImage?
    var accent: AccentColor = .white
    /// How much taller the expanded shapes are than designed, for a tall notch.
    var expandedExtra: CGFloat = 0
    /// What the open notch shows, kept after it closes so the content can fade out.
    var expandedContent: HoverMachine.ExpandedContent?
    /// The message the open notch shows instead of a view, if any.
    var message: NotchMessage?
    var forcedState: NotchForcedState?
    var actions = NotchActions(store: nil)

    init(outline: NotchOutline, band: CGFloat) {
        self.outline = outline
        self.band = band
    }
}

/// Takes the first click in the panel, which is never key, so a control works on the first
/// press instead of only bringing the window forward.
final class NotchHostingView: NSHostingView<NotchRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
