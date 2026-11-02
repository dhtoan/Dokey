// Dokey for macOS - the session event tap that turns key presses into Vietnamese.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// Virtual key codes. They name physical key positions, so they are the same
/// for every keyboard layout.
enum KeyCode {
    static let z: CGKeyCode = 6
    static let returnKey: CGKeyCode = 36
    static let tab: CGKeyCode = 48
    static let space: CGKeyCode = 49
    static let backspace: CGKeyCode = 51
    static let escape: CGKeyCode = 53
    static let keypadEnter: CGKeyCode = 76
    static let forwardDelete: CGKeyCode = 117
    static let leftArrow: CGKeyCode = 123
    /// Arrows, Home, End, Page Up, Page Down: the caret moves, so the word ends.
    static let caretMovers: Set<CGKeyCode> = [115, 116, 119, 121, 123, 124, 125, 126]

    /// The letter each key has on a US/ABC keyboard (kVK_ANSI_A ... kVK_ANSI_M).
    private static let letters: [CGKeyCode: Unicode.Scalar] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
        34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
    ]

    /// Korean 2-beolsik types by key position, so letters are read by key code,
    /// whatever the keyboard layout (Dvorak, AZERTY...). Caps Lock is ignored.
    static func usLetter(_ key: CGKeyCode, shift: Bool) -> UInt32? {
        guard let letter = letters[key] else { return nil }
        return shift ? letter.value - 0x20 : letter.value
    }
}

/// Written into every event Dokey posts, so the tap never processes its own output.
let dokeyEventTag: Int64 = 0x444F_4B45  // "DOKE"

/// What the tap thread needs to know; changed on the main thread.
struct TapState {
    var vietnamese = true
    var appKind = AppKind.normal
    var profile = AppKind.normal.profile(slowMachine: false)
    var debugLog = false
    var hotkey = SwitchHotkey.controlShift
    var encoding = Int32(DOKEY_UNICODE)
    var undoWithEsc = false
    /// Replaces the app's profile, e.g. for Google Docs (set from the window title).
    var siteProfile: DeliveryProfile?
    /// Prototype: Korean (2-beolsik) instead of Vietnamese (`defaults write ... language -string ko`).
    var korean = false
    /// The front app is VS Code or a fork (see AppClassifier.isVSCode).
    var vsCode = false
}

final class KeyboardTap {
    let engine: Engine
    /// Called on the main thread when the user presses the switch shortcut.
    var onToggle: (() -> Void)?

    private var port: CFMachPort?
    private var thread: Thread?
    private let stateLock = NSLock()
    private var _state = TapState()
    private let source = CGEventSource(stateID: .privateState)
    /// ⌃⇧ was pressed with nothing else; toggles when released. Tap thread only.
    private var modifierHotkeyArmed = false

    init(engine: Engine) {
        self.engine = engine
    }

