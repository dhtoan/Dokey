// Dokey for Windows - tray application.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include <windows.h>
#include <imm.h>
#include <shellapi.h>
#include <windowsx.h>

#include "dokey/dokey.h"
#include "keyboard.h"
#include "resource.h"
#include "settings.h"
#include "version.h"

using namespace dokey_win;

#ifndef IMC_GETOPENSTATUS
#define IMC_GETOPENSTATUS 0x0005  // from <ime.h>
#endif

namespace {

const wchar_t kWindowClass[] = L"DokeyMainWindow";  // also used by the installer
const wchar_t kMutexName[] = L"DokeyAppMutex";      // also used by the installer
constexpr UINT WM_TRAY = WM_APP + 10;
constexpr UINT kTrayId = 1;
constexpr UINT_PTR kImeTimer = 1;
constexpr UINT kImeTimerMs = 1000;

enum Command : UINT {
    CMD_TOGGLE = 100,
    CMD_TELEX,
    CMD_VNI,
    CMD_SPELLING,
    CMD_TONE_MODERN,
    CMD_TONE_CLASSIC,
    CMD_HOTKEY_CTRL_SHIFT,
    CMD_HOTKEY_ALT_Z,
    CMD_STARTUP,
    CMD_ABOUT,
    CMD_EXIT,
};

HINSTANCE g_instance = nullptr;
Settings g_settings;
HICON g_iconVietnamese = nullptr;
HICON g_iconEnglish = nullptr;
UINT g_taskbarCreated = 0;

// ---- icons -------------------------------------------------------------------

// Coverage (0..1) of a rounded square at pixel (x, y), 4x4 supersampled.
double RoundedSquareCoverage(int x, int y, int size) {
    const double radius = size * 0.22, inset = size >= 24 ? 0.5 : 0.0;
    const double lo = inset, hi = size - inset;
    int inside = 0;
    for (int sy = 0; sy < 4; sy++) {
        for (int sx = 0; sx < 4; sx++) {
            double px = x + (sx + 0.5) / 4, py = y + (sy + 0.5) / 4;
            double cx = px < lo + radius ? lo + radius : (px > hi - radius ? hi - radius : px);
            double cy = py < lo + radius ? lo + radius : (py > hi - radius ? hi - radius : py);
            double dx = px - cx, dy = py - cy;
            if (px >= lo && px <= hi && py >= lo && py <= hi && dx * dx + dy * dy <= radius * radius) inside++;
        }
    }
    return inside / 16.0;
}

// A white letter on a coloured rounded square, drawn at the exact tray size.
HICON MakeLetterIcon(wchar_t letter, COLORREF background, int size) {
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = size;
    bi.bmiHeader.biHeight = -size;  // top-down
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    HDC screen = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(screen);
    void* textBits = nullptr;
    HBITMAP textBitmap = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &textBits, nullptr, 0);
    void* colorBits = nullptr;
    HBITMAP colorBitmap = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &colorBits, nullptr, 0);
    ReleaseDC(nullptr, screen);
    if (!textBitmap || !colorBitmap) {
        if (textBitmap) DeleteObject(textBitmap);
        if (colorBitmap) DeleteObject(colorBitmap);
        DeleteDC(dc);
        return nullptr;
    }

    // 1. Render the letter white-on-black; its brightness is the coverage.
    HGDIOBJ oldBitmap = SelectObject(dc, textBitmap);
    RECT rc = {0, 0, size, size};
    FillRect(dc, &rc, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    HFONT font = CreateFontW(-MulDiv(size, 80, 100), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, VARIABLE_PITCH, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    wchar_t text[2] = {letter, 0};
    DrawTextW(dc, text, 1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();
    SelectObject(dc, oldFont);
    DeleteObject(font);
    SelectObject(dc, oldBitmap);

    // 2. Compose: background square, white letter, straight alpha.
    const BYTE* src = static_cast<const BYTE*>(textBits);
    BYTE* dst = static_cast<BYTE*>(colorBits);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            size_t i = (static_cast<size_t>(y) * size + x) * 4;
            double t = src[i + 2] / 255.0;
            double a = RoundedSquareCoverage(x, y, size);
            dst[i + 0] = static_cast<BYTE>(GetBValue(background) * (1 - t) + 255 * t);
            dst[i + 1] = static_cast<BYTE>(GetGValue(background) * (1 - t) + 255 * t);
            dst[i + 2] = static_cast<BYTE>(GetRValue(background) * (1 - t) + 255 * t);
            dst[i + 3] = static_cast<BYTE>(a * 255 + 0.5);
        }
    }

    HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
    ICONINFO info = {};
    info.fIcon = TRUE;
    info.hbmMask = mask;
    info.hbmColor = colorBitmap;
    HICON icon = CreateIconIndirect(&info);
    DeleteObject(mask);
    DeleteObject(colorBitmap);
    DeleteObject(textBitmap);
    DeleteDC(dc);
    return icon;
}

