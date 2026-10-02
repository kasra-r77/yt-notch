import AppKit
import SwiftUI

/// Everything the notch draws, top-centred in its panel: the shape, the wings, the peek's
/// line and the expanded content.
struct NotchRootView: View {
    let model: NotchModel
    /// False for the first frame, so a new notch fades in.
    @State private var hasAppeared: Bool

    init(model: NotchModel, fadesIn: Bool = true) {
        self.model = model
        _hasAppeared = State(initialValue: !fadesIn)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
            WingsView(model: model)
                .opacity(model.wingsShown ? 1 : 0)
            PeekLine(model: model)
                .opacity(model.peekShown ? 1 : 0)
            ExpandedContent(model: model)
                .opacity(model.contentShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(model.isHidden || !hasAppeared ? 0 : 1)
        .animation(Tokens.Motion.fade, value: model.isHidden || !hasAppeared)
        .onAppear { hasAppeared = true }
        .ignoresSafeArea()
    }

    /// The shape morphs between outlines; under Reduce Motion the old and new shapes
    /// crossfade in place instead.
    @ViewBuilder private var shape: some View {
        let body = NotchShape(model.outline)
            .fill(Tokens.Color.surface)
            .shadow(color: Tokens.Color.shadow.opacity(model.contentShown ? 1 : 0),
                    radius: Tokens.Size.shadowRadius / 2, y: Tokens.Size.shadowOffsetY)
        if model.reduceMotion {
            body.id(model.outline).transition(.opacity)
        } else {
            body
        }
    }
}

/// Artwork on the left wing, bars on the right, 12 in from each outer edge, on the band.
/// Nothing is drawn where the real notch is: both sit in the outer 44.
struct WingsView: View {
    let model: NotchModel

    var body: some View {
        let size = NotchLayout.wingArtworkSize(band: model.band)
        HStack(spacing: 0) {
            ArtworkTile(image: model.artwork, size: size,
                        radius: size >= Tokens.Size.wingArtwork ? Tokens.Radius.wingArtwork : Tokens.Radius.wingArtworkSmall)
            Spacer(minLength: 0)
            BarsView(accent: SwiftUI.Color(accent: model.accent),
                     isAnimating: model.isPlaying && model.wingsShown && !model.reduceMotion,
                     maxHeight: NotchLayout.barMaxHeight(band: model.band))
        }
        .padding(.horizontal, Tokens.Size.wingInset)
        .frame(width: model.outline.width, height: model.band)
    }
}

struct ArtworkTile: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Tokens.Color.placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Four bars in the accent. They swing while audio plays and rest otherwise; at rest the
/// timeline is paused, so a paused notch costs nothing.
struct BarsView: View {
    let accent: SwiftUI.Color
    let isAnimating: Bool
    let maxHeight: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isAnimating)) { context in
            HStack(alignment: .bottom, spacing: Tokens.Size.barGap) {
                ForEach(0..<Tokens.Size.barRestHeights.count, id: \.self) { bar in
                    RoundedRectangle(cornerRadius: Tokens.Radius.bar)
                        .fill(accent)
                        .frame(width: Tokens.Size.barWidth,
                               height: BarMotion.height(bar: bar, at: context.date.timeIntervalSinceReferenceDate,
                                                        isAnimating: isAnimating, maxHeight: maxHeight))
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
    }
}

/// The height of one bar at a moment.
enum BarMotion {
    static func height(bar: Int, at time: TimeInterval, isAnimating: Bool, maxHeight: CGFloat) -> CGFloat {
        let scale = maxHeight / Tokens.Size.barMaxHeight
        guard isAnimating else { return Tokens.Size.barRestHeights[bar] * scale }
        // A swing is low to high; a full cycle is two swings, eased at both ends.
        let cycle = 2 * Tokens.Timing.barSwings[bar]
        let phase = (time / cycle + Tokens.Timing.barPhases[bar]).truncatingRemainder(dividingBy: 1)
        let eased = 0.5 - 0.5 * cos(phase * 2 * .pi)
        let low = Tokens.Size.barLow * maxHeight
        return low + (maxHeight - low) * CGFloat(eased)
    }
}

/// The peek's one line under the band: the title, 6, the artist, centred. The title is cut
/// first; the artist stays whole.
struct PeekLine: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: Tokens.Size.peekTextGap) {
            Text(model.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !model.artist.isEmpty {
                Text(model.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .id(trackKey)
        .transition(.opacity)
        .animation(Tokens.Motion.crossfade, value: trackKey)
        .frame(width: lineWidth, height: lineHeight, alignment: .top)
        .padding(.top, model.band + Tokens.Size.peekTextTop)
    }

    /// Changes with the track, so a new title crossfades in.
    private var trackKey: String { model.title + "\n" + model.artist }
    private var lineWidth: CGFloat { max(0, model.outline.width - 2 * Tokens.Size.peekPadding) }
    private var lineHeight: CGFloat { Tokens.Size.peekRow - Tokens.Size.peekTextTop }
}

/// Where the expanded views go: Playing (N2.5), the messages (N2.6) and the lists (N2.7).
/// Laid out at the final size and revealed by the growing shape.
struct ExpandedContent: View {
    let model: NotchModel

    var body: some View {
        Color.clear
            .frame(width: model.outline.width, height: model.outline.height)
            .allowsHitTesting(false)
    }
}

extension SwiftUI.Color {
    init(accent: AccentColor) {
        self.init(.sRGB, red: accent.red, green: accent.green, blue: accent.blue, opacity: 1)
    }
}
