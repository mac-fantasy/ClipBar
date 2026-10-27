import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("用法：swift scripts/generate-icon.swift <输出 iconset 目录>")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func renderIcon(pixels: Int) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw CocoaError(.coderInvalidValue)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(
        roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205)
    NSGradient(
        starting: NSColor(srgbRed: 0.19, green: 0.60, blue: 0.98, alpha: 1),
        ending: NSColor(srgbRed: 0.13, green: 0.32, blue: 0.86, alpha: 1)
    )?.draw(in: background, angle: -90)

    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: 236, y: 217, width: 470, height: 567), xRadius: 55, yRadius: 55).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 318, y: 243, width: 470, height: 567), xRadius: 55, yRadius: 55).fill()
    NSColor(srgbRed: 0.16, green: 0.43, blue: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 443, y: 752, width: 220, height: 100), xRadius: 35, yRadius: 35).fill()
    NSColor(srgbRed: 0.83, green: 0.90, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 465, y: 772, width: 176, height: 58), xRadius: 20, yRadius: 20).fill()

    NSColor(srgbRed: 0.24, green: 0.49, blue: 0.91, alpha: 1).setFill()
    for (index, width) in [286, 286, 210].enumerated() {
        NSBezierPath(
            roundedRect: NSRect(x: 410, y: 606 - index * 103, width: width, height: 34), xRadius: 17, yRadius: 17
        ).fill()
    }
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.coderInvalidValue)
    }
    return data
}

for size in [16, 32, 128, 256, 512] {
    try renderIcon(pixels: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try renderIcon(pixels: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
