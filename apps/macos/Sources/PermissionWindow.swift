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
        window.title = tr("Cấp quyền Trợ năng cho Dokey", "Dokey에 손쉬운 사용 권한 허용")
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildContent()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: tr("Dokey cần quyền Trợ năng để gõ", "Dokey가 입력하려면 손쉬운 사용 권한이 필요합니다"))
        title.font = .boldSystemFont(ofSize: 15)

        let steps = NSTextField(wrappingLabelWithString: tr("""
        macOS chỉ cho phép bộ gõ đọc và sửa phím khi được cấp quyền Trợ năng (Accessibility). \
        Dokey không ghi lại, không lưu và không gửi phím gõ đi đâu.

        1. Bấm “Mở Cài đặt Trợ năng” bên dưới.
        2. Trong danh sách, bật công tắc cạnh Dokey. Nếu chưa có Dokey, bấm dấu + và chọn Dokey.app trong thư mục Applications.
        3. Quay lại đây. Dokey tự nhận quyền, không cần khởi động lại.

        Nếu bạn vừa cập nhật Dokey mà gõ không ra dấu: xoá Dokey khỏi danh sách (dấu −) rồi thêm lại. \
        Mỗi bản dựng mới có chữ ký khác nên macOS coi là ứng dụng mới.
        """, """
        macOS에서는 손쉬운 사용(Accessibility) 권한이 있는 입력기만 키 입력을 읽고 고칠 수 있습니다. \
        Dokey는 입력한 키를 기록하거나 저장하거나 외부로 보내지 않습니다.

        1. 아래의 “손쉬운 사용 설정 열기”를 누르세요.
        2. 목록에서 Dokey 옆의 스위치를 켜세요. Dokey가 없으면 + 버튼을 눌러 응용 프로그램 폴더의 Dokey.app을 추가하세요.
        3. 이 창으로 돌아오세요. 다시 시작하지 않아도 Dokey가 권한을 바로 인식합니다.

        업데이트 후 입력이 되지 않으면 목록에서 Dokey를 지운 뒤(− 버튼) 다시 추가하세요. \
        새 빌드마다 서명이 달라 macOS가 새 앱으로 인식하기 때문입니다.
        """))
        steps.font = .systemFont(ofSize: 13)

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let openButton = NSButton(title: tr("Mở Cài đặt Trợ năng", "손쉬운 사용 설정 열기"), target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        let laterButton = NSButton(title: tr("Để sau", "나중에"), target: self, action: #selector(closeWindow))
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
            statusLabel.stringValue = tr("✓ Đã có quyền. Bạn có thể bắt đầu gõ.", "✓ 권한이 허용되었습니다. 바로 입력할 수 있습니다.")
            statusLabel.textColor = .systemGreen
            timer?.invalidate()
            timer = nil
            onGranted?()
        } else {
            statusLabel.stringValue = tr("Chưa có quyền Trợ năng.", "아직 손쉬운 사용 권한이 없습니다.")
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
