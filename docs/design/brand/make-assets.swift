// Draws the brand assets approved in design D6 (YT-7) from their geometry, so they can be
// regenerated after any change. Run from the repository root:
//
//     swift docs/design/brand/make-assets.swift
//
// Writes:
//   App/Assets.xcassets/AppIcon.appiconset/          app icon, 16 to 512 at 1x and 2x
//   App/Assets.xcassets/MenuBarIcon.imageset/        menu bar template icon (PDF)
//   App/Assets.xcassets/MenuBarIconAttention.imageset/  the same with the "needs you" dot
//   docs/design/brand/dmg-background.png, @2x        disk image window background
//   docs/design/brand/icon-*.svg                     layers for Icon Composer

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("App/Assets.xcassets")
let brand = root.appendingPathComponent("docs/design/brand")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

/// A bitmap context with the origin at the top left, like the design files.
func bitmap(width: Int, height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    return context
}

func savePNG(_ context: CGContext, to url: URL) throws {
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: App icon

func gradient(_ from: UInt32, _ to: UInt32) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(from), color(to)] as CFArray, locations: [0, 1])!
}

/// A notch hanging from `top`, with concave flares where it meets the top edge.
func notchPath(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, flare: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left - flare, y: top))
    path.addLine(to: CGPoint(x: left + width + flare, y: top))
    if flare > 0 {
        path.addArc(center: CGPoint(x: left + width + flare, y: top + flare), radius: flare, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
    }
    path.addLine(to: CGPoint(x: left + width, y: top + height - radius))
    path.addArc(tangent1End: CGPoint(x: left + width, y: top + height), tangent2End: CGPoint(x: left + width - radius, y: top + height), radius: radius)
    path.addLine(to: CGPoint(x: left + radius, y: top + height))
    path.addArc(tangent1End: CGPoint(x: left, y: top + height), tangent2End: CGPoint(x: left, y: top + height - radius), radius: radius)
    path.addLine(to: CGPoint(x: left, y: top + flare))
    if flare > 0 {
        path.addArc(center: CGPoint(x: left - flare, y: top + flare), radius: flare, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
    }
    path.closeSubpath()
    return path
}

/// D9's C1 geometry, as fractions of the body. Below 40 px of body (about 48 px of icon) the
/// notch grows and loses its flares, and the bars get fewer and wider.
struct IconGeometry {
    let body: CGFloat
    var simple: Bool { body < 40 }
    var notchWidth: CGFloat { body * (simple ? 0.72 : 0.64) }
    var notchHeight: CGFloat { body * (simple ? 0.4 : 0.3) }
    var notchLeft: CGFloat { (body - notchWidth) / 2 }
    var radius: CGFloat { body * 0.11 }
    var flare: CGFloat { simple ? 0 : body * 0.04 }

    var bars: [CGRect] {
        let heights: [CGFloat] = simple ? (body < 20 ? [0.16, 0.24] : [0.14, 0.22, 0.17]) : [0.12, 0.2, 0.15]
        let width = simple ? max(1.5, body * 0.07) : body * 0.05
        let gap = simple ? max(1, body * 0.05) : body * 0.035
        let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
        let bottom = notchHeight - body * (simple ? 0.09 : 0.07)
        return heights.enumerated().map { index, height in
            CGRect(x: (body - total) / 2 + CGFloat(index) * (width + gap), y: bottom - body * height, width: width, height: body * height)
        }
    }

    /// The two beamed quavers, in a box of side `unit` centred below the notch.
    var unit: CGFloat { body * (simple ? 0.4 : 0.42) }
    var notesCentre: CGPoint { CGPoint(x: body / 2, y: body * (simple ? 0.7 : 0.655)) }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: notesCentre.x + x * unit, y: notesCentre.y + y * unit) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * unit, height: height * unit))
    }
    var heads: [CGRect] { [rect(-0.39, 0.175, 0.34, 0.25), rect(0.09, 0.075, 0.34, 0.25)] }
    var headAngle: CGFloat { -22 * .pi / 180 }
    var stems: [CGRect] { [rect(-0.15, -0.36, 0.08, 0.64), rect(0.33, -0.46, 0.08, 0.64)] }
    var beam: [CGPoint] { [point(-0.15, -0.38), point(0.41, -0.48), point(0.41, -0.31), point(-0.15, -0.21)] }
}

