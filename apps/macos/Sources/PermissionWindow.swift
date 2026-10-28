// Dokey for macOS - guide for granting Accessibility permission.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Dokey to the Accessibility list.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

final class PermissionWindowController: NSWindowController {
    private let statusLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    /// Called once permission is granted.
    var onGranted: (() -> Void)?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Cấp quyền Trợ năng cho Dokey"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildContent()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: "Dokey cần quyền Trợ năng để gõ tiếng Việt")
        title.font = .boldSystemFont(ofSize: 15)

        let steps = NSTextField(wrappingLabelWithString: """
        macOS chỉ cho phép bộ gõ đọc và sửa phím khi được cấp quyền Trợ năng (Accessibility). \
        Dokey không ghi lại, không lưu và không gửi phím gõ đi đâu.

        1. Bấm “Mở Cài đặt Trợ năng” bên dưới.
        2. Trong danh sách, bật công tắc cạnh Dokey. Nếu chưa có Dokey, bấm dấu + và chọn Dokey.app trong thư mục Applications.
        3. Quay lại đây. Dokey tự nhận quyền, không cần khởi động lại.

        Nếu bạn vừa cập nhật Dokey mà gõ không ra dấu: xoá Dokey khỏi danh sách (dấu −) rồi thêm lại. \
        Mỗi bản dựng mới có chữ ký khác nên macOS coi là ứng dụng mới.
        """)
        steps.font = .systemFont(ofSize: 13)

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let openButton = NSButton(title: "Mở Cài đặt Trợ năng", target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        let laterButton = NSButton(title: "Để sau", target: self, action: #selector(closeWindow))
        laterButton.bezelStyle = .rounded

        for view in [icon, title, steps, statusLabel, openButton, laterButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),

            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 16),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            steps.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            steps.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            steps.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            openButton.topAnchor.constraint(greaterThanOrEqualTo: steps.bottomAnchor, constant: 16),
            openButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            openButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            laterButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            laterButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
        ])
    }

    func present() {
        refresh()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        if Accessibility.isTrusted {
            statusLabel.stringValue = "✓ Đã có quyền. Bạn có thể bắt đầu gõ."
            statusLabel.textColor = .systemGreen
            timer?.invalidate()
            timer = nil
            onGranted?()
        } else {
            statusLabel.stringValue = "Chưa có quyền Trợ năng."
            statusLabel.textColor = .systemOrange
        }
    }

    @objc private func openSettings() {
        Accessibility.prompt()
        Accessibility.openSettings()
    }

    @objc private func closeWindow() {
        timer?.invalidate()
        timer = nil
        close()
    }
}
