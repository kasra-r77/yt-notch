import CoreGraphics
import Foundation
import Testing
@testable import NotchUI

/// The accent rule from D5: the artwork's dominant colour, lifted to 3:1 on black; white for
/// near-grey artwork and none.
struct AccentTests {
    /// A square image of one colour, with an optional patch of another in a corner.
    static func image(_ base: UInt32, patch: UInt32? = nil, patchSide: Int = 0, side: Int = 48) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ hex: UInt32, _ rect: CGRect) {
            let colour = AccentColor(hex: hex)
            context.setFillColor(CGColor(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: 1))
            context.fill(rect)
        }
        fill(base, CGRect(x: 0, y: 0, width: side, height: side))
        if let patch { fill(patch, CGRect(x: 0, y: 0, width: patchSide, height: patchSide)) }
        return context.makeImage()!
    }

    static func close(_ a: AccentColor, _ b: AccentColor, within tolerance: Double = 0.03) -> Bool {
        abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance && abs(a.blue - b.blue) <= tolerance
    }

    @Test func oklabRoundTrips() {
        for hex: UInt32 in [0xF0A84A, 0x1E2A5A, 0x5CC8C0, 0x8C8F94, 0xFFFFFF, 0x000000] {
            let colour = AccentColor(hex: hex)
            #expect(Self.close(colour.oklab.srgb, colour, within: 0.002))
        }
    }

    @Test func contrastOnBlack() {
        #expect(abs(AccentColor.white.contrastOnBlack - 21) < 0.01)
        #expect(abs(AccentColor(hex: 0xF0A84A).contrastOnBlack - 10.4) < 0.1)
        #expect(abs(AccentColor(hex: 0x1E2A5A).contrastOnBlack - 1.5) < 0.1)
    }

    @Test func aBrightColourIsUsedAsItIs() {
        let accent = AccentColor.from(Self.image(0xF0A84A))
        #expect(Self.close(accent, AccentColor(hex: 0xF0A84A)))
    }

    @Test func aDarkColourIsLiftedToThreeToOne() {
        let dark = AccentColor(hex: 0x1E2A5A)
        let lifted = dark.lifted()
        #expect(lifted.contrastOnBlack >= Tokens.Accent.minimumContrast)
        #expect(lifted.contrastOnBlack < Tokens.Accent.minimumContrast + 0.3, "lifted no further than needed")
        let hueBefore = atan2(dark.oklab.b, dark.oklab.a)
        let hueAfter = atan2(lifted.oklab.b, lifted.oklab.a)
        #expect(abs(hueBefore - hueAfter) < 0.1, "the hue stays")
        #expect(AccentColor.from(Self.image(0x1E2A5A)).contrastOnBlack >= Tokens.Accent.minimumContrast)
    }

    @Test func greyArtworkAndNoArtworkGiveWhite() {
        #expect(AccentColor.from(Self.image(0x8C8F94)) == .white)
        #expect(AccentColor.from(nil) == .white)
        #expect(AccentColor(hex: 0x8C8F94).lifted() == .white)
    }

    @Test func aSmallSplashOfColourOnGreyIsStillGrey() {
        // A 10 × 10 patch on 48 × 48 is about 4% of the pixels.
        #expect(AccentColor.from(Self.image(0x8C8F94, patch: 0xF0A84A, patchSide: 10)) == .white)
    }

    @Test func theMostColourfulHueWins() {
        // Mostly teal, a quarter amber: teal.
        let accent = AccentColor.from(Self.image(0x5CC8C0, patch: 0xF0A84A, patchSide: 24))
        #expect(Self.close(accent, AccentColor(hex: 0x5CC8C0), within: 0.05))
    }
}