func drawIconContents(_ context: CGContext, origin: CGPoint, body: CGFloat) {
    let icon = IconGeometry(body: body)
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    context.addPath(notchPath(left: icon.notchLeft, top: 0, width: icon.notchWidth, height: icon.notchHeight, radius: icon.radius, flare: icon.flare))
    context.setFillColor(color(0x000000))
    context.fillPath()

    context.setFillColor(color(0xFFFFFF))
    for bar in icon.bars {
        context.addPath(CGPath(roundedRect: bar, cornerWidth: bar.width / 2, cornerHeight: bar.width / 2, transform: nil))
    }
    for stem in icon.stems {
        context.addRect(stem)
    }
    context.addLines(between: icon.beam)
    context.closePath()
    context.fillPath()
    for head in icon.heads {
        context.saveGState()
        context.translateBy(x: head.midX, y: head.midY)
        context.rotate(by: icon.headAngle)
        context.fillEllipse(in: CGRect(x: -head.width / 2, y: -head.height / 2, width: head.width, height: head.height))
        context.restoreGState()
    }
    context.restoreGState()
}

/// One app icon image: the macOS grid, an 824 body on a 1024 canvas, with its shadow.
func appIcon(pixels: Int) -> CGContext {
    let size = CGFloat(pixels)
    let context = bitmap(width: pixels, height: pixels)
    let body = size * 824 / 1024
    let origin = CGPoint(x: size * 100 / 1024, y: size * 100 / 1024)
    let rect = CGRect(origin: origin, size: CGSize(width: body, height: body))
    let shape = CGPath(roundedRect: rect, cornerWidth: body * 0.2237, cornerHeight: body * 0.2237, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: size * 0.012), blur: size * 0.03, color: color(0x000000, 0.3))
    context.addPath(shape)
    context.setFillColor(color(0xE3892C))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(gradient(0xF8C46E, 0xE3892C), start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    drawIconContents(context, origin: origin, body: body)
    context.restoreGState()

    context.addPath(shape)
    context.setStrokeColor(color(0x000000, 0.12))
    context.setLineWidth(max(0.5, body * 0.002))
    context.strokePath()
    return context
}

let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try savePNG(appIcon(pixels: points * scale), to: iconSet.appendingPathComponent(name))
        images.append(#"    { "idiom" : "mac", "size" : "\#(points)x\#(points)", "scale" : "\#(scale)x", "filename" : "\#(name)" }"#)
    }
}
try write("{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"version\" : 1, \"author\" : \"xcode\" }\n}\n",
          to: iconSet.appendingPathComponent("Contents.json"))
try write("{\n  \"info\" : { \"version\" : 1, \"author\" : \"xcode\" }\n}\n", to: assets.appendingPathComponent("Contents.json"))

// MARK: Menu bar icon

/// The 18 pt template glyph, in a top-left space, drawn in black.
func drawGlyph(_ context: CGContext, attention: Bool) {
    context.saveGState()
    if attention {
        // Cut the dot's ring out of everything else.
        let clip = CGMutablePath()
        clip.addRect(CGRect(x: 0, y: 0, width: 18, height: 18))
        clip.addEllipse(in: CGRect(x: 15.5 - 3.4, y: 3.5 - 3.4, width: 6.8, height: 6.8))
        context.addPath(clip)
        context.clip(using: .evenOdd)
    }
    context.setStrokeColor(color(0x000000))
    context.setFillColor(color(0x000000))
    context.setLineWidth(1.5)
    context.addPath(CGPath(roundedRect: CGRect(x: 1.5, y: 3, width: 15, height: 12), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
    context.strokePath()
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: 6.5, y: 3))
    notch.addLine(to: CGPoint(x: 11.5, y: 3))
    notch.addLine(to: CGPoint(x: 11.5, y: 4.6))
    notch.addArc(tangent1End: CGPoint(x: 11.5, y: 6), tangent2End: CGPoint(x: 10.1, y: 6), radius: 1.4)
    notch.addLine(to: CGPoint(x: 7.9, y: 6))
    notch.addArc(tangent1End: CGPoint(x: 6.5, y: 6), tangent2End: CGPoint(x: 6.5, y: 4.6), radius: 1.4)
    notch.closeSubpath()
    context.addPath(notch)
    context.fillPath()
    for (x, y, height) in [(6.0, 9.5, 3.0), (8.25, 8.0, 4.5), (10.5, 10.0, 2.5)] as [(CGFloat, CGFloat, CGFloat)] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 1.5, height: height), cornerWidth: 0.75, cornerHeight: 0.75, transform: nil))
        context.fillPath()
    }
    context.restoreGState()
    if attention {
        context.addEllipse(in: CGRect(x: 15.5 - 2.4, y: 3.5 - 2.4, width: 4.8, height: 4.8))
        context.fillPath()
    }
}

func menuBarPDF(attention: Bool, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    context.translateBy(x: 0, y: 18)
    context.scaleBy(x: 1, y: -1)
    drawGlyph(context, attention: attention)
    context.endPDFPage()
    context.closePDF()
}

