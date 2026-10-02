import AppKit
import SwiftUI
import Testing
@testable import NotchUI

/// The panel's window behaviour. The window server's part (passing clicks through a window
/// that ignores mouse events, keeping a non-activating panel from taking focus) is AppKit's;
/// these tests check the panel asks for it.
@MainActor
@Suite(.serialized)
struct NotchPanelTests {
    let pointer = PointerTracker()

    init() {
        _ = NSApplication.shared
    }

    func panel(on screen: ScreenGeometry = Displays.external) -> NotchPanel {
        NotchPanel(screen: screen, pointer: pointer)
    }

    @Test func neverTakesKeyboardFocusOrActivatesTheApp() {
        let panel = panel()
        defer { panel.close() }
        let window = panel.window
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.styleMask.contains(.borderless) || window.styleMask == [.nonactivatingPanel])
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        window.makeKeyAndOrderFront(nil)
        #expect(!window.isKeyWindow)
    }

    @Test func sitsAboveTheMenuBarOnEverySpace() {
        let panel = panel()
        defer { panel.close() }
        let window = panel.window
        #expect(window.level.rawValue > NSWindow.Level.statusBar.rawValue)
        #expect(window.level.rawValue < NSWindow.Level.popUpMenu.rawValue)
        #expect(window.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]))
        #expect(!window.hidesOnDeactivate)
        #expect(window.isVisible)
        #expect(!window.isOpaque && !window.hasShadow)
    }

    @Test func thePanelIsWhereTheLayoutSays() {
        let panel = panel(on: Displays.macBookPro14)
        defer { panel.close() }
        #expect(panel.window.frame == PanelLayout.frame(on: Displays.macBookPro14))
        #expect(panel.model.outline == .idle(on: Displays.macBookPro14))
    }

    // On the external display the pill's centre is at x 2408 and its body runs from the top
    // edge (y 1120) down to y 1090.
    @Test func onlyTheShapeTakesClicks() {
        let panel = panel()
        defer { panel.close() }
        pointer.deliver(CGPoint(x: 2408, y: 1110))
        #expect(!panel.window.ignoresMouseEvents, "inside the pill")
        pointer.deliver(CGPoint(x: 2408 + 120, y: 1110))
        #expect(panel.window.ignoresMouseEvents, "beside the pill, still inside the panel")
        pointer.deliver(CGPoint(x: 2408, y: 1085))
        #expect(panel.window.ignoresMouseEvents, "below the pill")
        pointer.deliver(CGPoint(x: 2408 + 97, y: 1120))
        #expect(!panel.window.ignoresMouseEvents, "the flare at the top edge")
        pointer.deliver(CGPoint(x: 2408, y: 1120))
        #expect(!panel.window.ignoresMouseEvents, "the top edge itself")
        pointer.deliver(CGPoint(x: 100, y: 100))
        #expect(panel.window.ignoresMouseEvents, "elsewhere on the desktop")
    }

    @Test func clicksFollowTheTargetShapeAtOnce() {
        let panel = panel()
        defer { panel.close() }
        let below = CGPoint(x: 2408, y: 1000)
        #expect(!panel.contains(below))
        // A taller target counts as soon as it is set, before any animation has run.
        panel.model.outline = NotchOutline(width: 400, height: 148, bottomRadius: 24, flare: 12)
        #expect(panel.contains(below))
    }

    @Test func fullScreenHidesTheNotchAndItsClicks() {
        let panel = panel()
        defer { panel.close() }
        let inside = CGPoint(x: 2408, y: 1110)
        panel.setFullScreen(true)
        #expect(panel.model.isHidden)
        pointer.deliver(inside)
        #expect(panel.window.ignoresMouseEvents)
        panel.setFullScreen(false)
        #expect(!panel.model.isHidden)
        #expect(!panel.window.ignoresMouseEvents, "takes clicks again without waiting for the pointer to move")
    }

    @Test func aDisplayChangeResizesThePanel() {
        let panel = panel(on: Displays.macBookPro14)
        defer { panel.close() }
        panel.update(screen: Displays.tallNotch)
        #expect(panel.window.frame == PanelLayout.frame(on: Displays.tallNotch))
        #expect(panel.model.outline == .idle(on: Displays.tallNotch))
    }

    @Test func closingStopsFollowingThePointer() {
        let panel = panel()
        panel.close()
        #expect(!panel.window.isVisible)
        pointer.deliver(CGPoint(x: 2408, y: 1110))
        #expect(panel.window.ignoresMouseEvents)
    }

    @Test func drawsABlackShapeTopCentredOnAClearPanel() throws {
        let model = NotchModel(outline: .idle(on: Displays.external), band: Displays.external.band)
        let size = PanelLayout.frame(on: Displays.external).size
        let renderer = ImageRenderer(content: NotchRootView(model: model, fadesIn: false).frame(width: size.width, height: size.height))
        let image = try #require(renderer.cgImage)
        let pixels = try Pixels(image)
        let scale = CGFloat(image.width) / size.width
        func pixel(_ x: CGFloat, _ y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            pixels.at(x: Int(x * scale), y: Int(y * scale))
        }
        let centre = size.width / 2
        let inside = pixel(centre, 15)
        #expect(inside.a == 255 && inside.r == 0 && inside.g == 0 && inside.b == 0, "the surface is #000000")
        #expect(pixel(centre, 40).a == 0, "below the pill")
        #expect(pixel(centre + 150, 10).a == 0, "beside the pill")
    }
}

/// An image's pixels as 8-bit RGBA, top row first.
struct Pixels {
    let width: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw CocoaError(.featureUnsupported) }
        self.bytes = bytes
    }

    func at(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }
}
