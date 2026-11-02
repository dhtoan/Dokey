// Dokey for macOS - user preferences.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// Shortcut that switches between Vietnamese and English.
enum SwitchHotkey: Int, CaseIterable {
    case controlShift = 0   // press and release ⌃⇧ with no other key
    case optionZ = 1
    case controlSpace = 2
    case commandShiftSpace = 3

    var title: String {
        switch self {
        case .controlShift: return "⌃⇧  (Control + Shift)"
        case .optionZ: return "⌥Z  (Option + Z)"
        case .controlSpace: return "⌃Space  (Control + Space)"
        case .commandShiftSpace: return "⌘⇧Space  (Command + Shift + Space)"
        }
    }

    var shortTitle: String {
        switch self {
        case .controlShift: return "⌃⇧"
        case .optionZ: return "⌥Z"
        case .controlSpace: return "⌃Space"
        case .commandShiftSpace: return "⌘⇧Space"
        }
    }

    /// Key combination for the non modifier-only shortcuts.
    var combo: (key: CGKeyCode, flags: CGEventFlags)? {
        switch self {
        case .controlShift: return nil
        case .optionZ: return (KeyCode.z, .maskAlternate)
        case .controlSpace: return (KeyCode.space, .maskControl)
        case .commandShiftSpace: return (KeyCode.space, [.maskCommand, .maskShift])
        }
    }
}

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let vietnamese = "vietnamese"
        static let method = "inputMethod"
        static let encoding = "encoding"
        static let modernTone = "modernToneStyle"
        static let spelling = "checkSpelling"
        static let hotkey = "switchHotkey"
        static let rememberPerApp = "rememberModePerApp"
        static let perAppModes = "perAppModes"
        static let slowMachine = "slowMachineMode"
        static let quickTelex = "quickTelex"
        static let undoWithEsc = "undoWithEsc"
        static let macrosOn = "macrosEnabled"
        static let macroText = "macroText"
        static let excluded = "excludedApps"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let autoUpdate = "autoCheckUpdates"
        static let skippedVersion = "skippedVersion"
        static let updatedFrom = "updatedFrom"
    }

    private init() {
        defaults.register(defaults: [
            Key.vietnamese: true,
            Key.method: Int(DOKEY_TELEX),
            Key.encoding: Int(DOKEY_UNICODE),
            Key.modernTone: true,
            Key.spelling: true,
            Key.hotkey: SwitchHotkey.controlShift.rawValue,
            Key.rememberPerApp: true,
            Key.slowMachine: false,
            Key.quickTelex: false,
            Key.undoWithEsc: false,
            Key.autoUpdate: true,
            Key.macrosOn: true,
            Key.macroText: Settings.sampleMacros,
        ])
    }

    var vietnamese: Bool {
        get { defaults.bool(forKey: Key.vietnamese) }
        set { defaults.set(newValue, forKey: Key.vietnamese) }
    }

    var method: Int32 {
        get { Int32(defaults.integer(forKey: Key.method)) }
        set { defaults.set(Int(newValue), forKey: Key.method) }
    }

    var encoding: Int32 {
        get { Int32(defaults.integer(forKey: Key.encoding)) }
        set { defaults.set(Int(newValue), forKey: Key.encoding) }
    }

    var modernToneStyle: Bool {
        get { defaults.bool(forKey: Key.modernTone) }
        set { defaults.set(newValue, forKey: Key.modernTone) }
    }

    var checkSpelling: Bool {
        get { defaults.bool(forKey: Key.spelling) }
        set { defaults.set(newValue, forKey: Key.spelling) }
    }

    var hotkey: SwitchHotkey {
        get { SwitchHotkey(rawValue: defaults.integer(forKey: Key.hotkey)) ?? .controlShift }
        set { defaults.set(newValue.rawValue, forKey: Key.hotkey) }
    }

    var rememberModePerApp: Bool {
        get { defaults.bool(forKey: Key.rememberPerApp) }
        set { defaults.set(newValue, forKey: Key.rememberPerApp) }
    }

    /// Adds extra pauses between synthetic events for older, slower Macs.
    var slowMachineMode: Bool {
        get { defaults.bool(forKey: Key.slowMachine) }
        set { defaults.set(newValue, forKey: Key.slowMachine) }
    }

    /// Advanced, set with `defaults write`: see AppKind.profile.
    var tuning: [String: Any] {
        defaults.dictionary(forKey: "tuning") ?? [:]
    }

    var debugLog: Bool {
        defaults.bool(forKey: "debugLog")
    }

    /// Typing language: "vi" (default) or "ko" (Korean 2-beolsik). Chosen in the
    /// menu or the control panel; still the same `language` key the hidden
    /// prototype switch used (`defaults write com.dhtoan.dokey.mac language -string ko`).
    var languageCode: String {
        get {
            if let forced = ProcessInfo.processInfo.environment["DOKEY_LANG"] { return forced == "ko" ? "ko" : "vi" }  // screenshots
            return defaults.string(forKey: "language") == "ko" ? "ko" : "vi"
        }
        set { defaults.set(newValue, forKey: "language") }
    }

    var korean: Bool {
        languageCode == "ko"
    }

    var language: Int32 {
        korean ? Int32(DOKEY_LANG_KOREAN) : Int32(DOKEY_LANG_VIETNAMESE)
    }

    static let sampleMacros = """
    # Gõ tắt: mỗi dòng "từ tắt = nội dung". Gõ từ tắt rồi dấu cách để thay.
    # Viết hoa từ tắt để viết hoa nội dung: vn -> Việt Nam, Vn, VN -> VIỆT NAM.
    vn = Việt Nam
    ko = không
    dc = được
    btw = by the way
    """

    var quickTelex: Bool {
        get { defaults.bool(forKey: Key.quickTelex) }
        set { defaults.set(newValue, forKey: Key.quickTelex) }
    }

    /// Esc while a word has marks shows the keys as typed (tiếng -> tieesng).
    var undoWithEsc: Bool {
        get { defaults.bool(forKey: Key.undoWithEsc) }
        set { defaults.set(newValue, forKey: Key.undoWithEsc) }
    }

    var macrosEnabled: Bool {
        get { defaults.bool(forKey: Key.macrosOn) }
        set { defaults.set(newValue, forKey: Key.macrosOn) }
    }

    var macroText: String {
        get { defaults.string(forKey: Key.macroText) ?? "" }
        set { defaults.set(newValue, forKey: Key.macroText) }
    }

    /// Number of shortcuts in `macroText`.
    var macroCount: Int {
        macroText.split(separator: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("#") && (t.contains("=") || t.contains(":"))
        }.count
    }

    /// Apps where Dokey never types Vietnamese.
    var excludedApps: [String] {
        get { defaults.stringArray(forKey: Key.excluded) ?? [] }
        set { defaults.set(newValue, forKey: Key.excluded) }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    /// Look for a new release in the background (twice a day) and tell the user.
    var autoCheckUpdates: Bool {
        get { defaults.bool(forKey: Key.autoUpdate) }
        set { defaults.set(newValue, forKey: Key.autoUpdate) }
    }

    /// A release the user chose to skip: no reminder for it, only for newer ones.
    var skippedVersion: String? {
        get { defaults.string(forKey: Key.skippedVersion) }
        set { defaults.set(newValue, forKey: Key.skippedVersion) }
    }

    /// The version that installed an update and relaunched, so the new copy can say so.
    var updatedFrom: String? {
        get { defaults.string(forKey: Key.updatedFrom) }
        set { defaults.set(newValue, forKey: Key.updatedFrom) }
    }

    func savedMode(forApp bundleID: String) -> Bool? {
        let modes = defaults.dictionary(forKey: Key.perAppModes) as? [String: Bool]
        return modes?[bundleID]
    }

    func saveMode(_ vietnamese: Bool, forApp bundleID: String) {
        var modes = defaults.dictionary(forKey: Key.perAppModes) as? [String: Bool] ?? [:]
        modes[bundleID] = vietnamese
        defaults.set(modes, forKey: Key.perAppModes)
    }

    var engineOptions: dokey_options {
        dokey_options(method: method,
                      encoding: encoding,
                      modern_tone_style: modernToneStyle ? 1 : 0,
                      check_spelling: checkSpelling ? 1 : 0,
                      quick_telex: quickTelex ? 1 : 0)
    }
}
