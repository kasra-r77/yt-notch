import AppKit
import PlayerCore
import SwiftUI

/// The expanded Playing view, 400 × 148 (design spec D2). Positions are from the body's top
/// left; a notch taller than 32 moves everything below the band down by the difference.
struct PlayingView: View {
    let state: PlayerState
    let model: NotchModel
    let actions: NotchActions
    /// How much taller the band is than 32.
    let extra: CGFloat

    typealias S = Tokens.Size

    var body: some View {
        TimelineView(.animation(minimumInterval: Tokens.Timing.progressRefresh, paused: !state.isPlaying)) { context in
            let p = PlayingPresentation(state, at: context.date, forced: model.forcedState)
            ZStack(alignment: .topLeading) {
                band(p)
                ArtworkTile(image: p.hasTrack ? model.artwork : nil, size: S.artwork, radius: Tokens.Radius.artwork,
                            placeholderSymbol: p.hasTrack ? Tokens.Symbol.noArtwork : nil)
                    .offset(x: S.expandedPadding, y: S.titleY + extra)
                titleAndArtist(p)
                    .offset(x: S.textColumnX, y: S.titleY + extra)
                ProgressBand(presentation: p, accent: SwiftUI.Color(accent: model.accent), actions: actions)
                    .offset(x: S.textColumnX, y: S.progressY + S.progressRow / 2 - S.progressHitHeight / 2 + extra)
                controls(p)
                    .offset(x: S.textColumnX, y: S.controlsY + extra)
            }
            .frame(width: S.expandedWidth, height: S.expandedPlayingHeight + extra, alignment: .topLeading)
        }
    }

    // MARK: The band

    private func band(_ p: PlayingPresentation) -> some View {
        let bandHeight = S.expandedBand + extra
        return HStack(spacing: 0) {
            ViewSwitcher(selected: .playing, showsPlaylists: p.showsPlaylistsTab, showsUpNext: p.showsUpNextTab, select: actions.select)
            Spacer(minLength: 0)
            HStack(spacing: S.earGap) {
                Button(action: actions.toggleLike) {
                    Image(systemName: p.likeSymbol).font(Tokens.Font.icon)
                }
                .buttonStyle(NotchControlStyle())
                .disabled(!p.canLike)
                .help(PlayingPresentation.help(p.likeLabel, enabled: p.canLike))
                .accessibilityLabel(p.likeLabel)
                Button(action: actions.open) {
                    Image(systemName: Tokens.Symbol.open).font(Tokens.Font.icon)
                }
                .buttonStyle(NotchControlStyle())
                .disabled(actions.openFullWindow == nil)
                .help("Open YouTube Music")
                .accessibilityLabel("Open YouTube Music")
            }
        }
        .padding(.horizontal, S.expandedPadding)
        .frame(width: S.expandedWidth, height: bandHeight)
    }

    // MARK: Title and artist

    @ViewBuilder private func titleAndArtist(_ p: PlayingPresentation) -> some View {
        if p.hasTrack {
            VStack(alignment: .leading, spacing: S.lineGap) {
                Text(p.title)
                    .font(Tokens.Font.title)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text(p.artist)
                    .font(Tokens.Font.secondary)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: S.textColumnWidth, alignment: .leading)
            .help(p.help)
        } else {
            // Loading: two still bars where the title and artist will be.
            VStack(alignment: .leading, spacing: S.artistY - S.titleY - S.skeletonTitle.height) {
                RoundedRectangle(cornerRadius: Tokens.Radius.skeleton)
                    .fill(Tokens.Color.skeletonStrong)
                    .frame(width: S.skeletonTitle.width, height: S.skeletonTitle.height)
                RoundedRectangle(cornerRadius: Tokens.Radius.skeleton)
                    .fill(Tokens.Color.placeholder)
                    .frame(width: S.skeletonArtist.width, height: S.skeletonArtist.height)
            }
            .padding(.top, S.skeletonTitleTop)
        }
    }

