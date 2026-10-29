// Dokey for Windows - keyboard hook and input injection.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// Threads:
// - input thread: owns the engine, the WH_KEYBOARD_LL / WH_MOUSE_LL hooks and
//   the focus WinEvent hooks. The hook procedures only run the engine and
//   queue work; they never block, so Windows does not drop the hook.
// - sender thread: calls SendInput for each queued job, in order.
//
// Ordering: a job is "pending" from the moment it is queued until the hook
// sees its last event (tagged kTagEnd) come back. While a job is pending, keys
// that would normally pass through are queued behind it instead, so the user's
// next keystrokes can never overtake Dokey's own output.
#include "keyboard.h"

#include <atomic>
#include <condition_variable>
#include <cwctype>
#include <deque>
#include <mutex>
#include <thread>

#include "dokey/dokey.h"
#include "inject.h"

namespace dokey_win {

namespace {

constexpr UINT WM_DOKEY_CONFIG = WM_APP + 100;  // lParam: Settings* (input thread frees it)
constexpr ULONGLONG kPendingTimeoutMs = 400;     // give up waiting for our own events
constexpr WORD kMaskVk = 0xE8;                   // unassigned VK, hides a lone Alt press

// ---- shared between threads -------------------------------------------------

HWND g_owner = nullptr;
DWORD g_inputThreadId = 0;
std::thread g_inputThread;
std::thread g_senderThread;
std::atomic<bool> g_imeActive{false};

std::atomic<int> g_pending{0};
std::atomic<unsigned> g_markedWords{0};  // shown in the control panel
std::atomic<ULONGLONG> g_pendingSince{0};

std::mutex g_queueMutex;
std::condition_variable g_queueCv;
std::deque<Job> g_queue;
bool g_quit = false;

// ---- input thread only -----------------------------------------------------

dokey_engine* g_engine = nullptr;
Settings g_settings;
HHOOK g_keyboardHook = nullptr;
HHOOK g_mouseHook = nullptr;
HWINEVENTHOOK g_foregroundHook = nullptr;
HWINEVENTHOOK g_focusHook = nullptr;
HWND g_lastFocus = nullptr;
bool g_chromium = false;
bool g_swallowed[256] = {};
bool g_comboArmed = false;  // Ctrl+Shift pressed with nothing else in between
bool g_wordMarked = false;  // the current word was already counted in g_markedWords

void ApplyEngineOptions() {
    dokey_options o = {};
    o.method = g_settings.method;
    o.encoding = DOKEY_UNICODE;
    o.modern_tone_style = g_settings.modernTone ? 1 : 0;
    o.check_spelling = g_settings.checkSpelling ? 1 : 0;
    if (g_engine) {
        dokey_set_options(g_engine, &o);
        dokey_reset(g_engine);
    } else {
        g_engine = dokey_create(&o);
    }
}

bool IsPending() {
    if (g_pending.load() <= 0) return false;
    if (GetTickCount64() - g_pendingSince.load() > kPendingTimeoutMs) {
        // Our events never came back (blocked by UIPI, another hook...).
        // Do not hold the keyboard hostage.
        g_pending.store(0);
        return false;
    }
    return true;
}

void Enqueue(Job job) {
    if (g_pending.fetch_add(1) == 0) g_pendingSince.store(GetTickCount64());
    {
        std::lock_guard<std::mutex> lock(g_queueMutex);
        g_queue.push_back(std::move(job));
    }
    g_queueCv.notify_one();
}

void OnJobDelivered() {
    g_pendingSince.store(GetTickCount64());
    if (g_pending.fetch_sub(1) <= 0) g_pending.store(0);
}

void SenderLoop() {
    for (;;) {
        Job job;
        {
            std::unique_lock<std::mutex> lock(g_queueMutex);
            g_queueCv.wait(lock, [] { return g_quit || !g_queue.empty(); });
            if (g_quit) return;
            job = std::move(g_queue.front());
            g_queue.pop_front();
        }
        size_t split = 0;
        std::vector<INPUT> inputs = BuildInputs(job, &split);
        if (inputs.empty()) {
            OnJobDelivered();
            continue;
        }
        UINT sent;
        if (job.pauseMs > 0 && split > 0 && split < inputs.size()) {
            // Chromium: let the deletions land before the new text arrives.
            sent = SendInput(static_cast<UINT>(split), inputs.data(), sizeof(INPUT));
            Sleep(job.pauseMs);
            sent += SendInput(static_cast<UINT>(inputs.size() - split), inputs.data() + split, sizeof(INPUT));
        } else {
            sent = SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
        }
        if (sent < inputs.size()) OnJobDelivered();  // the end marker will not come back
    }
}

bool KeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

bool IsModifier(DWORD vk) {
    switch (vk) {
        case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT:
        case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL:
        case VK_MENU: case VK_LMENU: case VK_RMENU:
        case VK_LWIN: case VK_RWIN:
            return true;
        default:
            return false;
    }
}

// Keys that neither type nor move the caret: they leave the word alone.
// Letters and digits (VNI marks) belong to a word; anything else ends it.
bool IsWordChar(unsigned ch) { return ch < 0x10000 && iswalnum(static_cast<wint_t>(ch)); }

bool IsNeutral(DWORD vk) {
    switch (vk) {
        case VK_CAPITAL: case VK_NUMLOCK: case VK_SCROLL:
        case VK_VOLUME_MUTE: case VK_VOLUME_DOWN: case VK_VOLUME_UP:
        case VK_MEDIA_NEXT_TRACK: case VK_MEDIA_PREV_TRACK: case VK_MEDIA_STOP: case VK_MEDIA_PLAY_PAUSE:
            return true;
        default:
            return false;
    }
}

void UpdateFocus(HWND focus) {
    HWND foreground = GetForegroundWindow();
    wchar_t cls[64] = {};
    GetClassNameW(foreground, cls, 64);
    // Chrome, Edge, Brave, Opera, Electron apps (VS Code, Slack, Discord...).
    g_chromium = wcsncmp(cls, L"Chrome_WidgetWin_", 17) == 0;
    g_lastFocus = focus;
}

void Toggle() {
    g_settings.vietnamese = !g_settings.vietnamese;
    dokey_reset(g_engine);
    PostMessageW(g_owner, WM_DOKEY_TOGGLED, g_settings.vietnamese ? 1 : 0, 0);
}

// The character this key produces in the focused window's keyboard layout,
// or 0. Ctrl/Alt/Win are handled before this is called.
wchar_t Translate(const KBDLLHOOKSTRUCT& k) {
    BYTE state[256] = {};
    if (KeyDown(VK_SHIFT)) state[VK_SHIFT] = state[VK_LSHIFT] = 0x80;
    if (GetKeyState(VK_CAPITAL) & 1) state[VK_CAPITAL] = 0x01;
    if (GetKeyState(VK_NUMLOCK) & 1) state[VK_NUMLOCK] = 0x01;
    DWORD thread = GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
    HKL layout = GetKeyboardLayout(thread);
    wchar_t buffer[4] = {};
    // Flag 0x4: do not change the keyboard state (keeps dead keys working).
    int n = ToUnicodeEx(k.vkCode, k.scanCode, state, buffer, 4, 0x4, layout);
    if (n != 1) return 0;
    wchar_t ch = buffer[0];
    if (ch >= 0x20 || ch == L'\r' || ch == L'\t') return ch;
    return 0;
}

Job ReplayJob(const KBDLLHOOKSTRUCT& k) {
    Job job;
    job.replayVk = static_cast<WORD>(k.vkCode);
    job.replayScan = static_cast<WORD>(k.scanCode);
    job.replayExtended = (k.flags & LLKHF_EXTENDED) != 0;
    return job;
}

// Lets the key through, or queues it behind a pending job.
bool PassOrDefer(const KBDLLHOOKSTRUCT& k) {
    if (!IsPending()) return false;
    Enqueue(ReplayJob(k));
    g_swallowed[k.vkCode] = true;
    return true;
}

// Returns true to swallow the key.
bool OnKeyDown(const KBDLLHOOKSTRUCT& k) {
    const DWORD vk = k.vkCode;
    const bool ctrl = KeyDown(VK_CONTROL), shift = KeyDown(VK_SHIFT), alt = KeyDown(VK_MENU);
    const bool win = KeyDown(VK_LWIN) || KeyDown(VK_RWIN);

    if (IsModifier(vk)) {
        // The key being pressed is not in the async state yet.
        bool c = ctrl || vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_CONTROL;
        bool s = shift || vk == VK_LSHIFT || vk == VK_RSHIFT || vk == VK_SHIFT;
        bool a = alt || vk == VK_LMENU || vk == VK_RMENU || vk == VK_MENU;
        g_comboArmed = g_settings.hotkey == HOTKEY_CTRL_SHIFT && c && s && !a && !win;
        return false;
    }
    g_comboArmed = false;

    if (g_settings.hotkey == HOTKEY_ALT_Z && vk == 'Z' && alt && !ctrl && !win) {
        Toggle();
        g_swallowed[vk] = true;
        // Alt pressed and released alone would open the menu bar.
        Job mask;
        mask.replayVk = kMaskVk;
        Enqueue(mask);
        return true;
    }

    if (vk == VK_PACKET) {  // text injected by another program
        dokey_reset(g_engine);
        return PassOrDefer(k);
    }
    if (!g_settings.vietnamese || g_imeActive.load()) return PassOrDefer(k);

    if (ctrl || alt || win) {  // shortcuts
        dokey_reset(g_engine);
        return PassOrDefer(k);
    }
    if (vk == VK_BACK) {
        dokey_backspace(g_engine);
        return PassOrDefer(k);
    }
    if (IsNeutral(vk)) return PassOrDefer(k);

    wchar_t ch = Translate(k);
    if (ch == 0) {  // arrows, Home, Delete, Esc, F-keys...
        dokey_reset(g_engine);
        return PassOrDefer(k);
    }

    dokey_edit edit;
    if (!dokey_key(g_engine, ch, &edit)) {
        if (!IsWordChar(ch)) g_wordMarked = false;
        if (!IsPending()) return false;
        Job job = ch < 0x20 ? ReplayJob(k) : Job();
        if (ch >= 0x20) job.text.push_back(static_cast<char16_t>(ch));
        Enqueue(std::move(job));
        g_swallowed[vk] = true;
        return true;
    }

    if (edit.backspaces > 0 && !g_wordMarked) {
        g_markedWords++;
        g_wordMarked = true;
    }
    if (edit.length > 0 && !IsWordChar(edit.text[edit.length - 1])) g_wordMarked = false;

    Job job;
    job.backspaces = edit.backspaces;
    job.text.assign(reinterpret_cast<const char16_t*>(edit.text), static_cast<size_t>(edit.length));
    if (ch < 0x20 && !job.text.empty() && job.text.back() == ch) {
        // Enter/Tab ended the word: send the real key, not a control character.
        job.text.pop_back();
        Job replay = ReplayJob(k);
        job.replayVk = replay.replayVk;
        job.replayScan = replay.replayScan;
        job.replayExtended = replay.replayExtended;
    }
    if (g_chromium && job.backspaces > 0 && !job.text.empty()) job.pauseMs = g_settings.chromiumPauseMs;
    Enqueue(std::move(job));
    g_swallowed[vk] = true;
    return true;
}

bool OnKeyUp(const KBDLLHOOKSTRUCT& k) {
    const DWORD vk = k.vkCode;
    if (g_comboArmed && (vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_LSHIFT || vk == VK_RSHIFT ||
                         vk == VK_CONTROL || vk == VK_SHIFT)) {
        g_comboArmed = false;
        Toggle();
    }
    if (g_swallowed[vk]) {
        g_swallowed[vk] = false;
        return true;
    }
    return false;
}

LRESULT CALLBACK KeyboardProc(int code, WPARAM wParam, LPARAM lParam) {
    if (code == HC_ACTION) {
        const auto* k = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lParam);
        const bool up = wParam == WM_KEYUP || wParam == WM_SYSKEYUP;
        if (IsOwnEvent(k->dwExtraInfo)) {
            if (k->dwExtraInfo == kTagEnd && up) OnJobDelivered();
        } else if (k->vkCode < 256 && (up ? OnKeyUp(*k) : OnKeyDown(*k))) {
            return 1;
        }
    }
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

LRESULT CALLBACK MouseProc(int code, WPARAM wParam, LPARAM lParam) {
    if (code == HC_ACTION) {
        switch (wParam) {
            case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: case WM_MBUTTONDOWN: case WM_XBUTTONDOWN:
                dokey_reset(g_engine);  // the caret may have moved
                break;
            default:
                break;
        }
    }
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

void CALLBACK WinEventProc(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG, LONG, DWORD, DWORD) {
    if (event == EVENT_SYSTEM_FOREGROUND) {
        dokey_reset(g_engine);
        UpdateFocus(hwnd);
        PostMessageW(g_owner, WM_DOKEY_FOCUS, 0, 0);
    } else if (event == EVENT_OBJECT_FOCUS && hwnd != g_lastFocus) {
        // Only a change of window counts: Chromium raises focus events inside
        // one window (popups, accessibility) while the user is still typing.
        dokey_reset(g_engine);
        UpdateFocus(hwnd);
    }
}

void InputThread(HANDLE ready, bool* ok) {
    MSG msg;
    PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);  // create the message queue
    ApplyEngineOptions();
    HINSTANCE instance = GetModuleHandleW(nullptr);
    g_keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, KeyboardProc, instance, 0);
    g_mouseHook = SetWindowsHookExW(WH_MOUSE_LL, MouseProc, instance, 0);
    const DWORD flags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;
    g_foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, WinEventProc, 0, 0, flags);
    g_focusHook = SetWinEventHook(EVENT_OBJECT_FOCUS, EVENT_OBJECT_FOCUS, nullptr, WinEventProc, 0, 0, flags);
    UpdateFocus(GetForegroundWindow());
    *ok = g_keyboardHook != nullptr;
    SetEvent(ready);
    if (!g_keyboardHook) return;

    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (msg.hwnd == nullptr && msg.message == WM_DOKEY_CONFIG) {
            auto* s = reinterpret_cast<Settings*>(msg.lParam);
            g_settings = *s;
            delete s;
            ApplyEngineOptions();
            continue;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (g_focusHook) UnhookWinEvent(g_focusHook);
    if (g_foregroundHook) UnhookWinEvent(g_foregroundHook);
    if (g_mouseHook) UnhookWindowsHookEx(g_mouseHook);
    UnhookWindowsHookEx(g_keyboardHook);
    dokey_destroy(g_engine);
    g_engine = nullptr;
}

} // namespace

