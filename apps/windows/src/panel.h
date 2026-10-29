// Dokey for Windows - the control panel window.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

#include <string>

#include "settings.h"

namespace dokey_win {

// What the dashboard shows besides the settings.
struct PanelStatus {
    bool imeActive = false;      // a Chinese/Japanese/Korean IME is on: Dokey stands aside
    std::wstring appName;        // the last application the user typed in
    bool appChromium = false;    // Chrome, Edge, Electron...
    unsigned markedWords = 0;    // words Dokey added marks to since it started
};

struct PanelCallbacks {
    void (*settingsChanged)();   // the panel edited *settings: save and apply them
    PanelStatus (*status)();
};

// Starts GDI+ and registers the window class. `settings` stays owned by the caller.
bool InitPanel(HINSTANCE instance, Settings* settings, const PanelCallbacks& callbacks);
// Closes the panel and stops GDI+.
void ShutdownPanel();
// Opens the panel (or brings it to the front) on a page: 0 dashboard, 1 typing, 2 apps, 3 about.
void ShowPanel(int page);
// Redraws the panel after the settings changed elsewhere (tray menu, hotkey).
void RefreshPanel();
// --render-panel <prefix>: writes <prefix>-1.png ... for CI and the README.
int RenderPanelImages(const wchar_t* prefix);

} // namespace dokey_win
