import PlayerCore
import SwiftUI

/// The states in which the notch can't play (design spec D4).
public enum NotchMessage: String, CaseIterable, Sendable {
    case signedOut
    case offline
    case bridgeBroken
    case loading
}

/// What a debug menu can force on the notch, over what the player reports (N2.6, N2.7), so
/// each state can be looked at without breaking anything.
public enum NotchForcedState: Equatable, Sendable {
    case message(NotchMessage)
    /// The page plays but these parts can't be read.
    case missing(Set<Feature>)
    /// Both lists show this state, and both tabs show.
    case lists(ListState)

    public enum ListState: Equatable, Sendable {
        case loading
        /// Playlists shows its list as remembered, under the saved-list line.
        case saved
        case empty
    }
}

/// The one message, and at most one button, for a state (D4's wording).
struct MessagePresentation: Equatable {
    enum Action: Equatable {
        case signIn
        case retry
        case openFullWindow
    }

    var kind: NotchMessage
    /// Nil for loading, which shows a spinner.
    var symbol: String?
    var message: String
    var detail: String
    var button: (label: String, action: Action)?

    static func == (lhs: MessagePresentation, rhs: MessagePresentation) -> Bool {
        lhs.kind == rhs.kind && lhs.button?.label == rhs.button?.label && lhs.button?.action == rhs.button?.action
    }

    init(_ kind: NotchMessage) {
        self.kind = kind
        switch kind {
        case .signedOut:
            symbol = Tokens.Symbol.signedOut
            message = "Sign in to YouTube Music"
            detail = "YT Notch plays music from your own account."
            button = ("Sign In", .signIn)
        case .offline:
            symbol = Tokens.Symbol.offline
            message = "No connection"
            detail = "YT Notch keeps trying on its own."
            button = ("Try Again", .retry)
        case .bridgeBroken:
            symbol = Tokens.Symbol.bridgeBroken
            message = "Player needs an update"
            detail = "The page changed. Music still plays in the full window."
            button = ("Open Full Window", .openFullWindow)
        case .loading:
            symbol = nil
            message = "Loading YouTube Music…"
            detail = "This takes a moment the first time."
            button = nil
        }
    }

    /// The message the notch shows for this state, or nil when it can play. A page where
    /// every part is missing counts as broken.
    @MainActor
    static func kind(for state: PlayerState, forced: NotchForcedState? = nil) -> NotchMessage? {
        if case let .message(kind) = forced { return kind }
        switch state.health.status {
        case .starting: return .loading
        case .signedOut: return .signedOut
        case .offline: return .offline
        case .bridgeBroken: return .bridgeBroken
        case .ok: return Set(Feature.allCases).isSubset(of: missing(in: state, forced: forced)) ? .bridgeBroken : nil
        }
    }

    /// The parts that can't be read, with any forced ones added.
    @MainActor
    static func missing(in state: PlayerState, forced: NotchForcedState?) -> Set<Feature> {
        if case let .missing(features) = forced { return state.health.missing.union(features) }
        return state.health.missing
    }
}

/// One message and at most one button, centred below the band in the 400 × 148 frame. The
/// switcher and both ears are empty: none of the views work in these states.
struct MessageView: View {
    let presentation: MessagePresentation
    let actions: NotchActions
    /// How much taller the band is than 32.
    let extra: CGFloat

    typealias S = Tokens.Size

    var body: some View {
        let p = presentation
        VStack(spacing: 0) {
            Group {
                if let symbol = p.symbol {
                    Image(systemName: symbol).font(Tokens.Font.messageIcon)
                } else {
                    ProgressView().controlSize(.small).tint(Tokens.Color.textSecondary)
                }
            }
            .foregroundStyle(Tokens.Color.textSecondary)
            .frame(height: S.messageIcon)
            Text(p.message)
                .font(Tokens.Font.title)
                .foregroundStyle(Tokens.Color.textPrimary)
                .padding(.top, S.messageIconGap)
            Text(p.detail)
                .font(Tokens.Font.secondary)
                .foregroundStyle(Tokens.Color.textSecondary)
                .padding(.top, S.messageTextGap)
            if let button = p.button {
                Button(button.label) { actions.perform(button.action) }
                    .buttonStyle(MessageButtonStyle())
                    .disabled(!actions.canPerform(button.action))
                    .padding(.top, S.messageButtonGap)
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .padding(.horizontal, S.messageInset)
        .frame(width: S.expandedWidth, height: S.expandedPlayingHeight - S.expandedBand)
        .padding(.top, S.expandedBand + extra)
    }
}

/// The message state's one button: white with black text, 28 tall, radius 14. Hover white
/// 85%, pressed white 70%.
struct MessageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MessageButtonBody(configuration: configuration)
    }
}

private struct MessageButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(Tokens.Font.button)
            .foregroundStyle(Tokens.Color.buttonText)
            .padding(.horizontal, Tokens.Size.buttonPadding)
            .frame(height: Tokens.Size.buttonHeight)
            .background(Capsule().fill(background))
            .opacity(isEnabled ? 1 : Tokens.Opacity.unavailableProgress)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
    }

    private var background: SwiftUI.Color {
        if configuration.isPressed { return Tokens.Color.buttonBackgroundPressed }
        if isHovering { return Tokens.Color.buttonBackgroundHover }
        return Tokens.Color.buttonBackground
    }
}