for (name, attention) in [("MenuBarIcon", false), ("MenuBarIconAttention", true)] {
    let set = assets.appendingPathComponent("\(name).imageset")
    try menuBarPDF(attention: attention, to: set.appendingPathComponent("\(name).pdf"))
    try write("""
    {
      "images" : [ { "idiom" : "universal", "filename" : "\(name).pdf" } ],
      "info" : { "version" : 1, "author" : "xcode" },
      "properties" : { "template-rendering-intent" : "template", "preserves-vector-representation" : true }
    }

    """, to: set.appendingPathComponent("Contents.json"))
}

// MARK: Disk image background

func dmgBackground(scale: Int) -> CGContext {
    let s = CGFloat(scale)
    let context = bitmap(width: 660 * scale, height: 400 * scale)
    context.scaleBy(x: s, y: s)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xF4F5F7), color(0xE3E6EA)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 400), options: [])
    // The arrow from the app icon (centre 165, 180) to Applications (centre 495, 180).
    context.setStrokeColor(color(0x9AA0A8))
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 266, y: 180))
    context.addLine(to: CGPoint(x: 390, y: 180))
    context.move(to: CGPoint(x: 378, y: 168))
    context.addLine(to: CGPoint(x: 390, y: 180))
    context.addLine(to: CGPoint(x: 378, y: 192))
    context.strokePath()
    // The line of text, drawn through AppKit in the flipped context.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let text = "Drag YT Notch to Applications" as NSString
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    text.draw(in: CGRect(x: 0, y: 300, width: 660, height: 24), withAttributes: [
        .font: NSFont.systemFont(ofSize: 15),
        .foregroundColor: NSColor(cgColor: color(0x3A3F47))!,
        .paragraphStyle: style,
    ])
    NSGraphicsContext.restoreGraphicsState()
    return context
}

try savePNG(dmgBackground(scale: 1), to: brand.appendingPathComponent("dmg-background.png"))
try savePNG(dmgBackground(scale: 2), to: brand.appendingPathComponent("dmg-background@2x.png"))

// MARK: Icon Composer layers

/// Full-bleed 1024 layers: Icon Composer applies the system shape, shadow and appearances.
let full = IconGeometry(body: 1024)
func n(_ value: CGFloat) -> String { String(format: "%.2f", value) }
func svg(_ content: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n\(content)\n</svg>\n"
}
func svgPath(_ path: CGPath) -> String {
    var d = ""
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(n(p[0].x)) \(n(p[0].y)) "
        case .addLineToPoint: d += "L\(n(p[0].x)) \(n(p[0].y)) "
        case .addQuadCurveToPoint: d += "Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) "
        case .addCurveToPoint: d += "C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y)) "
        case .closeSubpath: d += "Z "
        @unknown default: break
        }
    }
    return d.trimmingCharacters(in: .whitespaces)
}

try write(svg("""
  <defs><linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F8C46E"/><stop offset="1" stop-color="#E3892C"/></linearGradient></defs>
  <rect width="1024" height="1024" fill="url(#body)"/>
"""), to: brand.appendingPathComponent("icon-body.svg"))
let notch = notchPath(left: full.notchLeft, top: 0, width: full.notchWidth, height: full.notchHeight, radius: full.radius, flare: full.flare)
try write(svg("  <path fill=\"#000\" d=\"\(svgPath(notch))\"/>"), to: brand.appendingPathComponent("icon-notch.svg"))
let degrees = n(full.headAngle * 180 / .pi)
let marks = full.bars.map { "  <rect x=\"\(n($0.minX))\" y=\"\(n($0.minY))\" width=\"\(n($0.width))\" height=\"\(n($0.height))\" rx=\"\(n($0.width / 2))\"/>" }
    + full.stems.map { "  <rect x=\"\(n($0.minX))\" y=\"\(n($0.minY))\" width=\"\(n($0.width))\" height=\"\(n($0.height))\"/>" }
    + ["  <polygon points=\"\(full.beam.map { "\(n($0.x)),\(n($0.y))" }.joined(separator: " "))\"/>"]
    + full.heads.map { "  <ellipse cx=\"\(n($0.midX))\" cy=\"\(n($0.midY))\" rx=\"\(n($0.width / 2))\" ry=\"\(n($0.height / 2))\" transform=\"rotate(\(degrees) \(n($0.midX)) \(n($0.midY)))\"/>" }
try write(svg("<g fill=\"#FFF\">\n" + marks.joined(separator: "\n") + "\n</g>"), to: brand.appendingPathComponent("icon-marks.svg"))

print("Wrote the app icon, menu bar icons, disk image background and Icon Composer layers.")
