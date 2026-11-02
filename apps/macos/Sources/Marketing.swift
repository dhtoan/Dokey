// Dokey for macOS - `Dokey --render-marketing <dir>`: draws the README banner
// and window screenshots from the real control panel, with sample data.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

private final class SampleData: ControlPanelDelegate {
    func panelToggleMode() {}
    func panelSettingsChanged() {}
    func panelShowPermission() {}
    var panelTapRunning: Bool { true }
    func panelClearExcluded() {}
    func panelCheckUpdates() {}
    func panelSetLanguage(_ code: String) {}
    var panelEditCount: Int { 1284 }
    /// A neutral example: no third-party icons in promotional images.
    var panelFrontApp: (name: String, kind: AppKind, icon: NSImage?)? {
        ("Chrome", .browser, nil)
    }
}

enum Marketing {
    /// Pixels per point: sharp on Retina screens, still light enough for a README.
    private static let scale: CGFloat = 1.5

    static func render(to dir: String) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let sample = SampleData()
        let panel = ControlPanelController()
        panel.delegate = sample
        panel.assumeReady = true
        guard let view = panel.window?.contentView else { return 1 }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var shots: [NSImage] = []
        for (page, name) in ["dashboard", "typing", "quick", "apps", "about"].enumerated() {
            panel.refresh()
            panel.showPage(page)
            view.layoutSubtreeIfNeeded()
            let content = snapshot(view)
            let shot = windowShot(content, title: "Dokey")
            shots.append(shot)
            guard write(shot, to: "\(dir)/\(name).png") else { return 1 }
        }
        guard write(banner(screenshot: shots[0]), to: "\(dir)/banner.png"),
              write(banner(screenshot: shots[0], height: 640, rounded: false, pixelScale: 1), to: "\(dir)/social.png")
        else { return 1 }
        return 0
    }

    /// The view drawn at `scale`.
    private static func snapshot(_ view: NSView) -> NSImage {
        let size = view.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Rounded window with traffic lights and a soft shadow on a transparent canvas.
    private static func windowShot(_ content: NSImage, title: String) -> NSImage {
        let margin: CGFloat = 56
        let size = NSSize(width: content.size.width + margin * 2, height: content.size.height + margin * 2)
        return draw(size: size) {
            let frame = NSRect(x: margin, y: margin, width: content.size.width, height: content.size.height)
            let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
            shadow.shadowBlurRadius = 36
            shadow.shadowOffset = NSSize(width: 0, height: -14)
            shadow.set()
            NSColor.black.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            content.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 1, alpha: 0.16).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            let colors = [NSColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1),
                          NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1),
                          NSColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1)]
            for (i, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: frame.minX + 14 + CGFloat(i) * 20, y: frame.maxY - 22, width: 12, height: 12)).fill()
            }
        }
    }

    /// The README banner (rounded) or, with `height` 640 and no rounding, the
    /// 1280x640 social preview used by GitHub, Facebook, Zalo and X.
    private static func banner(screenshot: NSImage, height: CGFloat = 520, rounded: Bool = true,
                               pixelScale: CGFloat? = nil) -> NSImage {
        let size = NSSize(width: 1280, height: height)
        return draw(size: size, pixelScale: pixelScale) {
            let bounds = NSRect(origin: .zero, size: size)
            if rounded { NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28).addClip() }
            NSGradient(colors: [Palette.backgroundTop, Palette.backgroundMiddle, Palette.backgroundBottom])?.draw(in: bounds, angle: -25)
            for (color, point, radius) in [(Palette.glowPink, NSPoint(x: 1050, y: 80), CGFloat(520)),
                                           (Palette.glowBlue, NSPoint(x: 180, y: 520), CGFloat(460))] {
                NSGradient(starting: color.withAlphaComponent(0.40), ending: color.withAlphaComponent(0))?
                    .draw(fromCenter: point, radius: 0, toCenter: point, radius: radius, options: [])
            }

            // Centre the 520-point-high composition vertically.
            let shift = NSAffineTransform()
            shift.translateX(by: 0, yBy: (height - 520) / 2)
            shift.concat()

            // Product screenshot on the right, cropped by the banner edge.
            let shotHeight: CGFloat = 470
            let shotWidth = screenshot.size.width * shotHeight / screenshot.size.height
            screenshot.draw(in: NSRect(x: size.width - shotWidth * 0.80, y: -60, width: shotWidth, height: shotHeight))

            let badge = GlossyBadge(shape: .squircle, top: NSColor(red: 0.98, green: 0.45, blue: 0.86, alpha: 1),
                                    bottom: NSColor(red: 0.45, green: 0.20, blue: 0.95, alpha: 1), symbol: .text("đ"))
            badge.frame = NSRect(x: 0, y: 0, width: 150, height: 150)
            if let rep = badge.bitmapImageRepForCachingDisplay(in: badge.bounds) {
                badge.cacheDisplay(in: badge.bounds, to: rep)
                let image = NSImage(size: badge.bounds.size)
                image.addRepresentation(rep)
                image.draw(in: NSRect(x: 56, y: 300, width: 150, height: 150))
            }

            func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, at p: NSPoint) {
                NSAttributedString(string: s, attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: NSColor(white: 1, alpha: alpha),
                ]).draw(at: p)
            }
            text("Dokey", size: 76, weight: .heavy, alpha: 1, at: NSPoint(x: 72, y: 196))
            text(tr("Bộ gõ tiếng Việt thế hệ mới", "글자가 사라지지 않는 한국어 입력기"), size: 30, weight: .semibold, alpha: 0.95, at: NSPoint(x: 76, y: 150))
            text(tr("Gõ đúng ngay lần đầu. Không nhảy chữ, kể cả trong Chrome và Claude.",
                    "두벌식 · Chrome, Claude, VS Code에서도 정확하게. 베트남어도 지원합니다."), size: 17, weight: .regular,
                 alpha: 0.72, at: NSPoint(x: 77, y: 116))

            var x: CGFloat = 76
            for chip in L10n.korean ? ["macOS", "두벌식", "한국어 · Tiếng Việt", "개인 무료"]
                                     : ["macOS", "Windows", "Telex · VNI", "Mã nguồn mới 100%"] {
                let attributed = NSAttributedString(string: chip, attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white,
                ])
                let w = attributed.size().width + 28
                let pill = NSBezierPath(roundedRect: NSRect(x: x, y: 58, width: w, height: 32), xRadius: 16, yRadius: 16)
                NSColor(white: 1, alpha: 0.14).setFill()
                pill.fill()
                NSColor(white: 1, alpha: 0.22).setStroke()
                pill.stroke()
                attributed.draw(at: NSPoint(x: x + 14, y: 58 + (32 - attributed.size().height) / 2))
                x += w + 10
            }
        }
    }

    /// Draws into a bitmap of `size` points at `scale`.
    private static func draw(size: NSSize, pixelScale: CGFloat? = nil, _ body: () -> Void) -> NSImage {
        let scale = pixelScale ?? Self.scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ image: NSImage, to path: String) -> Bool {
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
