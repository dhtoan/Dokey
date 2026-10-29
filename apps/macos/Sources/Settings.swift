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
                      check_spelling: checkSpelling ? 1 : 0)
    }
}
