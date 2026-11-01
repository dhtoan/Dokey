// Dokey for macOS - checks GitHub Releases for a newer version and installs it.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

/// The public GitHub API answers for public repositories. While the repository
/// is private, the GitHub CLI (`gh`, signed in) is used instead, and also to
/// download and run the release's install-macos.sh.
final class Updater {
    static let shared = Updater()

    private let repo = "dhtoan/Dokey"
    private var checking = false

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var ghPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "\(home)/.local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `interactive`: from the menu, always answers. Otherwise at most once a day
    /// and only speaks up when there is a new version.
    func check(interactive: Bool) {
        if checking { return }
        if !interactive, let last = Settings.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 86_400 { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let latest = self.latestVersion()
            DispatchQueue.main.async {
                self.checking = false
                Settings.shared.lastUpdateCheck = Date()
                self.report(latest: latest, interactive: interactive)
            }
        }
    }

    // MARK: - Finding the latest version

    private func latestVersion() -> String? {
        if let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tag = json["tag_name"] as? String {
            return tag
        }
        guard let gh = ghPath else { return nil }
        return run(gh, ["release", "view", "-R", repo, "--json", "tagName", "-q", ".tagName"])
    }

    private func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    /// "v0.4.1" > "0.4.0"?
    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Telling the user

    private func report(latest: String?, interactive: Bool) {
        let alert = NSAlert()
        if let latest = latest, Self.isNewer(latest, than: currentVersion) {
            let version = latest.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            alert.messageText = "Đã có Dokey \(version)"
            alert.informativeText = "Bạn đang dùng bản \(currentVersion). "
                + (ghPath != nil
                    ? "Dokey sẽ tải bản mới, cài vào Applications rồi mở lại. Sau đó hãy cấp lại quyền Trợ năng."
                    : "Mở trang Releases để tải bản mới.")
            alert.addButton(withTitle: ghPath != nil ? "Cập nhật ngay" : "Mở trang Releases")
            alert.addButton(withTitle: "Để sau")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if !install() { openReleases() }
            return
        }
        guard interactive else { return }
        if latest != nil {
            alert.messageText = "Bạn đang dùng bản mới nhất"
            alert.informativeText = "Dokey \(currentVersion)."
            alert.addButton(withTitle: "OK")
        } else {
            alert.messageText = "Không kiểm tra được bản mới"
            alert.informativeText = "Kho mã Dokey đang ở chế độ riêng tư. Hãy cài GitHub CLI và đăng nhập (gh auth login), "
                + "hoặc mở trang Releases để xem bản mới nhất."
            alert.addButton(withTitle: "Mở trang Releases")
            alert.addButton(withTitle: "Đóng")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn && latest == nil { openReleases() }
    }

    private func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/\(repo)/releases/latest")!)
    }

    /// Downloads and runs the release's install script; it quits this copy of
    /// Dokey, replaces /Applications/Dokey.app and opens the new one.
    private func install() -> Bool {
        guard let gh = ghPath else { return false }
        let dir = NSTemporaryDirectory()
        let script = "\"\(gh)\" release download -R \(repo) --pattern install-macos.sh --dir \"\(dir)\" --clobber && "
            + "/bin/bash \"\(dir)install-macos.sh\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ((gh as NSString).deletingLastPathComponent) + ":/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        do { try process.run() } catch { return false }
        return true
    }
}
