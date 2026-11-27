#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Generates a crisp Apple-style frosted-glass AppIcon.icns for Pliw Mix
// with the unified Pliw App ("P.") bottom-right corner badge.
let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "Resources/AppIcon.icns"
let previewPngPath = args.count > 2 ? args[2] : nil

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // 1. Standard macOS squircle (84% of canvas, centered) with soft drop shadow
    let innerSize = s * 0.84
    let inset = (s - innerSize) * 0.5
    let cardRect = CGRect(x: inset, y: inset, width: innerSize, height: innerSize)
    let cardRadius = innerSize * 0.225
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.014),
        blur: s * 0.028,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.22)
    )
    ctx.addPath(cardPath)
    ctx.setFillColor(CGColor(red: 0.88, green: 0.11, blue: 0.28, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Luminous Amber -> Vibrant Orange -> Deep Rose diagonal gradient
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()

    let bgColors = [
        CGColor(red: 0xFB / 255.0, green: 0x92 / 255.0, blue: 0x3C / 255.0, alpha: 1.0), // #FB923C warm amber top-left
        CGColor(red: 0xF9 / 255.0, green: 0x73 / 255.0, blue: 0x16 / 255.0, alpha: 1.0), // #F97316 vibrant orange center
        CGColor(red: 0xE1 / 255.0, green: 0x1D / 255.0, blue: 0x48 / 255.0, alpha: 1.0)  // #E11D48 deep rose bottom-right
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.48, 1.0]) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
            options: []
        )
    }

    // Soft top-left specular radial glow
    let glowColors = [
        CGColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 0.36),
        CGColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 0.0)
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: cardRect.minX + innerSize * 0.24, y: cardRect.maxY - innerSize * 0.18),
            startRadius: 0,
            endCenter: CGPoint(x: cardRect.minX + innerSize * 0.24, y: cardRect.maxY - innerSize * 0.18),
            endRadius: innerSize * 0.68,
            options: []
        )
    }
    ctx.restoreGState()

    // Subtle white inner rim highlight on squircle
    ctx.saveGState()
    let rimPath = CGPath(
        roundedRect: cardRect.insetBy(dx: s * 0.005, dy: s * 0.005),
        cornerWidth: cardRadius * 0.98,
        cornerHeight: cardRadius * 0.98,
        transform: nil
    )
    ctx.addPath(rimPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
    ctx.setLineWidth(max(1.0, s * 0.008))
    ctx.strokePath()
    ctx.restoreGState()

    // 3. Crisp Frosted-Glass 3-Channel Audio Mixer Faders (balanced upper-left away from "P." badge)
    let mixerW = innerSize * 0.56
    let mixerH = innerSize * 0.54
    let mx = cardRect.midX - mixerW * 0.53
    let my = cardRect.midY - mixerH * 0.47
    let mixerRect = CGRect(x: mx, y: my, width: mixerW, height: mixerH)

    let trackW = max(1.4, mixerW * 0.115)
    let knobR = max(2.2, mixerW * 0.125)
    let colXs: [CGFloat] = [
        mixerRect.minX + mixerW * 0.17,
        mixerRect.midX,
        mixerRect.maxX - mixerW * 0.17
    ]
    // Normalized fader levels (0 = bottom, 1 = top)
    let levels: [CGFloat] = [0.72, 0.34, 0.80]
    let trackBottom = mixerRect.minY + knobR * 0.55
    let trackTop = mixerRect.maxY - knobR * 0.55
    let trackHeight = trackTop - trackBottom

    for (x, level) in zip(colXs, levels) {
        let knobY = trackBottom + trackHeight * level

        // Translucent frosted background rail
        let fullTrackRect = CGRect(
            x: x - trackW * 0.5,
            y: trackBottom,
            width: trackW,
            height: trackHeight
        )
        let fullTrackPath = CGPath(
            roundedRect: fullTrackRect,
            cornerWidth: trackW * 0.5,
            cornerHeight: trackW * 0.5,
            transform: nil
        )
        ctx.saveGState()
        ctx.addPath(fullTrackPath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
        ctx.fillPath()
        ctx.restoreGState()

        // Active luminous lower fill bar (from bottom up to knob)
        let activeHeight = max(trackW, knobY - trackBottom)
        let activeRect = CGRect(
            x: x - trackW * 0.5,
            y: trackBottom,
            width: trackW,
            height: activeHeight
        )
        let activePath = CGPath(
            roundedRect: activeRect,
            cornerWidth: trackW * 0.5,
            cornerHeight: trackW * 0.5,
            transform: nil
        )
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.010),
            blur: s * 0.020,
            color: CGColor(red: 0.45, green: 0.05, blue: 0.10, alpha: 0.28)
        )
        ctx.addPath(activePath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.90))
        ctx.fillPath()
        ctx.restoreGState()

        // Crisp pure-white circular fader knob with soft shadow
        let knobRect = CGRect(x: x - knobR, y: knobY - knobR, width: knobR * 2, height: knobR * 2)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.014),
            blur: s * 0.026,
            color: CGColor(red: 0.38, green: 0.04, blue: 0.08, alpha: 0.36)
        )
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
        ctx.fillEllipse(in: knobRect)
        ctx.restoreGState()

        // Subtle inner center dot on knob for tactile studio fader feel (visible at >= 64px)
        if size >= 64 {
            let innerDotR = knobR * 0.32
            let dotRect = CGRect(x: x - innerDotR, y: knobY - innerDotR, width: innerDotR * 2, height: innerDotR * 2)
            ctx.saveGState()
            ctx.setFillColor(CGColor(red: 0xF9 / 255.0, green: 0x73 / 255.0, blue: 0x16 / 255.0, alpha: 0.85))
            ctx.fillEllipse(in: dotRect)
            ctx.restoreGState()
        }
    }

    // 4. Unified Pliw App ("P.") bottom-right corner badge (26% size, 0.05 inset)
    let badgeSize = s * 0.26
    let badgeInset = s * 0.05
    let badgeRect = CGRect(
        x: s - badgeInset - badgeSize,
        y: badgeInset,
        width: badgeSize,
        height: badgeSize
    )
    let badgeCorner = badgeSize * 0.25
    let borderW = max(2.0, badgeSize * 0.065)

    // White cutout ring + soft shadow
    ctx.saveGState()
    let ringRect = badgeRect.insetBy(dx: -borderW * 0.5, dy: -borderW * 0.5)
    let ringPath = CGPath(
        roundedRect: ringRect,
        cornerWidth: badgeCorner + borderW * 0.35,
        cornerHeight: badgeCorner + borderW * 0.35,
        transform: nil
    )
    ctx.setShadow(
        offset: CGSize(width: 0, height: -badgeSize * 0.045),
        blur: badgeSize * 0.12,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
    )
    ctx.addPath(ringPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.fillPath()
    ctx.restoreGState()

    // Dark macOS squircle fill
    ctx.saveGState()
    let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: badgeCorner, cornerHeight: badgeCorner, transform: nil)
    ctx.addPath(badgePath)
    ctx.clip()
    let badgeGradCols = [
        CGColor(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0, alpha: 1.0),
        CGColor(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x16 / 255.0, alpha: 1.0)
    ] as CFArray
    if let bg = CGGradient(colorsSpace: colorSpace, colors: badgeGradCols, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            bg,
            start: CGPoint(x: badgeRect.midX, y: badgeRect.maxY),
            end: CGPoint(x: badgeRect.midX, y: badgeRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Subtle inner rim on badge
    ctx.saveGState()
    let bRim = CGPath(
        roundedRect: badgeRect.insetBy(dx: badgeSize * 0.015, dy: badgeSize * 0.015),
        cornerWidth: badgeCorner * 0.94,
        cornerHeight: badgeCorner * 0.94,
        transform: nil
    )
    ctx.addPath(bRim)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(max(1.0, badgeSize * 0.02))
    ctx.strokePath()
    ctx.restoreGState()

    // Geometric "P." monogram inside badge
    func mapPt(_ svgX: CGFloat, _ svgY: CGFloat) -> CGPoint {
        CGPoint(
            x: badgeRect.minX + (svgX / 64.0) * badgeSize,
            y: badgeRect.minY + (1.0 - svgY / 64.0) * badgeSize
        )
    }
    ctx.saveGState()
    let pPath = CGMutablePath()
    pPath.move(to: mapPt(22.5, 45.0))
    pPath.addLine(to: mapPt(22.5, 19.5))
    pPath.addLine(to: mapPt(34.5, 19.5))
    pPath.addCurve(to: mapPt(44.0, 28.2), control1: mapPt(40.2, 19.5), control2: mapPt(44.0, 23.0))
    pPath.addCurve(to: mapPt(34.5, 36.8), control1: mapPt(44.0, 33.4), control2: mapPt(40.2, 36.8))
    pPath.addLine(to: mapPt(22.5, 36.8))

    ctx.addPath(pPath)
    ctx.setStrokeColor(CGColor(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0, alpha: 1.0))
    ctx.setLineWidth(max(1.2, badgeSize * (5.2 / 64.0)))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    if size >= 32 {
        let dotC = mapPt(43.0, 43.2)
        let dotR = badgeSize * (3.0 / 64.0)
        ctx.setFillColor(CGColor(red: 0xA1 / 255.0, green: 0xA1 / 255.0, blue: 0xA6 / 255.0, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2))
    }
    ctx.restoreGState()

    guard let cgImg = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImg)
    return rep.representation(using: .png, properties: [:])
}

let tmpIconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PliwMix.iconset")
try? FileManager.default.removeItem(at: tmpIconset)
try FileManager.default.createDirectory(at: tmpIconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    if let png = renderIcon(size: px) {
        try png.write(to: tmpIconset.appendingPathComponent(name))
        if px == 512, let previewPngPath = previewPngPath {
            try png.write(to: URL(fileURLWithPath: previewPngPath))
        }
    }
}

let outURL = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmpIconset.path, "-o", outURL.path]
try proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(at: tmpIconset)

if proc.terminationStatus == 0 {
    print("✅ Generated icon at \(outURL.path)")
} else {
    fputs("❌ iconutil failed with status \(proc.terminationStatus)\n", stderr)
    exit(1)
}
