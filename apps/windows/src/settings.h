// Dokey for Windows - user settings (HKCU\Software\Dokey).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

#include <string>
#include <vector>

namespace dokey_win {

enum Hotkey { HOTKEY_CTRL_SHIFT = 0, HOTKEY_ALT_Z = 1 };
enum Language { LANGUAGE_VIETNAMESE = 0, LANGUAGE_KOREAN = 1 };  // DOKEY_LANG_*

struct Settings {
    bool vietnamese = true;    // typing on (Vietnamese or Korean); off: the keys go through
    int language = LANGUAGE_VIETNAMESE;
    int method = 0;            // DOKEY_TELEX or DOKEY_VNI
    bool checkSpelling = true;
    bool modernTone = true;    // hoà, khoẻ, thuý
    int hotkey = HOTKEY_CTRL_SHIFT;
    DWORD chromiumPauseMs = 12;
    bool debugLog = false;  // registry only: %TEMP%\dokey-debug.log
    DWORD selectionGuard = 0x200B;  // registry only (testing): character typed before deletions, 0xFFFF Delete, 0 off
    bool quickTelex = false;   // cc gg kk nn pp qq tt -> ch gi kh ng ph qu th at a word start
    bool escUndo = false;      // Esc turns the current word back into its keys
    bool macrosEnabled = true;
    std::wstring macros;       // "shortcut = text" lines, # for comments
    std::vector<std::wstring> excludedApps;  // lower-case exe names, always English
    bool autoCheckUpdates = true;   // look for a new release in the background and say so
    std::wstring skippedVersion;    // a release the user chose to skip
    ULONGLONG lastUpdateCheck = 0;  // seconds since 1970 of the last successful check
};

extern const wchar_t kDefaultMacros[];

// The user interface follows Windows: Korean when the display language is Korean,
// Vietnamese otherwise. --ui-lang ko|vi overrides it (CI renders both).
bool UiKorean();
void SetUiKorean(bool korean);
inline const wchar_t* Tr(const wchar_t* vi, const wchar_t* ko) { return UiKorean() ? ko : vi; }

bool IsExcluded(const Settings& s, const std::wstring& exe);
void SetExcluded(Settings& s, const std::wstring& exe, bool excluded);

Settings LoadSettings();
void SaveSettings(const Settings& s);

bool IsStartupEnabled();
void SetStartupEnabled(bool enabled);

} // namespace dokey_win
