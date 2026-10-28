// Dokey for Windows - user settings (HKCU\Software\Dokey).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

namespace dokey_win {

enum Hotkey { HOTKEY_CTRL_SHIFT = 0, HOTKEY_ALT_Z = 1 };

struct Settings {
    bool vietnamese = true;
    int method = 0;            // DOKEY_TELEX or DOKEY_VNI
    bool checkSpelling = true;
    bool modernTone = true;    // hoà, khoẻ, thuý
    int hotkey = HOTKEY_CTRL_SHIFT;
    DWORD chromiumPauseMs = 12;
};

Settings LoadSettings();
void SaveSettings(const Settings& s);

bool IsStartupEnabled();
void SetStartupEnabled(bool enabled);

} // namespace dokey_win
