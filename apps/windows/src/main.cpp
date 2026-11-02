// Dokey for Windows - tray application.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include <windows.h>
#include <commctrl.h>
#include <imm.h>
#include <shellapi.h>
#include <windowsx.h>

#include <atomic>
#include <cstdio>
#include <ctime>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "dokey/dokey.h"
#include "keyboard.h"
#include "panel.h"
#include "resource.h"
#include "settings.h"
#include "updater.h"
#include "version.h"

using namespace dokey_win;

#ifndef IMC_GETOPENSTATUS
#define IMC_GETOPENSTATUS 0x0005  // from <ime.h>
#endif

namespace {

const wchar_t kWindowClass[] = L"DokeyMainWindow";  // also used by the installer
const wchar_t kMutexName[] = L"DokeyAppMutex";      // also used by the installer
constexpr UINT WM_TRAY = WM_APP + 10;
constexpr UINT WM_DOKEY_SHOWPANEL = WM_APP + 11;  // posted by a second Dokey.exe
constexpr UINT WM_DOKEY_UPDATE_CHECKED = WM_APP + 12;  // wParam: interactive, lParam: Release* or null
constexpr UINT kTrayId = 1;
constexpr UINT_PTR kImeTimer = 1;
constexpr UINT kImeTimerMs = 1000;
constexpr UINT_PTR kUpdateTimer = 2;
constexpr UINT kFirstUpdateCheckMs = 20 * 1000;             // soon after start
constexpr UINT kUpdateCheckEveryMs = 3 * 60 * 60 * 1000;    // then every 3 hours...
constexpr ULONGLONG kUpdateCheckGapSeconds = 12 * 60 * 60;  // ...but at most twice a day

enum Command : UINT {
    CMD_PANEL = 99,
    CMD_TOGGLE = 100,
    CMD_TELEX,
    CMD_VNI,
    CMD_SPELLING,
    CMD_TONE_MODERN,
    CMD_TONE_CLASSIC,
    CMD_HOTKEY_CTRL_SHIFT,
    CMD_HOTKEY_ALT_Z,
    CMD_STARTUP,
    CMD_EXCLUDE,
    CMD_LANG_VIETNAMESE,
    CMD_LANG_KOREAN,
    CMD_ABOUT,
    CMD_CHECK_UPDATES,
    CMD_INSTALL_UPDATE,
    CMD_EXIT,
};

HINSTANCE g_instance = nullptr;
Settings g_settings;
HICON g_iconVietnamese = nullptr;
HICON g_iconKorean = nullptr;
HICON g_iconEnglish = nullptr;
UINT g_taskbarCreated = 0;
HWND g_mainWindow = nullptr;
bool g_imeActive = false;
std::wstring g_appName;  // the application the user last typed in
std::wstring g_appExe;   // its exe name, for the excluded list
bool g_appChromium = false;
std::unique_ptr<Release> g_update;  // a newer release found by the last check
bool g_checkingUpdates = false;
bool g_installingUpdate = false;
bool g_balloonIsUpdate = false;     // a click on the tray balloon opens the update dialog

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
    const bool hangul = letter >= 0xAC00 && letter <= 0xD7A3;  // "한": a wider glyph, Malgun Gothic
    HFONT font = CreateFontW(-MulDiv(size, hangul ? 66 : 80, 100), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, VARIABLE_PITCH,
                             hangul ? L"Malgun Gothic" : L"Segoe UI");
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
    if (g_iconKorean) DestroyIcon(g_iconKorean);
    g_iconVietnamese = MakeLetterIcon(L'V', RGB(0xD7, 0x26, 0x1E), size);
    g_iconKorean = MakeLetterIcon(L'\uD55C', RGB(0x1F, 0x4F, 0xB8), size);  // 한
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
    const bool korean = g_settings.language == LANGUAGE_KOREAN;
    nid.hIcon = !g_settings.vietnamese ? g_iconEnglish : korean ? g_iconKorean : g_iconVietnamese;
    const wchar_t* method = g_settings.method == DOKEY_VNI ? L"VNI" : L"Telex";
    if (g_settings.vietnamese && korean) {
        lstrcpynW(nid.szTip, L"Dokey - 한국어 (두벌식)", ARRAYSIZE(nid.szTip));
    } else if (g_settings.vietnamese) {
        wsprintfW(nid.szTip, Tr(L"Dokey - Tiếng Việt (%s)", L"Dokey - 베트남어 (%s)"), method);
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
    RefreshPanel();
}

// ---- updates ---------------------------------------------------------------------

ULONGLONG NowSeconds() { return static_cast<ULONGLONG>(time(nullptr)); }

// A Windows notification from the tray icon. `update`: clicking it opens the update dialog.
void ShowBalloon(HWND hwnd, const std::wstring& title, const std::wstring& text, bool update) {
    NOTIFYICONDATAW nid;
    FillTrayData(hwnd, nid);
    nid.uFlags |= NIF_INFO;
    lstrcpynW(nid.szInfoTitle, title.c_str(), ARRAYSIZE(nid.szInfoTitle));
    lstrcpynW(nid.szInfo, text.c_str(), ARRAYSIZE(nid.szInfo));
    nid.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
    g_balloonIsUpdate = update;
    Shell_NotifyIconW(NIM_MODIFY, &nid);
}

// `interactive`: from the menu or the panel, always answers. Otherwise at most
// twice a day, and only a notification when there is a new version.
void CheckForUpdates(HWND hwnd, bool interactive) {
    if (g_checkingUpdates || g_installingUpdate) return;
    if (!interactive) {
        if (!g_settings.autoCheckUpdates) return;
        if (g_settings.lastUpdateCheck && NowSeconds() < g_settings.lastUpdateCheck + kUpdateCheckGapSeconds) return;
    }
    g_checkingUpdates = true;
    std::thread([hwnd, interactive] {
        auto release = std::make_unique<Release>();
        Release* found = FetchLatestRelease(*release) ? release.release() : nullptr;
        if (!PostMessageW(hwnd, WM_DOKEY_UPDATE_CHECKED, interactive ? 1 : 0, reinterpret_cast<LPARAM>(found))) {
            delete found;
        }
    }).detach();
}

int Ask(const std::wstring& text, UINT flags) {
    return MessageBoxW(nullptr, text.c_str(), L"Dokey", flags | MB_SETFOREGROUND | MB_TOPMOST);
}

// The download, shared by the worker thread and the progress dialog.
struct DownloadJob {
    Release release;
    std::wstring path;
    std::wstring error;
    std::atomic<unsigned long long> received{0};
    std::atomic<int> state{0};  // 0 running, 1 done, -1 failed
    std::atomic<bool> cancel{false};
};

bool OnDownloadProgress(unsigned long long received, unsigned long long, void* context) {
    auto* job = static_cast<DownloadJob*>(context);
    job->received = received;
    return !job->cancel;
}

HRESULT CALLBACK DownloadDialogProc(HWND dialog, UINT notification, WPARAM, LPARAM, LONG_PTR data) {
    auto* job = reinterpret_cast<DownloadJob*>(data);
    if (notification == TDN_CREATED) {
        SendMessageW(dialog, TDM_SET_PROGRESS_BAR_RANGE, 0, MAKELPARAM(0, 100));
    } else if (notification == TDN_TIMER) {
        if (job->state != 0) {
            SendMessageW(dialog, TDM_CLICK_BUTTON, IDCANCEL, 0);
            return S_OK;
        }
        const unsigned long long total = job->release.size, received = job->received;
        if (total) SendMessageW(dialog, TDM_SET_PROGRESS_BAR_POS, static_cast<WPARAM>(received * 100 / total), 0);
        wchar_t text[96];
        swprintf(text, ARRAYSIZE(text), L"%.1f / %.1f MB", received / 1048576.0, total / 1048576.0);
        SendMessageW(dialog, TDM_UPDATE_ELEMENT_TEXT, TDE_CONTENT, reinterpret_cast<LPARAM>(text));
    }
    return S_OK;
}

void InstallUpdate(HWND hwnd, const Release& release) {
    if (g_installingUpdate) return;
    auto job = std::make_shared<DownloadJob>();
    job->release = release;
    job->path = UpdateFolder() + L"\\Dokey-" + release.version + L"-Windows-Setup.exe";
    std::thread([job] {
        std::wstring error;
        const bool ok = DownloadInstaller(job->release, job->path, OnDownloadProgress, job.get(), error);
        job->error = error;
        job->state = ok ? 1 : -1;
    }).detach();

    std::wstring title = std::wstring(Tr(L"Đang tải Dokey ", L"Dokey 내려받는 중: ")) + release.version;
    TASKDIALOGCONFIG config = {};
    config.cbSize = sizeof(config);
    config.dwFlags = TDF_SHOW_PROGRESS_BAR | TDF_CALLBACK_TIMER | TDF_ALLOW_DIALOG_CANCELLATION;
    config.dwCommonButtons = TDCBF_CANCEL_BUTTON;
    config.pszWindowTitle = L"Dokey";
    config.pszMainInstruction = title.c_str();
    config.pszContent = L"0.0 MB";
    config.pszFooter = Tr(L"Dokey kiểm tra mã SHA-256 rồi cài đè đúng chỗ cũ và tự mở lại.",
                          L"SHA-256을 확인한 뒤 같은 위치에 설치하고 다시 엽니다.");
    config.pfCallback = DownloadDialogProc;
    config.lpCallbackData = reinterpret_cast<LONG_PTR>(job.get());
    TaskDialogIndirect(&config, nullptr, nullptr, nullptr);

    if (job->state == 0) {  // cancelled by the user
        job->cancel = true;
        return;
    }
    std::wstring error = job->error;
    if (job->state == 1 && RunInstaller(job->path, error)) {
        g_installingUpdate = true;  // the installer closes this Dokey and starts the new one
        return;
    }
    std::wstring text = std::wstring(Tr(L"Chưa cập nhật được Dokey: ", L"Dokey를 업데이트하지 못했습니다: ")) + error +
                        Tr(L".\nBản đang dùng vẫn giữ nguyên.\n\nMở trang phát hành để tải bằng tay?",
                           L".\n현재 버전은 그대로 유지됩니다.\n\n릴리스 페이지를 열까요?");
    if (Ask(text, MB_YESNO | MB_ICONWARNING) == IDYES) {
        ShellExecuteW(hwnd, L"open", release.page.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    }
}

enum { BUTTON_UPDATE = 100, BUTTON_LATER, BUTTON_SKIP };

// The update dialog for the release the last check found.
void OfferUpdate(HWND hwnd) {
    if (!g_update) {
        CheckForUpdates(hwnd, true);
        return;
    }
    const Release release = *g_update;
    const bool canInstall = !release.installer.empty();
    std::wstring instruction = std::wstring(Tr(L"Đã có Dokey ", L"새 버전: Dokey ")) + release.version;
    std::wstring content = std::wstring(Tr(L"Bạn đang dùng bản ", L"현재 버전: ")) + DOKEY_APP_VERSION_W + L".\n\n" +
                           (canInstall ? Tr(L"Dokey sẽ tự tải bản mới, kiểm tra mã SHA-256, cài đè đúng chỗ cũ rồi mở lại. "
                                            L"Không cần tải hay cài bằng tay.",
                                            L"Dokey가 새 버전을 내려받아 SHA-256을 확인하고, 같은 위치에 설치한 뒤 다시 엽니다. "
                                            L"직접 내려받거나 설치할 필요가 없습니다.")
                                       : Tr(L"Bản này chưa có bộ cài Windows. Mở trang phát hành để xem.",
                                            L"이 버전에는 Windows 설치 파일이 없습니다. 릴리스 페이지를 확인하세요."));
    const TASKDIALOG_BUTTON buttons[] = {
        {BUTTON_UPDATE, canInstall ? Tr(L"Cập nhật ngay", L"지금 업데이트") : Tr(L"Mở trang phát hành", L"릴리스 페이지 열기")},
        {BUTTON_LATER, Tr(L"Để sau", L"나중에")},
        {BUTTON_SKIP, Tr(L"Bỏ qua bản này", L"이 버전 건너뛰기")},
    };
    TASKDIALOGCONFIG config = {};
    config.cbSize = sizeof(config);
    config.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_EXPANDED_BY_DEFAULT | TDF_EXPAND_FOOTER_AREA;
    config.pszWindowTitle = L"Dokey";
    config.pszMainIcon = TD_INFORMATION_ICON;
    config.pszMainInstruction = instruction.c_str();
    config.pszContent = content.c_str();
    if (!release.notes.empty()) {
        config.pszExpandedInformation = release.notes.c_str();
        config.pszExpandedControlText = Tr(L"Ẩn ghi chú phát hành", L"릴리스 노트 숨기기");
        config.pszCollapsedControlText = Tr(L"Có gì mới", L"새로운 기능");
    }
    config.pButtons = buttons;
    config.cButtons = ARRAYSIZE(buttons);
    config.nDefaultButton = BUTTON_UPDATE;
    int pressed = 0;
    SetForegroundWindow(hwnd);
    if (FAILED(TaskDialogIndirect(&config, &pressed, nullptr, nullptr))) return;
    if (pressed == BUTTON_UPDATE) {
        if (canInstall) InstallUpdate(hwnd, release);
        else ShellExecuteW(hwnd, L"open", release.page.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    } else if (pressed == BUTTON_SKIP) {
        g_settings.skippedVersion = release.version;
        SaveSettings(g_settings);
    }
}

void OnUpdateChecked(HWND hwnd, bool interactive, Release* found) {
    std::unique_ptr<Release> release(found);
    g_checkingUpdates = false;
    if (release) {
        g_settings.lastUpdateCheck = NowSeconds();
        SaveSettings(g_settings);
    }
    if (release && IsNewerVersion(release->version, DOKEY_APP_VERSION_W)) {
        const bool fresh = !g_update || g_update->version != release->version;
        g_update = std::move(release);
        RefreshPanel();
        if (interactive) {
            OfferUpdate(hwnd);
        } else if (fresh && g_settings.skippedVersion != g_update->version) {
            ShowBalloon(hwnd, std::wstring(Tr(L"Đã có Dokey ", L"새 버전: Dokey ")) + g_update->version,
                        Tr(L"Bấm để xem có gì mới và cập nhật ngay trên máy.",
                           L"클릭하면 새 기능을 보고 바로 업데이트할 수 있습니다."),
                        true);
        }
        return;
    }
    if (!interactive) return;
    if (release) {
        Ask(std::wstring(Tr(L"Bạn đang dùng bản mới nhất: Dokey ", L"최신 버전을 사용하고 있습니다: Dokey ")) + DOKEY_APP_VERSION_W + L".",
            MB_OK | MB_ICONINFORMATION);
    } else {
        Ask(Tr(L"Không kiểm tra được bản mới. Hãy kiểm tra kết nối mạng rồi thử lại.",
               L"새 버전을 확인할 수 없습니다. 네트워크를 확인한 뒤 다시 시도하세요."),
            MB_OK | MB_ICONWARNING);
    }
}

// --download-update <folder>: fetch the latest release, download and verify its
// installer, write <folder>\result.txt and exit (used by CI).
int DownloadUpdateTest(const std::wstring& folder) {
    Release release;
    std::wstring error;
    bool ok = FetchLatestRelease(release);
    if (!ok) error = L"cannot read the latest release";
    const std::wstring path = folder + L"\\Dokey-" + release.version + L"-Windows-Setup.exe";
    if (ok) ok = DownloadInstaller(release, path, nullptr, nullptr, error);
    FILE* out = _wfopen((folder + L"\\result.txt").c_str(), L"w, ccs=UTF-8");
    if (out) {
        fwprintf(out, L"version=%ls\nnewer=%d\ninstaller=%ls\nsize=%llu\nsha256=%hs\nok=%d\nerror=%ls\nnotes=%ls\n",
                 release.version.c_str(), IsNewerVersion(release.version, DOKEY_APP_VERSION_W) ? 1 : 0,
                 release.installer.c_str(), release.size, release.sha256.c_str(), ok ? 1 : 0, error.c_str(),
                 release.notes.substr(0, 200).c_str());
        fclose(out);
    }
    return ok ? 0 : 3;
}

// ---- control panel ---------------------------------------------------------------

// "Google Chrome" for chrome.exe: the file description, else the file name.
std::wstring AppNameOf(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return L"";
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    BOOL ok = QueryFullProcessImageNameW(process, 0, path, &size);
    CloseHandle(process);
    if (!ok) return L"";

    std::wstring name;
    DWORD handle = 0, infoSize = GetFileVersionInfoSizeW(path, &handle);
    std::vector<BYTE> info(infoSize);
    struct Translation {
        WORD language, codePage;
    }* translation = nullptr;
    UINT length = 0;
    if (infoSize && GetFileVersionInfoW(path, 0, infoSize, info.data()) &&
        VerQueryValueW(info.data(), L"\\VarFileInfo\\Translation", reinterpret_cast<void**>(&translation), &length) &&
        length >= sizeof(Translation)) {
        wchar_t query[64];
        wsprintfW(query, L"\\StringFileInfo\\%04x%04x\\FileDescription", translation->language, translation->codePage);
        wchar_t* description = nullptr;
        if (VerQueryValueW(info.data(), query, reinterpret_cast<void**>(&description), &length) && length > 1) {
            name = description;
        }
    }
    if (name.empty()) {
        const wchar_t* file = wcsrchr(path, L'\\');
        name = file ? file + 1 : path;
        size_t dot = name.rfind(L'.');
        if (dot != std::wstring::npos) name.erase(dot);
    }
    return name;
}

// Remembers the foreground application for the dashboard (not Dokey itself).
void TrackForegroundApp() {
    HWND foreground = GetForegroundWindow();
    DWORD pid = 0;
    if (!foreground || !GetWindowThreadProcessId(foreground, &pid) || pid == GetCurrentProcessId()) return;
    static DWORD lastPid = 0;
    wchar_t className[64] = {};
    GetClassNameW(foreground, className, ARRAYSIZE(className));
    g_appChromium = wcsncmp(className, L"Chrome_WidgetWin_", 17) == 0;
    if (pid == lastPid && !g_appName.empty()) return;
    lastPid = pid;
    g_appName = AppNameOf(pid);
    g_appExe = ExeNameOf(pid);
}

void PanelSettingsChanged() { Apply(g_mainWindow); }

PanelStatus PanelState() {
    PanelStatus status;
    status.imeActive = g_imeActive;
    status.appName = g_appName;
    status.appChromium = g_appChromium;
    status.appExe = g_appExe;
    status.markedWords = MarkedWordCount();
    if (g_update) status.updateVersion = g_update->version;
    return status;
}

void PanelCheckUpdates() { OfferUpdate(g_mainWindow); }

void ShowMenu(HWND hwnd, int x, int y) {
    HMENU menu = CreatePopupMenu();
    HMENU hotkeys = CreatePopupMenu();
    if (g_update) {
        std::wstring label = std::wstring(Tr(L"\u2B06 Cập nhật lên Dokey ", L"\u2B06 Dokey 업데이트: ")) + g_update->version + L"\u2026";
        AppendMenuW(menu, MF_STRING, CMD_INSTALL_UPDATE, label.c_str());
    }
    AppendMenuW(menu, MF_STRING, CMD_PANEL, Tr(L"Mở bảng điều khiển", L"제어판 열기"));
    SetMenuDefaultItem(menu, CMD_PANEL, FALSE);
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    const UINT checked = MF_STRING | MF_CHECKED, unchecked = MF_STRING | MF_UNCHECKED;
    auto check = [&](bool on) { return on ? checked : unchecked; };

    const bool korean = g_settings.language == LANGUAGE_KOREAN;
    std::wstring toggleLabel = korean ? Tr(L"Gõ tiếng Hàn", L"한국어 입력") : Tr(L"Gõ tiếng Việt", L"베트남어 입력");
    toggleLabel += g_settings.hotkey == HOTKEY_ALT_Z ? L"\tAlt+Z" : L"\tCtrl+Shift";
    AppendMenuW(menu, check(g_settings.vietnamese), CMD_TOGGLE, toggleLabel.c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, check(!korean), CMD_LANG_VIETNAMESE, Tr(L"Tiếng Việt", L"베트남어 (Tiếng Việt)"));
    AppendMenuW(menu, check(korean), CMD_LANG_KOREAN, Tr(L"Tiếng Hàn (한국어, 두벌식)", L"한국어 (두벌식)"));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    if (!korean) {  // Vietnamese options
        AppendMenuW(menu, check(g_settings.method == DOKEY_TELEX), CMD_TELEX, Tr(L"Kiểu gõ Telex", L"Telex 입력"));
        AppendMenuW(menu, check(g_settings.method == DOKEY_VNI), CMD_VNI, Tr(L"Kiểu gõ VNI", L"VNI 입력"));
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, check(g_settings.checkSpelling), CMD_SPELLING, Tr(L"Kiểm tra chính tả", L"맞춤법 검사"));
        AppendMenuW(menu, check(g_settings.modernTone), CMD_TONE_MODERN,
                    Tr(L"Dấu kiểu mới (hoà, khoẻ, thuý)", L"새 성조 위치 (hoà, khoẻ, thuý)"));
        AppendMenuW(menu, check(!g_settings.modernTone), CMD_TONE_CLASSIC,
                    Tr(L"Dấu kiểu cũ (hòa, khỏe, thúy)", L"옛 성조 위치 (hòa, khỏe, thúy)"));
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    }
    AppendMenuW(hotkeys, check(g_settings.hotkey == HOTKEY_CTRL_SHIFT), CMD_HOTKEY_CTRL_SHIFT, L"Ctrl+Shift");
    AppendMenuW(hotkeys, check(g_settings.hotkey == HOTKEY_ALT_Z), CMD_HOTKEY_ALT_Z, L"Alt+Z");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(hotkeys),
                korean ? Tr(L"Phím tắt chuyển Anh/Hàn", L"한/영 전환 키") : Tr(L"Phím tắt chuyển Anh/Việt", L"전환 단축키"));
    AppendMenuW(menu, check(IsStartupEnabled()), CMD_STARTUP, Tr(L"Khởi động cùng Windows", L"Windows 시작 시 실행"));
    if (!g_appExe.empty()) {
        std::wstring label = UiKorean() ? g_appName + L"에서 사용 안 함" : L"Không gõ tiếng Việt trong " + g_appName;
        AppendMenuW(menu, check(IsExcluded(g_settings, g_appExe)), CMD_EXCLUDE, label.c_str());
    }
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, CMD_CHECK_UPDATES, Tr(L"Kiểm tra cập nhật\u2026", L"업데이트 확인\u2026"));
    AppendMenuW(menu, MF_STRING, CMD_ABOUT, Tr(L"Giới thiệu Dokey", L"Dokey 정보"));
    AppendMenuW(menu, MF_STRING, CMD_EXIT, Tr(L"Thoát", L"종료"));