void CreateTrayIcons() {
    int size = GetSystemMetrics(SM_CXSMICON);
    if (size < 16) size = 16;
    if (g_iconVietnamese) DestroyIcon(g_iconVietnamese);
    if (g_iconEnglish) DestroyIcon(g_iconEnglish);
    g_iconVietnamese = MakeLetterIcon(L'V', RGB(0xD7, 0x26, 0x1E), size);
    g_iconEnglish = MakeLetterIcon(L'E', RGB(0x5F, 0x63, 0x68), size);
}

// ---- tray ----------------------------------------------------------------------

void FillTrayData(HWND hwnd, NOTIFYICONDATAW& nid) {
    nid = {};
    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = kTrayId;
    nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE | NIF_SHOWTIP;
    nid.uCallbackMessage = WM_TRAY;
    nid.hIcon = g_settings.vietnamese ? g_iconVietnamese : g_iconEnglish;
    const wchar_t* method = g_settings.method == DOKEY_VNI ? L"VNI" : L"Telex";
    if (g_settings.vietnamese) {
        wsprintfW(nid.szTip, L"Dokey - Tiếng Việt (%s)", method);
    } else {
        lstrcpynW(nid.szTip, L"Dokey - English", ARRAYSIZE(nid.szTip));
    }
}

void AddTrayIcon(HWND hwnd) {
    NOTIFYICONDATAW nid;
    FillTrayData(hwnd, nid);
    Shell_NotifyIconW(NIM_ADD, &nid);
    nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &nid);
}

void UpdateTrayIcon(HWND hwnd) {
    NOTIFYICONDATAW nid;
    FillTrayData(hwnd, nid);
    if (!Shell_NotifyIconW(NIM_MODIFY, &nid)) AddTrayIcon(hwnd);
}

void RemoveTrayIcon(HWND hwnd) {
    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = kTrayId;
    Shell_NotifyIconW(NIM_DELETE, &nid);
}

void Apply(HWND hwnd) {
    SaveSettings(g_settings);
    UpdateKeyboard(g_settings);
    UpdateTrayIcon(hwnd);
}

