// Dokey for macOS - entry point.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
