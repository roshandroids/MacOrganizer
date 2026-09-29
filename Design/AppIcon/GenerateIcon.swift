#!/usr/bin/swift
import AppKit
import CoreGraphics

let size = 1024.0
let rect = CGRect(x: 0, y: 0, width: size, height: size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// MARK: - Background squircle with soft drop shadow

let margin = size * 0.045
let bgRect = rect.insetBy(dx: margin, dy: margin)
let cornerRadius = bgRect.width * 0.225

func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.018), blur: size * 0.035, color: rgb(10, 20, 40, 0.35))
ctx.addPath(squirclePath(in: bgRect, radius: cornerRadius))
ctx.setFillColor(rgb(0, 0, 0))
ctx.fillPath()
ctx.restoreGState()

// Background gradient: deep indigo -> teal, diagonal
ctx.saveGState()
ctx.addPath(squirclePath(in: bgRect, radius: cornerRadius))
ctx.clip()

let bgColors = [rgb(67, 56, 202), rgb(37, 99, 235), rgb(8, 145, 178)] as CFArray
guard let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 0.55, 1]) else { fatalError() }
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: bgRect.minX, y: bgRect.maxY),
    end: CGPoint(x: bgRect.maxX, y: bgRect.minY),
    options: []
)

// Soft top-left highlight sheen
let highlightColors = [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0.0)] as CFArray
guard let highlightGradient = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0, 1]) else { fatalError() }
ctx.drawRadialGradient(
    highlightGradient,
    startCenter: CGPoint(x: bgRect.minX + bgRect.width * 0.32, y: bgRect.maxY - bgRect.height * 0.28),
    startRadius: 0,
    endCenter: CGPoint(x: bgRect.minX + bgRect.width * 0.32, y: bgRect.maxY - bgRect.height * 0.28),
    endRadius: bgRect.width * 0.75,
    options: []
)

// Very subtle bottom vignette for depth
let vignetteColors = [rgb(0, 0, 0, 0.0), rgb(0, 0, 0, 0.16)] as CFArray
guard let vignetteGradient = CGGradient(colorsSpace: colorSpace, colors: vignetteColors, locations: [0, 1]) else { fatalError() }
ctx.drawLinearGradient(
    vignetteGradient,
    start: CGPoint(x: bgRect.midX, y: bgRect.minY + bgRect.height * 0.35),
    end: CGPoint(x: bgRect.midX, y: bgRect.minY),
    options: []
)
ctx.restoreGState()

// Inner hairline stroke for crispness against dark menu bars
ctx.saveGState()
ctx.addPath(squirclePath(in: bgRect.insetBy(dx: 1.5, dy: 1.5), radius: cornerRadius))
ctx.setStrokeColor(rgb(255, 255, 255, 0.12))
ctx.setLineWidth(2.5)
ctx.strokePath()
ctx.restoreGState()

// MARK: - Folder glyph

// Folder built from a back panel + a lighter front flap, in flattened
// "SF Symbols"-style geometry, centered and large enough to read at 16pt.
// Coordinates here follow CG convention: y increases UPWARD (maxY = visual top).
let glyphCenter = CGPoint(x: bgRect.midX, y: bgRect.midY - bgRect.height * 0.015)
let glyphWidth = bgRect.width * 0.58
let glyphHeight = glyphWidth * 0.72
let glyphRadius = glyphWidth * 0.075

let bodyRect = CGRect(
    x: glyphCenter.x - glyphWidth / 2, y: glyphCenter.y - glyphHeight / 2,
    width: glyphWidth, height: glyphHeight
)
let tabWidth = glyphWidth * 0.42
let tabHeight = glyphHeight * 0.20

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.022, color: rgb(10, 20, 45, 0.4))

// Back panel: one continuous silhouette — a tab at the top-left fused to the
// main body beneath it (classic folder shape, tab clearly above the body).
let backPath = CGMutablePath()
let tabTopY = bodyRect.maxY
let bodyTopY = bodyRect.maxY - tabHeight
backPath.move(to: CGPoint(x: bodyRect.minX + glyphRadius, y: tabTopY))
backPath.addLine(to: CGPoint(x: bodyRect.minX + tabWidth, y: tabTopY))
backPath.addLine(to: CGPoint(x: bodyRect.minX + tabWidth + tabHeight * 0.55, y: bodyTopY))
backPath.addLine(to: CGPoint(x: bodyRect.maxX - glyphRadius, y: bodyTopY))
backPath.addQuadCurve(to: CGPoint(x: bodyRect.maxX, y: bodyTopY - glyphRadius), control: CGPoint(x: bodyRect.maxX, y: bodyTopY))
backPath.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + glyphRadius))
backPath.addQuadCurve(to: CGPoint(x: bodyRect.maxX - glyphRadius, y: bodyRect.minY), control: CGPoint(x: bodyRect.maxX, y: bodyRect.minY))
backPath.addLine(to: CGPoint(x: bodyRect.minX + glyphRadius, y: bodyRect.minY))
backPath.addQuadCurve(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + glyphRadius), control: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
backPath.addLine(to: CGPoint(x: bodyRect.minX, y: tabTopY - glyphRadius))
backPath.addQuadCurve(to: CGPoint(x: bodyRect.minX + glyphRadius, y: tabTopY), control: CGPoint(x: bodyRect.minX, y: tabTopY))
backPath.closeSubpath()

