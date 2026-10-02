import PlayerCore
import SwiftUI

/// The playing pill's middle on a screen without a notch (D8, option A).
struct PillTitle: View {
    let title: String
    let artist: String
    let isPlaying: Bool
    let reduceMotion: Bool

    @State private var started = Date()

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width
            let overflow = NotchLayout.pillTextWidth(title: title, artist: artist) - available
            if overflow <= 0 {
                line.frame(width: available, height: geometry.size.height)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !scrolls)) { context in
                    let offset = scrolls ? NotchLayout.pillScrollOffset(overflow: overflow, elapsed: context.date.timeIntervalSince(started)) : 0
                    line
                        .offset(x: -offset)
                        .frame(width: available, height: geometry.size.height, alignment: .leading)
                        .mask(fades(offset: offset, overflow: overflow))
                }
            }
        }
        .onChange(of: title + "\n" + artist) { started = Date() }
        .onChange(of: isPlaying) { started = Date() }
    }

    private var scrolls: Bool { isPlaying && !reduceMotion }

    private var line: some View {
        HStack(spacing: Tokens.Size.pillTextGap) {
            Text(title)
                .font(Tokens.Font.pillTitle)
                .foregroundStyle(Tokens.Color.textPrimary)
            if !artist.isEmpty {
                Text(artist)
                    .font(Tokens.Font.pillArtist)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Fades the edge the text runs past: none at the very start, none at the very end.
    private func fades(offset: CGFloat, overflow: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: min(Tokens.Size.pillFadeStart, offset))
            SwiftUI.Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: min(Tokens.Size.pillFadeEnd, max(0, overflow - offset)))
        }
    }
}

struct PillProgressLine: View {
    let state: PlayerState
    let accent: SwiftUI.Color

    var body: some View {
        TimelineView(.animation(minimumInterval: Tokens.Timing.pillProgressRefresh, paused: !state.isPlaying)) { context in
            let fraction = Self.fraction(state, at: context.date)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Tokens.Color.pillTrack
                    accent.frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: Tokens.Size.pillProgress)
        }
    }

    static func fraction(_ state: PlayerState, at date: Date) -> CGFloat {
        guard let duration = state.track?.duration, duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, state.elapsed(at: date) / duration)))
    }
}
