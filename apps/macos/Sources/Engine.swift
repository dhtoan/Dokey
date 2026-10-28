// Dokey for macOS - thread-safe wrapper around the Dokey Core C API.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Foundation

/// The result of one key press: delete `backspaces` characters, then insert `text`.
struct EngineEdit {
    var backspaces: Int
    var text: [UInt16]
}

/// The engine is driven from the event-tap thread, while settings change on
/// the main thread, so every call goes through one lock.
final class Engine {
    private let lock = NSLock()
    private let handle: OpaquePointer

    init(options: dokey_options) {
        var o = options
        handle = dokey_create(&o)
    }

    deinit {
        dokey_destroy(handle)
    }

    func setOptions(_ options: dokey_options) {
        var o = options
        lock.lock()
        dokey_set_options(handle, &o)
        lock.unlock()
    }

    /// Returns nil when the original key should go through unchanged.
    func key(_ ch: UInt32) -> EngineEdit? {
        var out = dokey_edit()
        lock.lock()
        let handled = dokey_key(handle, ch, &out)
        lock.unlock()
        guard handled == 1 else { return nil }
        let count = Int(out.length)
        let text = withUnsafeBytes(of: &out.text) { raw in
            Array(raw.bindMemory(to: UInt16.self).prefix(count))
        }
        return EngineEdit(backspaces: Int(out.backspaces), text: text)
    }

    func backspace() {
        lock.lock()
        dokey_backspace(handle)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        dokey_reset(handle)
        lock.unlock()
    }

    /// Types `keys` into an in-memory buffer the way the event tap would (used by --self-test).
    func simulate(_ keys: String) -> String {
        reset()
        var buffer: [UInt16] = []
        for scalar in keys.unicodeScalars {
            if let edit = key(scalar.value) {
                buffer.removeLast(min(edit.backspaces, buffer.count))
                buffer.append(contentsOf: edit.text)
            } else {
                buffer.append(contentsOf: Array(String(scalar).utf16))
            }
        }
        reset()
        return String(decoding: buffer, as: UTF16.self)
    }
}
