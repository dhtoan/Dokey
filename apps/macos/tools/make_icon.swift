// Draws the Dokey app icon into an .iconset folder (build.sh turns it into AppIcon.icns).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// Usage: make_icon <output.iconset>
import Cocoa

func drawIcon(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded tile with a blue-to-indigo gradient, inset like other macOS icons.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let radius = tile.width * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.025
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    let gradient = NSGradient(starting: NSColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 1),
                              ending: NSColor(red: 0.37, green: 0.36, blue: 0.90, alpha: 1))!
    gradient.draw(in: path, angle: -60)

    // A white "đ" with a small tone mark: Vietnamese at a glance.
    let font = NSFont.systemFont(ofSize: s * 0.52, weight: .bold)
    let text = NSAttributedString(string: "đ", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = text.size()
    text.draw(at: NSPoint(x: tile.midX - size.width / 2 - s * 0.03, y: tile.midY - size.height / 2 + s * 0.02))

    let accent = NSBezierPath()
    accent.move(to: NSPoint(x: s * 0.63, y: s * 0.66))
    accent.line(to: NSPoint(x: s * 0.70, y: s * 0.75))
    accent.lineWidth = s * 0.045
    accent.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    accent.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: make_icon <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let dir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try drawIcon(pixels: points * scale).write(to: dir.appendingPathComponent(name))
    }
}
