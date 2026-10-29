// Dokey for Windows - keyboard hook and input injection.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

#include "settings.h"

namespace dokey_win {

// Posted to the owner window by the input thread.
constexpr UINT WM_DOKEY_TOGGLED = WM_APP + 1;  // wParam: 1 = Vietnamese, 0 = English
constexpr UINT WM_DOKEY_FOCUS = WM_APP + 2;    // the foreground window changed

// Starts the input thread (hooks + engine) and the sender thread.
bool StartKeyboard(HWND owner, const Settings& settings);
void StopKeyboard();
// Applies new settings on the input thread.
void UpdateKeyboard(const Settings& settings);
// Set by the UI thread after asking the focused window's IME (see main.cpp).
void SetImeActive(bool active);
// Words Dokey added marks to since it started (for the control panel).
unsigned MarkedWordCount();

} // namespace dokey_win
