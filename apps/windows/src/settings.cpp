// Dokey for Windows - user settings (HKCU\Software\Dokey).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "settings.h"

#include <algorithm>

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

std::wstring ReadString(HKEY key, const wchar_t* name, const std::wstring& fallback) {
    DWORD size = 0, type = 0;
    if (RegQueryValueExW(key, name, nullptr, &type, nullptr, &size) != ERROR_SUCCESS || type != REG_SZ) return fallback;
    std::wstring value(size / sizeof(wchar_t) + 1, L'\0');
    if (RegQueryValueExW(key, name, nullptr, nullptr, reinterpret_cast<BYTE*>(&value[0]), &size) != ERROR_SUCCESS) {
        return fallback;
    }
    value.resize(wcslen(value.c_str()));
    return value;
}

ULONGLONG ReadQword(HKEY key, const wchar_t* name, ULONGLONG fallback) {
    ULONGLONG value = 0;
    DWORD size = sizeof(value), type = 0;
    if (RegQueryValueExW(key, name, nullptr, &type, reinterpret_cast<BYTE*>(&value), &size) != ERROR_SUCCESS ||
        type != REG_QWORD) {
        return fallback;
    }
    return value;
}

void WriteQword(HKEY key, const wchar_t* name, ULONGLONG value) {
    RegSetValueExW(key, name, 0, REG_QWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
}

void WriteString(HKEY key, const wchar_t* name, const std::wstring& value) {
    RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                   static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

std::vector<std::wstring> SplitLines(const std::wstring& text) {
    std::vector<std::wstring> lines;
    size_t start = 0;
    while (start <= text.size()) {
        size_t end = text.find(L'\n', start);
        if (end == std::wstring::npos) end = text.size();
        std::wstring line = text.substr(start, end - start);
        if (!line.empty()) lines.push_back(line);
        start = end + 1;
    }
    return lines;
}

} // namespace

const wchar_t kDefaultMacros[] =
    L"# Gõ tắt: mỗi dòng \"từ tắt = nội dung\". Gõ từ tắt rồi dấu cách để thay.\n"
    L"# Viết hoa từ tắt để viết hoa nội dung: vn -> Việt Nam, Vn, VN -> VIỆT NAM.\n"
    L"vn = Việt Nam\n"
    L"ko = không\n"
    L"dc = được\n"
    L"btw = by the way\n";

namespace {
int g_uiKorean = -1;  // -1: follow Windows
}

bool UiKorean() {
    if (g_uiKorean < 0) g_uiKorean = PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_KOREAN ? 1 : 0;
    return g_uiKorean == 1;
}

void SetUiKorean(bool korean) { g_uiKorean = korean ? 1 : 0; }

bool IsExcluded(const Settings& s, const std::wstring& exe) {
    return !exe.empty() && std::find(s.excludedApps.begin(), s.excludedApps.end(), exe) != s.excludedApps.end();
}

void SetExcluded(Settings& s, const std::wstring& exe, bool excluded) {
    auto& apps = s.excludedApps;
    apps.erase(std::remove(apps.begin(), apps.end(), exe), apps.end());
    if (excluded && !exe.empty()) apps.push_back(exe);
}

Settings LoadSettings() {
    Settings s;
    s.macros = kDefaultMacros;
    s.language = UiKorean() ? LANGUAGE_KOREAN : LANGUAGE_VIETNAMESE;  // until the user picks one
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kKey, 0, KEY_READ, &key) != ERROR_SUCCESS) return s;
    s.vietnamese = ReadDword(key, L"Vietnamese", s.vietnamese) != 0;
    s.method = ReadDword(key, L"Method", s.method) == DOKEY_VNI ? DOKEY_VNI : DOKEY_TELEX;
    s.checkSpelling = ReadDword(key, L"CheckSpelling", s.checkSpelling) != 0;
    s.modernTone = ReadDword(key, L"ModernTone", s.modernTone) != 0;
    s.hotkey = ReadDword(key, L"Hotkey", s.hotkey) == HOTKEY_ALT_Z ? HOTKEY_ALT_Z : HOTKEY_CTRL_SHIFT;
    DWORD pause = ReadDword(key, L"ChromiumPauseMs", s.chromiumPauseMs);
    s.chromiumPauseMs = pause > 100 ? 100 : pause;
    s.language = ReadDword(key, L"Language", s.language) == LANGUAGE_KOREAN ? LANGUAGE_KOREAN : LANGUAGE_VIETNAMESE;
    s.quickTelex = ReadDword(key, L"QuickTelex", s.quickTelex) != 0;
    s.escUndo = ReadDword(key, L"EscUndo", s.escUndo) != 0;
    s.macrosEnabled = ReadDword(key, L"MacrosEnabled", s.macrosEnabled) != 0;
    s.macros = ReadString(key, L"Macros", s.macros);
    s.excludedApps = SplitLines(ReadString(key, L"ExcludedApps", L""));
    s.autoCheckUpdates = ReadDword(key, L"AutoCheckUpdates", s.autoCheckUpdates) != 0;
    s.skippedVersion = ReadString(key, L"SkippedVersion", L"");
    s.lastUpdateCheck = ReadQword(key, L"LastUpdateCheck", 0);
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
    WriteDword(key, L"Language", static_cast<DWORD>(s.language));
    WriteDword(key, L"QuickTelex", s.quickTelex);
    WriteDword(key, L"EscUndo", s.escUndo);
    WriteDword(key, L"MacrosEnabled", s.macrosEnabled);
    WriteString(key, L"Macros", s.macros);
    std::wstring apps;
    for (const auto& app : s.excludedApps) apps += app + L"\n";
    WriteString(key, L"ExcludedApps", apps);
    WriteDword(key, L"AutoCheckUpdates", s.autoCheckUpdates);
    WriteString(key, L"SkippedVersion", s.skippedVersion);
    WriteQword(key, L"LastUpdateCheck", s.lastUpdateCheck);
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
