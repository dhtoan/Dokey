// Dokey for macOS - `Dokey --self-test`: checks the bundled engine and app
// classification without a window, keyboard or Accessibility permission (used by CI).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ actual: String, _ expected: String) {
            if actual == expected {
                print("ok    \(name)")
            } else {
                print("FAIL  \(name): got \"\(actual)\", expected \"\(expected)\"")
                failures += 1
            }
        }

        let telex = Engine(options: dokey_options(method: Int32(DOKEY_TELEX), encoding: Int32(DOKEY_UNICODE),
                                                  modern_tone_style: 1, check_spelling: 1, quick_telex: 0))
        check("telex sentence", telex.simulate("Xin chaof cacs banj "), "Xin chào các bạn ")
        check("telex dd/uow", telex.simulate("dduowngf "), "đường ")
        check("english kept", telex.simulate("windows chrome "), "windows chrome ")
        check("end-of-word fix", telex.simulate("thuowr "), "thuở ")
        check("undo by repeat", telex.simulate("aaa "), "aa ")

        let vni = Engine(options: dokey_options(method: Int32(DOKEY_VNI), encoding: Int32(DOKEY_UNICODE),
                                                modern_tone_style: 0, check_spelling: 1, quick_telex: 0))
        check("vni", vni.simulate("Vie65t Nam "), "Việt Nam ")
        check("old tone style", vni.simulate("hoa2 "), "hòa ")

        let macros = Engine(options: dokey_options(method: Int32(DOKEY_TELEX), encoding: Int32(DOKEY_UNICODE),
                                                   modern_tone_style: 1, check_spelling: 1, quick_telex: 1))
        macros.setMacros("vn = Việt Nam")
        check("macro", macros.simulate("vn "), "Việt Nam ")
        check("quick telex", macros.simulate("ccaof "), "chào ")
        check("highland names", macros.simulate("DDawks Lawks "), "Đắk Lắk ")
        check("undo", { () -> String in
            macros.reset()
            for c in "tieengs".unicodeScalars { _ = macros.key(c.value) }
            guard let edit = macros.undo() else { return "nil" }
            return "\(edit.backspaces):" + String(decoding: edit.text, as: UTF16.self)
        }(), "3:eengs")

        let korean = Engine(options: dokey_options(method: Int32(DOKEY_TELEX), encoding: Int32(DOKEY_UNICODE),
                                                   modern_tone_style: 1, check_spelling: 1, quick_telex: 0))
        korean.setLanguage(Int32(DOKEY_LANG_KOREAN))
        check("korean", korean.simulate("dkssudgktpdy gksrnr"), "안녕하세요 한국")
        check("korean split", korean.simulate("rkqtdl dlTdj"), "값이 있어")
        var letters = ""
        let codes: [(CGKeyCode, Bool)] = [(4, false), (40, false), (15, true), (50, false)]
        for (key, shift) in codes {
            if let u = KeyCode.usLetter(key, shift: shift), let s = Unicode.Scalar(u) {
                letters.append(Character(s))
            } else {
                letters.append("-")
            }
        }
        check("korean key codes", letters, "hkR-")
        check("vscode", AppClassifier.isVSCode(bundleID: "com.microsoft.VSCode")
              && !AppClassifier.isVSCode(bundleID: "com.google.Chrome") ? "ok" : "bad", "ok")

        let kinds: [(String, AppKind)] = [
            ("com.google.Chrome", .browser),
            ("com.microsoft.edgemac", .browser),
            ("com.anthropic.claudefordesktop", .electron),
            ("com.microsoft.VSCode", .electron),
            ("com.apple.TextEdit", .normal),
        ]
        for (id, kind) in kinds {
            check("classify \(id)", AppClassifier.classify(bundleID: id, bundleURL: nil).rawValue, kind.rawValue)
        }

        // The send path against a text box that selects an inline completion after
        // the caret, like an address bar ("dd" used to give "dđ" there).
        for (keys, expected) in [("ddoox ", "đỗ "), ("thaayf ", "thầy "), ("dduowcj ", "được "), ("Vieetj ", "Việt ")] {
            for (select, completes) in [(true, true), (false, true), (true, false), (false, false)] {
                let field = CompletingField(words: completes ? ["dantri.com.vn", "thanhnien.vn", "duoc.vn", "vietnamnet.vn"] : [])
                let engine = Engine(options: dokey_options(method: Int32(DOKEY_TELEX), encoding: Int32(DOKEY_UNICODE),
                                                           modern_tone_style: 1, check_spelling: 1, quick_telex: 0))
                for scalar in keys.unicodeScalars {
                    guard let edit = engine.key(scalar.value) else { field.type([UInt16](String(scalar).utf16)); continue }
                    let steps = KeyboardTap.deletionSteps(backspaces: edit.backspaces, select: select && !edit.text.isEmpty,
                                                          clearSelection: true)
                    for step in steps {
                        switch step {
                        case .zeroWidthSpace: field.type([0x200B])
                        case .selectLeft: field.shiftLeft()
                        case .backspace: field.backspace()
                        }
                    }
                    if !edit.text.isEmpty { field.type(edit.text) }
                }
                check("\(completes ? "completion" : "plain") box, \(select ? "select" : "backspace"): \(keys)", field.typedText, expected)
            }
        }

        let icon = StatusIcon.image(vietnamese: true)
        check("status icon", icon.isTemplate && icon.size.width > 0 ? "ok" : "bad", "ok")

        print(failures == 0 ? "All self-tests passed." : "\(failures) self-test(s) failed.")
        return failures == 0 ? 0 : 1
    }

    /// Draws every control panel page into PNG files (for design review): <prefix>-1.png …
    static func renderPanel(to prefix: String) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let panel = ControlPanelController()
        panel.refresh()
        guard let window = panel.window, let view = window.contentView else { return 1 }
        for page in 0..<5 {
            panel.showPage(page)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
            do { try png.write(to: URL(fileURLWithPath: "\(prefix)-\(page + 1).png")) } catch { return 1 }
        }
        return 0
    }
}

/// A one-line text box that, like a browser address bar, fills in the rest of a
/// known word after each typed letter and selects it (anchor at the caret).
final class CompletingField {
    private var text: [UInt16] = []
    private var anchor = 0, focus = 0
    private let words: [[UInt16]]

    init(words: [String]) { self.words = words.map { Array($0.utf16) } }

    /// What the user typed: the text up to the selection (the completion is not theirs).
    var typedText: String { String(utf16CodeUnits: Array(text[0..<min(anchor, focus)]), count: min(anchor, focus)) }

    private func replaceSelection(with units: [UInt16]) {
        let lo = min(anchor, focus), hi = max(anchor, focus)
        text.replaceSubrange(lo..<hi, with: units)
        anchor = lo + units.count
        focus = anchor
    }

    func type(_ units: [UInt16]) {
        replaceSelection(with: units)
        // Inline completion of what is typed so far (nothing matches U+200B).
        let typed = text
        guard anchor == text.count, !typed.isEmpty,
              let word = words.first(where: { $0.count > typed.count && Array($0.prefix(typed.count)) == typed.map(Self.lower) })
        else { return }
        text += word[typed.count...]
        focus = text.count
    }

    func shiftLeft() { if focus > 0 { focus -= 1 } }

    func backspace() {
        if anchor != focus { replaceSelection(with: []) }
        else if focus > 0 { text.remove(at: focus - 1); focus -= 1; anchor = focus }
    }

    private static func lower(_ u: UInt16) -> UInt16 { (u >= 0x41 && u <= 0x5A) ? u + 32 : u }
}
