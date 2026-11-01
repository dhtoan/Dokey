// Dokey for macOS - controls for the control panel, all drawn in code
// (macOS 10.13 compatible: no NSSwitch, no SF Symbols, no image assets).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

enum Palette {
    static let backgroundTop = NSColor(red: 0.16, green: 0.06, blue: 0.38, alpha: 1)
    static let backgroundMiddle = NSColor(red: 0.31, green: 0.11, blue: 0.62, alpha: 1)
    static let backgroundBottom = NSColor(red: 0.45, green: 0.15, blue: 0.70, alpha: 1)
    static let glowPink = NSColor(red: 0.93, green: 0.30, blue: 0.85, alpha: 1)
    static let glowBlue = NSColor(red: 0.30, green: 0.45, blue: 1.00, alpha: 1)
    static let accentStart = NSColor(red: 0.98, green: 0.36, blue: 0.85, alpha: 1)
    static let accentEnd = NSColor(red: 0.60, green: 0.22, blue: 0.95, alpha: 1)
    static let success = NSColor(red: 0.38, green: 0.90, blue: 0.55, alpha: 1)
    static let warning = NSColor(red: 1.00, green: 0.74, blue: 0.35, alpha: 1)
    static let off = NSColor(white: 1, alpha: 0.20)
    static let card = NSColor(white: 1, alpha: 0.07)
    static let cardBorder = NSColor(white: 1, alpha: 0.11)
    static let text = NSColor.white
    static let secondaryText = NSColor(white: 1, alpha: 0.62)
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
           color: NSColor = Palette.text, wrapping: Bool = false) -> NSTextField {
    let field = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.backgroundColor = .clear
    field.isSelectable = false
    return field
}

/// The window background: a violet gradient with two soft glows.
final class GradientView: NSView {
    var colors: [NSColor] = [] { didSet { needsDisplay = true } }
    var angle: CGFloat = -60
    var glows = true

    override func draw(_ dirtyRect: NSRect) {
        guard colors.count >= 2, let gradient = NSGradient(colors: colors) else { return }
        gradient.draw(in: bounds, angle: angle)
        guard glows else { return }
        func glow(_ color: NSColor, at point: NSPoint, radius: CGFloat) {
            NSGradient(starting: color.withAlphaComponent(0.35), ending: color.withAlphaComponent(0))?
                .draw(fromCenter: point, radius: 0, toCenter: point, radius: radius, options: [])
        }
        glow(Palette.glowPink, at: NSPoint(x: bounds.maxX * 0.85, y: bounds.maxY * 0.15), radius: bounds.width * 0.45)
        glow(Palette.glowBlue, at: NSPoint(x: bounds.maxX * 0.25, y: bounds.maxY * 0.95), radius: bounds.width * 0.40)
    }
}

/// A frosted glass panel. Children that stick out (the glossy badge) are clipped.
class GlassCard: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.card.cgColor
        layer?.borderColor = Palette.cardBorder.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        // A faint sheen along the top edge, like light on glass.
        NSGradient(starting: NSColor(white: 1, alpha: 0.07), ending: NSColor(white: 1, alpha: 0))?
            .draw(in: NSRect(x: 0, y: bounds.height * 0.55, width: bounds.width, height: bounds.height * 0.45), angle: -90)
    }
}

/// A glossy, glowing 3D-looking emblem drawn with gradients (the big icons on cards).
final class GlossyBadge: NSView {
    enum Shape { case circle, hexagon, shield, squircle }
    enum Symbol { case text(String), image(NSImage), check, bolt, keycap, grid }

    var shape: Shape
    var top: NSColor { didSet { needsDisplay = true } }
    var bottom: NSColor { didSet { needsDisplay = true } }
    var symbol: Symbol { didSet { needsDisplay = true } }

