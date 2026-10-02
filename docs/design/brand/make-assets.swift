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

/// The notch, its flares and the amber parts, for a body of size `body` whose top left is
/// at `origin`. Below 40 px the artwork goes and fewer, wider bars stay (AppIconArt on the
/// canvas).
func drawIconContents(_ context: CGContext, origin: CGPoint, body: CGFloat) {
    let simple = body < 40
    let notchWidth = body * 0.6
    let notchHeight = simple ? body * 0.32 : body * 0.26
    let notchLeft = origin.x + (body - notchWidth) / 2
    let top = origin.y
    let radius = body * 0.083
    let flare = simple ? 0 : body * 0.034

    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: notchLeft - flare, y: top))
    notch.addLine(to: CGPoint(x: notchLeft + notchWidth + flare, y: top))
    if flare > 0 {
        notch.addArc(center: CGPoint(x: notchLeft + notchWidth + flare, y: top + flare), radius: flare,
                     startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
    }
    notch.addLine(to: CGPoint(x: notchLeft + notchWidth, y: top + notchHeight - radius))
    notch.addArc(tangent1End: CGPoint(x: notchLeft + notchWidth, y: top + notchHeight),
                 tangent2End: CGPoint(x: notchLeft + notchWidth - radius, y: top + notchHeight), radius: radius)
    notch.addLine(to: CGPoint(x: notchLeft + radius, y: top + notchHeight))
    notch.addArc(tangent1End: CGPoint(x: notchLeft, y: top + notchHeight),
                 tangent2End: CGPoint(x: notchLeft, y: top + notchHeight - radius), radius: radius)
    notch.addLine(to: CGPoint(x: notchLeft, y: top + flare))
    if flare > 0 {
        notch.addArc(center: CGPoint(x: notchLeft - flare, y: top + flare), radius: flare,
                     startAngle: 0, endAngle: -.pi / 2, clockwise: true)
    }
    notch.closeSubpath()
    context.addPath(notch)
    context.setFillColor(color(0x000000))
    context.fillPath()

    if !simple {
        let art = CGRect(x: notchLeft + body * 0.078, y: top + body * 0.063, width: body * 0.136, height: body * 0.136)
        context.saveGState()
        context.addPath(CGPath(roundedRect: art, cornerWidth: body * 0.03, cornerHeight: body * 0.03, transform: nil))
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xF5B85E), color(0xE0892E)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: art.origin, end: CGPoint(x: art.maxX, y: art.maxY), options: [])
        context.restoreGState()
    }

    let barWidth = simple ? max(1, body * 0.05) : body * 0.024
    let gap = simple ? max(1, body * 0.045) : body * 0.019
    let heights: [CGFloat] = simple ? (body < 20 ? [0.14, 0.2] : [0.12, 0.19, 0.15]) : [0.126, 0.19, 0.15, 0.087]
    let barsWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let barsLeft = simple ? notchLeft + (notchWidth - barsWidth) / 2 : notchLeft + notchWidth - body * 0.078 - barsWidth
    let bottom = top + notchHeight - (simple ? body * 0.08 : body * 0.06)
    context.setFillColor(color(0xF0A84A))
    for (index, height) in heights.enumerated() {
        let x = barsLeft + CGFloat(index) * (barWidth + gap)
        let bar = CGRect(x: x, y: bottom - body * height, width: barWidth, height: body * height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        context.fillPath()
    }
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
    context.setFillColor(color(0xD3D7DD))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xF4F5F7), color(0xD3D7DD)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
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
let b: CGFloat = 1024
func n(_ value: CGFloat) -> String { String(format: "%.2f", value) }
let notchLeft = b * 0.2, notchWidth = b * 0.6, notchHeight = b * 0.26, r = b * 0.083, f = b * 0.034
try write("""
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4F5F7"/><stop offset="1" stop-color="#D3D7DD"/></linearGradient></defs>
  <rect width="1024" height="1024" fill="url(#body)"/>
</svg>

""", to: brand.appendingPathComponent("icon-body.svg"))
try write("""
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <path fill="#000" d="M\(n(notchLeft - f)) 0 H\(n(notchLeft + notchWidth + f)) A\(n(f)) \(n(f)) 0 0 0 \(n(notchLeft + notchWidth)) \(n(f)) V\(n(notchHeight - r)) A\(n(r)) \(n(r)) 0 0 1 \(n(notchLeft + notchWidth - r)) \(n(notchHeight)) H\(n(notchLeft + r)) A\(n(r)) \(n(r)) 0 0 1 \(n(notchLeft)) \(n(notchHeight - r)) V\(n(f)) A\(n(f)) \(n(f)) 0 0 0 \(n(notchLeft - f)) 0 Z"/>
</svg>

""", to: brand.appendingPathComponent("icon-notch.svg"))
let barWidth = b * 0.024, barGap = b * 0.019
let barHeights: [CGFloat] = [0.126, 0.19, 0.15, 0.087]
let barsLeft = notchLeft + notchWidth - b * 0.078 - (4 * barWidth + 3 * barGap)
let barBottom = notchHeight - b * 0.06
let bars = barHeights.enumerated().map { index, height in
    "  <rect x=\"\(n(barsLeft + CGFloat(index) * (barWidth + barGap)))\" y=\"\(n(barBottom - b * height))\" width=\"\(n(barWidth))\" height=\"\(n(b * height))\" rx=\"\(n(barWidth / 2))\" fill=\"#F0A84A\"/>"
}.joined(separator: "\n")
try write("""
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><linearGradient id="art" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F5B85E"/><stop offset="1" stop-color="#E0892E"/></linearGradient></defs>
  <rect x="\(n(notchLeft + b * 0.078))" y="\(n(b * 0.063))" width="\(n(b * 0.136))" height="\(n(b * 0.136))" rx="\(n(b * 0.03))" fill="url(#art)"/>
\(bars)
</svg>

""", to: brand.appendingPathComponent("icon-amber.svg"))

print("Wrote the app icon, menu bar icons, disk image background and Icon Composer layers.")