void ShowMenu(HWND hwnd, int x, int y) {
    HMENU menu = CreatePopupMenu();
    HMENU hotkeys = CreatePopupMenu();
    const UINT checked = MF_STRING | MF_CHECKED, unchecked = MF_STRING | MF_UNCHECKED;
    auto check = [&](bool on) { return on ? checked : unchecked; };

    const wchar_t* toggleLabel = g_settings.hotkey == HOTKEY_ALT_Z ? L"Gõ tiếng Việt\tAlt+Z" : L"Gõ tiếng Việt\tCtrl+Shift";
    AppendMenuW(menu, check(g_settings.vietnamese), CMD_TOGGLE, toggleLabel);
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, check(g_settings.method == DOKEY_TELEX), CMD_TELEX, L"Kiểu gõ Telex");
    AppendMenuW(menu, check(g_settings.method == DOKEY_VNI), CMD_VNI, L"Kiểu gõ VNI");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, check(g_settings.checkSpelling), CMD_SPELLING, L"Kiểm tra chính tả");
    AppendMenuW(menu, check(g_settings.modernTone), CMD_TONE_MODERN, L"Dấu kiểu mới (hoà, khoẻ, thuý)");
    AppendMenuW(menu, check(!g_settings.modernTone), CMD_TONE_CLASSIC, L"Dấu kiểu cũ (hòa, khỏe, thúy)");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(hotkeys, check(g_settings.hotkey == HOTKEY_CTRL_SHIFT), CMD_HOTKEY_CTRL_SHIFT, L"Ctrl+Shift");
    AppendMenuW(hotkeys, check(g_settings.hotkey == HOTKEY_ALT_Z), CMD_HOTKEY_ALT_Z, L"Alt+Z");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(hotkeys), L"Phím tắt chuyển Anh/Việt");
    AppendMenuW(menu, check(IsStartupEnabled()), CMD_STARTUP, L"Khởi động cùng Windows");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, CMD_ABOUT, L"Giới thiệu Dokey");
    AppendMenuW(menu, MF_STRING, CMD_EXIT, L"Thoát");

    // Without this the menu does not close when the user clicks elsewhere.
    SetForegroundWindow(hwnd);
    UINT flags = TPM_RIGHTBUTTON | (GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN : TPM_LEFTALIGN);
    TrackPopupMenuEx(menu, flags, x, y, hwnd, nullptr);
    PostMessageW(hwnd, WM_NULL, 0, 0);
    DestroyMenu(menu);  // also destroys the submenu
}

void ShowAbout(HWND hwnd) {
    wchar_t text[512];
    wsprintfW(text,
              L"Dokey %s\n"
              L"Bộ gõ tiếng Việt cho Windows, dùng lõi Dokey Core.\n\n"
              L"Bật/tắt tiếng Việt: bấm vào biểu tượng V/E hoặc dùng phím tắt.\n\n"
              L"Copyright © 2026 Do Huy Toan.",
              DOKEY_APP_VERSION_W);
    MessageBoxW(hwnd, text, L"Dokey", MB_OK | MB_ICONINFORMATION);
}

void OnCommand(HWND hwnd, UINT id) {
    switch (id) {
        case CMD_TOGGLE: g_settings.vietnamese = !g_settings.vietnamese; break;
        case CMD_TELEX: g_settings.method = DOKEY_TELEX; break;
        case CMD_VNI: g_settings.method = DOKEY_VNI; break;
        case CMD_SPELLING: g_settings.checkSpelling = !g_settings.checkSpelling; break;
        case CMD_TONE_MODERN: g_settings.modernTone = true; break;
        case CMD_TONE_CLASSIC: g_settings.modernTone = false; break;
        case CMD_HOTKEY_CTRL_SHIFT: g_settings.hotkey = HOTKEY_CTRL_SHIFT; break;
        case CMD_HOTKEY_ALT_Z: g_settings.hotkey = HOTKEY_ALT_Z; break;
        case CMD_STARTUP: SetStartupEnabled(!IsStartupEnabled()); return;
        case CMD_ABOUT: ShowAbout(hwnd); return;
        case CMD_EXIT: DestroyWindow(hwnd); return;
        default: return;
    }
    Apply(hwnd);
}

// ---- IME detection ---------------------------------------------------------------

// Asks the focused window whether an East Asian (or Microsoft Vietnamese) IME
// is open; Dokey stays out of the way while it is. SendMessageTimeout keeps a
// hung application from freezing Dokey; the answer is cached per window.
void CheckIme(bool force) {
    static HWND lastWindow = nullptr;
    static HKL lastLayout = nullptr;
    static ULONGLONG lastCheck = 0;
    static bool lastResult = false;

    HWND foreground = GetForegroundWindow();
    HKL layout = GetKeyboardLayout(GetWindowThreadProcessId(foreground, nullptr));
    ULONGLONG now = GetTickCount64();
    if (!force && foreground == lastWindow && layout == lastLayout && now - lastCheck < 3000) return;

    bool active = false;
    switch (PRIMARYLANGID(LOWORD(reinterpret_cast<UINT_PTR>(layout)))) {
        case LANG_CHINESE: case LANG_JAPANESE: case LANG_KOREAN: case LANG_VIETNAMESE: {
            HWND ime = ImmGetDefaultIMEWnd(foreground);
            DWORD_PTR open = 0;
            if (ime && SendMessageTimeoutW(ime, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0,
                                           SMTO_ABORTIFHUNG | SMTO_BLOCK, 50, &open)) {
                active = open != 0;
            }
            break;
        }
        default:
            break;
    }
    lastWindow = foreground;
    lastLayout = layout;
    lastCheck = now;
    if (active != lastResult || force) {
        lastResult = active;
        SetImeActive(active);
    }
}