    var state: TapState {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _state }
        set { stateLock.lock(); _state = newValue; stateLock.unlock() }
    }

    var isRunning: Bool { port != nil }

    /// Words Dokey has changed (added marks to) since it started.
    var editedWords: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return _editedWords
    }
    private var _editedWords = 0
    private var wordCounted = false  // tap thread only

    private func newWord() {
        wordCounted = false
        engine.reset()
    }

    var isEnabled: Bool {
        guard let port = port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Creates the tap and runs it on its own thread, so a busy main thread
    /// (menus, windows) never delays typing. Fails without Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        port = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Dokey event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        return true
    }

    /// Watchdog: macOS turns a tap off when it is slow or after secure input.
    /// Returns true when the tap had to be switched back on.
    @discardableResult
    func ensureEnabled() -> Bool {
        guard let port = port, !CGEvent.tapIsEnabled(tap: port) else { return false }
        newWord()
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    // MARK: - Event handling (tap thread)

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            newWord()
            if let port = port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            modifierHotkeyArmed = false
            newWord()
            return pass
        case .flagsChanged:
            if modifierHotkeyReleased(event.flags) { requestToggle() }
            return pass
        case .keyDown:
            return keyDown(proxy: proxy, event: event)
        default:
            return pass
        }
    }

    private func keyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if event.getIntegerValueField(.eventSourceUserData) == dokeyEventTag { return pass }
        modifierHotkeyArmed = false
        if state.debugLog { DebugLog.key() }

        let keyCode = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let current = state

        if let combo = current.hotkey.combo, keyCode == combo.key,
           flags.intersection(Self.modifierMask) == combo.flags {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { requestToggle() }
            return nil
        }
        guard current.vietnamese else { return pass }

        // Holding a key down: treat what follows as a new word.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            newWord()
            return pass
        }
        // Shortcuts (⌘, ⌃, ⌥ layers) never go to the engine.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            newWord()
            return pass
        }

        switch keyCode {
        case KeyCode.backspace:
            // Usually goes through; the engine may instead correct the word
            // (the tone moves back: "hoàn" -> "hòa").
            guard let edit = engine.backspaceEdit() else { return pass }
            deliver(edit, typedKey: keyCode, proxy: proxy, state: current, then: nil)
            return nil
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab:
            // Ends the word: the engine may finish it (thuowr → thuở) before
            // the key itself goes through.
            let ch: UInt32 = keyCode == KeyCode.tab ? 0x09 : 0x0D
            guard var edit = engine.key(ch) else { return pass }
            if edit.text.last == UInt16(ch) { edit.text.removeLast() }
            deliver(edit, typedKey: keyCode, proxy: proxy, state: current, then: event)
            return nil
        case KeyCode.escape:
            // Esc shows the current word as typed (tiếng -> tieesng) when it has marks.
            if current.undoWithEsc, let edit = engine.undo() {
                deliver(edit, typedKey: keyCode, proxy: proxy, state: current, then: nil)
                return nil
            }
            newWord()
            return pass
        case KeyCode.forwardDelete:
            newWord()
            return pass
        default:
            if KeyCode.caretMovers.contains(keyCode) {
                newWord()
                return pass
            }
        }

        let letter = current.korean ? KeyCode.usLetter(keyCode, shift: flags.contains(.maskShift)) : nil
        guard let ch = letter ?? typedCharacter(event) else {
            newWord()
            return pass
        }
        if !(ch >= 0x41 && ch <= 0x5A) && !(ch >= 0x61 && ch <= 0x7A) { wordCounted = false }
        guard let edit = engine.key(ch) else { return pass }
        if !wordCounted && !edit.text.isEmpty {
            wordCounted = true
            stateLock.lock(); _editedWords += 1; stateLock.unlock()
        }
        deliver(edit, typedKey: keyCode, proxy: proxy, state: current, then: nil)
        return nil
    }

    private static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    private func modifierHotkeyReleased(_ flags: CGEventFlags) -> Bool {
        guard state.hotkey == .controlShift else { return false }
        let held = flags.intersection(Self.modifierMask)
        if held == [.maskControl, .maskShift] {
            modifierHotkeyArmed = true
        } else if held.isEmpty {
            defer { modifierHotkeyArmed = false }
            return modifierHotkeyArmed
        } else if !held.isSubset(of: [.maskControl, .maskShift]) {
            modifierHotkeyArmed = false
        }
        return false
    }

    private func requestToggle() {
        newWord()
        DispatchQueue.main.async { [weak self] in self?.onToggle?() }
    }

    /// The single printable character this key produces with the current layout.
    private func typedCharacter(_ event: CGEvent) -> UInt32? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        guard length == 1 else { return nil }
        let c = chars[0]
        if c < 0x20 || c == 0x7F { return nil }        // control characters
        if c >= 0xF700 && c <= 0xF8FF { return nil }   // function keys
        if c >= 0xD800 && c <= 0xDFFF { return nil }   // half of a surrogate pair
        return UInt32(c)
    }

    // MARK: - Synthetic events

    /// Swallows the original key and replays the edit: Backspaces, then the new text,
    /// then (for Return/Tab) a copy of the original key. CGEventTapPostEvent inserts
    /// the events right after this tap, ahead of any key the user types next.
    private func deliver(_ edit: EngineEdit, typedKey: CGKeyCode, proxy: CGEventTapProxy, state: TapState,
                         then original: CGEvent?) {
        var profile = state.siteProfile ?? state.profile
        // Spotlight's search field never becomes the front app; it has an inline
        // completion like a browser address bar, so treat it like one.
        if state.appKind == .normal, LauncherDetector.spotlightFocused() {
            profile = AppKind.browser.profile(slowMachine: state.profile.settle > 0)
        }
        // Korean rewrites nearly every key. VS Code's terminal (xterm.js) reads
        // Shift+← as an escape sequence, so VS Code gets Backspace instead.
        if state.korean && state.vsCode { profile.select = false }
        // Rich editors (ProseMirror/Tiptap in Claude, Notion…) can ignore synthetic
        // Backspaces, and browser address bars spend the first one on the inline
        // suggestion. Selecting the old letters with Shift+← and typing over them
        // works in both. Combining marks are skipped: ← moves by whole character.
        let select = profile.select && !edit.text.isEmpty
            && state.encoding != Int32(DOKEY_UNICODE_COMBINING)
        if state.debugLog { DebugLog.write(edit, kind: state.appKind, selected: select) }
        for _ in 0..<edit.backspaces {
            if select {
                postKey(KeyCode.leftArrow, flags: [.maskShift, .maskSecondaryFn, .maskNumericPad], proxy: proxy)
            } else {
                postKey(KeyCode.backspace, proxy: proxy)
            }
            pause(profile.step)
        }
        if edit.backspaces > 0 && !edit.text.isEmpty { pause(profile.settle) }

        let textKey: CGKeyCode
        switch profile.textKey {
        case -1: textKey = typedKey
        case ..<0: textKey = freeTextKey()
        default: textKey = CGKeyCode(profile.textKey)
        }
        let chunk = profile.unitsPerEvent
        var start = 0
        while start < edit.text.count {
            var end = min(start + chunk, edit.text.count)
            // Never split a surrogate pair across two events.
            if end < edit.text.count && UTF16.isLeadSurrogate(edit.text[end - 1]) { end += 1 }
            postText(Array(edit.text[start..<end]), key: textKey, up: profile.textUp, proxy: proxy)
            pause(profile.step)
            start = end
        }

        if !edit.text.isEmpty { pause(profile.tail) }

        if let copy = original?.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: dokeyEventTag)
            copy.tapPostEvent(proxy)
        }
    }

    /// The virtual key that text events carry. Apps see a key-down for that key, so
    /// it must not be one the user is still holding: typing "ma" + "f" fast, the
    /// A key is often still down, and a synthetic key-down for A then makes
    /// Chromium/Electron (Claude, Chrome) drop the "à" as a repeat. Use a key that
    /// is not down right now, preferring ones rarely held while typing.
    private func freeTextKey() -> CGKeyCode {
        for key: CGKeyCode in [11, 9, 45, 43, 47, 50, 41] where !CGEventSource.keyState(.hidSystemState, key: key) {
            return key  // b, v, n, comma, period, grave, semicolon
        }
        return 11
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags = [], proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags  // a held Shift must not turn Backspace into Shift-Backspace
            e.setIntegerValueField(.eventSourceUserData, value: dokeyEventTag)
            e.tapPostEvent(proxy)
        }
    }

    private func postText(_ units: [UInt16], key: CGKeyCode, up: Bool, proxy: CGEventTapProxy) {
        for down in up ? [true, false] : [true] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = []
            var chars = units
            e.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            e.setIntegerValueField(.eventSourceUserData, value: dokeyEventTag)
            e.tapPostEvent(proxy)
        }
    }

    private func pause(_ microseconds: useconds_t) {
        if microseconds > 0 { usleep(microseconds) }
    }
}

