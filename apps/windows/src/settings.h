// Dokey for Windows - user settings (HKCU\Software\Dokey).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

#include <string>
#include <vector>

namespace dokey_win {

enum Hotkey { HOTKEY_CTRL_SHIFT = 0, HOTKEY_ALT_Z = 1 };

struct Settings {
    bool vietnamese = true;
    int method = 0;            // DOKEY_TELEX or DOKEY_VNI
    bool checkSpelling = true;
    bool modernTone = true;    // hoà, khoẻ, thuý
    int hotkey = HOTKEY_CTRL_SHIFT;
    DWORD chromiumPauseMs = 12;
    bool quickTelex = false;   // cc gg kk nn pp qq tt -> ch gi kh ng ph qu th at a word start
    bool escUndo = false;      // Esc turns the current word back into its keys
    bool macrosEnabled = true;
    std::wstring macros;       // "shortcut = text" lines, # for comments
    std::vector<std::wstring> excludedApps;  // lower-case exe names, always English
};

extern const wchar_t kDefaultMacros[];

bool IsExcluded(const Settings& s, const std::wstring& exe);
void SetExcluded(Settings& s, const std::wstring& exe, bool excluded);

Settings LoadSettings();
void SaveSettings(const Settings& s);

bool IsStartupEnabled();
void SetStartupEnabled(bool enabled);

} // namespace dokey_win
