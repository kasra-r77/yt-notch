import AppKit
import PlayerCore
import SwiftUI

/// The Playlists and Up next views (design spec D3).
struct ListView: View {
    let state: PlayerState
    let view: HoverMachine.ExpandedView
    let model: NotchModel
    let actions: NotchActions
    /// How much taller the band is than 32.
    let extra: CGFloat

    typealias S = Tokens.Size

    var body: some View {
        let p = ListPresentation(view, state: state, forced: model.forcedState)
        VStack(spacing: 0) {
            band(p)
            ListBody(presentation: p, accent: SwiftUI.Color(accent: model.accent), reduceMotion: model.reduceMotion, actions: actions,
                     image: image)
                .frame(height: S.expandedListHeight - S.expandedBand)
        }
        .frame(width: S.expandedWidth, height: S.expandedListHeight + extra, alignment: .top)
    }

    private func image(_ url: URL) -> NSImage? {
        state.artwork[url].flatMap { ArtworkImages.shared.image(for: url, data: $0) }
    }

    private func band(_ p: ListPresentation) -> some View {
        HStack(spacing: 0) {
            ViewSwitcher(selected: view, showsPlaylists: p.showsPlaylistsTab, showsUpNext: p.showsUpNextTab, select: actions.select)
            Spacer(minLength: 0)
            OpenButton(actions: actions)
        }
        .padding(.horizontal, S.expandedPadding)
        .frame(width: S.expandedWidth, height: S.expandedBand + extra)
    }
}

/// Clipped to the shape's bottom corners, so rows scrolling under the bottom fade never show
/// outside it.
struct ListBody: View {
    let presentation: ListPresentation
    let accent: SwiftUI.Color
    let reduceMotion: Bool
    let actions: NotchActions
    var image: (URL) -> NSImage? = { _ in nil }

    typealias S = Tokens.Size

    var body: some View {
        let p = presentation
        VStack(spacing: 0) {
            if p.showsSavedLine {
                SavedLine().padding(.top, S.listTop)
            }
            switch p.content {
            case let .rows(rows):
                RowList(rows: rows, currentRowID: p.currentRowID, isPlaying: p.isPlaying, accent: accent,
                        reduceMotion: reduceMotion, actions: actions, image: image)
                    .padding(.top, p.showsSavedLine ? 0 : S.listTop)
            case .loading:
                LoadingRows(twoLines: p.view == .upNext)
                    .padding(.top, S.listTop)
            case let .empty(empty):
                EmptyListView(empty: empty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: S.expandedRadius, bottomTrailingRadius: S.expandedRadius, style: .continuous))
    }
}

struct RowList: View {
    let rows: [ListRow]
    let currentRowID: ListRow.ID?
    let isPlaying: Bool
    let accent: SwiftUI.Color
    let reduceMotion: Bool
    let actions: NotchActions
    var image: (URL) -> NSImage? = { _ in nil }

    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 0

    typealias S = Tokens.Size

    private nonisolated static let space = "rows"

    var body: some View {
        let contentHeight = CGFloat(rows.count) * S.row + S.listBottom
        let scrolls = viewport > 0 && contentHeight > viewport + 0.5
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        ListRowView(row: row, image: row.artworkURL.flatMap(image), isPlaying: isPlaying, accent: accent,
                                    reduceMotion: reduceMotion) {
                            actions.play(row.action)
                        }
                        .id(row.id)
                    }
                }
                .padding(.horizontal, S.rowInset)
                .padding(.bottom, S.listBottom)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    -geometry.frame(in: .named(Self.space)).minY
                } action: { offset = $0 }
            }
            .coordinateSpace(name: Self.space)
            .scrollIndicators(scrolls ? .automatic : .never)
            .scrollDisabled(!scrolls)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
            .onAppear {
                if let currentRowID { proxy.scrollTo(currentRowID, anchor: .top) }
            }
        }
        .overlay(alignment: .top) {
            if scrolls && offset > 0.5 { clipEdge }
        }
        .overlay(alignment: .bottom) {
            if scrolls && offset + viewport < contentHeight - 0.5 { bottomFade }
        }
    }

    private var clipEdge: some View {
        VStack(spacing: 0) {
            Tokens.Color.divider.frame(height: S.divider)
            LinearGradient(colors: [Tokens.Color.surface, Tokens.Color.surface.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: S.clipFade)
        }
        .allowsHitTesting(false)
    }

    private var bottomFade: some View {
        LinearGradient(colors: [Tokens.Color.surface.opacity(0), Tokens.Color.surface], startPoint: .top, endPoint: .bottom)
            .frame(height: S.bottomFade)
            .allowsHitTesting(false)
    }
}

struct ListRowView: View {
    let row: ListRow
    var image: NSImage?
    let isPlaying: Bool
    let accent: SwiftUI.Color
    let reduceMotion: Bool
    let action: () -> Void