    init(shape: Shape, top: NSColor, bottom: NSColor, symbol: Symbol) {
        self.shape = shape
        self.top = top
        self.bottom = bottom
        self.symbol = symbol
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func bodyPath(in r: NSRect) -> NSBezierPath {
        switch shape {
        case .circle:
            return NSBezierPath(ovalIn: r)
        case .squircle:
            return NSBezierPath(roundedRect: r, xRadius: r.width * 0.28, yRadius: r.width * 0.28)
        case .hexagon:
            return roundedPolygon(center: NSPoint(x: r.midX, y: r.midY), radius: r.width / 2, sides: 6,
                                  corner: r.width * 0.12, rotation: .pi / 6)
        case .shield:
            let p = NSBezierPath()
            let w = r.width, h = r.height
            p.move(to: NSPoint(x: r.midX, y: r.minY))
            p.curve(to: NSPoint(x: r.maxX, y: r.minY + h * 0.62),
                    controlPoint1: NSPoint(x: r.midX + w * 0.30, y: r.minY + h * 0.10),
                    controlPoint2: NSPoint(x: r.maxX, y: r.minY + h * 0.35))
            p.line(to: NSPoint(x: r.maxX, y: r.maxY - h * 0.12))
            p.curve(to: NSPoint(x: r.midX, y: r.maxY),
                    controlPoint1: NSPoint(x: r.maxX - w * 0.15, y: r.maxY - h * 0.04),
                    controlPoint2: NSPoint(x: r.midX + w * 0.20, y: r.maxY))
            p.curve(to: NSPoint(x: r.minX, y: r.maxY - h * 0.12),
                    controlPoint1: NSPoint(x: r.midX - w * 0.20, y: r.maxY),
                    controlPoint2: NSPoint(x: r.minX + w * 0.15, y: r.maxY - h * 0.04))
            p.line(to: NSPoint(x: r.minX, y: r.minY + h * 0.62))
            p.curve(to: NSPoint(x: r.midX, y: r.minY),
                    controlPoint1: NSPoint(x: r.minX, y: r.minY + h * 0.35),
                    controlPoint2: NSPoint(x: r.midX - w * 0.30, y: r.minY + h * 0.10))
            p.close()
            return p
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let r = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
            .insetBy(dx: side * 0.12, dy: side * 0.12)
        let body = bodyPath(in: r)

        // Coloured glow behind the emblem.
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = bottom.withAlphaComponent(0.45)
        glow.shadowBlurRadius = side * 0.08
        glow.shadowOffset = NSSize(width: 0, height: -side * 0.03)
        glow.set()
        bottom.setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Body: vertical gradient, then a darker edge for depth.
        NSGradient(starting: top, ending: bottom)?.draw(in: body, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSGradient(colors: [NSColor(white: 0, alpha: 0), NSColor(white: 0, alpha: 0.28)],
                   atLocations: [0.55, 1], colorSpace: .deviceRGB)?
            .draw(fromCenter: NSPoint(x: r.midX, y: r.midY + r.height * 0.1), radius: 0,
                  toCenter: NSPoint(x: r.midX, y: r.midY), radius: r.width * 0.75, options: [])
        // Specular highlight across the top.
        let shine = NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.12, y: r.midY + r.height * 0.08,
                                                width: r.width * 0.76, height: r.height * 0.46))
        NSGradient(starting: NSColor(white: 1, alpha: 0.26), ending: NSColor(white: 1, alpha: 0.0))?
            .draw(in: shine, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Glass rim.
        body.lineWidth = max(1, side * 0.012)
        NSColor(white: 1, alpha: 0.28).setStroke()
        body.stroke()

        drawSymbol(in: r.insetBy(dx: r.width * 0.24, dy: r.height * 0.24))
    }

    private func drawSymbol(in r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
        shadow.shadowBlurRadius = r.width * 0.06
        shadow.shadowOffset = NSSize(width: 0, height: -r.width * 0.03)
        shadow.set()
        let ink = NSColor(white: 1, alpha: 0.92)
        ink.setFill()
        ink.setStroke()
        switch symbol {
        case .text(let s):
            let font = NSFont.systemFont(ofSize: r.height * (s.count > 1 ? 0.62 : 0.95), weight: .heavy)
            let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink])
            let size = text.size()
            text.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2))
        case .image(let image):
            image.draw(in: r.insetBy(dx: -r.width * 0.08, dy: -r.height * 0.08))
        case .check:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + r.width * 0.12, y: r.midY))
            p.line(to: NSPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.20))
            p.line(to: NSPoint(x: r.maxX - r.width * 0.08, y: r.maxY - r.height * 0.15))
            p.lineWidth = r.width * 0.15
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        case .bolt:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + r.width * 0.60, y: r.maxY))
            p.line(to: NSPoint(x: r.minX + r.width * 0.18, y: r.midY - r.height * 0.02))
            p.line(to: NSPoint(x: r.midX, y: r.midY - r.height * 0.02))
            p.line(to: NSPoint(x: r.minX + r.width * 0.40, y: r.minY))
            p.line(to: NSPoint(x: r.maxX - r.width * 0.18, y: r.midY + r.height * 0.10))
            p.line(to: NSPoint(x: r.midX + r.width * 0.02, y: r.midY + r.height * 0.10))
            p.close()
            p.fill()
        case .keycap:
            let key = NSBezierPath(roundedRect: r.insetBy(dx: r.width * 0.04, dy: r.height * 0.12),
                                   xRadius: r.width * 0.16, yRadius: r.width * 0.16)
            key.lineWidth = r.width * 0.09
            key.stroke()
            let font = NSFont.systemFont(ofSize: r.height * 0.40, weight: .heavy)
            let text = NSAttributedString(string: "Aa", attributes: [.font: font, .foregroundColor: ink])
            let size = text.size()
            text.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2))
        case .grid:
            let cell = r.width / 2
            for i in 0..<2 {
                for j in 0..<2 {
                    let box = NSRect(x: r.minX + CGFloat(i) * cell, y: r.minY + CGFloat(j) * cell,
                                     width: cell, height: cell).insetBy(dx: cell * 0.12, dy: cell * 0.12)
                    NSBezierPath(roundedRect: box, xRadius: cell * 0.22, yRadius: cell * 0.22).fill()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Gently bob up and down, like the emblems in modern Mac utilities.
    func startFloating(distance: CGFloat = 5, duration: CFTimeInterval = 3) {
        guard let layer = layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = -distance
        animation.toValue = distance
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "float")
    }
}

