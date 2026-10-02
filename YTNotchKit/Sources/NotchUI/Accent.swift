import CoreGraphics
import Foundation

/// The accent colour from the artwork (design spec D5, "Accent").
struct AccentColor: Equatable, Sendable {
    /// sRGB components, 0 to 1.
    var red: Double
    var green: Double
    var blue: Double

    static let white = AccentColor(red: 1, green: 1, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func from(_ image: CGImage?) -> AccentColor {
        guard let image, let dominant = Self.dominant(in: image) else { return .white }
        return dominant.lifted()
    }

    /// WCAG contrast ratio on black.
    var contrastOnBlack: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05
    }

    var oklab: OKLab { OKLab(self) }

    /// Raises OKLCH lightness, keeping hue and chroma, until the colour reaches the minimum
    /// contrast on black. Near-grey colours become white.
    func lifted() -> AccentColor {
        let lab = oklab
        guard lab.chroma >= Tokens.Accent.greyChroma else { return .white }
        guard contrastOnBlack < Tokens.Accent.minimumContrast else { return self }
        var low = lab.lightness
        var high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if OKLab(lightness: middle, a: lab.a, b: lab.b).srgb.contrastOnBlack >= Tokens.Accent.minimumContrast {
                high = middle
            } else {
                low = middle
            }
        }
        return OKLab(lightness: high, a: lab.a, b: lab.b).srgb
    }

    /// The most colourful hue in the image, averaged; nil when the image is near grey.
    static func dominant(in image: CGImage) -> AccentColor? {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let bins = 12
        var weights = [Double](repeating: 0, count: bins)
        var sums = [(l: Double, a: Double, b: Double)](repeating: (0, 0, 0), count: bins)
        var colourful = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let colour = AccentColor(red: Double(pixels[index]) / 255 / alpha, green: Double(pixels[index + 1]) / 255 / alpha, blue: Double(pixels[index + 2]) / 255 / alpha)
            let lab = colour.oklab
            guard lab.chroma >= Tokens.Accent.greyChroma else { continue }
            colourful += 1
            var hue = atan2(lab.b, lab.a)
            if hue < 0 { hue += 2 * .pi }
            let bin = min(bins - 1, Int(hue / (2 * .pi) * Double(bins)))
            weights[bin] += lab.chroma
            sums[bin].l += lab.lightness * lab.chroma
            sums[bin].a += lab.a * lab.chroma
            sums[bin].b += lab.b * lab.chroma
        }
        // Fewer than a tenth of the pixels with any colour: treat the artwork as grey.
        guard colourful * 10 >= side * side, let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0 else {
            return nil
        }
        let weight = weights[best]
        let average = OKLab(lightness: sums[best].l / weight, a: sums[best].a / weight, b: sums[best].b / weight)
        guard average.chroma >= Tokens.Accent.greyChroma else { return nil }
        return average.srgb
    }
}

/// A colour in Björn Ottosson's OKLab space.
struct OKLab: Equatable, Sendable {
    var lightness: Double
    var a: Double
    var b: Double

    var chroma: Double { (a * a + b * b).squareRoot() }

    init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    init(_ colour: AccentColor) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(colour.red), g = linear(colour.green), bl = linear(colour.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    var srgb: AccentColor {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        func gamma(_ c: Double) -> Double {
            let clamped = min(1, max(0, c))
            return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return AccentColor(
            red: gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }
}
