// Dokey for macOS - menu bar icon, drawn in code.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// A small rounded badge: filled with the letter cut out for Vietnamese ("V"),
/// outlined for English ("E"). Template images follow the menu bar's light/dark look.
enum StatusIcon {
    /// `vietnamese`: typing is on (filled badge); `korean`: the badge shows 한 instead of V.
    static func image(vietnamese: Bool, korean: Bool = false) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let badge = rect.insetBy(dx: 1.5, dy: 1)
            let path = NSBezierPath(roundedRect: badge, xRadius: 3.5, yRadius: 3.5)
            let letter = vietnamese ? (korean ? "한" : "V") : "E"
            let font = NSFont.systemFont(ofSize: letter == "한" ? 10.5 : 11.5, weight: .heavy)
            NSColor.black.set()
            if vietnamese {
                path.fill()
            } else {
                path.lineWidth = 1.4
                path.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let textSize = text.size()
            let origin = NSPoint(x: badge.midX - textSize.width / 2,
                                 y: badge.midY - textSize.height / 2 + 0.5)
            if vietnamese, let context = NSGraphicsContext.current {
                context.compositingOperation = .destinationOut
                text.draw(at: origin)
                context.compositingOperation = .sourceOver
            } else {
                text.draw(at: origin)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = vietnamese
            ? (korean ? tr("Dokey: tiếng Hàn", "Dokey: 한국어") : tr("Dokey: tiếng Việt", "Dokey: 베트남어"))
            : tr("Dokey: tiếng Anh", "Dokey: 영어")
        return image
    }
}