func roundedPolygon(center: NSPoint, radius: CGFloat, sides: Int, corner: CGFloat, rotation: CGFloat) -> NSBezierPath {
    var points: [NSPoint] = []
    for i in 0..<sides {
        let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(sides)
        points.append(NSPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
    }
    let path = NSBezierPath()
    for i in 0..<sides {
        let prev = points[(i + sides - 1) % sides], cur = points[i], next = points[(i + 1) % sides]
        func toward(_ p: NSPoint, _ q: NSPoint, _ d: CGFloat) -> NSPoint {
            let len = hypot(q.x - p.x, q.y - p.y)
            return NSPoint(x: p.x + (q.x - p.x) * d / len, y: p.y + (q.y - p.y) * d / len)
        }
        let a = toward(cur, prev, corner), b = toward(cur, next, corner)
        if i == 0 { path.move(to: a) } else { path.line(to: a) }
        path.curve(to: b, controlPoint1: cur, controlPoint2: cur)
    }
    path.close()
    return path
}

/// An on/off switch with the accent gradient.
final class ToggleSwitch: NSControl {
    var isOn = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 42, height: 24) }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - 24) / 2, width: 42, height: 24)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 12, yRadius: 12)
        if isOn {
            NSGradient(starting: Palette.accentStart, ending: Palette.accentEnd)?.draw(in: trackPath, angle: 0)
        } else {
            Palette.off.setFill()
            trackPath.fill()
        }
        let knob = NSRect(x: isOn ? track.maxX - 22 : track.minX + 2, y: track.minY + 2, width: 20, height: 20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        sendAction(action, to: target)
    }
}

