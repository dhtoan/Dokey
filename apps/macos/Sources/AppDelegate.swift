// Dokey for macOS - menu bar app.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ControlPanelDelegate {
    private let settings = Settings.shared
    private lazy var engine = Engine(options: settings.engineOptions)
    private lazy var tap = KeyboardTap(engine: engine)
    private var statusItem: NSStatusItem!
    private var permissionWindow: PermissionWindowController?
    private var controlPanel: ControlPanelController?
    private var watchdog: Timer?
    private var frontApp: (bundleID: String, name: String, kind: AppKind, icon: NSImage?)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "Dokey"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        tap.onToggle = { [weak self] in self?.toggleMode() }
        engine.setMacros(settings.macrosEnabled ? settings.macroText : "")
        pushState()
        updateIcon()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let app = NSWorkspace.shared.frontmostApplication { activate(app) }

        installMainMenu()
        Updater.shared.start()
        NotificationCenter.default.addObserver(forName: .dokeyUpdateAvailable, object: nil, queue: .main) { [weak self] _ in
            self?.controlPanel?.refresh()
        }
        if !tap.start() {
            showPermissionGuide()
        } else if !launchedAtLogin {
            showControlPanel()
        }
        // Watchdog: start the tap once permission arrives, and switch it back
        // on if macOS disabled it (timeouts, secure input in password fields).
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.tap.isRunning {
                if Accessibility.isTrusted, self.tap.start() { self.controlPanel?.refresh() }
            } else {
                self.tap.ensureEnabled()
            }
            self.applyTuning()  // picks up `defaults write` tuning while running
        }
    }

    /// Opening Dokey.app again (Finder, Launchpad, Spotlight) shows the control panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlPanel()
        return false
    }

    /// Started by the login item: stay quietly in the menu bar.
    private var launchedAtLogin: Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        return ProcessInfo.processInfo.systemUptime < 120
    }

    // MARK: - Control panel

    private func showControlPanel() {
        if controlPanel == nil {
            let panel = ControlPanelController()
            panel.delegate = self
            panel.onClose = {
                // Back to a menu-bar-only app once the window is gone.
                DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
            }
            controlPanel = panel
        }
        // A Dock icon and ⌘-Tab entry while the window is open, like other apps.
        NSApp.setActivationPolicy(.regular)
        controlPanel?.present()
    }

    /// ⌘W, ⌘M and ⌘Q for the control panel.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Giới thiệu Dokey", "Dokey 정보"), action: #selector(menuAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ẩn Dokey", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: tr("Thoát Dokey", "Dokey 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: tr("Cửa sổ", "윈도우"))
        windowMenu.addItem(withTitle: tr("Đóng", "닫기"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: tr("Thu nhỏ", "최소화"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    func panelToggleMode() { toggleMode() }

    func panelSettingsChanged() {
        engineOptionsChanged()
        updateIcon()
    }

    func panelShowPermission() { showPermissionGuide() }

    var panelFrontApp: (name: String, kind: AppKind, icon: NSImage?)? {
        frontApp.map { ($0.name, $0.kind, $0.icon) }
    }

    var panelEditCount: Int { tap.editedWords }

    func panelClearExcluded() {
        settings.excludedApps = []
        engine.reset()
        pushState()
        updateIcon()
    }

    func panelCheckUpdates() { Updater.shared.showAvailable() }

    func panelSetLanguage(_ code: String) { setLanguage(code) }

    var panelTapRunning: Bool { tap.isRunning }

    // MARK: - State

    /// Vietnamese is on and the front app is not excluded.
    private var vietnameseActive: Bool {
        settings.vietnamese && !isExcluded(frontApp?.bundleID)
    }

    private func isExcluded(_ bundleID: String?) -> Bool {
        guard let id = bundleID, !id.isEmpty else { return false }
        return settings.excludedApps.contains(id)
    }

    /// Google Docs and friends, recognised from the front window's title.
    private var siteProfile: DeliveryProfile?

    private func refreshSiteRule() {
        guard frontApp?.kind == .browser, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            siteProfile = nil
            return
        }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let w = window, CFGetTypeID(w) == AXUIElementGetTypeID(),
           AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
           let text = title as? String {
            siteProfile = SiteRule.profile(forWindowTitle: text, slowMachine: settings.slowMachineMode)
        } else {
            siteProfile = nil
        }
    }

    private func pushState() {
        var state = tap.state
        state.vietnamese = vietnameseActive
        state.undoWithEsc = settings.undoWithEsc
        state.siteProfile = siteProfile
        state.hotkey = settings.hotkey
        state.encoding = settings.encoding
        state.appKind = frontApp?.kind ?? .normal
        state.vsCode = AppClassifier.isVSCode(bundleID: frontApp?.bundleID ?? "")
        state.profile = state.appKind.profile(slowMachine: settings.slowMachineMode, tuning: settings.tuning)
        state.debugLog = settings.debugLog
        state.korean = settings.korean
        engine.setLanguage(settings.language)
        tap.state = state
        controlPanel?.refresh()
    }

    private func applyTuning() {
        refreshSiteRule()
        var state = tap.state
        state.siteProfile = siteProfile
        state.profile = state.appKind.profile(slowMachine: settings.slowMachineMode, tuning: settings.tuning)
        state.debugLog = settings.debugLog
        state.korean = settings.korean  // picks up `defaults write ... language` while running
        engine.setLanguage(settings.language)
        tap.state = state
    }

    private func updateIcon() {
        statusItem.button?.image = StatusIcon.image(vietnamese: vietnameseActive, korean: settings.korean)
    }

    private func setVietnamese(_ on: Bool, remember: Bool) {
        settings.vietnamese = on
        if remember, settings.rememberModePerApp, let id = frontApp?.bundleID {
            settings.saveMode(on, forApp: id)
        }
        engine.reset()
        pushState()
        updateIcon()
        controlPanel?.refresh()
    }

    private func toggleMode() {
        // In an excluded app the shortcut means "type Vietnamese here after all".
        if let id = frontApp?.bundleID, isExcluded(id) {
            setExcluded(false, bundleID: id)
            if !settings.vietnamese { setVietnamese(true, remember: true) }
            return
        }
        setVietnamese(!settings.vietnamese, remember: true)
    }

    private func setExcluded(_ excluded: Bool, bundleID id: String) {
        var list = settings.excludedApps.filter { $0 != id }
        if excluded { list.append(id) }
        settings.excludedApps = list
        engine.reset()
        pushState()
        updateIcon()
    }

    private func engineOptionsChanged() {
        engine.setOptions(settings.engineOptions)
        engine.setMacros(settings.macrosEnabled ? settings.macroText : "")
        pushState()
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        activate(app)
    }

    private func activate(_ app: NSRunningApplication) {
        engine.reset()
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            // Typing in Dokey's own panel (the "Gõ thử" box): a normal Cocoa text field.
            var state = tap.state
            state.appKind = .normal
            state.vsCode = false
            state.profile = AppKind.normal.profile(slowMachine: settings.slowMachineMode, tuning: settings.tuning)
            tap.state = state
            return
        }
        let id = app.bundleIdentifier ?? ""
        frontApp = (id, app.localizedName ?? id, AppClassifier.classify(app), app.icon)
        refreshSiteRule()
        defer { updateIcon() }
        if settings.rememberModePerApp, !id.isEmpty, let saved = settings.savedMode(forApp: id),
           saved != settings.vietnamese {
            setVietnamese(saved, remember: false)
        } else {
            pushState()
        }
        controlPanel?.refresh()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let release = Updater.shared.available {
            menu.addItem(item(tr("⬆︎ Cập nhật lên Dokey ", "⬆︎ Dokey 업데이트: ") + release.version + "…", #selector(menuInstallUpdate)))
        }
        menu.addItem(item(tr("Mở bảng điều khiển…", "제어판 열기…"), #selector(menuControlPanel)))
        menu.addItem(.separator())
        let mode = item(settings.korean ? tr("Gõ tiếng Hàn", "한국어 입력") : tr("Gõ tiếng Việt", "베트남어 입력"),
                        #selector(menuToggleMode), key: "")
        mode.state = settings.vietnamese ? .on : .off
        menu.addItem(mode)
        let hint = NSMenuItem(title: tr("Chuyển ngôn ngữ / tiếng Anh: %@", "영문 전환: %@")
                                  .replacingOccurrences(of: "%@", with: settings.hotkey.shortTitle),
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        // Typing language: Vietnamese or Korean (2-beolsik).
        let languages = NSMenu()
        for (title, code) in [("Tiếng Việt", "vi"), ("한국어 (두벌식)", "ko")] {
            let l = item(title, #selector(menuSetLanguage(_:)))
            l.representedObject = code
            l.state = settings.languageCode == code ? .on : .off
            languages.addItem(l)
        }
        menu.addItem(submenu(tr("Ngôn ngữ gõ: ", "입력 언어: ") + (settings.korean ? "한국어" : "Tiếng Việt"), languages))

        let methods = NSMenu()
        for (title, value) in [("Telex", Int32(DOKEY_TELEX)), ("VNI", Int32(DOKEY_VNI))] {
            let m = item(title, #selector(menuSetMethod(_:)), tag: Int(value))
            m.state = settings.method == value ? .on : .off
            methods.addItem(m)
        }
        let methodItem = submenu(tr("Kiểu gõ tiếng Việt: ", "베트남어 입력 방식: ")
                                 + (settings.method == Int32(DOKEY_VNI) ? "VNI" : "Telex"), methods)
        methodItem.isEnabled = !settings.korean
        menu.addItem(methodItem)

        let encodings = NSMenu()
        for (title, value) in [(tr("Unicode dựng sẵn", "유니코드 완성형"), Int32(DOKEY_UNICODE)),
                               (tr("Unicode tổ hợp", "유니코드 조합형"), Int32(DOKEY_UNICODE_COMBINING))] {
            let e = item(title, #selector(menuSetEncoding(_:)), tag: Int(value))
            e.state = settings.encoding == value ? .on : .off
            encodings.addItem(e)
        }
        menu.addItem(submenu(tr("Bảng mã", "인코딩"), encodings))

        let spelling = item(tr("Kiểm tra chính tả", "맞춤법 검사"), #selector(menuToggleSpelling))
        spelling.state = settings.checkSpelling ? .on : .off
        menu.addItem(spelling)
        let tone = item(tr("Đặt dấu kiểu mới (hoà, khoẻ, thuý)", "새 성조 위치 (hoà, khoẻ, thuý)"), #selector(menuToggleTone))
        tone.state = settings.modernToneStyle ? .on : .off
        menu.addItem(tone)
        menu.addItem(.separator())

        let hotkeys = NSMenu()
        for hotkey in SwitchHotkey.allCases {
            let h = item(hotkey.title, #selector(menuSetHotkey(_:)), tag: hotkey.rawValue)
            h.state = settings.hotkey == hotkey ? .on : .off
            hotkeys.addItem(h)
        }
        menu.addItem(submenu(tr("Phím chuyển Anh/Việt", "입력 전환 단축키"), hotkeys))

        let perApp = item(tr("Nhớ chế độ Anh/Việt theo ứng dụng", "앱별 입력 모드 기억"), #selector(menuTogglePerApp))
        perApp.state = settings.rememberModePerApp ? .on : .off
        menu.addItem(perApp)
        let slow = item(tr("Tương thích máy chậm", "느린 Mac 호환 모드"), #selector(menuToggleSlow))
        slow.state = settings.slowMachineMode ? .on : .off
        slow.toolTip = tr("Thêm khoảng nghỉ giữa các phím gửi đi trong Chrome, Edge và ứng dụng Electron.", "Chrome, Edge, Electron 앱에 보내는 키 사이에 짧은 간격을 둡니다.")
        menu.addItem(slow)
        if let app = frontApp, !app.bundleID.isEmpty {
            let exclude = item(tr("Tắt bộ gõ trong %@", "%@에서는 입력기 끄기").replacingOccurrences(of: "%@", with: app.name),
                               #selector(menuToggleExcluded))
            exclude.state = isExcluded(app.bundleID) ? .on : .off
            menu.addItem(exclude)
        }
        let login = item(tr("Khởi động cùng macOS", "로그인 시 자동 실행"), #selector(menuToggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        if let app = frontApp {
            let info = NSMenuItem(title: tr("Ứng dụng: ", "앱: ") + "\(app.name) (\(app.kind.title))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        if !Accessibility.isTrusted || !tap.isRunning {
            let warning = item(tr("⚠️ Chưa có quyền Trợ năng: bấm để cấp quyền…", "⚠️ 손쉬운 사용 권한 없음: 클릭하여 허용…"), #selector(menuPermission))
            menu.addItem(warning)
        } else {
            menu.addItem(item(tr("Hướng dẫn cấp quyền Trợ năng…", "손쉬운 사용 권한 안내…"), #selector(menuPermission)))
        }
        menu.addItem(item(tr("Kiểm tra cập nhật…", "업데이트 확인…"), #selector(menuCheckUpdates)))
        menu.addItem(item(tr("Giới thiệu Dokey", "Dokey 정보"), #selector(menuAbout)))
        menu.addItem(.separator())
        menu.addItem(item(tr("Thoát Dokey", "Dokey 종료"), #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", tag: Int = 0,
                      target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        i.tag = tag
        return i
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = menu
        return i
    }

    @objc private func menuToggleMode() { toggleMode() }

    @objc private func menuControlPanel() { showControlPanel() }

    @objc private func menuSetLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        setLanguage(code)
    }

    /// "vi" or "ko". Switching language also turns typing on.
    private func setLanguage(_ code: String) {
        settings.languageCode = code
        engine.reset()
        if !settings.vietnamese { settings.vietnamese = true }
        pushState()
        updateIcon()
    }

    @objc private func menuToggleExcluded() {
        guard let id = frontApp?.bundleID, !id.isEmpty else { return }
        setExcluded(!isExcluded(id), bundleID: id)
    }

    @objc private func menuCheckUpdates() { Updater.shared.check(interactive: true) }

    @objc private func menuInstallUpdate() { Updater.shared.showAvailable() }

    @objc private func menuSetMethod(_ sender: NSMenuItem) {
        settings.method = Int32(sender.tag)
        engineOptionsChanged()
    }

    @objc private func menuSetEncoding(_ sender: NSMenuItem) {
        settings.encoding = Int32(sender.tag)
        engineOptionsChanged()
    }

    @objc private func menuToggleSpelling() {
        settings.checkSpelling.toggle()
        engineOptionsChanged()
    }

    @objc private func menuToggleTone() {
        settings.modernToneStyle.toggle()
        engineOptionsChanged()
    }

    @objc private func menuSetHotkey(_ sender: NSMenuItem) {
        settings.hotkey = SwitchHotkey(rawValue: sender.tag) ?? .controlShift
        pushState()
    }

    @objc private func menuTogglePerApp() {
        settings.rememberModePerApp.toggle()
    }

    @objc private func menuToggleSlow() {
        settings.slowMachineMode.toggle()
        pushState()
    }

    @objc private func menuToggleLogin() {
        if let error = LoginItem.setEnabled(!LoginItem.isEnabled) {
            let alert = NSAlert()
            alert.messageText = tr("Không đổi được mục khởi động cùng macOS", "로그인 항목을 변경하지 못했습니다")
            alert.informativeText = error
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func menuPermission() { showPermissionGuide() }

    private func showPermissionGuide() {
        if permissionWindow == nil {
            let controller = PermissionWindowController()
            controller.onGranted = { [weak self] in
                if self?.tap.isRunning == false { self?.tap.start() }
                self?.controlPanel?.refresh()
            }
            permissionWindow = controller
        }
        permissionWindow?.present()
    }

    @objc private func menuAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "Dokey \(version)"
        alert.informativeText = tr("""
        Bộ gõ tiếng Việt và tiếng Hàn cho macOS, chạy trên lõi Dokey Core.
        Telex, VNI, 2-beolsik, kiểm tra chính tả, giữ nguyên từ tiếng Anh.

        © 2026 Do Huy Toan (dhtoan). All rights reserved.
        Phần mềm độc quyền: cấm sao chép, sửa đổi, phân phối lại.
        """, """
        Dokey Core 엔진 기반의 macOS용 한국어·베트남어 입력기입니다.
        두벌식, Telex, VNI, 맞춤법 검사, 영어 단어 유지.

        © 2026 Do Huy Toan (dhtoan). All rights reserved.
        독점 소프트웨어: 복제, 수정, 재배포를 금지합니다.
        """)
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
