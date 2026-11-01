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
