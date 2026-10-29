// Dokey for macOS - custom controls for the control panel (drawn in code,
// macOS 10.13 compatible: no NSSwitch, no SF Symbols).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

enum Palette {
    static let backgroundTop = NSColor(red: 0.13, green: 0.10, blue: 0.33, alpha: 1)
    static let backgroundMiddle = NSColor(red: 0.33, green: 0.20, blue: 0.70, alpha: 1)
    static let backgroundBottom = NSColor(red: 0.66, green: 0.27, blue: 0.70, alpha: 1)
    static let accentStart = NSColor(red: 0.20, green: 0.90, blue: 0.75, alpha: 1)
    static let accentEnd = NSColor(red: 0.10, green: 0.62, blue: 1.00, alpha: 1)
    static let off = NSColor(white: 1, alpha: 0.22)
    static let card = NSColor(white: 1, alpha: 0.08)
    static let cardBorder = NSColor(white: 1, alpha: 0.12)
    static let text = NSColor.white
    static let secondaryText = NSColor(white: 1, alpha: 0.65)
    static let warning = NSColor(red: 1.0, green: 0.75, blue: 0.35, alpha: 1)
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

/// A view filled with a diagonal gradient.
final class GradientView: NSView {
    var colors: [NSColor] = [] { didSet { needsDisplay = true } }
    var angle: CGFloat = -60

    override func draw(_ dirtyRect: NSRect) {
        guard colors.count >= 2, let gradient = NSGradient(colors: colors) else { return }
        gradient.draw(in: bounds, angle: angle)
    }
}

/// A frosted rounded panel used to group settings.
final class CardView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.card.cgColor
        layer?.borderColor = Palette.cardBorder.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 14
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// An on/off switch in the style of iOS / CleanMyMac.
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

/// The big round button on the dashboard: Vietnamese on (glowing) or off.
final class PowerButton: NSControl {
    var isOn = true { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 190) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height) - 24
        let circle = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        if isOn {
            let glow = NSShadow()
            glow.shadowColor = Palette.accentStart.withAlphaComponent(0.8)
            glow.shadowBlurRadius = 22
            glow.set()
        }
        let ring = NSBezierPath(ovalIn: circle)
        if isOn {
            NSGradient(starting: Palette.accentStart, ending: Palette.accentEnd)?.draw(in: ring, angle: -45)
        } else {
            NSColor(white: 1, alpha: 0.18).setFill()
            ring.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let inner = NSBezierPath(ovalIn: circle.insetBy(dx: 9, dy: 9))
        NSGradient(starting: NSColor(red: 0.20, green: 0.13, blue: 0.45, alpha: 1),
                   ending: NSColor(red: 0.30, green: 0.17, blue: 0.58, alpha: 1))?.draw(in: inner, angle: -90)

        let letter = isOn ? "V" : "E"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: side * 0.42, weight: .heavy),
            .foregroundColor: isOn ? NSColor.white : NSColor(white: 1, alpha: 0.55),
        ]
        let text = NSAttributedString(string: letter, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

/// One entry in the sidebar.
final class SidebarButton: NSControl {
    var isSelected = false { didSet { needsDisplay = true } }
    private let title: String
    private let glyph: String

    init(title: String, glyph: String) {
        self.title = title
        self.glyph = glyph
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor(white: 1, alpha: 0.16).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        let glyphAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: isSelected ? Palette.accentStart : Palette.secondaryText,
        ]
        let g = NSAttributedString(string: glyph, attributes: glyphAttributes)
        g.draw(at: NSPoint(x: 12 + (18 - g.size().width) / 2, y: (bounds.height - g.size().height) / 2))
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium),
            .foregroundColor: isSelected ? Palette.text : Palette.secondaryText,
        ]
        let t = NSAttributedString(string: title, attributes: titleAttributes)
        t.draw(at: NSPoint(x: 38, y: (bounds.height - t.size().height) / 2))
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

    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(options.count) * 78, height: 28) }

    private func segment(_ i: Int) -> NSRect {
        let w = bounds.width / CGFloat(options.count)
        return NSRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.12).setFill()
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
