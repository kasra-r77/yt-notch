import Foundation

/// When one display's notch opens, closes and peeks (design spec, "Motion → Hover").
///
/// Plain logic with no views or timers: it takes events with their times, says what the
/// notch should show, and says when it next needs a `tick`. Each display has its own
/// machine, so opening one never opens another. Reduce Motion changes only the animations,
/// so nothing here knows about it.
public struct HoverMachine: Equatable, Sendable {
    /// What the collapsed notch shows.
    public enum Collapsed: Equatable, Sendable {
        case idle
        /// Wings either side: a track is loaded and has played.
        case playing
        /// The new track's title, slid out under the notch.
        case peek
    }

    /// The expanded notch's views.
    public enum ExpandedView: Equatable, Sendable {
        case playing
        case playlists
        case upNext

        /// Playing is 148 tall and the lists 300, so moving between them resizes the shape.
        var isList: Bool { self != .playing }
    }

    /// How far the pointer has got the notch.
    public enum Phase: Equatable, Sendable {
        case collapsed
        /// The pointer rests inside; the notch stays collapsed until the dwell has passed.
        case dwell(since: Date)
        case expanded
        /// The pointer has left; the notch stays open until the grace has passed.
        case grace(since: Date)
    }

    /// What the notch shows now. Shapes (N2.4) and views (N2.5) follow it.
    public enum Appearance: Equatable, Sendable {
        /// Another app is full screen on this display.
        case hidden
        case collapsed(Collapsed)
        case expanded(ExpandedContent)
    }

    public enum ExpandedContent: Equatable, Sendable {
        case view(ExpandedView)
        /// Signed out or bridge broken: one message and one button.
        case message
    }

    public struct Timing: Equatable, Sendable {
        public var dwell: TimeInterval
        public var grace: TimeInterval
        public var peekHold: TimeInterval
        public var reopenMemory: TimeInterval

        public static let tokens = Timing(
            dwell: Tokens.Timing.dwell,
            grace: Tokens.Timing.grace,
            peekHold: Tokens.Timing.peekHold,
            reopenMemory: Tokens.Timing.reopenMemory
        )
    }

    public let timing: Timing
    public private(set) var collapsed: Collapsed = .idle
    public private(set) var phase: Phase = .collapsed
    public private(set) var view: ExpandedView = .playing
    public private(set) var needsAttention = false
    public private(set) var isFullScreen = false

    /// When the peek finished sliding out. Nil while it slides out, and while the pointer
    /// rests on it (resting drops the peek's timer).
    private var peekOutSince: Date?
    private var lastClose: Close?
    private var isPointerInside = false
    private var isResizing = false
    /// After a dismiss, the pointer must leave the shape before resting on it opens it again.
    private var waitsForPointerToLeave = false

    public init(timing: Timing = .tokens) {
        self.timing = timing
    }

    public var appearance: Appearance {
        if isFullScreen { return .hidden }
        switch phase {
        case .collapsed, .dwell: return .collapsed(collapsed)
        case .expanded, .grace: return .expanded(needsAttention ? .message : .view(view))
        }
    }

    public var isExpanded: Bool {
        switch phase {
        case .expanded, .grace: true
        case .collapsed, .dwell: false
        }
    }

    /// When `tick` must next be called, if anything is waiting to happen.
    public var nextDeadline: Date? {
        switch phase {
        case let .dwell(since): since.addingTimeInterval(timing.dwell)
        case let .grace(since): since.addingTimeInterval(timing.grace)
        case .expanded: nil
        case .collapsed: collapsed == .peek ? peekOutSince?.addingTimeInterval(timing.peekHold) : nil
        }
    }

    // MARK: Events

    /// What the player reports. A track that starts playing brings the wings out; only
    /// losing the track takes them away, so pausing keeps them.
    public mutating func playback(hasTrack: Bool, isPlaying: Bool) {
        if !hasTrack {
            collapsed = .idle
            peekOutSince = nil
        } else if isPlaying, collapsed == .idle {
            collapsed = .playing
        }
    }

    /// The track changed. A collapsed Playing notch peeks; a peek already out crossfades
    /// its text and holds again from now. Never while expanded or full screen.
    public mutating func trackChanged(at now: Date) {
        guard !isFullScreen, phase == .collapsed else { return }
        switch collapsed {
        case .idle:
            break
        case .playing:
            collapsed = .peek
            peekOutSince = nil
        case .peek:
            if peekOutSince != nil { peekOutSince = now }
        }
    }