bool StartKeyboard(HWND owner, const Settings& settings) {
    g_owner = owner;
    g_settings = settings;
    g_quit = false;
    g_senderThread = std::thread(SenderLoop);

    HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    bool ok = false;
    g_inputThread = std::thread(InputThread, ready, &ok);
    g_inputThreadId = GetThreadId(g_inputThread.native_handle());
    WaitForSingleObject(ready, INFINITE);
    CloseHandle(ready);
    // Respond to hooks before any other thread in this process.
    SetThreadPriority(g_inputThread.native_handle(), THREAD_PRIORITY_TIME_CRITICAL);
    if (!ok) {
        g_inputThread.join();
        StopKeyboard();
    }
    return ok;
}

void StopKeyboard() {
    if (g_inputThread.joinable()) {
        PostThreadMessageW(g_inputThreadId, WM_QUIT, 0, 0);
        g_inputThread.join();
    }
    {
        std::lock_guard<std::mutex> lock(g_queueMutex);
        g_quit = true;
        g_queue.clear();
    }
    g_queueCv.notify_all();
    if (g_senderThread.joinable()) g_senderThread.join();
}

void UpdateKeyboard(const Settings& settings) {
    auto* copy = new Settings(settings);
    if (!PostThreadMessageW(g_inputThreadId, WM_DOKEY_CONFIG, 0, reinterpret_cast<LPARAM>(copy))) delete copy;
}

void SetImeActive(bool active) { g_imeActive.store(active); }

unsigned MarkedWordCount() { return g_markedWords.load(); }

} // namespace dokey_win
