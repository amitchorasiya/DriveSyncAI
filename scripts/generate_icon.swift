#!/usr/bin/env swift
// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Cocoa

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let pad = s * 0.08

    // Background: rounded rect with deep purple-blue AI gradient
    let bgRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let bgRadius = s * 0.22
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil)

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.38, green: 0.15, blue: 0.90, alpha: 1.0),
            CGColor(red: 0.12, green: 0.10, blue: 0.65, alpha: 1.0),
            CGColor(red: 0.08, green: 0.06, blue: 0.45, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: pad, y: s - pad), end: CGPoint(x: s - pad, y: pad), options: [])
    ctx.restoreGState()

    // Neural network nodes (background decoration)
    let nodeColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
    ctx.setFillColor(nodeColor)
    let nodePositions: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.20, 0.80, 0.025), (0.35, 0.85, 0.018), (0.75, 0.82, 0.022),
        (0.85, 0.70, 0.015), (0.15, 0.65, 0.020), (0.90, 0.55, 0.018),
        (0.12, 0.40, 0.015), (0.88, 0.35, 0.020), (0.20, 0.22, 0.018),
        (0.80, 0.20, 0.015), (0.50, 0.15, 0.022), (0.65, 0.88, 0.015),
    ]
    for node in nodePositions {
        let r = s * node.r
        ctx.fillEllipse(in: CGRect(x: s * node.x - r, y: s * node.y - r, width: r * 2, height: r * 2))
    }

    // Neural connection lines (subtle)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
    ctx.setLineWidth(s * 0.004)
    let connections: [(from: Int, to: Int)] = [
        (0, 1), (1, 5), (2, 5), (3, 7), (4, 6), (6, 8), (7, 9), (8, 10), (9, 10), (0, 4), (2, 3), (1, 11)
    ]
    for conn in connections {
        let from = nodePositions[conn.from]
        let to = nodePositions[conn.to]
        ctx.beginPath()
        ctx.move(to: CGPoint(x: s * from.x, y: s * from.y))
        ctx.addLine(to: CGPoint(x: s * to.x, y: s * to.y))
        ctx.strokePath()
    }

    // Central brain/AI icon - stylized brain outline
    let centerX = s * 0.50
    let centerY = s * 0.55
    let brainScale = s * 0.18

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(s * 0.025)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Left hemisphere
    ctx.beginPath()
    ctx.move(to: CGPoint(x: centerX, y: centerY + brainScale * 0.9))
    ctx.addCurve(
        to: CGPoint(x: centerX - brainScale * 1.0, y: centerY + brainScale * 0.2),
        control1: CGPoint(x: centerX - brainScale * 0.3, y: centerY + brainScale * 1.1),
        control2: CGPoint(x: centerX - brainScale * 1.2, y: centerY + brainScale * 0.8)
    )
    ctx.addCurve(
        to: CGPoint(x: centerX - brainScale * 0.6, y: centerY - brainScale * 0.8),
        control1: CGPoint(x: centerX - brainScale * 1.1, y: centerY - brainScale * 0.3),
        control2: CGPoint(x: centerX - brainScale * 0.9, y: centerY - brainScale * 0.7)
    )
    ctx.addCurve(
        to: CGPoint(x: centerX, y: centerY - brainScale * 0.9),
        control1: CGPoint(x: centerX - brainScale * 0.3, y: centerY - brainScale * 0.95),
        control2: CGPoint(x: centerX - brainScale * 0.1, y: centerY - brainScale * 0.9)
    )
    ctx.strokePath()

    // Right hemisphere
    ctx.beginPath()
    ctx.move(to: CGPoint(x: centerX, y: centerY + brainScale * 0.9))
    ctx.addCurve(
        to: CGPoint(x: centerX + brainScale * 1.0, y: centerY + brainScale * 0.2),
        control1: CGPoint(x: centerX + brainScale * 0.3, y: centerY + brainScale * 1.1),
        control2: CGPoint(x: centerX + brainScale * 1.2, y: centerY + brainScale * 0.8)
    )
    ctx.addCurve(
        to: CGPoint(x: centerX + brainScale * 0.6, y: centerY - brainScale * 0.8),
        control1: CGPoint(x: centerX + brainScale * 1.1, y: centerY - brainScale * 0.3),
        control2: CGPoint(x: centerX + brainScale * 0.9, y: centerY - brainScale * 0.7)
    )
    ctx.addCurve(
        to: CGPoint(x: centerX, y: centerY - brainScale * 0.9),
        control1: CGPoint(x: centerX + brainScale * 0.3, y: centerY - brainScale * 0.95),
        control2: CGPoint(x: centerX + brainScale * 0.1, y: centerY - brainScale * 0.9)
    )
    ctx.strokePath()

    // Center line (brain split)
    ctx.setLineWidth(s * 0.012)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: centerX, y: centerY - brainScale * 0.85))
    ctx.addLine(to: CGPoint(x: centerX, y: centerY + brainScale * 0.85))
    ctx.strokePath()

    // Sync arrows below brain (small, indicates sync functionality)
    let arrowCX = centerX
    let arrowCY = s * 0.28
    let arrowR = s * 0.08
    let arrowW = s * 0.02

    ctx.setStrokeColor(CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.9))
    ctx.setLineWidth(arrowW)
    ctx.setLineCap(.round)

    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: arrowCX, y: arrowCY), radius: arrowR, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
    ctx.strokePath()

    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: arrowCX, y: arrowCY), radius: arrowR, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
    ctx.strokePath()

    // Arrowheads
    let aLen = s * 0.035
    ctx.setFillColor(CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.9))

    let tip1Angle = CGFloat.pi * 0.8
    let tip1X = arrowCX + arrowR * cos(tip1Angle)
    let tip1Y = arrowCY + arrowR * sin(tip1Angle)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: tip1X, y: tip1Y))
    ctx.addLine(to: CGPoint(x: tip1X + aLen, y: tip1Y + aLen * 0.4))
    ctx.addLine(to: CGPoint(x: tip1X + aLen * 0.2, y: tip1Y - aLen * 0.5))
    ctx.closePath()
    ctx.fillPath()

    let tip2Angle = CGFloat.pi * 1.8
    let tip2X = arrowCX + arrowR * cos(tip2Angle)
    let tip2Y = arrowCY + arrowR * sin(tip2Angle)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: tip2X, y: tip2Y))
    ctx.addLine(to: CGPoint(x: tip2X - aLen, y: tip2Y - aLen * 0.4))
    ctx.addLine(to: CGPoint(x: tip2X - aLen * 0.2, y: tip2Y + aLen * 0.5))
    ctx.closePath()
    ctx.fillPath()

    // Sparkle accents (AI magic feel)
    let sparkleColor = CGColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 0.8)
    drawSparkle(ctx: ctx, x: s * 0.78, y: s * 0.78, size: s * 0.04, color: sparkleColor)
    drawSparkle(ctx: ctx, x: s * 0.22, y: s * 0.75, size: s * 0.03, color: sparkleColor)
    drawSparkle(ctx: ctx, x: s * 0.82, y: s * 0.48, size: s * 0.025, color: sparkleColor)

    image.unlockFocus()
    return image
}

