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
    /// Arrows, Home, End, Page Up, Page Down: the caret moves, so the word ends.
    static let caretMovers: Set<CGKeyCode> = [115, 116, 119, 121, 123, 124, 125, 126]
}

/// Written into every event Dokey posts, so the tap never processes its own output.
let dokeyEventTag: Int64 = 0x444F_4B45  // "DOKE"

/// What the tap thread needs to know; changed on the main thread.
struct TapState {
    var vietnamese = true
    var appKind = AppKind.normal
    var slowMachine = false
    var hotkey = SwitchHotkey.controlShift
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
        engine.reset()
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    // MARK: - Event handling (tap thread)

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            engine.reset()
            if let port = port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            modifierHotkeyArmed = false
            engine.reset()
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
            engine.reset()
            return pass
        }
        // Shortcuts (⌘, ⌃, ⌥ layers) never go to the engine.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            engine.reset()
            return pass
        }

        switch keyCode {
        case KeyCode.backspace:
            engine.backspace()
            return pass
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab:
            // Ends the word: the engine may finish it (thuowr → thuở) before
            // the key itself goes through.
            let ch: UInt32 = keyCode == KeyCode.tab ? 0x09 : 0x0D
            guard var edit = engine.key(ch) else { return pass }
            if edit.text.last == UInt16(ch) { edit.text.removeLast() }
            deliver(edit, proxy: proxy, state: current, then: event)
            return nil
        case KeyCode.escape, KeyCode.forwardDelete:
            engine.reset()
            return pass
        default:
            if KeyCode.caretMovers.contains(keyCode) {
                engine.reset()
                return pass
            }
        }

        guard let ch = typedCharacter(event) else {
            engine.reset()
            return pass
        }
        guard let edit = engine.key(ch) else { return pass }
        deliver(edit, proxy: proxy, state: current, then: nil)
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
        engine.reset()
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
    private func deliver(_ edit: EngineEdit, proxy: CGEventTapProxy, state: TapState, then original: CGEvent?) {
        let delays = state.appKind.delays(slowMachine: state.slowMachine)
        for _ in 0..<edit.backspaces {
            postKey(KeyCode.backspace, proxy: proxy)
            pause(delays.step)
        }
        if edit.backspaces > 0 && !edit.text.isEmpty { pause(delays.settle) }

        let chunk = state.appKind.unitsPerEvent
        var start = 0
        while start < edit.text.count {
            var end = min(start + chunk, edit.text.count)
            // Never split a surrogate pair across two events.
            if end < edit.text.count && UTF16.isLeadSurrogate(edit.text[end - 1]) { end += 1 }
            postText(Array(edit.text[start..<end]), proxy: proxy)
            pause(delays.step)
            start = end
        }

        if let copy = original?.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: dokeyEventTag)
            copy.tapPostEvent(proxy)
        }
    }

    private func postKey(_ key: CGKeyCode, proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = []  // a held Shift must not turn Backspace into Shift-Backspace
            e.setIntegerValueField(.eventSourceUserData, value: dokeyEventTag)
            e.tapPostEvent(proxy)
        }
    }

    private func postText(_ units: [UInt16], proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
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
