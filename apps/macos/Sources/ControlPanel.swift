// Dokey for macOS - the control panel window shown when the app is opened.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

protocol ControlPanelDelegate: AnyObject {
    func panelToggleMode()
    /// Settings changed in the panel: apply them to the engine and the tap.
    func panelSettingsChanged()
    func panelShowPermission()
    var panelFrontApp: (name: String, kind: AppKind)? { get }
    var panelTapRunning: Bool { get }
}

final class ControlPanelController: NSWindowController, NSWindowDelegate {
    weak var delegate: ControlPanelDelegate?
    var onClose: (() -> Void)?

    private let settings = Settings.shared
    private let content = NSView()
    private var pages: [NSView] = []
    private var sidebarButtons: [SidebarButton] = []

    // Dashboard
    private let power = PowerButton()
    private let modeTitle = label("", size: 24, weight: .bold)
    private let modeSubtitle = label("", size: 13, color: Palette.secondaryText)
    private let permissionValue = label("", size: 14, weight: .semibold)
    private let permissionButton = AccentButton(title: "Cấp quyền")
    private let appValue = label("", size: 14, weight: .semibold)
    private let appDetail = label("", size: 11, color: Palette.secondaryText)
    private let methodValue = label("", size: 14, weight: .semibold)
    private let methodDetail = label("", size: 11, color: Palette.secondaryText)

    // Typing
    private let methodPicker = PillPicker(options: ["Telex", "VNI"])
    private let encodingPicker = PillPicker(options: ["Dựng sẵn", "Tổ hợp"])
    private let spellingSwitch = ToggleSwitch()
    private let toneSwitch = ToggleSwitch()
    private let hotkeyPopup = NSPopUpButton()
    private let examples = label("", size: 12, color: Palette.secondaryText, wrapping: true)

