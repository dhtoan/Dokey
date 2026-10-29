// Dokey for macOS - entry point.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}
if let i = CommandLine.arguments.firstIndex(of: "--render-marketing"), i + 1 < CommandLine.arguments.count {
    exit(Marketing.render(to: CommandLine.arguments[i + 1]))
}
if let i = CommandLine.arguments.firstIndex(of: "--render-panel"), i + 1 < CommandLine.arguments.count {
    exit(SelfTest.renderPanel(to: CommandLine.arguments[i + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
