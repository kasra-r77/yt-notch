import AppKit
import NotchUI
import PlayerCore
import SystemMedia
import SwiftUI
import WebPlayer

/// The app target only wires the modules together. For now it shows the menu bar item;
/// each module is hooked up here as it lands.
@main
struct YTNotchApp: App {
    var body: some Scene {
        MenuBarExtra("YT Notch", systemImage: "music.note") {
            Text("YT Notch \(Self.version)")
            Divider()
            Button("Quit YT Notch") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