    /// The peek has finished sliding out; its hold starts now.
    public mutating func peekFullyOut(at now: Date) {
        guard collapsed == .peek, phase == .collapsed, peekOutSince == nil else { return }
        peekOutSince = now
    }

    /// The pointer, on every move: inside the target shape (flares included) or not, and
    /// whether a mouse button is held. Moving within the shape doesn't restart the dwell,
    /// and a held button (dragging along the top edge) doesn't start one.
    public mutating func pointer(inside: Bool, buttonDown: Bool, at now: Date) {
        isPointerInside = inside
        guard !isFullScreen else { return }
        switch phase {
        case .collapsed:
            if waitsForPointerToLeave {
                if !inside { waitsForPointerToLeave = false }
                return
            }
            guard inside, !buttonDown else { return }
            phase = .dwell(since: now)
            if collapsed == .peek { peekOutSince = nil }
        case .dwell:
            guard !inside else { return }
            // Back to where it was; nothing moves. A peek holds again from now.
            phase = .collapsed
            if collapsed == .peek { peekOutSince = now }
        case .expanded:
            if !inside, !isResizing { phase = .grace(since: now) }
        case .grace:
            if inside { phase = .expanded }
        }
    }

    /// Moves time on: opens after the dwell, closes after the grace, takes a peek back after
    /// its hold.
    public mutating func tick(at now: Date) {
        guard let deadline = nextDeadline, now >= deadline else { return }
        switch phase {
        case .dwell: open(at: now)
        case .grace: close(at: now)
        case .collapsed:
            collapsed = .playing
            peekOutSince = nil
        case .expanded: break
        }
    }

    /// Picks a view in the open notch. Switching never closes it; between Playing and a
    /// list the shape resizes, and until `resizeSettled` the pointer leaving doesn't start
    /// the grace.
    public mutating func select(_ newView: ExpandedView) {
        guard phase == .expanded, newView != view else { return }
        if newView.isList != view.isList { isResizing = true }
        view = newView
    }

    /// The resize has settled. If it left the pointer outside, the grace starts now.
    public mutating func resizeSettled(at now: Date) {
        guard isResizing else { return }
        isResizing = false
        if phase == .expanded, !isPointerInside { phase = .grace(since: now) }
    }

    /// Something in the open notch took the user elsewhere (Open, Sign In, Open Full
    /// Window): it closes at once, with no grace, and stays closed until the pointer has left
    /// the shape and come back.
    public mutating func dismiss(at now: Date) {
        switch phase {
        case .expanded, .grace:
            close(at: now)
            waitsForPointerToLeave = isPointerInside
        case .dwell:
            phase = .collapsed
            waitsForPointerToLeave = isPointerInside
        case .collapsed:
            break
        }
    }

    /// Signed out or bridge broken: the open notch shows one message and one button
    /// instead of a view. It doesn't open by itself; the next hover shows it.
    public mutating func attention(_ needed: Bool) {
        needsAttention = needed
    }

    /// A full-screen app took this display, or let it go. While it is full screen the notch
    /// is hidden: an open notch closes at once with no grace, a peek ends, and hovering does
    /// nothing.
    public mutating func fullScreen(_ isOn: Bool, at now: Date) {
        guard isOn != isFullScreen else { return }
        isFullScreen = isOn
        guard isOn else { return }
        switch phase {
        case .expanded, .grace: close(at: now)
        case .dwell: phase = .collapsed
        case .collapsed: break
        }
        if collapsed == .peek {
            collapsed = .playing
            peekOutSince = nil
        }
    }

    // MARK: Opening and closing

    /// Opens on Playing, unless it closed less than `reopenMemory` ago: then on the view it
    /// closed on. Opening from a peek drops the peek.
    private mutating func open(at now: Date) {
        phase = .expanded
        if let lastClose, now < lastClose.at.addingTimeInterval(timing.reopenMemory) {
            view = lastClose.view
        } else {
            view = .playing
        }
        if collapsed == .peek {
            collapsed = .playing
            peekOutSince = nil
        }
    }

    private struct Close: Equatable, Sendable {
        var at: Date
        var view: ExpandedView
    }

    private mutating func close(at now: Date) {
        lastClose = Close(at: now, view: view)
        phase = .collapsed
        isResizing = false
    }
}