    typealias S = Tokens.Size

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                RowTile(tile: row.tile, image: image)
                VStack(alignment: .leading, spacing: S.rowLineGap) {
                    Text(row.title)
                        .font(row.isCurrent ? Tokens.Font.title : Tokens.Font.row)
                        .foregroundStyle(Tokens.Color.textPrimary)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(Tokens.Font.secondary)
                            .foregroundStyle(Tokens.Color.textSecondary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, S.tileGap)
                if row.isCurrent || row.length != nil {
                    HStack(spacing: S.rowTrailingGap) {
                        if row.isCurrent {
                            ListBars(accent: accent, isAnimating: isPlaying && !reduceMotion)
                        }
                        if let length = row.length {
                            Text(length)
                                .font(Tokens.Font.time)
                                .foregroundStyle(Tokens.Color.textSecondary)
                        }
                    }
                    .fixedSize()
                    .padding(.leading, S.rowTrailingGap)
                }
            }
            .padding(.horizontal, S.rowPadding)
            .frame(height: S.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowStyle(isCurrent: row.isCurrent))
        .help(row.help)
        .accessibilityLabel(row.help)
        .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
    }
}

struct ListRowStyle: ButtonStyle {
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        ListRowBody(configuration: configuration, isCurrent: isCurrent)
    }
}

private struct ListRowBody: View {
    let configuration: ButtonStyleConfiguration
    let isCurrent: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous).fill(background))
            .onHover { isHovering = $0 }
    }

    private var background: SwiftUI.Color {
        if configuration.isPressed { return Tokens.Color.rowPressed }
        if isCurrent { return Tokens.Color.rowCurrent }
        if isHovering { return Tokens.Color.rowHover }
        return .clear
    }
}

struct RowTile: View {
    let tile: ListRow.Tile
    let image: NSImage?

    var body: some View {
        switch tile {
        case let .symbol(symbol):
            ZStack {
                Tokens.Color.placeholder
                Image(systemName: symbol)
                    .font(Tokens.Font.icon)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            .frame(width: Tokens.Size.thumbnail, height: Tokens.Size.thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail, style: .continuous))
        case .artwork:
            ArtworkTile(image: image, size: Tokens.Size.thumbnail, radius: Tokens.Radius.thumbnail)
        }
    }
}

struct ListBars: View {
    let accent: SwiftUI.Color
    let isAnimating: Bool

    typealias S = Tokens.Size

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isAnimating)) { context in
            HStack(alignment: .bottom, spacing: S.barGap) {
                ForEach(0..<S.listBarRestHeights.count, id: \.self) { bar in
                    RoundedRectangle(cornerRadius: Tokens.Radius.bar)
                        .fill(accent)
                        .frame(width: S.barWidth, height: height(bar, at: context.date))
                }
            }
            .frame(height: S.listBarMaxHeight, alignment: .bottom)
        }
    }

    private func height(_ bar: Int, at date: Date) -> CGFloat {
        guard isAnimating else { return S.listBarRestHeights[bar] }
        return BarMotion.height(bar: bar, at: date.timeIntervalSinceReferenceDate, isAnimating: true, maxHeight: S.listBarMaxHeight)
    }
}

struct LoadingRows: View {
    let twoLines: Bool

    typealias S = Tokens.Size

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<S.visibleRows, id: \.self) { _ in
                HStack(spacing: S.tileGap) {
                    RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail, style: .continuous)
                        .fill(Tokens.Color.placeholder)
                        .frame(width: S.thumbnail, height: S.thumbnail)
                    VStack(alignment: .leading, spacing: S.skeletonRowGap) {
                        RoundedRectangle(cornerRadius: Tokens.Radius.skeleton)
                            .fill(Tokens.Color.skeletonStrong)
                            .frame(width: S.skeletonTitle.width, height: S.skeletonTitle.height)
                        if twoLines {
                            RoundedRectangle(cornerRadius: Tokens.Radius.skeleton)
                                .fill(Tokens.Color.placeholder)
                                .frame(width: S.skeletonArtist.width, height: S.skeletonArtist.height)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, S.rowPadding)
                .frame(height: S.row)
            }
        }
        .padding(.horizontal, S.rowInset)
    }
}

struct SavedLine: View {
    var body: some View {
        HStack(spacing: Tokens.Size.savedIconGap) {
            Image(systemName: Tokens.Symbol.savedList).font(Tokens.Font.savedIcon)
            Text(ListPresentation.savedLine).font(Tokens.Font.secondary)
        }
        .foregroundStyle(Tokens.Color.textSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Size.expandedPadding)
        .frame(height: Tokens.Size.savedLine)
    }
}

struct EmptyListView: View {
    let empty: ListPresentation.EmptyList

    typealias S = Tokens.Size

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: empty.symbol)
                .font(Tokens.Font.emptyIcon)
                .foregroundStyle(Tokens.Color.emptyIcon)
            Text(empty.title)
                .font(Tokens.Font.title)
                .foregroundStyle(Tokens.Color.textPrimary)
                .padding(.top, S.messageIconGap)
            Text(empty.detail)
                .font(Tokens.Font.secondary)
                .foregroundStyle(Tokens.Color.textSecondary)
                .padding(.top, S.messageTextGap)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .padding(.horizontal, S.messageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
