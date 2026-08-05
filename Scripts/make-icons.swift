#!/usr/bin/env swift
//
// Renders app-icon candidates to PNG.
//
//   swift Scripts/make-icons.swift <output-directory>
//
// Drawn with CoreGraphics rather than shipped as binary assets, so the icon
// stays editable in source and re-renders at any size.

import AppKit

let palette = (
    green:  NSColor(srgbRed: 140/255, green: 255/255, blue: 160/255, alpha: 1),
    teal:   NSColor(srgbRed: 110/255, green: 231/255, blue: 183/255, alpha: 1),
    violet: NSColor(srgbRed: 185/255, green: 156/255, blue: 255/255, alpha: 1),
    amber:  NSColor(srgbRed: 255/255, green: 176/255, blue: 103/255, alpha: 1),
    yellow: NSColor(srgbRed: 255/255, green: 225/255, blue:  86/255, alpha: 1)
)

// MARK: - Shapes

/// Apple-style squircle. A plain rounded rect reads noticeably "off" beside
/// stock icons in the Dock.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let exponent: CGFloat = 4.6
    let steps = 1440
    let a = rect.width / 2, b = rect.height / 2

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / exponent)
        let y = rect.midY + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / exponent)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func bar(_ context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat,
         height: CGFloat, color: NSColor, alpha: CGFloat = 1) {
    let rect = CGRect(x: x, y: y, width: width, height: height)
    context.setFillColor(color.withAlphaComponent(alpha).cgColor)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: height / 2,
                           cornerHeight: height / 2, transform: nil))
    context.fillPath()
}

func gradient(_ colors: [NSColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colors.map(\.cgColor) as CFArray,
               locations: locations)!
}

/// The dark glass slab every design sits on.
func backdrop(_ context: CGContext, _ rect: CGRect, top: NSColor, bottom: NSColor) {
    context.saveGState()
    context.addPath(squircle(in: rect))
    context.clip()

    context.drawLinearGradient(gradient([top, bottom], [0, 1]),
                               start: CGPoint(x: rect.midX, y: rect.maxY),
                               end: CGPoint(x: rect.midX, y: rect.minY),
                               options: [])

    // Light catching the top-left, which is what sells it as glass.
    context.drawRadialGradient(
        gradient([NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)], [0, 1]),
        startCenter: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.18),
        startRadius: 0,
        endCenter: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.18),
        endRadius: rect.width * 0.62,
        options: [])
    context.restoreGState()
}

/// Hairline rim so the icon keeps an edge on a light Dock background.
/// Scaled by `unit`, or a 4px stroke would swallow a 16px icon.
func rim(_ context: CGContext, _ rect: CGRect, _ unit: CGFloat) {
    context.saveGState()
    context.addPath(squircle(in: rect.insetBy(dx: 2 * unit, dy: 2 * unit)))
    context.setStrokeColor(NSColor(white: 1, alpha: 0.14).cgColor)
    context.setLineWidth(max(0.5, 4 * unit))
    context.strokePath()
    context.restoreGState()
}

// MARK: - Designs

enum Design: String, CaseIterable {
    /// Greyscale code lines with the caret as the single accent.
    case caretAccent = "caret-accent"
    /// No colour at all — white on near-black.
    case caretMono = "caret-mono"
    /// One hue throughout, the caret brightest.
    case caretGreen = "caret-green"

    case monogram, window, panes

    var filename: String { "icon-\(rawValue).png" }

