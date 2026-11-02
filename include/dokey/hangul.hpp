// Dokey Core - Korean (Hangul) composition, 2-beolsik (두벌식) layout.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// Prototype rule pack (see docs/hangul-design.md). Not wired into the
// platform apps yet.
#pragma once

#include "dokey/engine.hpp"

#include <string>

namespace dokey {
namespace hangul {

// The jamo (compatibility jamo U+3131..U+3163) that a key of the 2-beolsik
// layout types, by the key's Latin letter on a US/ABC layout: r -> ㄱ, k -> ㅏ,
// R -> ㄲ. Shift only matters on q w e r t o p. Returns 0 for other keys.
char16_t jamoForKey(char32_t key);

// Is this a key the composer consumes (a Latin letter)?
bool isJamoKey(char32_t key);

// Pure function: the text that these keys type. Jamo are joined into
// precomposed syllables (U+AC00..U+D7A3); a jamo that cannot join a syllable
// is shown as compatibility jamo. "gksrnr" -> 한국, "rkqk" -> 가바.
std::u16string compose(const std::u16string& keys);

} // namespace hangul

// Drives compose() the way Engine drives the Vietnamese rules: keeps the keys
// of the current word and turns each key into an Edit (delete N, insert text).
// The text on screen is always final; nothing is ever pending or "marked".
class HangulEngine {
public:
    // A key typed by the user. Letters are jamo keys; anything else ends the
    // word and is never handled (there is nothing left to flush).
    Edit key(char32_t ch);

    // Backspace removes the last key (jamo) of the current word: 한 ⌫ -> 하.
    // Handled when the platform must swallow the Backspace and apply the edit;
    // not handled when a plain Backspace already gives the right text.
    Edit backspaceEdit();

    // Start a new word (mouse click, arrow keys, focus change...).
    void reset();

    const std::u16string& currentWord() const { return display_; }

    // Type `keys` into an in-memory buffer (\b = Backspace) and return the text.
    static std::u16string simulate(const std::string& keys);

private:
    Edit commit(std::u16string next, char32_t typed);

    std::u16string raw_;      // keys of the current word
    std::u16string display_;  // what is on screen for the current word
};

} // namespace dokey
