// Dokey for Windows - building the synthetic input for one edit.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

#include <string>
#include <vector>

namespace dokey_win {

// Every event Dokey injects carries one of these in dwExtraInfo, so the hook
// can recognise (and ignore) its own output. The last event of a job carries
// kTagEnd: when the hook sees it, the job has been delivered.
constexpr ULONG_PTR kTagMid = 0x444F4B00;  // "DOK\0"
constexpr ULONG_PTR kTagEnd = 0x444F4B01;

// A text box may hold a selected inline completion after the caret (address
// bars, Excel, Explorer): the first Backspace would delete that instead of the
// letter. Typing this invisible character first replaces any selection, and
// one more Backspace removes it again.
constexpr char16_t kSelectionGuard = 0x200B;  // ZERO WIDTH SPACE
constexpr char16_t kGuardDelete = 0xFFFF;

inline bool IsOwnEvent(ULONG_PTR extra) { return extra == kTagMid || extra == kTagEnd; }

// One unit of work for the sender thread.
struct Job {
    int backspaces = 0;      // Backspace presses to send first
    char16_t guard = 0;      // before the Backspaces: this character, deleted again (kGuardDelete: the Delete key)
    std::u16string text;     // then this text, as KEYEVENTF_UNICODE events
    WORD replayVk = 0;       // then this virtual key (Enter, Tab, deferred keys)
    WORD replayScan = 0;
    bool replayExtended = false;
    DWORD pauseMs = 0;       // pause between the backspaces and the rest (Chromium)
    DWORD perKeyMs = 0;      // > 0: one key per SendInput with this pause (Google Docs)
};

inline INPUT MakeKey(WORD vk, WORD scan, DWORD flags) {
    INPUT in = {};
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.wScan = scan;
    in.ki.dwFlags = flags;
    in.ki.dwExtraInfo = kTagMid;
    return in;
}

// Returns the events for `job`. `*split` receives the number of leading
// events that are the guard and Backspaces, so a caller can pause after them.
inline std::vector<INPUT> BuildInputs(const Job& job, size_t* split) {
    std::vector<INPUT> out;
    out.reserve(static_cast<size_t>(job.backspaces) * 2 + job.text.size() * 2 + 6);
    const WORD backScan = static_cast<WORD>(MapVirtualKeyW(VK_BACK, MAPVK_VK_TO_VSC));
    int extra = 0;
    if (job.guard == kGuardDelete && job.backspaces > 0) {
        const WORD delScan = static_cast<WORD>(MapVirtualKeyW(VK_DELETE, MAPVK_VK_TO_VSC));
        out.push_back(MakeKey(VK_DELETE, delScan, KEYEVENTF_EXTENDEDKEY));
        out.push_back(MakeKey(VK_DELETE, delScan, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP));
    } else if (job.guard != 0 && job.backspaces > 0) {
        out.push_back(MakeKey(0, job.guard, KEYEVENTF_UNICODE));
        out.push_back(MakeKey(0, job.guard, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
        extra = 1;
    }
    for (int i = 0; i < job.backspaces + extra; i++) {
        out.push_back(MakeKey(VK_BACK, backScan, 0));
        out.push_back(MakeKey(VK_BACK, backScan, KEYEVENTF_KEYUP));
    }
    if (split) *split = out.size();
    for (char16_t c : job.text) {
        out.push_back(MakeKey(0, static_cast<WORD>(c), KEYEVENTF_UNICODE));
        out.push_back(MakeKey(0, static_cast<WORD>(c), KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
    }
    if (job.replayVk != 0) {
        DWORD ext = job.replayExtended ? KEYEVENTF_EXTENDEDKEY : 0;
        out.push_back(MakeKey(job.replayVk, job.replayScan, ext));
        out.push_back(MakeKey(job.replayVk, job.replayScan, ext | KEYEVENTF_KEYUP));
    }
    if (!out.empty()) out.back().ki.dwExtraInfo = kTagEnd;
    return out;
}

} // namespace dokey_win
