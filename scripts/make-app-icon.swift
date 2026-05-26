#!/usr/bin/env swift
//
// make-app-icon.swift — generate macOS app icon PNGs at all required sizes.
//
// Renders a blue-gradient rounded-square background with a white calendar
// SF Symbol centered on top, then exports the 7 unique pixel sizes the
// AppIcon.appiconset needs.
//
// Usage: ./scripts/make-app-icon.swift CalWidget/Assets.xcassets/AppIcon.appiconset

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-app-icon.swift <output-appiconset-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outputDir = CommandLine.arguments[1]

func makeIcon(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    bitmap.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)

    // macOS Big Sur+ icon corner radius is ~22.37% of the icon size (the
    // mask Apple ships in Icon Composer). Match it so the icon looks native.
    let cornerRadius = size * 0.2237
    let bgPath = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)

    // Background: vertical blue gradient (lighter at top, darker at bottom).
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.58, blue: 1.00, alpha: 1.0),
        NSColor(srgbRed: 0.00, green: 0.38, blue: 0.86, alpha: 1.0)
    ])!
    gradient.draw(in: bgPath, angle: -90)

    // Calendar SF Symbol, white, ~58% of icon size.
    let symbolSize = size * 0.58
    let pointSize = symbolSize * 0.78
    let palette = NSImage.SymbolConfiguration(paletteColors: [.white])
    let weighted = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    let config = palette.applying(weighted)

    if let symbol = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let rendered = symbol.size
        let target = NSRect(
            x: (size - rendered.width) / 2,
            y: (size - rendered.height) / 2,
            width: rendered.width,
            height: rendered.height
        )
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    } else {
        FileHandle.standardError.write("warning: failed to load SF Symbol 'calendar'\n".data(using: .utf8)!)
    }

    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])!
}

// macOS app icon: 7 unique sizes (each is 1x and the previous tier's 2x).
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for px in sizes {
    let data = makeIcon(pixelSize: px)
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent("icon_\(px).png")
    try data.write(to: url)
    print("wrote \(url.lastPathComponent)")
}

// Rewrite Contents.json to reference the generated files.
let contentsJSON = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contentsJSON.write(toFile: URL(fileURLWithPath: outputDir).appendingPathComponent("Contents.json").path, atomically: true, encoding: .utf8)
print("wrote Contents.json")
