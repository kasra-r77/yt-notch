import AppKit
import NotchUI
import OSLog
import ServiceManagement
import SwiftUI

/// The Settings window (design spec D7): a standard macOS settings window, 520 wide, whose
/// changes apply at once. The Updates pane shows once the update check is set up (R5.2).
struct SettingsView: View {
    let notches: NotchDisplayManager
    let updater: Updater

    var body: some View {
        TabView {
            GeneralPane(notches: notches)
                .tabItem { Label("General", systemImage: "gearshape") }
            if updater.isEnabled {
                UpdatesPane(updater: updater)
                    .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
    }
}

/// Where the notch shows, and opening at login.
private struct GeneralPane: View {
    let notches: NotchDisplayManager
    @State private var opensAtLogin = LoginItem.isEnabled

    enum Choice: Hashable { case all, builtInOnly, picked }

    var body: some View {
        Form {
            Section {
                Picker("Show the notch on", selection: choice) {
                    Text("All displays").tag(Choice.all)
                    Text("Built-in display only").tag(Choice.builtInOnly)
                    Text("These displays:").tag(Choice.picked)
                }
                .pickerStyle(.radioGroup)
                ForEach(notches.displays, id: \.key) { display in
                    Toggle(display.name, isOn: picked(display))
                        .disabled(choice.wrappedValue != .picked)
                        .padding(.leading, 20)
                }
                Text("A display with a notch uses it. Any other display gets the simulated notch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: { setOpensAtLogin($0) }))
                Text("YT Notch starts when you log in, signed in and ready.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { opensAtLogin = LoginItem.isEnabled }
    }

    private var choice: Binding<Choice> {
        Binding(get: { currentChoice() }, set: { choose($0) })
    }

    private func currentChoice() -> Choice {
        if notches.setting == .all { return .all }
        if notches.setting == .builtInOnly { return .builtInOnly }
        return .picked
    }

    private func choose(_ newValue: Choice) {
        if newValue == .all {
            notches.setting = .all
        } else if newValue == .builtInOnly {
            notches.setting = .builtInOnly
        } else if currentChoice() != .picked {
            // Start from the displays that show a notch now.
            let shown = notches.displays.filter { notches.setting.includes($0) }.map(\.key)
            notches.setting = .picked(Set(shown))
        }
    }

    private func picked(_ display: ScreenGeometry) -> Binding<Bool> {
        Binding(get: { notches.setting.includes(display) }, set: { isOn in toggle(display, isOn) })
    }

    private func toggle(_ display: ScreenGeometry, _ isOn: Bool) {
        guard case var .picked(keys) = notches.setting else { return }
        if isOn { keys.insert(display.key) } else { keys.remove(display.key) }
        notches.setting = .picked(keys)
    }

    private func setOpensAtLogin(_ isOn: Bool) {
        LoginItem.set(isOn)
        opensAtLogin = LoginItem.isEnabled
    }
}

/// Opening at login, through the system's login items, so it also shows in System Settings
/// › General › Login Items.
enum LoginItem {
    private static let log = Logger(subsystem: "io.github.kasra-r77.ytnotch", category: "App")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ isOn: Bool) {
        let change = isOn ? "turned on" : "turned off"
        do {
            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let reason = error.localizedDescription
            log.error("open at login could not be \(change, privacy: .public): \(reason, privacy: .public)")
        }
    }
}

/// Checking for updates: automatically once a day, or now.
private struct UpdatesPane: View {
    let updater: Updater
    @State private var checksAutomatically = true

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: Binding(get: { checksAutomatically }, set: { setAutomatic($0) }))
                HStack {
                    Text(lastCheckedText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { updater.checkForUpdates() }
                }
                Text("YT Notch \(AboutPane.version) (\(AboutPane.build))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { checksAutomatically = updater.checksAutomatically }
    }

    private var lastCheckedText: String {
        guard let date = updater.lastChecked else { return "Not checked yet" }
        return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func setAutomatic(_ isOn: Bool) {
        updater.checksAutomatically = isOn
        checksAutomatically = updater.checksAutomatically
    }
}

/// The app, its version, what it is, and that it is unofficial.
struct AboutPane: View {
    static let repository = URL(string: "https://github.com/kasra-r77/yt-notch")!

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("YT Notch")
                .font(.title2.weight(.semibold))
            Text("Version \(Self.version) (\(Self.build))")
                .foregroundStyle(.secondary)
            Text("A notch player for YouTube Music on the Mac.")
            Text("Unofficial. Not affiliated with, endorsed by or sponsored by Google or YouTube. YouTube Music is a trademark of Google LLC.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Source Code") { NSWorkspace.shared.open(Self.repository) }
                Button("Report an Issue") { NSWorkspace.shared.open(Self.repository.appendingPathComponent("issues/new")) }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}
