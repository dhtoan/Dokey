// Dokey for macOS - sorts apps by how carefully synthetic keys must be sent.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// Chromium browsers and Electron apps handle key events in a separate
/// renderer process. When Backspace and the replacement text arrive back to
/// back, a busy renderer can apply them out of order, so letters get jumbled,
/// doubled or lost. Those apps get select-then-type and short pauses.
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

    /// How synthetic keys are sent to this kind of app. `tuning` overrides
    /// the defaults without a rebuild, e.g.
    /// `defaults write com.dhtoan.dokey.mac tuning -dict electron.settle -int 20000`
    /// (keys: <kind>.step, <kind>.settle, <kind>.tail in microseconds, <kind>.units,
    /// <kind>.select, <kind>.textKey: virtual key for text events, -1 = the key just typed,
    /// <kind>.textUp: 0 to send text as key-down only).
    func profile(slowMachine: Bool, tuning: [String: Any] = [:]) -> DeliveryProfile {
        var p: DeliveryProfile
        switch self {
        // Select-then-type: rich editors (ProseMirror in Claude, Notion) can ignore
        // synthetic Backspaces, and address bars spend one on the inline suggestion.
        // No pauses: the events are posted at the tap's own position, so they are
        // already ahead of the next key, and sleeping inside the tap only delays
        // the user's next key (other Vietnamese IMEs found the same).
        case .browser, .electron:
            p = DeliveryProfile(select: true, unitsPerEvent: 20, step: 0, settle: 0, tail: 0, textKey: 0, textUp: true)
        // Shift+← is an escape sequence in Terminal, so normal apps get Backspace.
        case .normal:
            p = DeliveryProfile(select: false, unitsPerEvent: 20, step: 0, settle: 0, tail: 0, textKey: 0, textUp: true)
        }
        if slowMachine && self != .normal {
            // A short breather for old Macs (the "Tương thích máy chậm" switch).
            p.settle = 2_000
        }
        func number(_ key: String) -> Int? { (tuning["\(rawValue).\(key)"] as? NSNumber)?.intValue }
        if let v = number("step") { p.step = useconds_t(max(0, min(v, 100_000))) }
        if let v = number("settle") { p.settle = useconds_t(max(0, min(v, 200_000))) }
        if let v = number("units") { p.unitsPerEvent = max(1, min(v, 20)) }
        if let v = number("select") { p.select = v != 0 }
        if let v = number("tail") { p.tail = useconds_t(max(0, min(v, 200_000))) }
        if let v = number("textKey") { p.textKey = max(-1, min(v, 127)) }
        if let v = number("textUp") { p.textUp = v != 0 }
        return p
    }
}

/// How one edit is replayed: delete by Backspace or by selecting with Shift+←,
/// how many UTF-16 units per key event, pauses in microseconds (after each
/// event, before the first new letter, after the last one), and which virtual
/// key the text events carry.
struct DeliveryProfile {
    var select: Bool
    var unitsPerEvent: Int
    var step: useconds_t
    var settle: useconds_t
    var tail: useconds_t
    var textKey: Int
    var textUp: Bool
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
