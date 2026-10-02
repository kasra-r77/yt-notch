import CoreGraphics
import SwiftUI
import Testing
@testable import NotchUI

/// Displays as their screens report them.
enum Displays {
    /// A 14-inch MacBook Pro at default scaling: 1512 × 982 with a 185 × 32 notch.
    static let macBookPro14 = ScreenGeometry(
        displayID: 1, key: "built-in", name: "Built-in Retina Display", isBuiltIn: true,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notch: CGRect(x: 663.5, y: 950, width: 185, height: 32),
        menuBarHeight: 32
    )

    /// A display without a notch to the right of it, with macOS 26's 30 pt menu bar.
    static let external = ScreenGeometry(
        displayID: 2, key: "external", name: "Studio Display",
        frame: CGRect(x: 1512, y: 0, width: 1792, height: 1120),
        notch: nil,
        menuBarHeight: 30
    )

    /// A notch taller than the 32 the expanded heights are designed around.
    static let tallNotch = ScreenGeometry(
        displayID: 3, key: "tall", isBuiltIn: true,
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        notch: CGRect(x: 768, y: 1079, width: 192, height: 38),
        menuBarHeight: 38
    )
}

struct NotchGeometryTests {
    @Test func idleOnABuiltInDisplayIsExactlyTheNotch() {
        #expect(NotchOutline.idle(on: Displays.macBookPro14) == NotchOutline(width: 185, height: 32, bottomRadius: 10, flare: 0))
    }

    @Test func idleWithoutANotchIsThePill() {
        #expect(NotchOutline.idle(on: Displays.external) == NotchOutline(width: 190, height: 30, bottomRadius: 10, flare: 6))
        #expect(NotchOutline.idle(on: Displays.external).footprint == CGSize(width: 202, height: 30))
    }

    @Test func theBandIsTheNotchOrTheMenuBar() {
        #expect(Displays.macBookPro14.band == 32)
        #expect(Displays.external.band == 30)
    }

    @Test func thePanelFitsTheLargestShapeAndIsTopCentred() {
        // 424 × 300 for the expanded list view, plus 24 for the shadow at the sides and
        // 24 + 8 below.
        #expect(PanelLayout.frame(on: Displays.macBookPro14) == CGRect(x: 520, y: 650, width: 472, height: 332))
        let external = PanelLayout.frame(on: Displays.external)
        #expect(external.midX == Displays.external.frame.midX)
        #expect(external.maxY == Displays.external.frame.maxY)
    }

    @Test func aTallerNotchMakesThePanelTaller() {
        let frame = PanelLayout.frame(on: Displays.tallNotch)
        #expect(frame.height == CGFloat(338), "332, plus 6 for a 38 pt notch")
        #expect(frame.midX == Displays.tallNotch.notch!.midX)
    }
}