func drawSparkle(ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    let arm = size
    let thick = size * 0.3

    // Vertical arm
    ctx.beginPath()
    ctx.move(to: CGPoint(x: x, y: y + arm))
    ctx.addLine(to: CGPoint(x: x + thick * 0.5, y: y))
    ctx.addLine(to: CGPoint(x: x, y: y - arm))
    ctx.addLine(to: CGPoint(x: x - thick * 0.5, y: y))
    ctx.closePath()
    ctx.fillPath()

    // Horizontal arm
    ctx.beginPath()
    ctx.move(to: CGPoint(x: x + arm, y: y))
    ctx.addLine(to: CGPoint(x: x, y: y + thick * 0.5))
    ctx.addLine(to: CGPoint(x: x - arm, y: y))
    ctx.addLine(to: CGPoint(x: x, y: y - thick * 0.5))
    ctx.closePath()
    ctx.fillPath()
}

// Main
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let iconsetDir = projectDir.appendingPathComponent("build_tmp/AppIcon.iconset")
let icnsOutput = projectDir.appendingPathComponent("Sources/DriveSyncAI/Resources/AppIcon.icns")

let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for entry in sizes {
    let img = drawIcon(size: CGFloat(entry.size))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to generate \(entry.name)\n", stderr)
        exit(1)
    }
    let outURL = iconsetDir.appendingPathComponent("\(entry.name).png")
    try png.write(to: outURL)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsOutput.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Generated \(icnsOutput.path)")
    try? fm.removeItem(at: iconsetDir.deletingLastPathComponent())
} else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}
