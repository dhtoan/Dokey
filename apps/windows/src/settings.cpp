// Dokey for Windows - user settings (HKCU\Software\Dokey).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "settings.h"

#include "dokey/dokey.h"

namespace dokey_win {

namespace {

const wchar_t kKey[] = L"Software\\Dokey";
const wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const wchar_t kRunValue[] = L"Dokey";

DWORD ReadDword(HKEY key, const wchar_t* name, DWORD fallback) {
    DWORD value = 0, size = sizeof(value), type = 0;
    if (RegQueryValueExW(key, name, nullptr, &type, reinterpret_cast<BYTE*>(&value), &size) != ERROR_SUCCESS ||
        type != REG_DWORD) {
        return fallback;
    }
    return value;
}

void WriteDword(HKEY key, const wchar_t* name, DWORD value) {
    RegSetValueExW(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
}

} // namespace

Settings LoadSettings() {
    Settings s;
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kKey, 0, KEY_READ, &key) != ERROR_SUCCESS) return s;
    s.vietnamese = ReadDword(key, L"Vietnamese", s.vietnamese) != 0;
    s.method = ReadDword(key, L"Method", s.method) == DOKEY_VNI ? DOKEY_VNI : DOKEY_TELEX;
    s.checkSpelling = ReadDword(key, L"CheckSpelling", s.checkSpelling) != 0;
    s.modernTone = ReadDword(key, L"ModernTone", s.modernTone) != 0;
    s.hotkey = ReadDword(key, L"Hotkey", s.hotkey) == HOTKEY_ALT_Z ? HOTKEY_ALT_Z : HOTKEY_CTRL_SHIFT;
    DWORD pause = ReadDword(key, L"ChromiumPauseMs", s.chromiumPauseMs);
    s.chromiumPauseMs = pause > 100 ? 100 : pause;
    RegCloseKey(key);
    return s;
}

void SaveSettings(const Settings& s) {
    HKEY key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kKey, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return;
    }
    WriteDword(key, L"Vietnamese", s.vietnamese);
    WriteDword(key, L"Method", static_cast<DWORD>(s.method));
    WriteDword(key, L"CheckSpelling", s.checkSpelling);
    WriteDword(key, L"ModernTone", s.modernTone);
    WriteDword(key, L"Hotkey", static_cast<DWORD>(s.hotkey));
    WriteDword(key, L"ChromiumPauseMs", s.chromiumPauseMs);
    RegCloseKey(key);
}

bool IsStartupEnabled() {
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_READ, &key) != ERROR_SUCCESS) return false;
    bool found = RegQueryValueExW(key, kRunValue, nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS;
    RegCloseKey(key);
    return found;
}

void SetStartupEnabled(bool enabled) {
    HKEY key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return;
    }
    if (enabled) {
        wchar_t path[MAX_PATH];
        DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
        if (n > 0 && n < MAX_PATH) {
            wchar_t command[MAX_PATH + 32];
            wsprintfW(command, L"\"%s\" --background", path);  // start in the tray, no panel
            RegSetValueExW(key, kRunValue, 0, REG_SZ, reinterpret_cast<const BYTE*>(command),
                           static_cast<DWORD>((lstrlenW(command) + 1) * sizeof(wchar_t)));
        }
    } else {
        RegDeleteValueW(key, kRunValue);
    }
    RegCloseKey(key);
}

} // namespace dokey_win
