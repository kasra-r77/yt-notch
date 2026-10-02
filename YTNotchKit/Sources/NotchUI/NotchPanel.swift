import AppKit
import Observation
import PlayerCore
import SwiftUI

/// The notch on one display. It never takes keyboard focus or activates the app, so typing
/// elsewhere is never interrupted. It ignores mouse events except while the pointer is inside
/// the target shape, so clicks everywhere else reach the app underneath.
@MainActor
public final class NotchPanel {
    public private(set) var screen: ScreenGeometry
    public private(set) var isFullScreen = false
    public private(set) var isClosed = false
    /// A pill with no room left of the menu bar icons is hidden until there is (D8).
    public private(set) var isCrowdedOut = false
    /// In screen x.
    public private(set) var firstIconX: CGFloat?

    let model: NotchModel
    let window: NotchWindow
    private(set) var machine = HoverMachine()
    private let store: PlayerStore?
    private let pointer: PointerTracker
    private let images: ArtworkImages
    private var pointerObservation: Int?
    private var cachedHitPath: (outline: NotchOutline, size: CGSize, path: CGPath)?
    private var tickTask: Task<Void, Never>?
    private var lastTrackID: String?
    private var reduceMotionObserver: NSObjectProtocol?

    /// Tests replace the clock and turn `schedulesTicks` off to drive `tick(at:)` themselves.
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
        images = .shared
        model = NotchModel(outline: .idle(on: screen), band: screen.band)
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.expandedExtra = NotchLayout.expandedExtra(on: screen)
        machine.peeksOnTrackChange = screen.hasNotch
        window = NotchWindow(frame: PanelLayout.frame(on: screen))
        model.actions = NotchActions(
            store: store, openFullWindow: openFullWindow, retry: retry,
            select: { [weak self] view in self?.select(view) },
            dismiss: { [weak self] in self?.dismiss() }
        )

        let host = NotchHostingView(rootView: NotchRootView(model: model))
        // The panel's size is fixed by PanelLayout; the content must not resize it.
        host.sizingOptions = []
        // The surface is always black, so system parts (the list's scroller) draw for dark.
        host.appearance = NSAppearance(named: .darkAqua)
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

    public func update(screen: ScreenGeometry) {
        guard screen != self.screen else { return }
        self.screen = screen
        model.band = screen.band
        model.expandedExtra = NotchLayout.expandedExtra(on: screen)
        machine.peeksOnTrackChange = screen.hasNotch
        model.outline = target(for: machine.appearance)
        window.setFrame(PanelLayout.frame(on: screen), display: true)
        refreshHitTesting()
    }

    public func setFullScreen(_ isFullScreen: Bool) {
        guard isFullScreen != self.isFullScreen else { return }
        self.isFullScreen = isFullScreen
        model.isHidden = isFullScreen || isCrowdedOut
        machine.fullScreen(isFullScreen, at: now())
        apply()
    }