struct NotchShapeTests {
    /// The shape for a display, placed in its panel and turned back into screen coordinates.
    static func shapeOnScreen(_ screen: ScreenGeometry) -> CGRect {
        let panel = PanelLayout.frame(on: screen)
        let bounds = NotchShape.path(.idle(on: screen), topCentre: CGPoint(x: panel.width / 2, y: 0)).boundingRect
        return CGRect(x: panel.minX + bounds.minX, y: panel.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    @Test(arguments: [Displays.macBookPro14, Displays.tallNotch])
    func theShapeLinesUpWithTheHardwareNotch(screen: ScreenGeometry) throws {
        let shape = Self.shapeOnScreen(screen)
        let notch = try #require(screen.notch)
        #expect(abs(shape.minX - notch.minX) < 0.01)
        #expect(abs(shape.maxX - notch.maxX) < 0.01)
        #expect(abs(shape.minY - notch.minY) < 0.01)
        #expect(abs(shape.maxY - notch.maxY) < 0.01)
    }

    @Test func thePillIsCentredOnTheTopEdge() {
        let shape = Self.shapeOnScreen(Displays.external)
        #expect(abs(shape.midX - Displays.external.frame.midX) < 0.01)
        #expect(abs(shape.maxY - Displays.external.frame.maxY) < 0.01)
        #expect(abs(shape.width - 202) < 0.01)
        #expect(abs(shape.height - 30) < 0.01)
    }

    // The pill around (0, 0): its body spans x −95…95 and y 0…30 (y down), and each flare
    // fills out to 6 beyond the body at the top edge.
    // Tested with CGPath, as hit testing is (see NotchPanel.contains).
    static var pill: CGPath { NotchShape.path(.idle(on: Displays.external), topCentre: .zero).cgPath }

    @Test func theBodyIsFilled() {
        #expect(Self.pill.contains(CGPoint(x: 0, y: 15)))
        #expect(Self.pill.contains(CGPoint(x: -94, y: 15)))
        #expect(!Self.pill.contains(CGPoint(x: 0, y: 30.5)))
    }

    @Test func theBottomCornersAreRounded() {
        #expect(!Self.pill.contains(CGPoint(x: -94.5, y: 29.5)))
        #expect(!Self.pill.contains(CGPoint(x: 94.5, y: 29.5)))
        #expect(Self.pill.contains(CGPoint(x: -85, y: 29.5)))
    }

    @Test func theFlaresCurveOutIntoTheTopEdge() {
        // Near the top edge, just outside the body: filled.
        #expect(Self.pill.contains(CGPoint(x: -96, y: 1)))
        #expect(Self.pill.contains(CGPoint(x: 96, y: 1)))
        // Further out, under the curve: empty.
        #expect(!Self.pill.contains(CGPoint(x: -99, y: 3)))
        #expect(!Self.pill.contains(CGPoint(x: 99, y: 3)))
        // Beside the body below the flare, and beyond the footprint: empty.
        #expect(!Self.pill.contains(CGPoint(x: -96, y: 10)))
        #expect(!Self.pill.contains(CGPoint(x: -102, y: 0.5)))
    }

    @Test func theBuiltInIdleShapeHasNoFlare() {
        let notch = NotchShape.path(.idle(on: Displays.macBookPro14), topCentre: .zero).cgPath
        #expect(notch.contains(CGPoint(x: -92, y: 0.5)))
        #expect(!notch.contains(CGPoint(x: -93.5, y: 0.5)))
    }

    @Test func impossibleValuesStillDrawAShape() {
        let path = NotchShape.path(NotchOutline(width: 10, height: 4, bottomRadius: 10, flare: 6), topCentre: .zero)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.height <= 4.01)
    }

    @Test func theShapeAnimatesAllFourValues() {
        var shape = NotchShape(NotchOutline(width: 1, height: 2, bottomRadius: 3, flare: 4))
        shape.animatableData = AnimatablePair(AnimatablePair(10, 20), AnimatablePair(30, AnimatablePair(40, -50)))
        #expect(shape.outline == NotchOutline(width: 10, height: 20, bottomRadius: 30, flare: 40, offset: -50))
    }
}

struct FullScreenDetectorTests {
    static let display = CGRect(x: 0, y: 0, width: 1792, height: 1120)
    static let other: pid_t = 501
    static let own: pid_t = 777

    static func isFullScreen(_ windows: FullScreenDetector.WindowInfo...) -> Bool {
        FullScreenDetector.isFullScreen(display: display, windows: windows, ownPID: own)
    }

    @Test func anotherAppsWindowCoveringTheDisplayIsFullScreen() {
        #expect(Self.isFullScreen(.init(ownerPID: Self.other, layer: 0, bounds: Self.display)))
    }

    @Test func otherWindowsAreNot() {
        // A zoomed window leaves the menu bar out.
        #expect(!Self.isFullScreen(.init(ownerPID: Self.other, layer: 0, bounds: CGRect(x: 0, y: 30, width: 1792, height: 1090))))
        // The menu bar and other system windows sit above the normal level.
        #expect(!Self.isFullScreen(.init(ownerPID: Self.other, layer: 24, bounds: Self.display)))
        // This app's own windows don't count.
        #expect(!Self.isFullScreen(.init(ownerPID: Self.own, layer: 0, bounds: Self.display)))
        // Full screen on another display.
        #expect(!Self.isFullScreen(.init(ownerPID: Self.other, layer: 0, bounds: CGRect(x: 1792, y: 0, width: 1920, height: 1080))))
    }
}
