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
    func panelClearExcluded()
    func panelCheckUpdates()
    /// "vi" or "ko".
    func panelSetLanguage(_ code: String)
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
    private let titles = [tr("Bảng điều khiển", "제어판"), tr("Kiểu gõ", "입력 방식"), tr("Gõ nhanh", "빠른 입력"), tr("Ứng dụng", "앱"), tr("Giới thiệu", "정보")]
    private let orb = OrbButton()
    private var timer: Timer?

    // Dashboard
    private let modeCard = StatCard(caption: tr("Chế độ gõ", "입력 모드"),
                                    badge: GlossyBadge(shape: .squircle, top: NSColor(red: 0.98, green: 0.45, blue: 0.86, alpha: 1),
                                                       bottom: NSColor(red: 0.62, green: 0.16, blue: 0.80, alpha: 1), symbol: .text("V")),
                                    badgeSize: 96, valueSize: 28)
    private let permissionCard = StatCard(caption: tr("Quyền Trợ năng", "손쉬운 사용 권한"),
                                          badge: GlossyBadge(shape: .shield, top: NSColor(red: 0.40, green: 0.92, blue: 0.62, alpha: 1),
                                                             bottom: NSColor(red: 0.05, green: 0.55, blue: 0.40, alpha: 1), symbol: .check),
                                          badgeSize: 80)
    private let methodCard = StatCard(caption: tr("Kiểu gõ", "입력 방식"),
                                      badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1),
                                                         bottom: NSColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1), symbol: .keycap),
                                      badgeSize: 60, valueSize: 19)
    private let appCard = StatCard(caption: tr("Ứng dụng", "앱"),
                                   badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1),
                                                      bottom: NSColor(red: 0.18, green: 0.25, blue: 0.85, alpha: 1), symbol: .grid),
                                   badgeSize: 60, valueSize: 19)
    private let countCard = StatCard(caption: tr("Đã thêm dấu", "변환한 단어"),
                                     badge: GlossyBadge(shape: .circle, top: NSColor(red: 0.35, green: 0.95, blue: 0.90, alpha: 1),
                                                        bottom: NSColor(red: 0.05, green: 0.55, blue: 0.70, alpha: 1), symbol: .bolt),
                                     badgeSize: 60, valueSize: 19)
    private let permissionButton = AccentButton(title: tr("Cấp quyền", "권한 허용"))
    private let tryField = NSTextField(string: "")

    // Typing
    private let languagePicker = PillPicker(options: ["Tiếng Việt", "한국어"])
    private let methodPicker = PillPicker(options: ["Telex", "VNI"])
    private let encodingPicker = PillPicker(options: [tr("Dựng sẵn", "완성형"), tr("Tổ hợp", "조합형")])
    private let spellingSwitch = ToggleSwitch()
    private let toneSwitch = ToggleSwitch()
    private let hotkeyPopup = NSPopUpButton()
    private let examples = label("", size: 12, color: Palette.secondaryText, wrapping: true)

    // Quick typing
    private let quickTelexSwitch = ToggleSwitch()
    private let escSwitch = ToggleSwitch()
    private let macroSwitch = ToggleSwitch()
    private let macroSummary = label("", size: 12, color: Palette.secondaryText, wrapping: true)
    private var macroEditor: MacroEditorController?

    // Apps
    private let excludedValue = label("", size: 12, weight: .medium, color: Palette.secondaryText)
    private let perAppSwitch = ToggleSwitch()
    private let slowSwitch = ToggleSwitch()
    private let loginSwitch = ToggleSwitch()
    private let updateSwitch = ToggleSwitch()
    private let updateButton = AccentButton(title: tr("Kiểm tra cập nhật", "업데이트 확인"))
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

        pages = [dashboardPage(), typingPage(), quickPage(), appsPage(), aboutPage()]
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
        let icons: [SidebarButton.Icon] = [.dashboard, .keyboard, .bolt, .apps, .info]
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
        modeCard.toolTip = tr("Bấm để chuyển Anh/Việt", "클릭하여 입력 언어 전환")

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
        let caption = label(tr("Gõ thử", "입력해 보기"), size: 12, weight: .medium, color: Palette.secondaryText)
        updatePlaceholder()
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
        languagePicker.target = self
        languagePicker.action = #selector(languageChanged)
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

        let hero = heroCard(tr("Kiểu gõ", "입력 방식"), tr("Chọn cách gõ dấu và cách Dokey xử lý chữ.", "입력 언어와 입력 방식을 고르세요."),
                            badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1),
                                               bottom: NSColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1), symbol: .keycap))
        let card = settingsCard([
            (tr("Ngôn ngữ gõ", "입력 언어"), tr("Tiếng Hàn dùng bàn phím 2-beolsik (두벌식)", "한국어는 두벌식 자판, 베트남어는 Telex·VNI"), languagePicker),
            (tr("Kiểu gõ", "입력 방식"), tr("Gõ dấu bằng chữ cái (Telex) hoặc chữ số (VNI)", "베트남어 성조를 글자(Telex) 또는 숫자(VNI)로 입력"), methodPicker),
            (tr("Bảng mã", "인코딩"), tr("Dựng sẵn hợp với mọi ứng dụng; tổ hợp tách riêng dấu thanh", "완성형은 모든 앱과 호환, 조합형은 성조 부호를 분리"), encodingPicker),
            (tr("Kiểm tra chính tả", "맞춤법 검사"), tr("Giữ nguyên từ không phải tiếng Việt: windows, chrome…", "베트남어가 아닌 단어는 그대로: windows, chrome…"), spellingSwitch),
            (tr("Đặt dấu kiểu mới", "새 성조 위치"), tr("Bật: hoà, khoẻ, thuý · Tắt: hòa, khỏe, thúy", "켜기: hoà, khoẻ, thuý · 끄기: hòa, khỏe, thúy"), toneSwitch),
            (tr("Phím chuyển Anh/Việt", "입력 전환 단축키"), tr("Dùng được ở mọi ứng dụng", "모든 앱에서 사용"), hotkeyPopup),
        ])
        let page = vertical([hero, card, examples], spacing: 12)
        fullWidth([hero, card, examples], in: page)
        return page
    }

    private func quickPage() -> NSView {
        quickTelexSwitch.target = self
        quickTelexSwitch.action = #selector(quickTelexChanged)
        escSwitch.target = self
        escSwitch.action = #selector(escChanged)
        macroSwitch.target = self
        macroSwitch.action = #selector(macrosChanged)
        let edit = AccentButton(title: tr("Sửa danh sách…", "목록 편집…"))
        edit.target = self
        edit.action = #selector(editMacros)
        let macroControls = NSStackView(views: [edit, macroSwitch])
        macroControls.spacing = 12

        let hero = heroCard(tr("Gõ nhanh", "빠른 입력"), tr("Gõ tắt, Quick Telex và hoàn tác bằng Esc.", "단축어, Quick Telex, Esc로 되돌리기 (베트남어)."),
                            badge: GlossyBadge(shape: .circle, top: NSColor(red: 0.35, green: 0.95, blue: 0.90, alpha: 1),
                                               bottom: NSColor(red: 0.05, green: 0.55, blue: 0.70, alpha: 1), symbol: .bolt))
        let card = settingsCard([
            (tr("Gõ tắt", "단축어"), tr("Gõ từ tắt rồi dấu cách: vn → Việt Nam, ko → không", "단축어를 입력하고 스페이스: vn → Việt Nam, ko → không"), macroControls),
            ("Quick Telex", tr("cc → ch, gg → gi, kk → kh, nn → ng, pp → ph, qq → qu, tt → th (đầu từ)", "단어 첫머리에서 cc → ch, gg → gi, kk → kh, nn → ng, pp → ph, qq → qu, tt → th"), quickTelexSwitch),
            (tr("Hoàn tác bằng Esc", "Esc로 되돌리기"), tr("Bấm Esc khi đang gõ để trả từ về đúng phím đã gõ: tiếng → tieesng", "입력 중 Esc를 누르면 입력한 키 그대로 되돌립니다: tiếng → tieesng"), escSwitch),
        ])
        let tips = label(tr("""
        Mẹo: gõ "xin", dấu cách rồi Backspace là quay lại sửa dấu từ đó ("f" ra "xìn"). Xoá phụ âm cuối thì dấu thanh tự về đúng chỗ.
        """, """
        단축어, Quick Telex, Esc 되돌리기는 베트남어 입력에 적용됩니다. 한국어는 Backspace로 자모 단위로 지웁니다 (한 ⌫ → 하).
        """), size: 12, color: Palette.secondaryText, wrapping: true)
        let page = vertical([hero, card, macroSummary, tips], spacing: 12)
        fullWidth([hero, card, macroSummary, tips], in: page)
        return page
    }

    private func appsPage() -> NSView {
        perAppSwitch.target = self
        perAppSwitch.action = #selector(perAppChanged)
        slowSwitch.target = self
        slowSwitch.action = #selector(slowChanged)
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged)
        updateSwitch.target = self
        updateSwitch.action = #selector(updateChanged)

        let hero = heroCard(tr("Ứng dụng", "앱"), tr("Dokey tự nhận biết trình duyệt, Electron và ứng dụng thường.", "Dokey가 브라우저, Electron 앱, 일반 앱을 자동으로 구분합니다."),
                            badge: GlossyBadge(shape: .hexagon, top: NSColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1),
                                               bottom: NSColor(red: 0.18, green: 0.25, blue: 0.85, alpha: 1), symbol: .grid))
        let card = settingsCard([
            (tr("Nhớ chế độ theo ứng dụng", "앱별 모드 기억"), tr("Mỗi ứng dụng giữ chế độ Anh/Việt của riêng nó", "앱마다 입력 모드를 따로 기억합니다"), perAppSwitch),
            (tr("Tương thích máy chậm", "느린 Mac 호환 모드"), tr("Thêm 2 ms nghỉ trong Chrome, Edge, Claude, VS Code…", "Chrome, Edge, Claude, VS Code 등에서 2ms 간격 추가"), slowSwitch),
            (tr("Khởi động cùng macOS", "로그인 시 자동 실행"), tr("Tự chạy Dokey khi đăng nhập", "로그인할 때 Dokey 자동 실행"), loginSwitch),
            (tr("Tự kiểm tra bản mới", "새 버전 자동 확인"), tr("Báo khi có bản phát hành mới, cập nhật ngay trên máy", "새 버전이 나오면 알리고 바로 업데이트합니다"), updateSwitch),
            (tr("Ứng dụng loại trừ", "제외할 앱"), tr("Thêm từ thanh menu: \"Tắt bộ gõ trong …\"", "메뉴 막대에서 추가: \"…에서는 입력기 끄기\""), excludedRow()),
        ])
        let note = label(tr("""
        Trình duyệt và ứng dụng Electron/IDE (Claude, VS Code, Slack, Zalo…): Dokey bôi đen chữ cũ rồi gõ đè cả cụm chữ mới. \
        Ứng dụng thường (TextEdit, Notes, Terminal…): Dokey dùng Backspace.
        """, """
        브라우저와 Electron/IDE 앱(Claude, VS Code, Slack, KakaoTalk 등): 이전 글자를 선택한 뒤 새 글자로 덮어씁니다. \
        일반 앱(TextEdit, 메모, 터미널 등): Backspace로 지웁니다.
        """), size: 12, color: Palette.secondaryText, wrapping: true)
        let page = vertical([hero, card, note, currentAppLine], spacing: 12)
        fullWidth([hero, card, note, currentAppLine], in: page)
        return page
    }

    private func excludedRow() -> NSView {
        let clear = AccentButton(title: tr("Bỏ hết", "모두 해제"))
        clear.target = self
        clear.action = #selector(clearExcluded)
        let row = NSStackView(views: [excludedValue, clear])
        row.spacing = 10
        return row
    }

    private func aboutPage() -> NSView {
        let badge = GlossyBadge(shape: .squircle, top: NSColor(red: 0.98, green: 0.45, blue: 0.86, alpha: 1),
                                bottom: NSColor(red: 0.45, green: 0.20, blue: 0.95, alpha: 1), symbol: .text("đ"))
        badge.widthAnchor.constraint(equalToConstant: 112).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let text = label(tr("""
        Bộ gõ tiếng Việt và tiếng Hàn cho macOS, chạy trên lõi Dokey Core.
        Mỗi phím, Dokey dựng lại cả từ, nên chữ trên màn hình luôn khớp với phím đã gõ:
        không nhảy chữ, không mất chữ, kể cả trong Chrome và Claude.
        """, """
        Dokey Core 엔진 기반의 macOS용 한국어·베트남어 입력기입니다.
        키를 누를 때마다 글자 전체를 다시 조합하므로, Chrome이나 Claude에서도
        글자가 뒤섞이거나 사라지지 않습니다.
        """), size: 13, color: Palette.secondaryText, wrapping: true)
        text.alignment = .center
        let github = AccentButton(title: tr("Trang dự án trên GitHub", "GitHub 프로젝트 페이지"))
        github.target = self
        github.action = #selector(openGitHub)
        updateButton.target = self
        updateButton.action = #selector(checkUpdates)
        let link = NSStackView(views: [updateButton, github])
        link.spacing = 10
        let legal = label("© 2026 Do Huy Toan (dhtoan). All rights reserved.\n"
                          + tr("Phần mềm độc quyền: cấm sao chép, sửa đổi, phân phối lại.", "독점 소프트웨어: 복제, 수정, 재배포를 금지합니다."),
                          size: 11, color: NSColor(white: 1, alpha: 0.45))
        legal.alignment = .center
        let page = vertical([badge, label("Dokey", size: 32, weight: .bold),
                             label(tr("Phiên bản ", "버전 ") + Self.version, size: 13, color: Palette.secondaryText),
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

    private func updatePlaceholder() {
        tryField.placeholderString = settings.korean
            ? tr("Gõ thử ở đây, ví dụ: dkssudgktpdy → 안녕하세요", "여기에 입력해 보세요. 예: dkssudgktpdy → 안녕하세요")
            : tr("Gõ thử ở đây, ví dụ: Vieetj Nam, dduowngf, Haxy…", "여기에 입력해 보세요. 예: Vieetj Nam → Việt Nam")
    }

    func refresh() {
        guard isWindowLoaded else { return }
        let vietnamese = settings.vietnamese  // typing on (in the chosen language)
        let korean = settings.korean
        let languageName = korean ? tr("Tiếng Hàn", "한국어") : tr("Tiếng Việt", "베트남어")
        orb.isLit = vietnamese
        orb.title = vietnamese ? tr("Tắt", "끄기") : tr("Bật", "켜기")
        orb.toolTip = vietnamese ? tr("Chuyển sang gõ tiếng Anh", "영문 입력으로 전환")
                                 : tr("Bật lại bộ gõ", "입력기 다시 켜기")
        modeCard.value.stringValue = vietnamese ? languageName : tr("Tiếng Anh", "영어")
        modeCard.badge.symbol = .text(vietnamese ? (korean ? "한" : "V") : "E")
        let key = settings.hotkey.shortTitle
        modeCard.setStatus(vietnamese ? tr("Đang bật · %@ để chuyển", "켜짐 · %@로 전환").replacingOccurrences(of: "%@", with: key)
                                      : tr("Đang tắt · %@ để bật", "꺼짐 · %@로 켜기").replacingOccurrences(of: "%@", with: key),
                           ok: vietnamese)
        languagePicker.selectedIndex = korean ? 1 : 0
        updatePlaceholder()

        let ready = assumeReady || (Accessibility.isTrusted && (delegate?.panelTapRunning ?? false))
        permissionCard.value.stringValue = ready ? tr("Sẵn sàng", "준비됨") : tr("Chưa cấp", "권한 없음")
        permissionCard.setStatus(ready ? tr("Dokey đang nghe bàn phím", "Dokey가 키보드를 받고 있습니다")
                                       : tr("Cần quyền để gõ", "입력하려면 권한이 필요합니다"), ok: ready)
        permissionCard.setAccessory(ready ? nil : permissionButton)
        permissionCard.badge.symbol = ready ? .check : .text("!")
        permissionCard.badge.top = ready ? NSColor(red: 0.40, green: 0.92, blue: 0.62, alpha: 1)
                                         : NSColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 1)
        permissionCard.badge.bottom = ready ? NSColor(red: 0.05, green: 0.55, blue: 0.40, alpha: 1)
                                            : NSColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 1)

        let vni = settings.method == Int32(DOKEY_VNI)
        let combining = settings.encoding == Int32(DOKEY_UNICODE_COMBINING)
        if korean {
            methodCard.value.stringValue = tr("2-beolsik", "두벌식")
            methodCard.setStatus(tr("Bàn phím tiếng Hàn chuẩn", "표준 한국어 자판"), ok: true)
        } else {
            methodCard.value.stringValue = vni ? "VNI" : "Telex"
            methodCard.setStatus(combining ? tr("Unicode tổ hợp", "유니코드 조합형") : tr("Unicode dựng sẵn", "유니코드 완성형"), ok: true)
        }

        if let app = delegate?.panelFrontApp {
            appCard.value.stringValue = app.name
            appCard.setStatus(tr("Nhóm: ", "유형: ") + app.kind.title, ok: true)
            appCard.badge.symbol = app.icon.map { .image($0) } ?? .grid
            currentAppLine.stringValue = tr("Ứng dụng vừa dùng: ", "최근 사용한 앱: ") + "\(app.name) (\(app.kind.title))."
        } else {
            appCard.value.stringValue = "—"
            appCard.setStatus(tr("Chưa có", "없음"), ok: false)
            appCard.badge.symbol = .grid
            currentAppLine.stringValue = ""
        }

        let count = delegate?.panelEditCount ?? 0
        countCard.value.stringValue = Self.grouped(count) + tr(" từ", " 단어")
        countCard.setStatus(tr("từ lúc mở Dokey", "Dokey 실행 이후"), ok: true)

        methodPicker.selectedIndex = vni ? 1 : 0
        encodingPicker.selectedIndex = combining ? 1 : 0
        spellingSwitch.isOn = settings.checkSpelling
        toneSwitch.isOn = settings.modernToneStyle
        hotkeyPopup.selectItem(at: settings.hotkey.rawValue)
        examples.stringValue = korean
            ? tr("Ví dụ tiếng Hàn:  dkssudgktpdy → 안녕하세요   ·   rkatkgkqslek → 감사합니다   ·   Shift + q w e r t → ㅃ ㅉ ㄸ ㄲ ㅆ",
                 "예:  dkssudgktpdy → 안녕하세요   ·   rkatkgkqslek → 감사합니다   ·   Shift + q w e r t → ㅃ ㅉ ㄸ ㄲ ㅆ")
            : vni
            ? "Ví dụ VNI:  Vie65t Nam → Việt Nam   ·   d9u7o7ng2 → đường   ·   1–5 = sắc huyền hỏi ngã nặng, 6 = mũ, 7 = móc, 8 = trăng, 9 = đ"
            : "Ví dụ Telex:  Vieetj Nam → Việt Nam   ·   dduowngf → đường   ·   s f r x j = sắc huyền hỏi ngã nặng, aa ee oo = â ê ô, aw ow uw = ă ơ ư, dd = đ"

        perAppSwitch.isOn = settings.rememberModePerApp
        quickTelexSwitch.isOn = settings.quickTelex
        escSwitch.isOn = settings.undoWithEsc
        macroSwitch.isOn = settings.macrosEnabled
        macroSummary.stringValue = settings.macrosEnabled
            ? tr("Đang có %d từ tắt. Viết hoa từ tắt để viết hoa nội dung (Vn → Việt Nam, VN → VIỆT NAM).",
                 "단축어 %d개. 단축어를 대문자로 쓰면 내용도 대문자가 됩니다 (Vn → Việt Nam, VN → VIỆT NAM).")
                .replacingOccurrences(of: "%d", with: "\(settings.macroCount)")
            : tr("Gõ tắt đang tắt.", "단축어가 꺼져 있습니다.")
        let excluded = settings.excludedApps
        excludedValue.stringValue = excluded.isEmpty ? tr("Chưa có", "없음") : "\(excluded.count)" + tr(" ứng dụng", "개 앱")
        slowSwitch.isOn = settings.slowMachineMode
        loginSwitch.isOn = LoginItem.isEnabled
        updateSwitch.isOn = settings.autoCheckUpdates
        updateButton.title = Updater.shared.available.map { tr("Cập nhật lên ", "업데이트: ") + $0.version }
            ?? tr("Kiểm tra cập nhật", "업데이트 확인")
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

    @objc private func languageChanged() {
        delegate?.panelSetLanguage(languagePicker.selectedIndex == 1 ? "ko" : "vi")
        refresh()
    }

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

    @objc private func quickTelexChanged() {
        settings.quickTelex = quickTelexSwitch.isOn
        changed()
    }

    @objc private func escChanged() {
        settings.undoWithEsc = escSwitch.isOn
        changed()
    }

    @objc private func macrosChanged() {
        settings.macrosEnabled = macroSwitch.isOn
        changed()
    }

    @objc private func editMacros() {
        let editor = macroEditor ?? MacroEditorController()
        editor.onSave = { [weak self] text in
            self?.settings.macroText = text
            self?.changed()
        }
        macroEditor = editor
        editor.present(text: settings.macroText, over: window)
    }

    @objc private func clearExcluded() {
        delegate?.panelClearExcluded()
        refresh()
    }

    @objc private func checkUpdates() { delegate?.panelCheckUpdates() }

    @objc private func updateChanged() {
        settings.autoCheckUpdates = updateSwitch.isOn
        if updateSwitch.isOn { Updater.shared.check(interactive: false) }
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
            alert.messageText = tr("Không đổi được mục khởi động cùng macOS", "로그인 항목을 변경하지 못했습니다")
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