    /// `firstX` is in screen x, or nil when there are no icons.
    public func setMenuBarIcons(firstX: CGFloat?) {
        guard firstX != firstIconX else { return }
        firstIconX = firstX
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

    public var forcedState: NotchForcedState? {
        get { model.forcedState }
        set {
            guard newValue != model.forcedState else { return }
            model.forcedState = newValue
            if let store { read(store.state) }
        }
    }

    func dismiss() {
        machine.dismiss(at: now())
        apply()
    }

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

    /// `point` is in screen coordinates. While a shape animates, this tests its target, as the
    /// spec asks.
    public func contains(_ point: CGPoint) -> Bool {
        let frame = window.frame
        // Most pointer moves are nowhere near the panel. Its top edge counts as inside.
        guard !isFullScreen, !isCrowdedOut, !isClosed, (frame.minX...frame.maxX).contains(point.x), (frame.minY...frame.maxY).contains(point.y) else {
            return false
        }
        // Into the panel's y-down space. The top row of pixels counts as inside, so throwing
        // the pointer against the top edge hits the notch.
        let local = CGPoint(x: point.x - frame.minX, y: max(frame.maxY - point.y, 0.5))
        return hitPath(in: frame.size).contains(local)
    }

    /// CGPath's test, not SwiftUI's: SwiftUI's `Path.contains` misreads the joined outline.
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

    func tick(at time: Date) {
        machine.tick(at: time)
        apply()
    }

    private func apply() {
        guard !isClosed else { return }
        let appearance = machine.appearance
        let previous = model.appearance
        let outline = target(for: appearance)
        let middle = !screen.hasNotch && appearance == .collapsed(.playing)
            && NotchLayout.pillMiddleWidth(pillWidth: outline.width, band: screen.band) >= Tokens.Size.pillMiddleMinimum
        if model.middleShown != middle { model.middleShown = middle }
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

    /// Also updates `isCrowdedOut`: a collapsed pill hides when it can't keep clear of the menu
    /// bar icons (D8).
    private func target(for appearance: HoverMachine.Appearance) -> NotchOutline {
        var outline = NotchLayout.outline(for: appearance, on: screen, peekTextWidth: peekTextWidth)
        var crowdedOut = false
        if !screen.hasNotch, case .collapsed = appearance {
            let placement = NotchLayout.pillPlacement(
                width: outline.width, flare: outline.flare, centreX: screen.centreX,
                firstIconX: firstIconX, room: PanelLayout.frame(on: screen).width / 2
            )
            outline.width = placement.width
            outline.offset = placement.offset
            crowdedOut = placement.isHidden
        }
        if crowdedOut != isCrowdedOut {
            isCrowdedOut = crowdedOut
            model.isHidden = isFullScreen || crowdedOut
        }
        return outline
    }

    /// Wings, peek text and expanded content each fade on their own clock (design spec,
    /// "Motion").
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
        if case let .expanded(expandedContent) = appearance, expandedContent != model.expandedContent {
            switchContent(to: expandedContent, switching: previous.isExpanded, reduce: reduce)
        }
        let content = appearance.isExpanded
        if content != model.contentShown {
            withAnimation(fade(in: content, reduce: reduce)) { model.contentShown = content }
        }
    }

    /// Opening shows the view with no fade of its own: the content as a whole fades in.
    private func switchContent(to content: HoverMachine.ExpandedContent, switching: Bool, reduce: Bool) {
        guard switching, let old = model.expandedContent else {
            model.viewTransition = .identity
            model.expandedContent = content
            return
        }
        let resizes = old.isList != content.isList
        let fadeIn: Animation
        if reduce {
            fadeIn = Tokens.Motion.crossfade
        } else if resizes {
            fadeIn = .easeOut(duration: Tokens.Timing.contentFadeIn).delay(Tokens.Timing.contentFadeInDelay)
        } else {
            fadeIn = .linear(duration: Tokens.Timing.contentFadeIn)
        }
        let fadeOut = reduce ? Tokens.Motion.crossfade : .linear(duration: Tokens.Timing.contentFadeOut)
        model.viewTransition = .asymmetric(insertion: .opacity.animation(fadeIn), removal: .opacity.animation(fadeOut))
        withAnimation(fadeOut) { model.expandedContent = content }
    }

    private func fade(in isIn: Bool, reduce: Bool) -> Animation {
        if reduce { return Tokens.Motion.crossfade }
        return isIn
            ? .easeOut(duration: Tokens.Timing.contentFadeIn).delay(Tokens.Timing.contentFadeInDelay)
            : .linear(duration: Tokens.Timing.contentFadeOut)
    }

    /// The shape has arrived. Tests call it to stand for the animation finishing.
    func settled() {
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
        let tabs = ListPresentation.tabs(state, forced: model.forcedState, selected: .playing)
        machine.lists(playlists: tabs.playlists, upNext: tabs.upNext)
        showArtwork(track?.artworkURL, in: state)
        apply()
    }

    private func showArtwork(_ url: URL?, in state: PlayerState) {
        let artwork = url.flatMap { url in state.artwork[url].flatMap { images.artwork(for: url, data: $0) } }
        if model.artwork !== artwork?.image { model.artwork = artwork?.image }
        let accent = artwork?.accent ?? .white
        if model.accent != accent { model.accent = accent }
    }
}

extension HoverMachine.Appearance {
    var isExpanded: Bool {
        if case .expanded = self { true } else { false }
    }

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
    var band: CGFloat
    var isHidden = false
    var reduceMotion = false
    var wingsShown = false
    var middleShown = false
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
    var viewTransition: AnyTransition = .identity
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
