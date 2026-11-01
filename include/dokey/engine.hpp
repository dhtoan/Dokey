// Dokey Core - Vietnamese input engine.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <string>
#include <vector>

namespace dokey {

enum class InputMethod { Telex, VNI };

enum class Encoding {
    Unicode,           // precomposed (NFC)
    UnicodeCombining   // precomposed base letters + combining tone marks
};

struct Options {
    InputMethod method = InputMethod::Telex;
    Encoding encoding = Encoding::Unicode;
    bool modernToneStyle = true;  // hoà, khoẻ, thuý (instead of hòa, khỏe, thúy)
    bool checkSpelling = true;    // show the typed keys when the word is not Vietnamese
    bool quickTelex = false;      // cc gg kk nn pp qq tt at the start of a word -> ch gi kh ng ph qu th
};

// A text shortcut: typing `key` then a word break inserts `text` ("btw" -> "by the way").
struct Macro {
    std::u16string key;
    std::u16string text;
};

// What the platform must do after a key press.
struct Edit {
    bool handled = false;          // false: let the original key through unchanged
    int backspaces = 0;            // characters to delete before inserting
    std::u16string insert;         // text to insert (UTF-16)
};

class Engine {
public:
    explicit Engine(const Options& options = Options());

    void setOptions(const Options& options);
    const Options& options() const { return options_; }

    // A printable character typed by the user.
    Edit key(char32_t ch);

    // The user pressed Backspace. The platform lets the key through; the
    // engine only updates its view of the current word.
    void backspace();

    // Backspace for platforms that can apply an edit. If `handled` is set the
    // platform swallows the Backspace and applies the edit instead (which
    // already includes the deletion): the tone moved ("hoàn" -> "hòa" in the
    // old style). Otherwise the Backspace goes through as usual.
    // Backspace right after "word + space" reopens that word (xin ␣ ⌫ f -> xìn).
    Edit backspaceEdit();

    // Undo the marks of the current word: show the keys exactly as typed
    // (tiếng -> tieesng). Not handled when the word has no marks.
    Edit undo();

    // Text shortcuts, expanded when a word break follows the key (case of the
    // typed key decides the case: btw, Btw, BTW). An empty list turns them off.
    void setMacros(const std::vector<Macro>& macros);

    // Start a new word: call on mouse clicks, focus/app changes, arrow keys,
    // shortcuts and anything else that moves the caret.
    void reset();

    // The word currently shown, as the engine believes it (for tests/debugging).
    const std::u16string& currentWord() const { return display_; }

    // Convenience for tests: type a whole string and return the final text,
    // applying every edit to an in-memory buffer.
    static std::u16string simulate(const std::string& keys, const Options& options = Options());

private:
    std::u16string render(const std::u16string& keys, bool wordEnded) const;
    Edit commit(std::u16string next, char32_t typed);
    Edit backspaceImpl(bool allowEdit);
    bool expandMacro(char32_t breakKey, Edit& edit);
    void endWord();

    Options options_;
    std::vector<Macro> macros_;
    std::u16string raw_;      // keys of the current word, as the parser reads them
    std::u16string typed_;    // keys exactly as typed (for undo)
    std::u16string display_;  // what is on screen for the current word
    bool literal_ = false;    // after undo: the rest of the word is typed as is
    // The previous word, while only one space follows it (for reopening).
    bool hasPrevious_ = false;
    std::u16string prevRaw_, prevTyped_, prevDisplay_;
};

// UTF helpers (exposed for tests and platform glue).
std::string toUtf8(const std::u16string& s);
std::u16string fromUtf8(const std::string& s);

} // namespace dokey
