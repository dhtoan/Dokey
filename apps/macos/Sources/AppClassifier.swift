// Dokey for macOS - sorts apps by how carefully synthetic keys must be sent.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// Chromium browsers and Electron apps handle key events in a separate
/// renderer process. When Backspace and the replacement text arrive back to
/// back, a busy renderer can apply them out of order, so letters get jumbled
/// or doubled. Those apps get one character per event and short pauses.
enum AppKind: String {
    case browser
    case electron
    case normal

    var title: String {
        switch self {
        case .browser: return "trình duyệt"
        case .electron: return "Electron/IDE"
        case .normal: return "thường"
        }
    }

    /// Pauses in microseconds: after each synthetic event, and once between
    /// the Backspaces and the new text.
    func delays(slowMachine: Bool) -> (step: useconds_t, settle: useconds_t) {
        let base: (useconds_t, useconds_t)
        switch self {
        case .browser: base = (1_500, 4_000)
        case .electron: base = (1_000, 3_000)
        case .normal: base = (0, 0)
        }
        if slowMachine {
            return (base.0 * 2 + 300, base.1 * 2 + 1_000)
        }
        return base
    }

    /// Replace letters by selecting them (Shift+←) and typing over the
    /// selection, instead of Backspace. Not for normal apps: in Terminal,
    /// Shift+← is an escape sequence, not a selection.
    var selectsBeforeReplacing: Bool {
        self != .normal
    }

    /// How many UTF-16 units may share one synthetic key event.
    var unitsPerEvent: Int {
        self == .normal ? 20 : 1
    }
}

enum AppClassifier {
    private static let browserPrefixes = [
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",   // Arc
        "com.coccoc.Coccoc",
        "com.naver.Whale",
        "ru.yandex.desktop.yandex-browser",
        "org.mozilla.firefox",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
    ]

    private static let electronPrefixes = [
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        "com.microsoft.VSCode",
        "com.visualstudio.code",
        "com.todesktop.",               // Cursor and other ToDesktop apps
        "com.exafunction.windsurf",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "notion.id",
        "com.figma.Desktop",
        "md.obsidian",
        "com.microsoft.teams",
        "com.github.GitHubClient",
        "com.postmanlabs.mac",
        "com.jetbrains.",
        "com.google.android.studio",
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "com.facebook.archon",          // Messenger
        "com.vng.zalo",
        "com.skype.skype",
    ]

    private static var cache: [String: AppKind] = [:]

    /// Must be called on the main thread.
    static func classify(_ app: NSRunningApplication) -> AppKind {
        guard let id = app.bundleIdentifier else { return .normal }
        if let known = cache[id] { return known }
        let kind = classify(bundleID: id, bundleURL: app.bundleURL)
        cache[id] = kind
        return kind
    }

    static func classify(bundleID id: String, bundleURL: URL?) -> AppKind {
        if browserPrefixes.contains(where: { id.hasPrefix($0) }) { return .browser }
        if electronPrefixes.contains(where: { id.hasPrefix($0) }) { return .electron }
        guard let url = bundleURL else { return .normal }
        return classify(frameworks: url.appendingPathComponent("Contents/Frameworks"))
    }

    /// Unknown apps: look at the frameworks they ship.
    static func classify(frameworks dir: URL) -> AppKind {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names {
            if name == "Electron Framework.framework" || name == "Chromium Embedded Framework.framework" {
                return .electron
            }
            if name.hasSuffix(" Framework.framework"),
               ["Chrome", "Chromium", "Edge", "Brave", "Opera", "Vivaldi"].contains(where: { name.contains($0) }) {
                return .browser
            }
        }
        return .normal
    }
}
