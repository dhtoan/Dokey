// Dokey for macOS - finds a newer release on GitHub, tells the user, and
// installs it in place: download, verify, replace the app, relaunch.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa
import CommonCrypto
import UserNotifications

extension Notification.Name {
    /// Posted on the main thread when `Updater.shared.available` changes.
    static let dokeyUpdateAvailable = Notification.Name("DokeyUpdateAvailable")
}

/// A release as the GitHub API describes it.
struct Release {
    let version: String        // "0.4.1"
    let notes: String          // release notes, plain text
    let page: URL              // the release page
    let dmg: URL?              // Dokey-<version>.dmg
    let size: Int
    let sha256: String?        // GitHub's digest of the .dmg, when it has one
}

final class Updater: NSObject {
    static let shared = Updater()

    private let repo = "dhtoan/Dokey"
    private var checking = false
    private var timer: Timer?
    /// A newer release than this copy, once a check found one.
    private(set) var available: Release? {
        didSet { NotificationCenter.default.post(name: .dokeyUpdateAvailable, object: self) }
    }

    private var progressWindow: UpdateProgressWindow?
    private var session: URLSession?
    private var downloading: Release?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Called once at launch: welcomes a freshly updated copy and starts the
    /// background checks (soon after launch, then every few hours).
    func start() {
        if #available(macOS 10.14, *) {
            UNUserNotificationCenter.current().delegate = self
            let open = UNNotificationAction(identifier: "update", title: tr("Cập nhật", "업데이트"), options: [.foreground])
            let category = UNNotificationCategory(identifier: "update", actions: [open], intentIdentifiers: [], options: [])
            UNUserNotificationCenter.current().setNotificationCategories([category])
        } else {
            NSUserNotificationCenter.default.delegate = self
        }
        if let from = Settings.shared.updatedFrom {
            Settings.shared.updatedFrom = nil
            if from != currentVersion { notify(title: tr("Đã cập nhật Dokey ", "Dokey 업데이트 완료: ") + currentVersion,
                                               body: tr("Nếu gõ không ra dấu, hãy cấp lại quyền Trợ năng.",
                                                        "입력이 되지 않으면 손쉬운 사용 권한을 다시 허용하세요."),
                                               action: false) }
        }
        if CommandLine.arguments.contains("--check-updates") {  // `open -a Dokey --args --check-updates`
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.check(interactive: true) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.check(interactive: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            self?.check(interactive: false)
        }
    }

    /// `interactive`: from the menu or the panel, always answers. Otherwise at
    /// most twice a day, and only a notification when there is a new version.
    func check(interactive: Bool) {
        if checking { return }
        if !interactive {
            guard Settings.shared.autoCheckUpdates else { return }
            if let last = Settings.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 12 * 3600 { return }
        }
        checking = true
        fetchLatest { release in
            self.checking = false
            if release != nil { Settings.shared.lastUpdateCheck = Date() }
            if let release = release, Self.isNewer(release.version, than: self.currentVersion) {
                self.available = release
                if interactive {
                    self.offer(release)
                } else if Settings.shared.skippedVersion != release.version {
                    self.notify(title: tr("Đã có Dokey ", "새 버전: Dokey ") + release.version,
                                body: tr("Bấm để xem có gì mới và cập nhật ngay trên máy.",
                                         "클릭하면 새 기능을 보고 바로 업데이트할 수 있습니다."),
                                action: true)
                }
            } else if interactive {
                self.reportNothing(failed: release == nil)
            }
        }
    }

    /// Shows the update dialog for the release found by the last check.
    func showAvailable() {
        if let release = available { offer(release) } else { check(interactive: true) }
    }

    // MARK: - Finding the latest release

    private func fetchLatest(_ done: @escaping (Release?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return done(nil) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Dokey/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { Self.parse($0) }
            DispatchQueue.main.async { done(release) }
        }.resume()
    }

