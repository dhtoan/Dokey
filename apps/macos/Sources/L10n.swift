// Dokey for macOS - interface language (Vietnamese or Korean).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Foundation

/// The interface follows the system language: Korean on a Korean Mac,
/// Vietnamese otherwise. `defaults write com.dhtoan.dokey.mac uiLanguage -string ko`
/// (or `vi`) overrides it; DOKEY_UI=ko does the same for screenshots.
enum L10n {
    static let korean: Bool = {
        if let forced = ProcessInfo.processInfo.environment["DOKEY_UI"] { return forced == "ko" }
        if let chosen = UserDefaults.standard.string(forKey: "uiLanguage") { return chosen == "ko" }
        return Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
    }()
}

/// The Vietnamese text, or its Korean translation on a Korean interface.
/// Both live side by side at each call site so they never drift apart.
func tr(_ vietnamese: String, _ korean: String) -> String {
    L10n.korean ? korean : vietnamese
}
