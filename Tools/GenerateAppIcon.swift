#!/usr/bin/env swift
// Draws the app icon and writes every macOS size into the asset catalog.
// Vector-drawn at each pixel size (no upscaling), so 16pt stays crisp.
//
//   swift Tools/GenerateAppIcon.swift
//
// Design: a signal fanning out from an antenna over a county grid — the two
// things this logger is about (radio contacts, county lines). Deep-blue
// squircle, gold signal, in the macOS Big Sur icon grid (824/1024 body).

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: Geometry

/// Apple-style continuous-corner squircle (superellipse, n≈5).
func superellipse(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: Drawing

func drawIcon(into ctx: CGContext, size S: CGFloat) {
    let margin = S * 0.0977                       // Big Sur grid: 824 body in 1024
    let body = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let shape = superellipse(in: body)
    let cx = S / 2
    let detail = S >= 64                          // fine detail vanishes at 16/32px

    // Drop shadow under the squircle.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -S * 0.014),
        blur: S * 0.030,
        color: rgb(0x000000, 0.38)
    )
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x0B2545))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Background: night-sky blue, lighter at the top.
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [rgb(0x061A33), rgb(0x11477F), rgb(0x2E90F0)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: body.minY),
        end: CGPoint(x: 0, y: body.maxY),
        options: []
    )

    // County grid: faint map lines across the lower third.
    if detail {
        ctx.saveGState()
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
        ctx.setLineWidth(S * 0.006)
        let gridTop = S * 0.34
        for i in 1...5 {                          // verticals
            let x = body.minX + body.width * CGFloat(i) / 6
            ctx.move(to: CGPoint(x: x, y: body.minY))
            ctx.addLine(to: CGPoint(x: x, y: gridTop))
        }
        for i in 1...3 {                          // horizontals
            let y = body.minY + (gridTop - body.minY) * CGFloat(i) / 4
            ctx.move(to: CGPoint(x: body.minX, y: y))
            ctx.addLine(to: CGPoint(x: body.maxX, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Horizon line under the antenna.
    let groundY = S * 0.262
    ctx.setFillColor(rgb(0xFFFFFF, 0.92))
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: cx - S * 0.22, y: groundY - S * 0.017, width: S * 0.44, height: S * 0.034),
        cornerWidth: S * 0.017, cornerHeight: S * 0.017, transform: nil
    ))
    ctx.fillPath()

    // Tapered antenna mast.
    let mastBottom = groundY + S * 0.008
    let mastTop = S * 0.545
    let mast = CGMutablePath()
    mast.move(to: CGPoint(x: cx - S * 0.060, y: mastBottom))
    mast.addLine(to: CGPoint(x: cx + S * 0.060, y: mastBottom))
    mast.addLine(to: CGPoint(x: cx + S * 0.023, y: mastTop))
    mast.addLine(to: CGPoint(x: cx - S * 0.023, y: mastTop))
    mast.closeSubpath()
    ctx.addPath(mast)
    ctx.setFillColor(rgb(0xFFFFFF, 0.95))
    ctx.fillPath()

    // Feed point + radiating signal. Opaque gold tints, not alpha — gold
    // faded over blue turns olive.
    let feed = CGPoint(x: cx, y: S * 0.566)
    ctx.setFillColor(rgb(0xFFC42E))
    ctx.fillEllipse(in: CGRect(
        x: feed.x - S * 0.044, y: feed.y - S * 0.044,
        width: S * 0.088, height: S * 0.088
    ))

    ctx.setLineCap(.round)
    ctx.setLineWidth(S * 0.036)
    for (radius, color) in [(0.130, 0xFFC42E), (0.205, 0xFFD463), (0.280, 0xFFE49B)] {
        ctx.setStrokeColor(rgb(UInt32(color)))
        ctx.addArc(
            center: feed, radius: S * CGFloat(radius),
            startAngle: 22 * .pi / 180, endAngle: 158 * .pi / 180,
            clockwise: false
        )
        ctx.strokePath()
    }

    // Morse "dit dah dit" — the CW heart of the app.
    if detail {
        let y = S * 0.176
        let h = S * 0.028
        let dot = S * 0.028, dash = S * 0.078, gap = S * 0.028
        let total = dot + gap + dash + gap + dot
        var x = cx - total / 2
        ctx.setFillColor(rgb(0xFFC42E))
        for width in [dot, dash, dot] {
            ctx.addPath(CGPath(
                roundedRect: CGRect(x: x, y: y - h / 2, width: width, height: h),
                cornerWidth: h / 2, cornerHeight: h / 2, transform: nil
            ))
            x += width + gap
        }
        ctx.fillPath()
    }

    // Glass highlight across the top.
    let highlight = CGGradient(
        colorsSpace: space,
        colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: 0, y: body.maxY),
        end: CGPoint(x: 0, y: body.midY),
        options: []
    )

    ctx.restoreGState()
}

// MARK: Output

func render(px: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(into: ctx, size: CGFloat(px))

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("render failed at \(px)px") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

/// (idiom point size, scale) → macOS needs 16/32/128/256/512 at 1x and 2x.
let entries: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

var images: [[String: String]] = []
for entry in entries {
    let px = entry.size * entry.scale
    let name = "icon_\(entry.size)x\(entry.size)@\(entry.scale)x.png"
    render(px: px, to: iconSet.appendingPathComponent(name))
    images.append([
        "idiom": "mac",
        "size": "\(entry.size)x\(entry.size)",
        "scale": "\(entry.scale)x",
        "filename": name,
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: iconSet.appendingPathComponent("Contents.json"))

// Catalog root marker, so the folder is a valid .xcassets.
let catalogInfo: [String: Any] = ["info": ["version": 1, "author": "xcode"]]
try JSONSerialization
    .data(withJSONObject: catalogInfo, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("Resources/Assets.xcassets/Contents.json"))

// Standalone 1024 preview (DMG background art, README, eyeballing).
render(px: 1024, to: root.appendingPathComponent("Tools/icon-preview.png"))
print("Wrote \(entries.count) icons to \(iconSet.path)")