    static func parse(_ data: Data) -> Release? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        var dmg: URL?, size = 0, sha: String?
        for asset in json["assets"] as? [[String: Any]] ?? [] {
            guard let name = asset["name"] as? String, name.hasPrefix("Dokey-"), name.hasSuffix(".dmg"),
                  let link = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)),
                  link.scheme == "https" else { continue }
            dmg = link
            size = asset["size"] as? Int ?? 0
            if let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") {
                sha = String(digest.dropFirst(7)).lowercased()
            }
        }
        return Release(version: version, notes: plainNotes(json["body"] as? String ?? ""),
                       page: page, dmg: dmg, size: size, sha256: sha)
    }

    /// Release notes are Markdown; the dialog shows them as plain text.
    private static func plainNotes(_ markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("<") || line.hasPrefix("![") { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty && (lines.last?.isEmpty ?? true) { continue }
            lines.append(line)
        }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 900 { text = String(text.prefix(900)) + "…" }
        return text
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

    private func notify(title: String, body: String, action: Bool) {
        if #available(macOS 10.14, *) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else {
                    // No notifications allowed: fall back to the dialog for a new version.
                    if action { DispatchQueue.main.async { self.showAvailable() } }
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                if action { content.categoryIdentifier = "update" }
                center.add(UNNotificationRequest(identifier: action ? "update" : "updated", content: content, trigger: nil))
            }
        } else {
            let note = NSUserNotification()
            note.title = title
            note.informativeText = body
            note.hasActionButton = action
            note.actionButtonTitle = tr("Cập nhật", "업데이트")
            note.userInfo = ["update": action]
            NSUserNotificationCenter.default.deliver(note)
        }
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = tr("Đã có Dokey ", "새 버전: Dokey ") + release.version
        var info = tr("Bạn đang dùng bản ", "현재 버전: ") + currentVersion + ".\n\n"
        if !release.notes.isEmpty { info += release.notes + "\n\n" }
        let canInstall = release.dmg != nil && installTarget != nil
        info += canInstall
            ? tr("Dokey sẽ tự tải bản mới, kiểm tra chữ ký, thay bản cũ rồi mở lại. Không cần tải hay cài đè bằng tay.",
                 "Dokey가 새 버전을 내려받아 서명을 확인하고, 기존 앱을 바꾼 뒤 다시 엽니다. 직접 내려받거나 설치할 필요가 없습니다.")
            : tr("Dokey không ghi được vào thư mục của ứng dụng, nên hãy tải bản mới từ trang Releases.",
                 "Dokey가 앱 폴더에 쓸 수 없으므로 Releases 페이지에서 새 버전을 내려받으세요.")
        alert.informativeText = info
        alert.addButton(withTitle: canInstall ? tr("Cập nhật ngay", "지금 업데이트") : tr("Mở trang Releases", "Releases 페이지 열기"))
        alert.addButton(withTitle: tr("Để sau", "나중에"))
        alert.addButton(withTitle: tr("Bỏ qua bản này", "이 버전 건너뛰기"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall { download(release) } else { NSWorkspace.shared.open(release.page) }
        case .alertThirdButtonReturn:
            Settings.shared.skippedVersion = release.version
        default:
            break
        }
    }

    private func reportNothing(failed: Bool) {
        let alert = NSAlert()
        if failed {
            alert.messageText = tr("Không kiểm tra được bản mới", "새 버전을 확인할 수 없습니다")
            alert.informativeText = tr("Không kết nối được GitHub. Hãy kiểm tra mạng rồi thử lại.",
                                       "GitHub에 연결할 수 없습니다. 네트워크를 확인한 뒤 다시 시도하세요.")
        } else {
            alert.messageText = tr("Bạn đang dùng bản mới nhất", "최신 버전을 사용하고 있습니다")
            alert.informativeText = "Dokey \(currentVersion)."
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func fail(_ message: String) {
        progressWindow?.close()
        progressWindow = nil
        downloading = nil
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Chưa cập nhật được Dokey", "Dokey를 업데이트하지 못했습니다")
        alert.informativeText = message + "\n\n" + tr("Bản đang dùng vẫn giữ nguyên.", "현재 버전은 그대로 유지됩니다.")
        alert.addButton(withTitle: tr("Mở trang Releases", "Releases 페이지 열기"))
        alert.addButton(withTitle: tr("Đóng", "닫기"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(repo)/releases/latest")!)
        }
    }

    // MARK: - Installing

    /// The app bundle to replace, when its folder is writable and it is not
    /// running from a disk image or a translocated copy.
    private var installTarget: URL? {
        let app = Bundle.main.bundleURL
        let path = app.path
        guard path.hasSuffix(".app"), !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else { return nil }
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path), fm.isWritableFile(atPath: path) else { return nil }
        return app
    }

    private func download(_ release: Release) {
        guard let url = release.dmg, downloading == nil else { return }
        downloading = release
        let window = UpdateProgressWindow(version: release.version)
        window.onCancel = { [weak self] in
            self?.session?.invalidateAndCancel()
            self?.session = nil
            self?.downloading = nil
            self?.progressWindow = nil
        }
        window.present()
        progressWindow = window
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: url).resume()
    }

    /// Mounts the downloaded disk image, checks the app inside and copies it
    /// next to the download. Runs off the main thread.
    private func stage(dmg: URL, release: Release, in work: URL) throws -> URL {
        if let expected = release.sha256, Self.sha256(of: dmg) != expected {
            throw UpdateError(tr("Tệp tải về không khớp mã SHA-256 của bản phát hành.", "내려받은 파일의 SHA-256이 릴리스와 다릅니다."))
        }
        if release.size > 0, let size = (try? dmg.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size != release.size {
            throw UpdateError(tr("Tệp tải về không đủ dung lượng.", "내려받은 파일 크기가 맞지 않습니다."))
        }
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) else {
            throw UpdateError(tr("Không mở được tệp .dmg.", ".dmg 파일을 열 수 없습니다."))
        }
        defer { _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        let mounted = mount.appendingPathComponent("Dokey.app")
        let info = NSDictionary(contentsOf: mounted.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let version = info?["CFBundleShortVersionString"] as? String, version == release.version else {
            throw UpdateError(tr("Trong tệp .dmg không có đúng bản Dokey ", ".dmg 안에 올바른 Dokey가 없습니다: ") + release.version + ".")
        }
        let staged = work.appendingPathComponent("Dokey.app")
        guard Self.run("/usr/bin/ditto", [mounted.path, staged.path]),
              Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]) else {
            throw UpdateError(tr("Chữ ký của bản mới không hợp lệ.", "새 버전의 서명이 올바르지 않습니다."))
        }
        _ = Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    /// Hands over to a small script that waits for this copy to quit, swaps
    /// the app (restoring the old one if anything fails) and opens the new one.
    private func swapAndRelaunch(staged: URL, target: URL, work: URL) {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        if mv "$3" "$4/old.app" && /usr/bin/ditto "$2" "$3"; then
            rm -rf "$4/old.app"
        else
            rm -rf "$3"; mv "$4/old.app" "$3"
        fi
        /usr/bin/open "$3"
        rm -rf "$4"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "dokey-update", String(getpid()), staged.path, target.path, work.path]
        do { try process.run() } catch {
            return fail(tr("Không chạy được bước thay ứng dụng.", "앱을 교체하는 단계를 실행할 수 없습니다."))
        }
        Settings.shared.updatedFrom = currentVersion
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { handle.closeFile() }
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            chunk.withUnsafeBytes { _ = CC_SHA256_Update(&context, $0.baseAddress, CC_LONG(chunk.count)) }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

// MARK: - Download progress

extension Updater: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(downloading?.size ?? 0)
        progressWindow?.show(received: totalBytesWritten, total: total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let release = downloading else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            return fail(tr("GitHub trả về lỗi ", "GitHub 오류 ") + "\(http.statusCode).")
        }
        // The downloaded file is removed when this method returns: keep it.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("dokey-update-\(UUID().uuidString)")
        let dmg = work.appendingPathComponent("Dokey.dmg")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: dmg)
        } catch {
            return fail(tr("Không lưu được tệp tải về.", "내려받은 파일을 저장할 수 없습니다."))
        }
        guard let target = installTarget else {
            return fail(tr("Dokey không ghi được vào thư mục của ứng dụng.", "Dokey가 앱 폴더에 쓸 수 없습니다."))
        }
        progressWindow?.showInstalling()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let staged = try self.stage(dmg: dmg, release: release, in: work)
                DispatchQueue.main.async { self.swapAndRelaunch(staged: staged, target: target, work: work) }
            } catch {
                try? FileManager.default.removeItem(at: work)
                let message = (error as? UpdateError)?.message ?? error.localizedDescription
                DispatchQueue.main.async { self.fail(message) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if self.session === session { self.session = nil }
        guard let error = error, downloading != nil else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        fail(tr("Không tải được bản mới: ", "새 버전을 내려받지 못했습니다: ") + error.localizedDescription)
    }
}