    // MARK: Controls

    /// Shuffle, previous, play or pause, next, repeat: each takes a 44 wide column down to
    /// the bottom edge, so a click between two controls lands on the nearer one.
    private func controls(_ p: PlayingPresentation) -> some View {
        let height = S.expandedPlayingHeight + extra - (S.controlsY + extra)
        return HStack(spacing: 0) {
            if p.showsShuffle {
                transport(Tokens.Symbol.shuffle, label: p.shuffleOn ? "Shuffle On" : "Shuffle Off", quiet: !p.shuffleOn, isOn: p.shuffleOn,
                          enabled: p.canShuffle, action: actions.toggleShuffle)
            }
            transport(Tokens.Symbol.previous, label: "Previous", enabled: p.canPrevious, action: actions.previous)
            transport(p.playSymbol, label: p.playLabel, font: Tokens.Font.playIcon, enabled: p.canPlayPause, action: actions.togglePlayPause)
            transport(Tokens.Symbol.next, label: "Next", enabled: p.canNext, action: actions.next)
            if p.showsRepeat {
                transport(p.repeatSymbol, label: p.repeatLabel, quiet: !p.repeatOn, isOn: p.repeatOn,
                          enabled: p.canRepeat, action: actions.cycleRepeat)
            }
        }
        .frame(width: S.textColumnWidth, height: height, alignment: .top)
    }

    private func transport(_ symbol: String, label: String, font: SwiftUI.Font = Tokens.Font.icon, quiet: Bool = false, isOn: Bool = false,
                           enabled: Bool, action: @escaping () -> Void) -> some View {
        let height = S.expandedPlayingHeight + extra - (S.controlsY + extra)
        return Button(action: action) {
            Image(systemName: symbol).font(font)
        }
        .buttonStyle(NotchControlStyle(quiet: quiet, isOn: isOn, hitSize: CGSize(width: S.transportHitWidth, height: height)))
        .disabled(!enabled)
        .help(PlayingPresentation.help(label, enabled: enabled))
        .accessibilityLabel(label)
    }
}

/// The view switcher in the left ear: Playing, Playlists, Up next. A tab whose view has no
/// data is hidden and the others close up.
struct ViewSwitcher: View {
    let selected: HoverMachine.ExpandedView
    let showsPlaylists: Bool
    let showsUpNext: Bool
    let select: @MainActor (HoverMachine.ExpandedView) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.playing, symbol: Tokens.Symbol.tabPlaying, label: "Playing")
            if showsPlaylists { tab(.playlists, symbol: Tokens.Symbol.tabPlaylists, label: "Playlists") }
            if showsUpNext { tab(.upNext, symbol: Tokens.Symbol.tabUpNext, label: "Up next") }
        }
    }

    private func tab(_ view: HoverMachine.ExpandedView, symbol: String, label: String) -> some View {
        Button { select(view) } label: {
            Image(systemName: symbol).font(Tokens.Font.icon)
        }
        .buttonStyle(NotchControlStyle(quiet: true, isSelected: view == selected))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(view == selected ? .isSelected : [])
    }
}

/// Every control in the notch: 28 square, radius 8. Hover white 10%, pressed and selected
/// white 16%, unavailable white 25% with no hover. A quiet control (an unselected tab, a
/// toggle that is off) rests at 60% and comes up to 100% under the pointer. A toggle that is
/// on gets a 4 pt dot under its icon.
struct NotchControlStyle: ButtonStyle {
    var quiet = false
    var isOn = false
    var isSelected = false
    /// The area that takes the click, if larger than the 28 square (it grows down and out).
    var hitSize: CGSize?

    func makeBody(configuration: Configuration) -> some View {
        NotchControlBody(configuration: configuration, quiet: quiet, isOn: isOn, isSelected: isSelected, hitSize: hitSize)
    }
}

