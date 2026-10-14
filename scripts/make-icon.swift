// Draws the app icon (a battery ring around a mouse glyph) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // macOS icon grid: the tile is 80% of the canvas, corner radius ~22.5% of the tile.
    let tile = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.08, alpha: 1)])?.draw(in: shape, angle: -90)

    let center = NSPoint(x: tile.midX, y: tile.midY)
    let radius = tile.width * 0.30
    let lineWidth = tile.width * 0.075
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    NSColor(white: 1, alpha: 0.14).setStroke()
    track.stroke()

    let level = NSBezierPath()
    level.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * 0.72, clockwise: true)
    level.lineWidth = lineWidth
    level.lineCapStyle = .round
    NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).setStroke()
    level.stroke()

    let glyphSize = tile.width * 0.26
    let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let box = glyph.size
        glyph.draw(in: NSRect(x: center.x - box.width / 2, y: center.y - box.height / 2, width: box.width, height: box.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        guard let png = render(pixels: points * scale) else { continue }
        try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
