// Dokey for macOS - editor for text shortcuts (gõ tắt).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// A sheet with one shortcut per line: "vn = Việt Nam".
final class MacroEditorController: NSWindowController {
    var onSave: ((String) -> Void)?
    private let textView = NSTextView()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = tr("Gõ tắt", "단축어")
        if #available(macOS 10.14, *) {
            window.appearance = NSAppearance(named: .darkAqua)
        } else {
            window.appearance = NSAppearance(named: .vibrantDark)
        }
        self.init(window: window)
        build()
    }

    private func build() {
        guard let window = window else { return }
        let background = GradientView()
        background.colors = [Palette.backgroundTop, Palette.backgroundMiddle]
        background.glows = false
        window.contentView = background

        let title = label(tr("Gõ tắt", "단축어"), size: 20, weight: .bold)
        let help = label(tr("Mỗi dòng một từ tắt: từ tắt = nội dung. Dòng bắt đầu bằng # là ghi chú.", "한 줄에 하나씩: 단축어 = 내용. #으로 시작하는 줄은 메모입니다."),
                         size: 12, color: Palette.secondaryText, wrapping: true)

        textView.isRichText = false
        textView.font = NSFont(name: "Menlo", size: 13) ?? .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.backgroundColor = NSColor(white: 0, alpha: 0.22)
        textView.insertionPointColor = .white
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10

        let save = AccentButton(title: tr("Lưu", "저장"))
        save.target = self
        save.action = #selector(saveClicked)
        let cancel = NSButton(title: tr("Huỷ", "취소"), target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .rounded

        for v in [title, help, scroll, save, cancel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(v)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            help.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            help.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            help.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: help.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -14),
            save.trailingAnchor.constraint(equalTo: help.trailingAnchor),
            save.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
        ])
    }

    func present(text: String, over parent: NSWindow?) {
        textView.string = text
        if let parent = parent, let window = window {
            parent.beginSheet(window, completionHandler: nil)
        } else {
            window?.center()
            showWindow(nil)
        }
    }

    private func dismiss() {
        guard let window = window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    @objc private func saveClicked() {
        onSave?(textView.string)
        dismiss()
    }

    @objc private func cancelClicked() { dismiss() }
}