private let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyboardTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(proxy: proxy, type: type, event: event)
}

/// Opt-in trace of what Dokey sends, for diagnosing lost letters:
/// `defaults write com.dhtoan.dokey.mac debugLog -bool true`, then read
/// ~/Library/Logs/Dokey.log. Off by default; it contains the words typed.
enum DebugLog {
    private static let queue = DispatchQueue(label: "Dokey debug log")
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dokey.log")

    /// A physical key arrived (only the time is logged, not which key).
    static func key() {
        let time = Date().timeIntervalSince1970
        queue.async { append(String(format: "%.3f key\n", time)) }
    }

    static func write(_ edit: EngineEdit, kind: AppKind, selected: Bool) {
        let time = Date().timeIntervalSince1970
        let text = String(decoding: edit.text, as: UTF16.self)
        queue.async {
            let line = String(format: "%.3f %@ %@ x%d -> \"%@\"\n", time, kind.rawValue,
                              selected ? "select" : "backspace", edit.backspaces, text)
            append(line)
        }
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Finds out whether Spotlight's search field has keyboard focus.
enum LauncherDetector {
    private static let systemWide = AXUIElementCreateSystemWide()

    static func spotlightFocused() -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let app = value, CFGetTypeID(app) == AXUIElementGetTypeID() else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app as! AXUIElement, &pid) == .success else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.Spotlight"
    }
}