private struct NotchControlBody: View {
    let configuration: ButtonStyleConfiguration
    let quiet: Bool
    let isOn: Bool
    let isSelected: Bool
    let hitSize: CGSize?
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let size = Tokens.Size.control
        configuration.label
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(background))
            .overlay(alignment: .bottom) {
                if isOn && isEnabled {
                    Circle()
                        .fill(foreground)
                        .frame(width: Tokens.Size.toggleDot, height: Tokens.Size.toggleDot)
                        .padding(.bottom, Tokens.Size.toggleDotInset)
                }
            }
            .frame(width: hitSize?.width ?? size, height: hitSize?.height ?? size, alignment: .top)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private var foreground: SwiftUI.Color {
        if !isEnabled { return Tokens.Color.textDisabled }
        if quiet && !isOn && !isSelected && !isHovering && !configuration.isPressed { return Tokens.Color.textSecondary }
        return Tokens.Color.textPrimary
    }

    private var background: SwiftUI.Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return Tokens.Color.pressed }
        if isSelected { return Tokens.Color.selected }
        if isHovering { return Tokens.Color.hover }
        return .clear
    }
}

/// Elapsed, the track, total; 268 wide with a 28 tall band that takes clicks and drags.
/// Idle: no knob. Hover: a 10 pt knob. Dragging: a 12 pt knob with a halo, and the elapsed
/// time follows it; the seek happens on release.
struct ProgressBand: View {
    let presentation: PlayingPresentation
    let accent: SwiftUI.Color
    let actions: NotchActions

    @State private var isHovering = false
    @State private var dragFraction: Double?
    @State private var trackFrame: CGRect = .zero

    typealias S = Tokens.Size

    var body: some View {
        let p = presentation
        let fraction = dragFraction ?? p.progress
        HStack(spacing: S.timeGap) {
            Text(dragFraction.map { PlayingPresentation.time($0 * (p.duration ?? 0)) } ?? p.elapsed)
                .foregroundStyle(dragFraction == nil ? Tokens.Color.textSecondary : Tokens.Color.textPrimary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Color.track).frame(height: S.track)
                    Capsule().fill(accent).frame(width: geometry.size.width * fraction, height: S.track)
                    if p.canSeek && (isHovering || dragFraction != nil) {
                        knob.offset(x: geometry.size.width * fraction - knobSize / 2)
                    }
                }
                .frame(maxHeight: .infinity)
                .onAppear { trackFrame = geometry.frame(in: .named(Self.space)) }
                .onChange(of: geometry.size) { trackFrame = geometry.frame(in: .named(Self.space)) }
            }
            .frame(height: S.progressRow)
            Text(p.total)
                .foregroundStyle(Tokens.Color.textSecondary)
        }
        .font(Tokens.Font.time)
        .frame(width: S.textColumnWidth, height: S.progressHitHeight)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.space)
        .onHover { isHovering = $0 }
        .gesture(seeking)
        .opacity(p.hasTrack && !p.canSeek ? Tokens.Opacity.unavailableProgress : 1)
        .allowsHitTesting(p.canSeek)
    }

    private static let space = "progress"

    private var knobSize: CGFloat { dragFraction == nil ? S.knob : S.dragKnob }

    private var knob: some View {
        Circle()
            .fill(Tokens.Color.textPrimary)
            .frame(width: knobSize, height: knobSize)
            .shadow(color: dragFraction == nil ? Tokens.Color.knobShadow : .clear, radius: S.knobShadowRadius, y: S.knobShadowY)
            .background(Circle().fill(Tokens.Color.halo).padding(dragFraction == nil ? 0 : -S.halo))
    }

    private var seeking: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard trackFrame.width > 0 else { return }
                dragFraction = min(1, max(0, (value.location.x - trackFrame.minX) / trackFrame.width))
            }
            .onEnded { _ in
                if let dragFraction { actions.seek(toFraction: dragFraction) }
                dragFraction = nil
            }
    }
}
