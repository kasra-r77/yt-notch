import Foundation

/// When one display's notch opens, closes and peeks (design spec, "Motion → Hover").
/// Plain logic with no views or timers: it takes events with their times and says when it
/// next needs a `tick`. Reduce Motion changes only the animations, so nothing here knows
/// about it.
public struct HoverMachine: Equatable, Sendable {
    public enum Collapsed: Equatable, Sendable {
        case idle
        /// Wings either side: a track is loaded and has played.
        case playing
        case peek
    }

    public enum ExpandedView: Equatable, Sendable {
        case playing
        case playlists
        case upNext

        /// Playing is 148 tall and the lists 300, so moving between them resizes the shape.
        var isList: Bool { self != .playing }
    }

    public enum Phase: Equatable, Sendable {
        case collapsed
        case dwell(since: Date)
        case expanded
        case grace(since: Date)
    }

    public enum Appearance: Equatable, Sendable {
        /// Another app is full screen on this display.
        case hidden
        case collapsed(Collapsed)
        case expanded(ExpandedContent)
    }

    public enum ExpandedContent: Equatable, Sendable {
        case view(ExpandedView)
        case message

        var isList: Bool { self == .view(.playlists) || self == .view(.upNext) }
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
    /// Off on a screen without a notch, where the pill shows the title already (D8).
    public var peeksOnTrackChange = true

    /// When the peek finished sliding out. Nil while it slides out, and while the pointer
    /// rests on it (resting drops the peek's timer).
    private var peekOutSince: Date?
    private var lastClose: Close?
    private var isPointerInside = false
    private var isResizing = false
    private var waitsForPointerToLeave = false
    private var availableLists: Set<ExpandedView> = [.playlists, .upNext]

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

    /// Only losing the track takes the wings away, so pausing keeps them.
    public mutating func playback(hasTrack: Bool, isPlaying: Bool) {
        if !hasTrack {
            collapsed = .idle
            peekOutSince = nil
        } else if isPlaying, collapsed == .idle {
            collapsed = .playing
        }
    }

    public mutating func trackChanged(at now: Date) {
        guard peeksOnTrackChange, !isFullScreen, phase == .collapsed else { return }
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

    /// Called on every move, with `inside` tested against the target shape (flares included).
    /// A held button (dragging along the top edge) doesn't start a dwell.
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
            phase = .collapsed
            if collapsed == .peek { peekOutSince = now }
        case .expanded:
            if !inside, !isResizing { phase = .grace(since: now) }
        case .grace:
            if inside { phase = .expanded }
        }
    }

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

    /// Between Playing and a list the shape resizes; until `resizeSettled` the pointer
    /// leaving doesn't start the grace.
    public mutating func select(_ newView: ExpandedView) {
        guard phase == .expanded, newView != view else { return }
        if newView.isList != view.isList { isResizing = true }
        view = newView
    }

    public mutating func resizeSettled(at now: Date) {
        guard isResizing else { return }
        isResizing = false
        if phase == .expanded, !isPointerInside { phase = .grace(since: now) }
    }

    /// For controls that take the user elsewhere: closes at once, with no grace, and stays
    /// closed until the pointer has left the shape and come back.
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

    public mutating func lists(playlists: Bool, upNext: Bool) {
        availableLists = Set([playlists ? .playlists : nil, upNext ? .upNext : nil].compactMap { $0 })
    }

    /// It doesn't open the notch by itself; the next hover shows the message.
    public mutating func attention(_ needed: Bool) {
        needsAttention = needed
    }

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

    private mutating func open(at now: Date) {
        phase = .expanded
        if let lastClose, now < lastClose.at.addingTimeInterval(timing.reopenMemory),
           !lastClose.view.isList || availableLists.contains(lastClose.view) {
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
