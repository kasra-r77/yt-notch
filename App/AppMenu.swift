import AppKit
import NotchUI
import OSLog
import PlayerCore
import SwiftUI

/// The menu bar menu (design spec D7). Playback controls live in the notch, not here.
struct AppMenu: View {
    let store: PlayerStore
    let notches: NotchDisplayManager
    /// Nil without the web player.
    let openWindow: (@MainActor (_ signIn: Bool) -> Void)?
    let retry: (@MainActor () -> Void)?
    let engineName: String
    let updater: Updater

    @Environment(\.openSettings) private var openSettings
    @State private var copied = false

    var body: some View {
        let status = store.state.health.status
        if let line = Self.statusLine(status) {
            Text(line)
            switch status {
            case .signedOut:
                Button("Sign In…") { openWindow?(true) }
                    .disabled(openWindow == nil)
            case .offline:
                Button("Try Again") { retry?() }
                    .disabled(retry == nil)
            default:
                // Player needs an update: the window moves up here, as the way to keep playing.
                openWindowButton
            }
            Divider()
        }
        if status != .bridgeBroken {
            openWindowButton
        }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        if updater.isEnabled {
            Button { updater.checkForUpdates() } label: {
                if updater.updateWaiting {
                    Text("Update Available…").fontWeight(.semibold)
                } else {
                    Text("Check for Updates…")
                }
            }
        }
        Button(copied ? "Copied" : "Copy Diagnostics") { copyDiagnostics() }
        #if DEBUG
        Divider()
        DebugMenu(notches: notches)
        #endif
        Divider()
        Button("Quit YT Notch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var openWindowButton: some View {
        Button("Open YT Notch Window") { openWindow?(false) }
            .disabled(openWindow == nil)
    }

    static func statusLine(_ status: Health.Status) -> String? {
        switch status {
        case .signedOut: "Signed out of YouTube Music"
        case .offline: "No connection"
        case .bridgeBroken: "Player needs an update"
        case .ok, .starting: nil
        }
    }

    private func copyDiagnostics() {
        let versions = Diagnostics.Versions(
            app: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            engine: engineName
        )
        let state = store.state
        Task {
            let lines = await RecentLog.lines(limit: Diagnostics.logLimit)
            let report = Diagnostics.report(versions: versions, state: state, logLines: lines)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            copied = true
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// This process's log lines. Safe to share: the app never logs anything from the user's account.
enum RecentLog {
    static let subsystem = "io.github.kasra-r77.ytnotch"

    static func lines(limit: Int) async -> [String] {
        await Task.detached(priority: .utility) {
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
            let start = store.position(timeIntervalSinceEnd: -3600)
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let entries = (try? store.getEntries(at: start, matching: predicate)) ?? AnySequence([])
            let formatter = ISO8601DateFormatter()
            let lines = entries.compactMap { entry -> String? in
                guard let log = entry as? OSLogEntryLog else { return nil }
                return "\(formatter.string(from: log.date)) [\(log.category)] \(log.composedMessage)"
            }
            return Array(lines.suffix(limit))
        }.value
    }
}

#if DEBUG
/// Forces how the notch looks without touching the player; Normal shows what it really reports.
private struct DebugMenu: View {
    let notches: NotchDisplayManager

    var body: some View {
        Menu("Debug") {
            Picker("Notch State", selection: Binding(get: { Choice(notches.forcedState) }, set: { notches.forcedState = $0.forced })) {
                ForEach(Choice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.inline)
        }
    }

    enum Choice: CaseIterable, Hashable {
        case normal, signedOut, offline, bridgeBroken, loading, partlyWorking, listsLoading, savedPlaylists, emptyLists

        init(_ forced: NotchForcedState?) {
            switch forced {
            case .message(.signedOut): self = .signedOut
            case .message(.offline): self = .offline
            case .message(.bridgeBroken): self = .bridgeBroken
            case .message(.loading): self = .loading
            case .missing: self = .partlyWorking
            case .lists(.loading): self = .listsLoading
            case .lists(.saved): self = .savedPlaylists
            case .lists(.empty): self = .emptyLists
            case nil: self = .normal
            }
        }

        var forced: NotchForcedState? {
            switch self {
            case .normal: nil
            case .signedOut: .message(.signedOut)
            case .offline: .message(.offline)
            case .bridgeBroken: .message(.bridgeBroken)
            case .loading: .message(.loading)
            case .partlyWorking: .missing([.like, .seek, .shuffle, .repeatMode])
            case .listsLoading: .lists(.loading)
            case .savedPlaylists: .lists(.saved)
            case .emptyLists: .lists(.empty)
            }
        }

        var title: String {
            switch self {
            case .normal: "Normal"
            case .signedOut: "Signed Out"
            case .offline: "No Connection"
            case .bridgeBroken: "Player Needs an Update"
            case .loading: "Loading"
            case .partlyWorking: "Partly Working"
            case .listsLoading: "Lists Loading"
            case .savedPlaylists: "Saved Playlists"
            case .emptyLists: "Empty Lists"
            }
        }
    }
}
#endif