    // Apps
    private let perAppSwitch = ToggleSwitch()
    private let slowSwitch = ToggleSwitch()
    private let loginSwitch = ToggleSwitch()
    private let currentAppLine = label("", size: 12, color: Palette.secondaryText, wrapping: true)

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Dokey"
        if #available(macOS 10.14, *) {
            window.appearance = NSAppearance(named: .darkAqua)
        } else {
            window.appearance = NSAppearance(named: .vibrantDark)
        }
        self.init(window: window)
        window.delegate = self
        build()
    }

    // MARK: - Layout

    private func build() {
        guard let window = window else { return }
        let background = GradientView()
        background.colors = [Palette.backgroundTop, Palette.backgroundMiddle, Palette.backgroundBottom]
        window.contentView = background

        let sidebar = GradientView()
        sidebar.colors = [NSColor(white: 0, alpha: 0.30), NSColor(white: 0, alpha: 0.18)]
        sidebar.angle = -90
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor

        for view in [sidebar, divider, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: background.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: background.topAnchor),
            divider.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            content.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        buildSidebar(in: sidebar)

        pages = [dashboardPage(), typingPage(), appsPage(), aboutPage()]
        for page in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
                page.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
                page.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
                page.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            ])
        }
        select(page: 0)
    }

    private func buildSidebar(in sidebar: NSView) {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = label("Dokey", size: 17, weight: .bold)
        let version = label("Phiên bản \(Self.version)", size: 11, color: Palette.secondaryText)
        let titles = [("Bảng điều khiển", "◉"), ("Kiểu gõ", "Aa"), ("Ứng dụng", "▦"), ("Giới thiệu", "ⓘ")]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        for (i, item) in titles.enumerated() {
            let b = SidebarButton(title: item.0, glyph: item.1)
            b.tag = i
            b.target = self
            b.action = #selector(sidebarClicked(_:))
            sidebarButtons.append(b)
            stack.addArrangedSubview(b)
            b.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let footer = label("© 2026 Do Huy Toan", size: 10, color: NSColor(white: 1, alpha: 0.4))

        for view in [icon, name, version, stack, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 44),
            icon.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.topAnchor.constraint(equalTo: icon.topAnchor, constant: 3),
            version.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            version.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            stack.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16),
        ])
    }

    private func vertical(_ views: [NSView], spacing: CGFloat = 14, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    /// A card holding rows of "title + explanation ... control".
    private func settingsCard(_ rows: [(String, String, NSView)]) -> CardView {
        let card = CardView()
        let stack = vertical([], spacing: 0)
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let line = NSView()
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            let text = vertical([label(row.0, size: 13, weight: .semibold),
                                 label(row.1, size: 11, color: Palette.secondaryText)], spacing: 2)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [text, spacer, row.2])
            line.orientation = .horizontal
            line.alignment = .centerY
            line.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
        ])
        return card
    }

    private func pageHeader(_ title: String, _ subtitle: String) -> NSView {
        vertical([label(title, size: 26, weight: .bold), label(subtitle, size: 13, color: Palette.secondaryText)], spacing: 4)
    }

    private func fullWidth(_ views: [NSView], in stack: NSStackView) {
        for v in views { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    // MARK: - Pages

    private func dashboardPage() -> NSView {
        power.target = self
        power.action = #selector(powerClicked)
        power.widthAnchor.constraint(equalToConstant: 190).isActive = true
        power.heightAnchor.constraint(equalToConstant: 190).isActive = true

        permissionButton.target = self
        permissionButton.action = #selector(permissionClicked)

        func statusCard(_ caption: String, _ value: NSTextField, _ detail: NSView) -> CardView {
            let card = CardView()
            let stack = vertical([label(caption, size: 11, weight: .semibold, color: Palette.secondaryText),
                                  value, detail], spacing: 6)
            stack.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
                card.heightAnchor.constraint(equalToConstant: 112),
            ])
            return card
        }
        let cards = NSStackView(views: [
            statusCard("Quyền Trợ năng", permissionValue, permissionButton),
            statusCard("Ứng dụng đang dùng", appValue, appDetail),
            statusCard("Kiểu gõ", methodValue, methodDetail),
        ])
        cards.orientation = .horizontal
        cards.distribution = .fillEqually
        cards.spacing = 12

        let hero = vertical([power, modeTitle, modeSubtitle], spacing: 8, alignment: .centerX)
        let page = vertical([hero, cards], spacing: 26, alignment: .centerX)
        cards.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        return page
    }

    private func typingPage() -> NSView {
        methodPicker.target = self
        methodPicker.action = #selector(methodChanged)
        encodingPicker.target = self
        encodingPicker.action = #selector(encodingChanged)
        encodingPicker.widthAnchor.constraint(equalToConstant: 170).isActive = true
        spellingSwitch.target = self
        spellingSwitch.action = #selector(spellingChanged)
        toneSwitch.target = self
        toneSwitch.action = #selector(toneChanged)
        hotkeyPopup.removeAllItems()
        for hotkey in SwitchHotkey.allCases { hotkeyPopup.addItem(withTitle: hotkey.title) }
        hotkeyPopup.target = self
        hotkeyPopup.action = #selector(hotkeyChanged)
        hotkeyPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let card = settingsCard([
            ("Kiểu gõ", "Cách gõ dấu bằng chữ cái (Telex) hoặc chữ số (VNI)", methodPicker),
            ("Bảng mã", "Dựng sẵn hợp với mọi ứng dụng; tổ hợp tách riêng dấu thanh", encodingPicker),
            ("Kiểm tra chính tả", "Giữ nguyên từ không phải tiếng Việt: windows, chrome…", spellingSwitch),
            ("Đặt dấu kiểu mới", "Bật: hoà, khoẻ, thuý · Tắt: hòa, khỏe, thúy", toneSwitch),
            ("Phím chuyển Anh/Việt", "Dùng được ở mọi ứng dụng", hotkeyPopup),
        ])
        let exampleCard = CardView()
        examples.translatesAutoresizingMaskIntoConstraints = false
        exampleCard.addSubview(examples)
        NSLayoutConstraint.activate([
            examples.leadingAnchor.constraint(equalTo: exampleCard.leadingAnchor, constant: 18),
            examples.trailingAnchor.constraint(equalTo: exampleCard.trailingAnchor, constant: -18),
            examples.topAnchor.constraint(equalTo: exampleCard.topAnchor, constant: 12),
            examples.bottomAnchor.constraint(equalTo: exampleCard.bottomAnchor, constant: -12),
        ])
        let page = vertical([pageHeader("Kiểu gõ", "Chọn cách gõ và cách Dokey xử lý chữ."), card, exampleCard], spacing: 16)
        fullWidth([card, exampleCard], in: page)
        return page
    }

    private func appsPage() -> NSView {
        perAppSwitch.target = self
        perAppSwitch.action = #selector(perAppChanged)
        slowSwitch.target = self
        slowSwitch.action = #selector(slowChanged)
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged)

        let card = settingsCard([
            ("Nhớ chế độ theo ứng dụng", "Mỗi ứng dụng giữ chế độ Anh/Việt của riêng nó", perAppSwitch),
            ("Tương thích máy chậm", "Gửi phím chậm hơn trong Chrome, Edge, Claude, VS Code…", slowSwitch),
            ("Khởi động cùng macOS", "Tự chạy Dokey khi đăng nhập", loginSwitch),
        ])
        let info = CardView()
        let infoText = vertical([
            label("Dokey tự nhận biết ứng dụng", size: 13, weight: .semibold),
            label("""
            • Trình duyệt (Chrome, Edge, Cốc Cốc, Brave, Arc, Firefox) và \
            ứng dụng Electron/IDE (Claude, VS Code, Slack, Zalo…): Dokey bôi đen chữ cũ rồi gõ đè, \
            gửi từng ký tự và nghỉ rất ngắn giữa các phím, để không mất hay lặp chữ.
            • Ứng dụng thường (TextEdit, Notes, Pages, Terminal…): gửi Backspace và chữ mới ngay.
            """, size: 12, color: Palette.secondaryText, wrapping: true),
            currentAppLine,
        ], spacing: 8)
        infoText.translatesAutoresizingMaskIntoConstraints = false
        info.addSubview(infoText)
        NSLayoutConstraint.activate([
            infoText.leadingAnchor.constraint(equalTo: info.leadingAnchor, constant: 18),
            infoText.trailingAnchor.constraint(equalTo: info.trailingAnchor, constant: -18),
            infoText.topAnchor.constraint(equalTo: info.topAnchor, constant: 14),
            infoText.bottomAnchor.constraint(equalTo: info.bottomAnchor, constant: -14),
        ])
        let page = vertical([pageHeader("Ứng dụng", "Dokey làm việc thế nào với từng ứng dụng."), card, info], spacing: 16)
        fullWidth([card, info], in: page)
        return page
    }

    private func aboutPage() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 112).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let text = label("""
        Bộ gõ tiếng Việt cho macOS, chạy trên lõi Dokey Core.
        Mỗi phím, Dokey dựng lại cả từ và kiểm tra chính tả với 3.759 âm tiết,
        nên gõ đúng ngay lần đầu và giữ nguyên các từ tiếng Anh.
        """, size: 13, color: Palette.secondaryText, wrapping: true)
        text.alignment = .center
        let link = AccentButton(title: "Trang dự án trên GitHub")
        link.target = self
        link.action = #selector(openGitHub)
        let page = vertical([icon, label("Dokey", size: 30, weight: .bold),
                             label("Phiên bản \(Self.version)", size: 13, color: Palette.secondaryText),
                             text, link,
                             label("© 2026 Do Huy Toan. All rights reserved.", size: 11, color: NSColor(white: 1, alpha: 0.45))],
                            spacing: 10, alignment: .centerX)
        page.setCustomSpacing(18, after: text)
        text.widthAnchor.constraint(equalTo: page.widthAnchor, multiplier: 0.85).isActive = true
        return page
    }

    // MARK: - State

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func refresh() {
        guard isWindowLoaded else { return }
        let vietnamese = settings.vietnamese
        power.isOn = vietnamese
        modeTitle.stringValue = vietnamese ? "Đang gõ tiếng Việt" : "Đang gõ tiếng Anh"
        modeSubtitle.stringValue = "Bấm vào nút tròn hoặc \(settings.hotkey.shortTitle) để chuyển"

        let ready = Accessibility.isTrusted && (delegate?.panelTapRunning ?? false)
        permissionValue.stringValue = ready ? "✓ Đã sẵn sàng" : "Chưa có quyền"
        permissionValue.textColor = ready ? Palette.accentStart : Palette.warning
        permissionButton.isHidden = ready

        if let app = delegate?.panelFrontApp {
            appValue.stringValue = app.name
            appDetail.stringValue = "Nhóm: \(app.kind.title)"
            currentAppLine.stringValue = "Ứng dụng vừa dùng: \(app.name) (\(app.kind.title))."
        } else {
            appValue.stringValue = "—"
            appDetail.stringValue = ""
            currentAppLine.stringValue = ""
        }

        let vni = settings.method == Int32(DOKEY_VNI)
        let combining = settings.encoding == Int32(DOKEY_UNICODE_COMBINING)
        methodValue.stringValue = vni ? "VNI" : "Telex"
        methodDetail.stringValue = combining ? "Unicode tổ hợp" : "Unicode dựng sẵn"
        methodPicker.selectedIndex = vni ? 1 : 0
        encodingPicker.selectedIndex = combining ? 1 : 0
        spellingSwitch.isOn = settings.checkSpelling
        toneSwitch.isOn = settings.modernToneStyle
        hotkeyPopup.selectItem(at: settings.hotkey.rawValue)
        examples.stringValue = vni
            ? "Ví dụ VNI:  Vie65t Nam → Việt Nam   ·   d9u7o7ng2 → đường   ·   1 2 3 4 5 = sắc huyền hỏi ngã nặng, 6 = mũ, 7 = móc, 8 = trăng, 9 = đ"
            : "Ví dụ Telex:  Vieetj Nam → Việt Nam   ·   dduowngf → đường   ·   s f r x j = sắc huyền hỏi ngã nặng, aa ee oo = â ê ô, aw ow uw = ă ơ ư, dd = đ"

        perAppSwitch.isOn = settings.rememberModePerApp
        slowSwitch.isOn = settings.slowMachineMode
        loginSwitch.isOn = LoginItem.isEnabled
    }

    func present() {
        refresh()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func showPage(_ index: Int) { select(page: index) }

    private func select(page index: Int) {
        for (i, page) in pages.enumerated() { page.isHidden = i != index }
        for (i, b) in sidebarButtons.enumerated() { b.isSelected = i == index }
    }

    // MARK: - Actions

    @objc private func sidebarClicked(_ sender: SidebarButton) { select(page: sender.tag) }

    @objc private func powerClicked() {
        delegate?.panelToggleMode()
        refresh()
    }

    @objc private func permissionClicked() { delegate?.panelShowPermission() }

    @objc private func methodChanged() {
        settings.method = methodPicker.selectedIndex == 1 ? Int32(DOKEY_VNI) : Int32(DOKEY_TELEX)
        changed()
    }

    @objc private func encodingChanged() {
        settings.encoding = encodingPicker.selectedIndex == 1 ? Int32(DOKEY_UNICODE_COMBINING) : Int32(DOKEY_UNICODE)
        changed()
    }

    @objc private func spellingChanged() {
        settings.checkSpelling = spellingSwitch.isOn
        changed()
    }

    @objc private func toneChanged() {
        settings.modernToneStyle = toneSwitch.isOn
        changed()
    }

    @objc private func hotkeyChanged() {
        settings.hotkey = SwitchHotkey(rawValue: hotkeyPopup.indexOfSelectedItem) ?? .controlShift
        changed()
    }

    @objc private func perAppChanged() {
        settings.rememberModePerApp = perAppSwitch.isOn
        changed()
    }

    @objc private func slowChanged() {
        settings.slowMachineMode = slowSwitch.isOn
        changed()
    }

    @objc private func loginChanged() {
        if let error = LoginItem.setEnabled(loginSwitch.isOn) {
            let alert = NSAlert()
            alert.messageText = "Không đổi được mục khởi động cùng macOS"
            alert.informativeText = error
            if let window = window { alert.beginSheetModal(for: window) }
        }
        refresh()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/dhtoan/Dokey")!)
    }

    private func changed() {
        delegate?.panelSettingsChanged()
        refresh()
    }
}