    /// Bar colours top-to-bottom, the caret, and the backdrop, for the caret
    /// family. Nil for the other designs.
    var caretPalette: (bars: [(NSColor, CGFloat)], caret: NSColor,
                       top: NSColor, bottom: NSColor)? {
        let neutralTop = NSColor(srgbRed: 0.13, green: 0.14, blue: 0.15, alpha: 1)
        let neutralBottom = NSColor(srgbRed: 0.03, green: 0.035, blue: 0.04, alpha: 1)

        switch self {
        case .caretAccent:
            return (bars: [(NSColor.white, 0.62), (.white, 0.46), (.white, 0.30)],
                    caret: palette.green, top: neutralTop, bottom: neutralBottom)
        case .caretMono:
            return (bars: [(NSColor.white, 0.52), (.white, 0.38), (.white, 0.24)],
                    caret: NSColor(white: 0.97, alpha: 1), top: neutralTop, bottom: neutralBottom)
        case .caretGreen:
            return (bars: [(palette.green, 0.52), (palette.green, 0.36), (palette.green, 0.22)],
                    caret: palette.green,
                    top: NSColor(srgbRed: 0.07, green: 0.15, blue: 0.12, alpha: 1),
                    bottom: NSColor(srgbRed: 0.02, green: 0.05, blue: 0.04, alpha: 1))
        default:
            return nil
        }
    }
}

