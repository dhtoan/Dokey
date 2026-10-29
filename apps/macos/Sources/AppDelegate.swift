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
        pushState()
        updateIcon()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let app = NSWorkspace.shared.frontmostApplication { activate(app) }

        installMainMenu()
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
        appMenu.addItem(withTitle: "Giới thiệu Dokey", action: #selector(menuAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ẩn Dokey", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Thoát Dokey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenu.addItem(withTitle: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
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

    var panelTapRunning: Bool { tap.isRunning }

    // MARK: - State

    private func pushState() {
        var state = tap.state
        state.vietnamese = settings.vietnamese
        state.hotkey = settings.hotkey
        state.encoding = settings.encoding
        state.appKind = frontApp?.kind ?? .normal
        state.profile = state.appKind.profile(slowMachine: settings.slowMachineMode, tuning: settings.tuning)
        state.debugLog = settings.debugLog
        tap.state = state
        controlPanel?.refresh()
    }

    private func applyTuning() {
        var state = tap.state
        state.profile = state.appKind.profile(slowMachine: settings.slowMachineMode, tuning: settings.tuning)
        state.debugLog = settings.debugLog
        tap.state = state
    }

    private func updateIcon() {
        statusItem.button?.image = StatusIcon.image(vietnamese: settings.vietnamese)
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
        setVietnamese(!settings.vietnamese, remember: true)
    }

    private func engineOptionsChanged() {
        engine.setOptions(settings.engineOptions)
        pushState()
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        activate(app)
    }

    private func activate(_ app: NSRunningApplication) {
        engine.reset()
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let id = app.bundleIdentifier ?? ""
        frontApp = (id, app.localizedName ?? id, AppClassifier.classify(app), app.icon)
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

        menu.addItem(item("Mở bảng điều khiển…", #selector(menuControlPanel)))
        menu.addItem(.separator())
        let mode = item("Gõ tiếng Việt", #selector(menuToggleMode), key: "")
        mode.state = settings.vietnamese ? .on : .off
        menu.addItem(mode)
        let hint = NSMenuItem(title: "Chuyển Anh/Việt: \(settings.hotkey.shortTitle)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let methods = NSMenu()
        for (title, value) in [("Telex", Int32(DOKEY_TELEX)), ("VNI", Int32(DOKEY_VNI))] {
            let m = item(title, #selector(menuSetMethod(_:)), tag: Int(value))
            m.state = settings.method == value ? .on : .off
            methods.addItem(m)
        }
        menu.addItem(submenu("Kiểu gõ: \(settings.method == Int32(DOKEY_VNI) ? "VNI" : "Telex")", methods))

        let encodings = NSMenu()
        for (title, value) in [("Unicode dựng sẵn", Int32(DOKEY_UNICODE)),
                               ("Unicode tổ hợp", Int32(DOKEY_UNICODE_COMBINING))] {
            let e = item(title, #selector(menuSetEncoding(_:)), tag: Int(value))
            e.state = settings.encoding == value ? .on : .off
            encodings.addItem(e)
        }
        menu.addItem(submenu("Bảng mã", encodings))

        let spelling = item("Kiểm tra chính tả", #selector(menuToggleSpelling))
        spelling.state = settings.checkSpelling ? .on : .off
        menu.addItem(spelling)
        let tone = item("Đặt dấu kiểu mới (hoà, khoẻ, thuý)", #selector(menuToggleTone))
        tone.state = settings.modernToneStyle ? .on : .off
        menu.addItem(tone)
        menu.addItem(.separator())

        let hotkeys = NSMenu()
        for hotkey in SwitchHotkey.allCases {
            let h = item(hotkey.title, #selector(menuSetHotkey(_:)), tag: hotkey.rawValue)
            h.state = settings.hotkey == hotkey ? .on : .off
            hotkeys.addItem(h)
        }
        menu.addItem(submenu("Phím chuyển Anh/Việt", hotkeys))

        let perApp = item("Nhớ chế độ Anh/Việt theo ứng dụng", #selector(menuTogglePerApp))
        perApp.state = settings.rememberModePerApp ? .on : .off
        menu.addItem(perApp)
        let slow = item("Tương thích máy chậm", #selector(menuToggleSlow))
        slow.state = settings.slowMachineMode ? .on : .off
        slow.toolTip = "Thêm khoảng nghỉ giữa các phím gửi đi trong Chrome, Edge và ứng dụng Electron."
        menu.addItem(slow)
        let login = item("Khởi động cùng macOS", #selector(menuToggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        if let app = frontApp {
            let info = NSMenuItem(title: "Ứng dụng: \(app.name) (\(app.kind.title))", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        if !Accessibility.isTrusted || !tap.isRunning {
            let warning = item("⚠️ Chưa có quyền Trợ năng: bấm để cấp quyền…", #selector(menuPermission))
            menu.addItem(warning)
        } else {
            menu.addItem(item("Hướng dẫn cấp quyền Trợ năng…", #selector(menuPermission)))
        }
        menu.addItem(item("Giới thiệu Dokey", #selector(menuAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Thoát Dokey", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
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
            alert.messageText = "Không đổi được mục khởi động cùng macOS"
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
        alert.informativeText = """
        Bộ gõ tiếng Việt cho macOS, chạy trên lõi Dokey Core.
        Telex, VNI, kiểm tra chính tả, giữ nguyên từ tiếng Anh.

        © 2026 Do Huy Toan. All rights reserved.
        """
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