    // Without this the menu does not close when the user clicks elsewhere.
    SetForegroundWindow(hwnd);
    UINT flags = TPM_RIGHTBUTTON | (GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN : TPM_LEFTALIGN);
    TrackPopupMenuEx(menu, flags, x, y, hwnd, nullptr);
    PostMessageW(hwnd, WM_NULL, 0, 0);
    DestroyMenu(menu);  // also destroys the submenu
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
        case CMD_PANEL: ShowPanel(0); return;
        case CMD_LANG_VIETNAMESE: g_settings.language = LANGUAGE_VIETNAMESE; g_settings.vietnamese = true; break;
        case CMD_LANG_KOREAN: g_settings.language = LANGUAGE_KOREAN; g_settings.vietnamese = true; break;
        case CMD_EXCLUDE: SetExcluded(g_settings, g_appExe, !IsExcluded(g_settings, g_appExe)); break;
        case CMD_ABOUT: ShowPanel(4); return;
        case CMD_CHECK_UPDATES: CheckForUpdates(hwnd, true); return;
        case CMD_INSTALL_UPDATE: OfferUpdate(hwnd); return;
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
        g_imeActive = active;
        SetImeActive(active);
    }
}

// ---- window --------------------------------------------------------------------

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE:
            AddTrayIcon(hwnd);
            SetTimer(hwnd, kImeTimer, kImeTimerMs, nullptr);
            SetTimer(hwnd, kUpdateTimer, kFirstUpdateCheckMs, nullptr);
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
                case NIN_BALLOONUSERCLICK:
                    if (g_balloonIsUpdate) OfferUpdate(hwnd);
                    g_balloonIsUpdate = false;
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
            RefreshPanel();
            return 0;
        case WM_DOKEY_FOCUS:
            CheckIme(true);
            TrackForegroundApp();
            return 0;
        case WM_DOKEY_UNEXCLUDE: {
            std::unique_ptr<std::wstring> exe(reinterpret_cast<std::wstring*>(lParam));
            if (exe) SetExcluded(g_settings, *exe, false);
            SaveSettings(g_settings);  // the input thread already has the change
            RefreshPanel();
            return 0;
        }
        case WM_DOKEY_SHOWPANEL:
            ShowPanel(0);
            return 0;
        case WM_TIMER:
            if (wParam == kImeTimer) CheckIme(false);
            if (wParam == kUpdateTimer) {
                SetTimer(hwnd, kUpdateTimer, kUpdateCheckEveryMs, nullptr);
                CheckForUpdates(hwnd, false);
            }
            return 0;
        case WM_DOKEY_UPDATE_CHECKED:
            OnUpdateChecked(hwnd, wParam != 0, reinterpret_cast<Release*>(lParam));
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
            KillTimer(hwnd, kUpdateTimer);
            ShutdownPanel();
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

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    g_instance = instance;
    // --self-test: install and remove the hooks, then exit (used by CI).
    // --background: start in the tray without opening the control panel (sign-in).
    // --render-panel <prefix>: draw the control panel pages to PNG files and exit.
    // --updated: started by the installer after an update (tray only, a notification).
    // --download-update <folder>: download and verify the latest installer, then exit (CI).
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    bool selfTest = false, background = false, updated = false;
    std::wstring renderPrefix, downloadFolder;
    for (int i = 1; argv && i < argc; i++) {
        if (wcscmp(argv[i], L"--self-test") == 0) selfTest = true;
        if (wcscmp(argv[i], L"--background") == 0) background = true;
        if (wcscmp(argv[i], L"--updated") == 0) background = updated = true;
        if (wcscmp(argv[i], L"--download-update") == 0 && i + 1 < argc) downloadFolder = argv[++i];
        if (wcscmp(argv[i], L"--render-panel") == 0 && i + 1 < argc) renderPrefix = argv[++i];
        if (wcscmp(argv[i], L"--ui-lang") == 0 && i + 1 < argc) SetUiKorean(wcscmp(argv[++i], L"ko") == 0);
    }
    if (argv) LocalFree(argv);

    g_settings = LoadSettings();
    if (!downloadFolder.empty()) return DownloadUpdateTest(downloadFolder);
    if (!renderPrefix.empty()) {
        if (!InitPanel(instance, &g_settings, {})) return 2;
        int result = RenderPanelImages(renderPrefix.c_str());
        ShutdownPanel();
        return result;
    }

    HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
    if (GetLastError() == ERROR_ALREADY_EXISTS && !selfTest) {
        // Started again (Start menu, desktop icon): show the running Dokey's panel.
        HWND running = FindWindowW(kWindowClass, nullptr);
        DWORD pid = 0;
        if (running && GetWindowThreadProcessId(running, &pid)) {
            AllowSetForegroundWindow(pid);
            PostMessageW(running, WM_DOKEY_SHOWPANEL, 0, 0);
        }
        if (mutex) CloseHandle(mutex);
        return 0;
    }

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
    g_mainWindow = hwnd;

    if (selfTest) {
        bool ok = StartKeyboard(hwnd, g_settings);
        if (ok) StopKeyboard();
        DestroyWindow(hwnd);
        return ok ? 0 : 2;
    }
    if (!StartKeyboard(hwnd, g_settings)) {
        MessageBoxW(hwnd,
                    Tr(L"Không cài được bộ bắt phím của Windows. Dokey sẽ thoát.",
                       L"Windows 키보드 후크를 설치할 수 없습니다. Dokey를 종료합니다."),
                    L"Dokey", MB_OK | MB_ICONERROR);
        DestroyWindow(hwnd);
        return 1;
    }

    InitPanel(instance, &g_settings, {PanelSettingsChanged, PanelState, PanelCheckUpdates});
    TrackForegroundApp();
    if (!background) ShowPanel(0);
    if (updated) {
        ShowBalloon(hwnd, std::wstring(Tr(L"Đã cập nhật Dokey ", L"Dokey 업데이트 완료: ")) + DOKEY_APP_VERSION_W,
                    Tr(L"Dokey đang chạy bản mới. Cài đặt của bạn vẫn giữ nguyên.",
                       L"새 버전이 실행 중입니다. 설정은 그대로 유지됩니다."),
                    false);
    }

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    StopKeyboard();
    if (g_iconVietnamese) DestroyIcon(g_iconVietnamese);
    if (g_iconEnglish) DestroyIcon(g_iconEnglish);
    if (g_iconKorean) DestroyIcon(g_iconKorean);
    if (mutex) {
        ReleaseMutex(mutex);
        CloseHandle(mutex);
    }
    return 0;
}