/// The glowing round button at the bottom of the window (CleanMyMac's "Scan" button).
final class OrbButton: NSControl {
    var title = "" { didSet { needsDisplay = true } }
    var isLit = true { didSet { needsDisplay = true; updatePulse() } }
    private let halo = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        halo.fillColor = NSColor.clear.cgColor
        halo.strokeColor = Palette.accentStart.withAlphaComponent(0.8).cgColor
        halo.lineWidth = 2
        layer?.addSublayer(halo)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 96) }

    override func layout() {
        super.layout()
        let circle = orbRect.insetBy(dx: -1, dy: -1)
        halo.frame = bounds
        halo.path = CGPath(ellipseIn: circle, transform: nil)
        updatePulse()
    }

    private var orbRect: NSRect {
        let side = min(bounds.width, bounds.height) - 24
        return NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    }

    private func updatePulse() {
        halo.removeAllAnimations()
        halo.isHidden = !isLit
        guard isLit else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.22
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        halo.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        halo.position = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.bounds = bounds
        halo.add(group, forKey: "pulse")
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = orbRect
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = (isLit ? Palette.accentStart : NSColor(white: 1, alpha: 0.3)).withAlphaComponent(0.9)
        glow.shadowBlurRadius = 18
        glow.set()
        let body = NSBezierPath(ovalIn: circle)
        (isLit ? Palette.accentEnd : NSColor(white: 0.35, alpha: 1)).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
        if isLit {
            NSGradient(starting: Palette.accentStart, ending: Palette.accentEnd)?.draw(in: body, angle: -60)
        } else {
            NSGradient(starting: NSColor(white: 0.55, alpha: 1), ending: NSColor(white: 0.30, alpha: 1))?.draw(in: body, angle: -60)
        }
        let shine = NSBezierPath(ovalIn: NSRect(x: circle.minX + circle.width * 0.18, y: circle.midY + circle.height * 0.05,
                                                width: circle.width * 0.64, height: circle.height * 0.40))
        NSGradient(starting: NSColor(white: 1, alpha: 0.30), ending: NSColor(white: 1, alpha: 0))?.draw(in: shine, angle: -90)
        body.lineWidth = 2
        NSColor(white: 1, alpha: 0.55).setStroke()
        body.stroke()
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

/// An icon-only sidebar entry (the narrow CleanMyMac-style sidebar).
final class SidebarButton: NSControl {
    enum Icon { case dashboard, keyboard, bolt, apps, info }
    var isSelected = false { didSet { needsDisplay = true } }
    private let icon: Icon

    init(icon: Icon, tooltip: String) {
        self.icon = icon
        super.init(frame: .zero)
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 40) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 2, dy: 2)
        if isSelected {
            NSColor(white: 1, alpha: 0.14).setFill()
            NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        }
        let r = NSRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
        let path = NSBezierPath()
        switch icon {
        case .dashboard:
            for (x, y, w, h) in [(0.0, 0.45, 0.42, 0.55), (0.55, 0.62, 0.45, 0.38), (0.0, 0.0, 0.42, 0.35), (0.55, 0.0, 0.45, 0.52)] {
                path.append(NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * CGFloat(x), y: r.minY + r.height * CGFloat(y),
                                                             width: r.width * CGFloat(w), height: r.height * CGFloat(h)),
                                         xRadius: 2.5, yRadius: 2.5))
            }
        case .keyboard:
            path.append(NSBezierPath(roundedRect: r.insetBy(dx: 0, dy: 3), xRadius: 3, yRadius: 3))
            path.appendRect(NSRect(x: r.minX + 4, y: r.minY + 6, width: r.width - 8, height: 1.6))
            for i in 0..<4 { path.appendRect(NSRect(x: r.minX + 3.5 + CGFloat(i) * 3.4, y: r.midY + 1, width: 1.8, height: 1.8)) }
        case .apps:
            for i in 0..<3 { for j in 0..<3 {
                path.appendOval(in: NSRect(x: r.minX + CGFloat(i) * 6.6, y: r.minY + CGFloat(j) * 6.6, width: 4.8, height: 4.8))
            } }
        case .bolt:
            path.move(to: NSPoint(x: r.minX + r.width * 0.62, y: r.maxY))
            path.line(to: NSPoint(x: r.minX + r.width * 0.16, y: r.midY - 1))
            path.line(to: NSPoint(x: r.midX, y: r.midY - 1))
            path.line(to: NSPoint(x: r.minX + r.width * 0.38, y: r.minY))
            path.line(to: NSPoint(x: r.maxX - r.width * 0.16, y: r.midY + 2))
            path.line(to: NSPoint(x: r.midX + 1, y: r.midY + 2))
            path.close()
        case .info:
            path.appendOval(in: r)
        }
        let color: NSColor = isSelected ? Palette.accentStart : NSColor(white: 1, alpha: 0.6)
        if icon == .info {
            path.lineWidth = 1.6
            color.setStroke()
            path.stroke()
            let i = NSAttributedString(string: "i", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: color])
            i.draw(at: NSPoint(x: r.midX - i.size().width / 2, y: r.midY - i.size().height / 2))
        } else if icon == .keyboard {
            color.setStroke()
            color.setFill()
            let outline = NSBezierPath(roundedRect: r.insetBy(dx: 0, dy: 3), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.6
            outline.stroke()
            NSBezierPath(rect: NSRect(x: r.minX + 4, y: r.minY + 5.5, width: r.width - 8, height: 1.6)).fill()
            for i in 0..<4 { NSBezierPath(rect: NSRect(x: r.minX + 3.2 + CGFloat(i) * 3.4, y: r.midY + 0.5, width: 1.8, height: 1.8)).fill() }
        } else {
            color.setFill()
            path.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

/// A pill-shaped choice between a few options (Telex | VNI).
final class PillPicker: NSControl {
    private let options: [String]
    var selectedIndex = 0 { didSet { needsDisplay = true } }

    init(options: [String]) {
        self.options = options
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(options.count) * 82, height: 28) }

    private func segment(_ i: Int) -> NSRect {
        let w = bounds.width / CGFloat(options.count)
        return NSRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.10).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let selected = segment(selectedIndex).insetBy(dx: 2, dy: 2)
        let pill = NSBezierPath(roundedRect: selected, xRadius: selected.height / 2, yRadius: selected.height / 2)
        NSGradient(starting: Palette.accentStart, ending: Palette.accentEnd)?.draw(in: pill, angle: 0)
        for (i, option) in options.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: i == selectedIndex ? NSColor.white : Palette.secondaryText,
            ]
            let t = NSAttributedString(string: option, attributes: attributes)
            let r = segment(i)
            t.draw(at: NSPoint(x: r.midX - t.size().width / 2, y: r.midY - t.size().height / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in options.indices where segment(i).contains(p) {
            if i != selectedIndex {
                selectedIndex = i
                sendAction(action, to: target)
            }
        }
    }
}

/// A rounded button with the accent gradient.
final class AccentButton: NSControl {
    var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var attributed: NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
    }

    override var intrinsicContentSize: NSSize { NSSize(width: attributed.size().width + 32, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSGradient(starting: Palette.accentStart, ending: Palette.accentEnd)?.draw(in: path, angle: 0)
        let t = attributed
        t.draw(at: NSPoint(x: (bounds.width - t.size().width) / 2, y: (bounds.height - t.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}