ctx.addPath(backPath)
ctx.setFillColor(rgb(219, 227, 255, 1.0))
ctx.fillPath()
ctx.restoreGState()

// Front flap — inset and shorter than the back panel, sitting lower, so the
// back panel's tab (and a thin sliver of its top edge) stays visible above it.
let frontInsetX = bodyRect.width * 0.045
let frontTopY = bodyTopY - tabHeight * 0.32
let frontRect = CGRect(
    x: bodyRect.minX + frontInsetX, y: bodyRect.minY,
    width: bodyRect.width - frontInsetX * 2, height: frontTopY - bodyRect.minY
)
let frontPath = CGPath(
    roundedRect: frontRect, cornerWidth: glyphRadius * 0.8, cornerHeight: glyphRadius * 0.8, transform: nil
)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.006), blur: size * 0.01, color: rgb(10, 20, 45, 0.18))
ctx.addPath(frontPath)
ctx.setFillColor(rgb(255, 255, 255, 1.0))
ctx.fillPath()
ctx.restoreGState()

// Three small "organized category" ticks on the front flap
ctx.saveGState()
let tickColors = [rgb(59, 130, 246), rgb(20, 184, 166), rgb(99, 102, 241)]
let tickWidth = frontRect.width * 0.16
let tickHeight = frontRect.height * 0.13
let tickGap = frontRect.width * 0.08
let ticksTotalWidth = tickWidth * 3 + tickGap * 2
var tickX = frontRect.midX - ticksTotalWidth / 2
let tickY = frontRect.minY + frontRect.height * 0.28
for color in tickColors {
    let tickRect = CGRect(x: tickX, y: tickY, width: tickWidth, height: tickHeight)
    ctx.addPath(CGPath(roundedRect: tickRect, cornerWidth: tickHeight * 0.3, cornerHeight: tickHeight * 0.3, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
    tickX += tickWidth + tickGap
}
ctx.restoreGState()

// MARK: - Sparkle badge (top-right), signals "smart / automatic"

func sparklePath(center: CGPoint, size: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let big = size
    let small = size * 0.32
    path.move(to: CGPoint(x: center.x, y: center.y + big))
    path.addQuadCurve(to: CGPoint(x: center.x + small, y: center.y + small), control: CGPoint(x: center.x, y: center.y + small))
    path.addQuadCurve(to: CGPoint(x: center.x + big, y: center.y), control: CGPoint(x: center.x + small, y: center.y))
    path.addQuadCurve(to: CGPoint(x: center.x + small, y: center.y - small), control: CGPoint(x: center.x + small, y: center.y))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - big), control: CGPoint(x: center.x, y: center.y - small))
    path.addQuadCurve(to: CGPoint(x: center.x - small, y: center.y - small), control: CGPoint(x: center.x, y: center.y - small))
    path.addQuadCurve(to: CGPoint(x: center.x - big, y: center.y), control: CGPoint(x: center.x - small, y: center.y))
    path.addQuadCurve(to: CGPoint(x: center.x - small, y: center.y + small), control: CGPoint(x: center.x - small, y: center.y))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + big), control: CGPoint(x: center.x, y: center.y + small))
    path.closeSubpath()
    return path
}

let sparkleCenter = CGPoint(x: bodyRect.maxX - glyphWidth * 0.02, y: bodyRect.maxY - glyphHeight * 0.08)

// Warm glow behind the sparkle
ctx.saveGState()
let glowColors = [rgb(253, 224, 71, 0.55), rgb(253, 224, 71, 0.0)] as CFArray
guard let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) else { fatalError() }
ctx.drawRadialGradient(
    glowGradient, startCenter: sparkleCenter, startRadius: 0,
    endCenter: sparkleCenter, endRadius: glyphWidth * 0.22, options: []
)
ctx.restoreGState()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: size * 0.012, color: rgb(180, 120, 0, 0.5))
ctx.addPath(sparklePath(center: sparkleCenter, size: glyphWidth * 0.11))
ctx.setFillColor(rgb(255, 214, 92))
ctx.fillPath()
ctx.restoreGState()

let smallSparkleCenter = CGPoint(x: sparkleCenter.x - glyphWidth * 0.16, y: sparkleCenter.y + glyphWidth * 0.14)
ctx.saveGState()
ctx.addPath(sparklePath(center: smallSparkleCenter, size: glyphWidth * 0.05))
ctx.setFillColor(rgb(255, 255, 255, 0.9))
ctx.fillPath()
ctx.restoreGState()

// MARK: - Export

guard let image = ctx.makeImage() else { fatalError("no image") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("no png data") }

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