func draw(_ design: Design, in context: CGContext, size: CGFloat) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    // Icons sit inside a margin so they match the visual weight of stock ones.
    let rect = full.insetBy(dx: size * 0.08, dy: size * 0.08)
    let unit = size / 1024

    switch design {

    // A caret on a pane of glass, with code lines above it.
    case .caretAccent, .caretMono, .caretGreen:
        let scheme = design.caretPalette!
        backdrop(context, rect, top: scheme.top, bottom: scheme.bottom)

        context.saveGState()
        context.addPath(squircle(in: rect))
        context.clip()

        let left = rect.minX + 170 * unit
        let lineHeight = 42 * unit
        let gap = 104 * unit
        var y = rect.midY + 190 * unit

        for (width, entry) in zip([330 * unit, 470 * unit, 250 * unit], scheme.bars) {
            bar(context, x: left, y: y, width: width, height: lineHeight,
                color: entry.0, alpha: entry.1)
            y -= gap
        }

        // The caret sits on its own line below the code, clear of it.
        let caret = CGRect(x: left, y: y - 38 * unit, width: 44 * unit, height: 128 * unit)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 60 * unit,
                          color: scheme.caret.withAlphaComponent(0.9).cgColor)
        context.setFillColor(scheme.caret.cgColor)
        context.addPath(CGPath(roundedRect: caret, cornerWidth: 20 * unit,
                               cornerHeight: 20 * unit, transform: nil))
        context.fillPath()
        context.restoreGState()

        context.restoreGState()
        rim(context, rect, unit)

    // A "V" cut from glass, refracting the palette.
    case .monogram:
        backdrop(context, rect,
                 top: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.16, alpha: 1),
                 bottom: NSColor(srgbRed: 0.02, green: 0.03, blue: 0.05, alpha: 1))

        context.saveGState()
        context.addPath(squircle(in: rect))
        context.clip()

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX - 235 * unit, y: rect.midY + 250 * unit))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - 250 * unit))
        path.addLine(to: CGPoint(x: rect.midX + 235 * unit, y: rect.midY + 250 * unit))

        context.saveGState()
        context.addPath(path)
        context.setLineWidth(96 * unit)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(
            gradient([palette.violet, palette.teal, palette.amber], [0, 0.5, 1]),
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: [])
        context.restoreGState()

        context.restoreGState()
        rim(context, rect, unit)

    // A miniature editor: gutter, code, caret.
    case .window:
        backdrop(context, rect,
                 top: NSColor(srgbRed: 0.06, green: 0.13, blue: 0.11, alpha: 1),
                 bottom: NSColor(srgbRed: 0.02, green: 0.04, blue: 0.03, alpha: 1))

        context.saveGState()
        context.addPath(squircle(in: rect))
        context.clip()

        // Title strip with the tab underline.
        let stripHeight = 130 * unit
        context.setFillColor(NSColor(white: 1, alpha: 0.06).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.maxY - stripHeight,
                            width: rect.width, height: stripHeight))
        context.setFillColor(palette.teal.withAlphaComponent(0.95).cgColor)
        context.fill(CGRect(x: rect.minX + 250 * unit, y: rect.maxY - stripHeight,
                            width: 260 * unit, height: 10 * unit))

        for (index, colour) in [palette.amber, palette.yellow, palette.green].enumerated() {
            let dot = CGRect(x: rect.minX + (60 + CGFloat(index) * 68) * unit,
                             y: rect.maxY - stripHeight / 2 - 22 * unit,
                             width: 44 * unit, height: 44 * unit)
            context.setFillColor(colour.withAlphaComponent(0.9).cgColor)
            context.fillEllipse(in: dot)
        }

        // Gutter.
        let gutter = rect.minX + 150 * unit
        context.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
        context.fill(CGRect(x: gutter, y: rect.minY, width: 4 * unit,
                            height: rect.maxY - stripHeight - rect.minY))

        var y = rect.maxY - stripHeight - 130 * unit
        for (indent, width, colour) in [
            (0 as CGFloat,  300 * unit, palette.violet),
            (70 * unit,     380 * unit, palette.teal),
            (70 * unit,     240 * unit, palette.amber),
            (0 as CGFloat,  180 * unit, palette.violet),
        ] {
            bar(context, x: gutter + 70 * unit + indent, y: y, width: width,
                height: 38 * unit, color: colour, alpha: 0.72)
            y -= 96 * unit
        }

        context.restoreGState()
        rim(context, rect, unit)

    // Overlapping panes of tinted glass.
    case .panes:
        backdrop(context, rect,
                 top: NSColor(srgbRed: 0.05, green: 0.07, blue: 0.09, alpha: 1),
                 bottom: NSColor(srgbRed: 0.01, green: 0.02, blue: 0.03, alpha: 1))

        context.saveGState()
        context.addPath(squircle(in: rect))
        context.clip()

        // Yellow rather than amber for the last pane: amber at low alpha over a
        // near-black backdrop reads as muddy brown, not glass.
        for (offset, colour) in [
            (CGPoint(x: -110 * unit, y:  110 * unit), palette.violet),
            (CGPoint(x:    0,        y:    0),        palette.teal),
            (CGPoint(x:  110 * unit, y: -110 * unit), palette.yellow),
        ] {
            let pane = CGRect(x: rect.midX - 210 * unit + offset.x,
                              y: rect.midY - 210 * unit + offset.y,
                              width: 420 * unit, height: 420 * unit)
            context.saveGState()
            context.translateBy(x: pane.midX, y: pane.midY)
            context.rotate(by: -12 * .pi / 180)
            context.translateBy(x: -pane.midX, y: -pane.midY)

            let path = CGPath(roundedRect: pane, cornerWidth: 70 * unit,
                              cornerHeight: 70 * unit, transform: nil)
            context.addPath(path)
            context.setFillColor(colour.withAlphaComponent(0.46).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(colour.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(9 * unit)
            context.strokePath()
            context.restoreGState()
        }

        context.restoreGState()
        rim(context, rect, unit)
    }
}

// MARK: - Render

func render(_ design: Design, size: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let nsContext = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    draw(design, in: nsContext.cgContext, size: size)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("""
    usage:
      make-icons.swift <out-dir>                          all designs at 1024
      make-icons.swift <out-file.png> <design> <size>     one design, one size

    designs: \(Design.allCases.map(\.rawValue).joined(separator: ", "))

    """.utf8))
    exit(1)
}

// Single design at a given size — used to render each entry of the iconset
// natively rather than downscaling one big PNG, which keeps 16px legible.
if arguments.count >= 4 {
    guard let design = Design(rawValue: arguments[2]), let size = Double(arguments[3]) else {
        FileHandle.standardError.write(Data("unknown design or size\n".utf8))
        exit(1)
    }
    guard let data = render(design, size: CGFloat(size)) else { exit(1) }
    try! data.write(to: URL(fileURLWithPath: arguments[1]))
    exit(0)
}

let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for design in Design.allCases {
    guard let data = render(design, size: 1024) else {
        FileHandle.standardError.write(Data("failed to render \(design.rawValue)\n".utf8))
        exit(1)
    }
    let url = outputDirectory.appendingPathComponent(design.filename)
    try! data.write(to: url)
    print("wrote \(url.path)")
}
