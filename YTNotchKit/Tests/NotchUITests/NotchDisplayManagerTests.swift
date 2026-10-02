import AppKit
import Foundation
import Testing
@testable import NotchUI

/// The display manager against displays the test plugs in and out.
@MainActor
@Suite(.serialized)
struct NotchDisplayManagerTests {
    /// The connected displays, as `NSScreen.screens` would list them, and what is on screen.
    final class Desk {
        var screens: [ScreenGeometry]
        var windows: [FullScreenDetector.WindowInfo] = []

        init(_ screens: [ScreenGeometry]) {
            self.screens = screens
        }
    }

    /// A second external display, left of the built-in one.
    static let leftMonitor = ScreenGeometry(
        displayID: 4, key: "left", name: "Left Monitor",
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), notch: nil, menuBarHeight: 30
    )

    let pointer = PointerTracker()

    init() {
        _ = NSApplication.shared
    }

    func manager(_ desk: Desk, setting: NotchDisplaySetting = .all, defaults: UserDefaults? = nil) -> NotchDisplayManager {
        NotchDisplayManager(setting: setting, defaults: defaults, screens: { desk.screens }, windows: { desk.windows }, pointer: pointer)
    }

    func keys(_ manager: NotchDisplayManager) -> [String] {
        manager.notches.map(\.screen.key)
    }

    @Test func everyDisplayGetsANotchByDefault() {
        let manager = manager(Desk([Displays.macBookPro14, Displays.external]))
        defer { manager.stop() }
        #expect(keys(manager) == ["built-in", "external"])
        #expect(manager.notches.allSatisfy { $0.window.isVisible })
        #expect(manager.notches[1].window.frame == PanelLayout.frame(on: Displays.external))
    }

    @Test func builtInOnly() {
        let desk = Desk([Displays.macBookPro14, Displays.external])
        let manager = manager(desk, setting: .builtInOnly)
        defer { manager.stop() }
        #expect(keys(manager) == ["built-in"])

        // Lid closed: the built-in display is gone, and no other display takes its place.
        desk.screens = [Displays.external]
        manager.rebuild()
        #expect(manager.notches.isEmpty)
    }

    @Test func pickedDisplays() {
        let manager = manager(Desk([Displays.macBookPro14, Displays.external, Self.leftMonitor]), setting: .picked(["external", "left"]))
        defer { manager.stop() }
        #expect(keys(manager) == ["external", "left"])
        #expect(manager.displays.count == 3, "the picker still lists every display")
    }

    @Test func pluggingAMonitorInAndOutTenTimesLeavesOneNotchPerDisplay() {
        let desk = Desk([Displays.macBookPro14])
        let manager = manager(desk)
        defer { manager.stop() }
        let builtIn = manager.notches[0]
        var made: [NotchPanel] = []

        for _ in 1...10 {
            desk.screens = [Displays.macBookPro14, Displays.external]
            manager.rebuild()
            #expect(keys(manager) == ["built-in", "external"])
            made.append(manager.notches[1])

            desk.screens = [Displays.macBookPro14]
            manager.rebuild()
            #expect(keys(manager) == ["built-in"])
        }

        #expect(manager.notches[0] === builtIn, "the built-in notch is never rebuilt")
        #expect(Set(made.map(ObjectIdentifier.init)).count == 10)
        #expect(made.allSatisfy { $0.isClosed && !$0.window.isVisible }, "every unplugged notch is gone")
        // Only this manager's windows: other suites' panels may be open at the same time.
        let visible = ([builtIn] + made).filter { $0.window.isVisible }
        #expect(visible.count == 1)
    }

    @Test func rearrangingMovesTheSameNotch() {
        let desk = Desk([Displays.macBookPro14, Displays.external])
        let manager = manager(desk)
        defer { manager.stop() }
        let notch = manager.notches[1]

        var moved = Displays.external
        moved.frame.origin = CGPoint(x: -1792, y: 200)
        desk.screens = [Displays.macBookPro14, moved]
        manager.rebuild()
        #expect(manager.notches[1] === notch)
        #expect(notch.window.frame == PanelLayout.frame(on: moved))
    }

    @Test func aDisplayKeepsItsNotchWhenItsIDChanges() {
        let desk = Desk([Displays.macBookPro14, Displays.external])
        let manager = manager(desk, setting: .picked(["external"]))
        defer { manager.stop() }
        let notch = manager.notches[0]
        var replugged = Displays.external
        replugged.displayID = 99
        desk.screens = [Displays.macBookPro14, replugged]
        manager.rebuild()
        #expect(manager.notches.count == 1)
        #expect(manager.notches[0] === notch)
        #expect(notch.screen.displayID == 99)
    }

    @Test func twoIdenticalMonitorsGetANotchEach() {
        var twin = Displays.external
        twin.displayID = 5
        twin.frame.origin.x += 1792
        let manager = manager(Desk([Displays.macBookPro14, Displays.external, twin]))
        defer { manager.stop() }
        #expect(manager.notches.count == 3)
    }

    @Test func changingTheSettingRebuildsAndIsSaved() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchDisplayManagerTests-\(UUID())"))
        let manager = manager(Desk([Displays.macBookPro14, Displays.external]), defaults: defaults)
        defer { manager.stop() }
        manager.setting = .picked(["external"])
        #expect(keys(manager) == ["external"])
        #expect(NotchDisplaySetting.load(from: defaults) == .picked(["external"]))
        manager.setting = .builtInOnly
        #expect(keys(manager) == ["built-in"])
        #expect(NotchDisplaySetting.load(from: defaults) == .builtInOnly)
    }

    @Test func aMissingOrUnreadableSettingMeansAllDisplays() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchDisplayManagerTests-\(UUID())"))
        #expect(NotchDisplaySetting.load(from: defaults) == .all)
        defaults.set(Data("nonsense".utf8), forKey: NotchDisplaySetting.defaultsKey)
        #expect(NotchDisplaySetting.load(from: defaults) == .all)
    }

    @Test func fullScreenHidesOnlyThatDisplaysNotch() {
        let desk = Desk([Displays.macBookPro14, Displays.external])
        let manager = manager(desk)
        defer { manager.stop() }
        // The external display, in window-list coordinates: the built-in display (982 tall)
        // is at the origin, and y runs down.
        desk.windows = [.init(ownerPID: 1, layer: 0, bounds: CGRect(x: 1512, y: 982 - 1120, width: 1792, height: 1120))]
        manager.refreshFullScreen()
        #expect(!manager.notches[0].isFullScreen)
        #expect(manager.notches[1].isFullScreen)

        desk.windows = []
        manager.refreshFullScreen()
        #expect(!manager.notches[1].isFullScreen)
    }

    @Test func aNewNotchStartsHiddenIfItsDisplayIsFullScreen() {
        let desk = Desk([Displays.macBookPro14])
        let manager = manager(desk)
        defer { manager.stop() }
        desk.windows = [.init(ownerPID: 1, layer: 0, bounds: CGRect(x: 1512, y: 982 - 1120, width: 1792, height: 1120))]
        desk.screens = [Displays.macBookPro14, Displays.external]
        manager.rebuild()
        #expect(manager.notches[1].isFullScreen)
    }

    @Test func stopClosesEveryNotch() {
        let manager = manager(Desk([Displays.macBookPro14, Displays.external]))
        let notches = manager.notches
        manager.stop()
        #expect(notches.allSatisfy { $0.isClosed })
        #expect(manager.notches.isEmpty)
    }
}
