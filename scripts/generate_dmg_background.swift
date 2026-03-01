#!/usr/bin/env swift
// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import Cocoa

let width: CGFloat = 640
let height: CGFloat = 480

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("Failed to get graphics context\n", stderr)
    exit(1)
}

// Deep purple-blue gradient matching AI icon
let bgGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.12, green: 0.08, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.08, green: 0.06, blue: 0.18, alpha: 1.0),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: width / 2, y: height), end: CGPoint(x: width / 2, y: 0), options: [])

// Subtle accent line at top
let accentGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.50, green: 0.25, blue: 1.0, alpha: 0.9),
        CGColor(red: 0.25, green: 0.15, blue: 0.85, alpha: 0.9),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: height - 3, width: width, height: 3))
ctx.drawLinearGradient(accentGradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: height), options: [])
ctx.restoreGState()

// Arrow pointing right
let arrowCenterX = width / 2
let arrowCenterY = height * 0.42
let arrowLen: CGFloat = 60
let arrowHead: CGFloat = 18

ctx.setStrokeColor(CGColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 0.6))
ctx.setLineWidth(2.5)
ctx.setLineCap(.round)

ctx.beginPath()
ctx.move(to: CGPoint(x: arrowCenterX - arrowLen / 2, y: arrowCenterY))
ctx.addLine(to: CGPoint(x: arrowCenterX + arrowLen / 2, y: arrowCenterY))
ctx.strokePath()

ctx.beginPath()
ctx.move(to: CGPoint(x: arrowCenterX + arrowLen / 2 - arrowHead, y: arrowCenterY + arrowHead * 0.6))
ctx.addLine(to: CGPoint(x: arrowCenterX + arrowLen / 2, y: arrowCenterY))
ctx.addLine(to: CGPoint(x: arrowCenterX + arrowLen / 2 - arrowHead, y: arrowCenterY - arrowHead * 0.6))
ctx.strokePath()

// "Drag to install" text
let textY = height * 0.25
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(red: 0.75, green: 0.65, blue: 0.95, alpha: 0.8),
    .paragraphStyle: paragraphStyle,
]

let text = "Drag DriveSyncAI to Applications to install"
let textRect = CGRect(x: 40, y: textY - 10, width: width - 80, height: 24)
(text as NSString).draw(in: textRect, withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to generate background image\n", stderr)
    exit(1)
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let outputDir = projectDir.appendingPathComponent("build_tmp")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let outputPath = outputDir.appendingPathComponent("dmg_background.png")
try png.write(to: outputPath)
print("Generated \(outputPath.path)")