// MARK: - Notification clicks

@available(macOS 10.14, *)
extension Updater: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let isUpdate = response.notification.request.content.categoryIdentifier == "update"
        DispatchQueue.main.async { if isUpdate { self.showAvailable() } }
        completionHandler()
    }

    /// Dokey is a menu bar app and counts as "in front" more often than not: show banners anyway.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .sound])
    }
}

extension Updater: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if notification.userInfo?["update"] as? Bool == true { showAvailable() }
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        true
    }
}

/// A small window with a progress bar while the update downloads and installs.
final class UpdateProgressWindow: NSWindowController {
    private let status = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let cancel = NSButton(title: tr("Huỷ", "취소"), target: nil, action: nil)
    var onCancel: (() -> Void)?

    convenience init(version: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = tr("Cập nhật Dokey ", "Dokey 업데이트: ") + version
        window.isReleasedWhenClosed = false
        self.init(window: window)
        status.stringValue = tr("Đang tải Dokey ", "Dokey 내려받는 중: ") + version + "…"
        status.font = .systemFont(ofSize: 13)
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        cancel.target = self
        cancel.action = #selector(cancelPressed)
        cancel.bezelStyle = .rounded
        guard let content = window.contentView else { return }
        for view in [status, bar, cancel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            bar.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    func present() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    func show(received: Int64, total: Int64) {
        guard total > 0 else { bar.isIndeterminate = true; bar.startAnimation(nil); return }
        bar.doubleValue = Double(received) / Double(total)
        let mb = { (bytes: Int64) in String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        status.stringValue = tr("Đang tải: ", "내려받는 중: ") + mb(received) + " / " + mb(total)
    }

    func showInstalling() {
        status.stringValue = tr("Đang kiểm tra chữ ký và cài đặt… Dokey sẽ tự mở lại.",
                                "서명을 확인하고 설치하는 중… Dokey가 곧 다시 열립니다.")
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        cancel.isEnabled = false
    }

    @objc private func cancelPressed() {
        onCancel?()
        close()
    }
}