// ---- window --------------------------------------------------------------------

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE:
            AddTrayIcon(hwnd);
            SetTimer(hwnd, kImeTimer, kImeTimerMs, nullptr);
            return 0;
        case WM_TRAY:
            switch (LOWORD(lParam)) {
                case NIN_SELECT:
                case NIN_KEYSELECT:
                    OnCommand(hwnd, CMD_TOGGLE);
                    break;
                case WM_CONTEXTMENU:
                    ShowMenu(hwnd, GET_X_LPARAM(wParam), GET_Y_LPARAM(wParam));
                    break;
                default:
                    break;
            }
            return 0;
        case WM_COMMAND:
            OnCommand(hwnd, LOWORD(wParam));
            return 0;
        case WM_DOKEY_TOGGLED:
            g_settings.vietnamese = wParam != 0;
            SaveSettings(g_settings);
            UpdateTrayIcon(hwnd);
            return 0;
        case WM_DOKEY_FOCUS:
            CheckIme(true);
            return 0;
        case WM_TIMER:
            if (wParam == kImeTimer) CheckIme(false);
            return 0;
        case WM_SETTINGCHANGE:
        case WM_DISPLAYCHANGE:
            CreateTrayIcons();
            UpdateTrayIcon(hwnd);
            return 0;
        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            KillTimer(hwnd, kImeTimer);
            RemoveTrayIcon(hwnd);
            PostQuitMessage(0);
            return 0;
        default:
            if (msg == g_taskbarCreated && g_taskbarCreated != 0) {  // Explorer restarted
                AddTrayIcon(hwnd);
                return 0;
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}

} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR commandLine, int) {
    g_instance = instance;
    // --self-test: install and remove the hooks, then exit (used by CI).
    const bool selfTest = commandLine && wcsstr(commandLine, L"--self-test") != nullptr;
    HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
    if (GetLastError() == ERROR_ALREADY_EXISTS && !selfTest) {
        MessageBoxW(nullptr, L"Dokey đang chạy. Biểu tượng V/E nằm ở khay hệ thống, góc phải thanh tác vụ.",
                    L"Dokey", MB_OK | MB_ICONINFORMATION);
        return 0;
    }

    g_settings = LoadSettings();
    g_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    CreateTrayIcons();

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_DOKEY));
    wc.lpszClassName = kWindowClass;
    RegisterClassExW(&wc);
    // A hidden top-level window (not message-only) so the installer can find it.
    HWND hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, kWindowClass, L"Dokey", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
                                instance, nullptr);
    if (!hwnd) return 1;

    if (selfTest) {
        bool ok = StartKeyboard(hwnd, g_settings);
        if (ok) StopKeyboard();
        DestroyWindow(hwnd);
        return ok ? 0 : 2;
    }
    if (!StartKeyboard(hwnd, g_settings)) {
        MessageBoxW(hwnd, L"Không cài được bộ bắt phím của Windows. Dokey sẽ thoát.", L"Dokey", MB_OK | MB_ICONERROR);
        DestroyWindow(hwnd);
        return 1;
    }

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    StopKeyboard();
    if (g_iconVietnamese) DestroyIcon(g_iconVietnamese);
    if (g_iconEnglish) DestroyIcon(g_iconEnglish);
    if (mutex) {
        ReleaseMutex(mutex);
        CloseHandle(mutex);
    }
    return 0;
}
