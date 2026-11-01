// Dokey for macOS - the control panel window shown when the app is opened.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

protocol ControlPanelDelegate: AnyObject {
    func panelToggleMode()
    /// Settings changed in the panel: apply them to the engine and the tap.
    func panelSettingsChanged()
    func panelShowPermission()
    var panelFrontApp: (name: String, kind: AppKind, icon: NSImage?)? { get }
    var panelTapRunning: Bool { get }
    /// Words Dokey has added marks to since it started.
    var panelEditCount: Int { get }
}

/// A compact glass card: emblem on the left, then caption, value and status,
/// with an optional button on the right.
final class StatCard: GlassCard {
    let caption = label("", size: 12, weight: .medium, color: Palette.secondaryText)
    let value = label("", size: 22, weight: .bold)
    let status = label("", size: 12, weight: .medium, color: Palette.success)
    let badge: GlossyBadge
    private let accessory = NSStackView()

    init(caption text: String, badge: GlossyBadge, badgeSize: CGFloat, valueSize: CGFloat = 22) {
        self.badge = badge
        super.init(frame: .zero)
        caption.stringValue = text
        value.font = .systemFont(ofSize: valueSize, weight: .bold)
        value.lineBreakMode = .byTruncatingTail
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accessory.orientation = .horizontal
        let text = NSStackView(views: [caption, value, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setCustomSpacing(4, after: value)
        for v in [badge, text, accessory] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -10),
            accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            accessory.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setAccessory(_ view: NSView?) {
        accessory.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let view = view { accessory.addArrangedSubview(view) }
    }

    func setStatus(_ text: String, ok: Bool) {
        status.stringValue = (ok ? "✓  " : "●  ") + text
        status.textColor = ok ? Palette.success : Palette.warning
    }
}

final class ControlPanelController: NSWindowController, NSWindowDelegate {
    weak var delegate: ControlPanelDelegate?
    var onClose: (() -> Void)?
    /// Screenshots only: show the panel as if Accessibility were granted.
    var assumeReady = false

    private let settings = Settings.shared
    private let content = NSView()
    private let pageTitle = label("", size: 13, weight: .semibold, color: NSColor(white: 1, alpha: 0.85))
    private var pages: [NSView] = []
    private var sidebarButtons: [SidebarButton] = []
    private let titles = ["Bảng điều khiển", "Kiểu gõ", "Ứng dụng", "Giới thiệu"]
    private let orb = OrbButton()
    private var timer: Timer?

    // Dashboard
    private let modeCard = StatCard(caption: "Chế độ gõ",
                                    badge: GlossyBadge(shape: .squircle, top: NSColor(red: 0.98, green: 0.45, blue: 0.86, alpha: 1),
                                                       bottom: NSColor(red: 0.62, green: 0.16, blue: 0.80, alpha: 1), symbol: .text("V")),
                                    badgeSize: 96, valueSize: 28)
    private let permissionCard = StatCard(caption: "Quyền Trợ năng",
                                          badge: GlossyBadge(shape: .shield, top: NSColor(red: 0.40, green: 0.92, blue: 0.62, alpha: 1),
                                                             bottom: NSColor(red: 0.05, green: 0.55, blue: 0.40, alpha: 1), symbol: .check),
                                          badgeSize: 80)
    private let methodCard = StatCard(caption: "Kiểu gõ",
                                      badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1),
                                                         bottom: NSColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1), symbol: .keycap),
                                      badgeSize: 60, valueSize: 19)
    private let appCard = StatCard(caption: "Ứng dụng",
                                   badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1),
                                                      bottom: NSColor(red: 0.18, green: 0.25, blue: 0.85, alpha: 1), symbol: .grid),
                                   badgeSize: 60, valueSize: 19)
    private let countCard = StatCard(caption: "Đã thêm dấu",
                                     badge: GlossyBadge(shape: .circle, top: NSColor(red: 0.35, green: 0.95, blue: 0.90, alpha: 1),
                                                        bottom: NSColor(red: 0.05, green: 0.55, blue: 0.70, alpha: 1), symbol: .bolt),
                                     badgeSize: 60, valueSize: 19)
    private let permissionButton = AccentButton(title: "Cấp quyền")
    private let tryField = NSTextField(string: "")

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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 500),
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
        background.wantsLayer = true
        window.contentView = background

        let sidebar = GradientView()
        sidebar.glows = false
        sidebar.colors = [NSColor(white: 0, alpha: 0.22), NSColor(white: 0, alpha: 0.10)]
        sidebar.angle = -90

        orb.target = self
        orb.action = #selector(orbClicked)

        for view in [sidebar, content, pageTitle, orb] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: background.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 68),
            pageTitle.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            pageTitle.topAnchor.constraint(equalTo: background.topAnchor, constant: 7),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: background.topAnchor, constant: 44),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
            orb.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            orb.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
            orb.widthAnchor.constraint(equalToConstant: 100),
            orb.heightAnchor.constraint(equalToConstant: 100),
        ])
        buildSidebar(in: sidebar)

        pages = [dashboardPage(), typingPage(), appsPage(), aboutPage()]
        for page in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                page.topAnchor.constraint(equalTo: content.topAnchor),
                page.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            ])
        }
        select(page: 0, animated: false)
    }

    private func buildSidebar(in sidebar: NSView) {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        let icons: [SidebarButton.Icon] = [.dashboard, .keyboard, .apps, .info]
        for (i, kind) in icons.enumerated() {
            let b = SidebarButton(icon: kind, tooltip: titles[i])
            b.tag = i
            b.target = self
            b.action = #selector(sidebarClicked(_:))
            sidebarButtons.append(b)
            stack.addArrangedSubview(b)
        }
        for view in [icon, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 40),
            icon.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            stack.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 22),
            stack.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
        ])
    }

    private func vertical(_ views: [NSView], spacing: CGFloat = 14,
                          alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    private func horizontal(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = spacing
        return stack
    }

    /// A page header card: big title and subtitle with a glossy emblem.
    private func heroCard(_ title: String, _ subtitle: String, badge: GlossyBadge) -> GlassCard {
        let card = GlassCard()
        let text = vertical([label(title, size: 22, weight: .bold),
                             label(subtitle, size: 13, color: Palette.secondaryText)], spacing: 4)
        for v in [badge, text] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 88),
            badge.widthAnchor.constraint(equalToConstant: 80),
            badge.heightAnchor.constraint(equalToConstant: 80),
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 6),
            text.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    /// A glass card holding rows of "title + explanation ... control".
    private func settingsCard(_ rows: [(String, String, NSView)]) -> GlassCard {
        let card = GlassCard()
        let stack = vertical([], spacing: 0)
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let line = NSView()
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
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
            line.edgeInsets = NSEdgeInsets(top: 9, left: 18, bottom: 9, right: 18)
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -3),
        ])
        return card
    }

    private func fullWidth(_ views: [NSView], in stack: NSStackView) {
        for v in views { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    // MARK: - Pages

    private func dashboardPage() -> NSView {
        permissionButton.target = self
        permissionButton.action = #selector(permissionClicked)
        modeCard.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(orbClicked)))
        modeCard.toolTip = "Bấm để chuyển Anh/Việt"

        let top = horizontal([modeCard, permissionCard])
        let bottom = horizontal([methodCard, appCard, countCard])
        bottom.distribution = .fillEqually
        let page = vertical([top, bottom, tryCard()], spacing: 12)
        fullWidth(page.arrangedSubviews, in: page)
        NSLayoutConstraint.activate([
            modeCard.heightAnchor.constraint(equalToConstant: 112),
            permissionCard.heightAnchor.constraint(equalTo: modeCard.heightAnchor),
            modeCard.widthAnchor.constraint(equalTo: permissionCard.widthAnchor, multiplier: 1.25),
            methodCard.heightAnchor.constraint(equalToConstant: 92),
            appCard.heightAnchor.constraint(equalTo: methodCard.heightAnchor),
            countCard.heightAnchor.constraint(equalTo: methodCard.heightAnchor),
        ])
        return page
    }

    /// A place to try typing without leaving the panel.
    private func tryCard() -> GlassCard {
        let card = GlassCard()
        let caption = label("Gõ thử", size: 12, weight: .medium, color: Palette.secondaryText)
        tryField.placeholderString = "Gõ thử ở đây, ví dụ: Vieetj Nam, dduowngf, Haxy…"
        tryField.font = .systemFont(ofSize: 17, weight: .medium)
        tryField.textColor = .white
        tryField.isBordered = false
        tryField.drawsBackground = false
        tryField.focusRingType = .none
        let well = NSView()
        well.wantsLayer = true
        well.layer?.backgroundColor = NSColor(white: 0, alpha: 0.18).cgColor
        well.layer?.cornerRadius = 10
        for v in [caption, well, tryField] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 92),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            caption.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            well.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            well.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            well.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 8),
            well.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            tryField.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            tryField.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
            tryField.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])
        return card
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

        let hero = heroCard("Kiểu gõ", "Chọn cách gõ dấu và cách Dokey xử lý chữ.",
                            badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1),
                                               bottom: NSColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1), symbol: .keycap))
        let card = settingsCard([
            ("Kiểu gõ", "Gõ dấu bằng chữ cái (Telex) hoặc chữ số (VNI)", methodPicker),
            ("Bảng mã", "Dựng sẵn hợp với mọi ứng dụng; tổ hợp tách riêng dấu thanh", encodingPicker),
            ("Kiểm tra chính tả", "Giữ nguyên từ không phải tiếng Việt: windows, chrome…", spellingSwitch),
            ("Đặt dấu kiểu mới", "Bật: hoà, khoẻ, thuý · Tắt: hòa, khỏe, thúy", toneSwitch),
            ("Phím chuyển Anh/Việt", "Dùng được ở mọi ứng dụng", hotkeyPopup),
        ])
        let page = vertical([hero, card, examples], spacing: 12)
        fullWidth([hero, card, examples], in: page)
        return page
    }

    private func appsPage() -> NSView {
        perAppSwitch.target = self
        perAppSwitch.action = #selector(perAppChanged)
        slowSwitch.target = self
        slowSwitch.action = #selector(slowChanged)
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged)

        let hero = heroCard("Ứng dụng", "Dokey tự nhận biết trình duyệt, Electron và ứng dụng thường.",
                            badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1),
                                               bottom: NSColor(red: 0.18, green: 0.25, blue: 0.85, alpha: 1), symbol: .grid))
        let card = settingsCard([
            ("Nhớ chế độ theo ứng dụng", "Mỗi ứng dụng giữ chế độ Anh/Việt của riêng nó", perAppSwitch),
            ("Tương thích máy chậm", "Thêm 2 ms nghỉ trong Chrome, Edge, Claude, VS Code…", slowSwitch),
            ("Khởi động cùng macOS", "Tự chạy Dokey khi đăng nhập", loginSwitch),
        ])
        let note = label("""
        Trình duyệt và ứng dụng Electron/IDE (Claude, VS Code, Slack, Zalo…): Dokey bôi đen chữ cũ rồi gõ đè cả cụm chữ mới. \
        Ứng dụng thường (TextEdit, Notes, Terminal…): Dokey dùng Backspace.
        """, size: 12, color: Palette.secondaryText, wrapping: true)
        let page = vertical([hero, card, note, currentAppLine], spacing: 12)
        fullWidth([hero, card, note, currentAppLine], in: page)
        return page
    }

    private func aboutPage() -> NSView {
        let badge = GlossyBadge(shape: .squircle, top: NSColor(red: 0.98, green: 0.45, blue: 0.86, alpha: 1),
                                bottom: NSColor(red: 0.45, green: 0.20, blue: 0.95, alpha: 1), symbol: .text("đ"))
        badge.widthAnchor.constraint(equalToConstant: 112).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let text = label("""
        Bộ gõ tiếng Việt cho macOS, chạy trên lõi Dokey Core.
        Mỗi phím, Dokey dựng lại cả từ và kiểm tra chính tả với 3.759 âm tiết,
        nên gõ đúng ngay lần đầu và giữ nguyên các từ tiếng Anh.
        """, size: 13, color: Palette.secondaryText, wrapping: true)
        text.alignment = .center
        let link = AccentButton(title: "Trang dự án trên GitHub")
        link.target = self
        link.action = #selector(openGitHub)
        let legal = label("© 2026 Do Huy Toan (dhtoan). All rights reserved.\nPhần mềm độc quyền: cấm sao chép, sửa đổi, phân phối lại.",
                          size: 11, color: NSColor(white: 1, alpha: 0.45))
        legal.alignment = .center
        let page = vertical([badge, label("Dokey", size: 32, weight: .bold),
                             label("Phiên bản \(Self.version)", size: 13, color: Palette.secondaryText),
                             text, link,
                             legal],
                            spacing: 8, alignment: .centerX)
        page.setCustomSpacing(16, after: text)
        text.widthAnchor.constraint(equalTo: page.widthAnchor, multiplier: 0.8).isActive = true
        return page
    }

    // MARK: - State

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func refresh() {
        guard isWindowLoaded else { return }
        let vietnamese = settings.vietnamese
        orb.isLit = vietnamese
        orb.title = vietnamese ? "Tắt" : "Bật"
        orb.toolTip = vietnamese ? "Chuyển sang gõ tiếng Anh" : "Chuyển sang gõ tiếng Việt"
        modeCard.value.stringValue = vietnamese ? "Tiếng Việt" : "Tiếng Anh"
        modeCard.badge.symbol = .text(vietnamese ? "V" : "E")
        modeCard.setStatus(vietnamese ? "Đang bật · \(settings.hotkey.shortTitle) để chuyển" : "Đang tắt · \(settings.hotkey.shortTitle) để bật", ok: vietnamese)

        let ready = assumeReady || (Accessibility.isTrusted && (delegate?.panelTapRunning ?? false))
        permissionCard.value.stringValue = ready ? "Sẵn sàng" : "Chưa cấp"
        permissionCard.setStatus(ready ? "Dokey đang nghe bàn phím" : "Cần quyền để gõ tiếng Việt", ok: ready)
        permissionCard.setAccessory(ready ? nil : permissionButton)
        permissionCard.badge.symbol = ready ? .check : .text("!")
        permissionCard.badge.top = ready ? NSColor(red: 0.40, green: 0.92, blue: 0.62, alpha: 1)
                                         : NSColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 1)
        permissionCard.badge.bottom = ready ? NSColor(red: 0.05, green: 0.55, blue: 0.40, alpha: 1)
                                            : NSColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 1)

        let vni = settings.method == Int32(DOKEY_VNI)
        let combining = settings.encoding == Int32(DOKEY_UNICODE_COMBINING)
        methodCard.value.stringValue = vni ? "VNI" : "Telex"
        methodCard.setStatus(combining ? "Unicode tổ hợp" : "Unicode dựng sẵn", ok: true)

        if let app = delegate?.panelFrontApp {
            appCard.value.stringValue = app.name
            appCard.setStatus("Nhóm: \(app.kind.title)", ok: true)
            appCard.badge.symbol = app.icon.map { .image($0) } ?? .grid
            currentAppLine.stringValue = "Ứng dụng vừa dùng: \(app.name) (\(app.kind.title))."
        } else {
            appCard.value.stringValue = "—"
            appCard.setStatus("Chưa có", ok: false)
            appCard.badge.symbol = .grid
            currentAppLine.stringValue = ""
        }

        let count = delegate?.panelEditCount ?? 0
        countCard.value.stringValue = "\(Self.grouped(count)) từ"
        countCard.setStatus("từ lúc mở Dokey", ok: true)

        methodPicker.selectedIndex = vni ? 1 : 0
        encodingPicker.selectedIndex = combining ? 1 : 0
        spellingSwitch.isOn = settings.checkSpelling
        toneSwitch.isOn = settings.modernToneStyle
        hotkeyPopup.selectItem(at: settings.hotkey.rawValue)
        examples.stringValue = vni
            ? "Ví dụ VNI:  Vie65t Nam → Việt Nam   ·   d9u7o7ng2 → đường   ·   1–5 = sắc huyền hỏi ngã nặng, 6 = mũ, 7 = móc, 8 = trăng, 9 = đ"
            : "Ví dụ Telex:  Vieetj Nam → Việt Nam   ·   dduowngf → đường   ·   s f r x j = sắc huyền hỏi ngã nặng, aa ee oo = â ê ô, aw ow uw = ă ơ ư, dd = đ"

        perAppSwitch.isOn = settings.rememberModePerApp
        slowSwitch.isOn = settings.slowMachineMode
        loginSwitch.isOn = LoginItem.isEnabled
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    func present() {
        refresh()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        modeCard.badge.startFloating()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        onClose?()
    }

    func showPage(_ index: Int) { select(page: index, animated: false) }

    private func select(page index: Int, animated: Bool = true) {
        for (i, page) in pages.enumerated() { page.isHidden = i != index }
        for (i, b) in sidebarButtons.enumerated() { b.isSelected = i == index }
        pageTitle.stringValue = titles[index]
        orb.isHidden = index != 0
        guard let page = pages[safe: index] else { return }
        guard animated else {
            page.alphaValue = 1
            return
        }
        page.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            page.animator().alphaValue = 1
        }, completionHandler: nil)
    }

    // MARK: - Actions

    @objc private func sidebarClicked(_ sender: SidebarButton) { select(page: sender.tag) }

    @objc private func orbClicked() {
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

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
