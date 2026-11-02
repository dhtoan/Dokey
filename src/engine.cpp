// Dokey Core - Vietnamese input engine.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// Design: the engine keeps the raw keys of the current word and, after every
// key, re-derives the whole word from scratch (see SPEC.md). Because the
// derivation is a pure function of the keys, there is no incremental state
// to drift out of sync with what is on screen.
#include "dokey/engine.hpp"

#include "vietnamese.hpp"

#include <algorithm>
#include <cstring>

namespace dokey {

namespace {

constexpr size_t kMaxWordKeys = 32;

struct Letter {
    char base;          // 'a'..'z'
    Mark mark;
    bool upper;
    bool standaloneW;   // "ư" created by a lone Telex w
};

// Which modifier keys were undone ("aaa", "ss", ...) and now type literally.
enum KeyClass { kCircA, kCircE, kCircO, kHorn, kBreve, kStroke, kTone, kClassCount };

struct Word {
    std::vector<Letter> letters;
    Tone tone = Tone::None;
    bool disabled[kClassCount] = {};
    std::u16string typed;   // what to show if the word is not Vietnamese
    bool undid = false;     // the last key cancelled a modifier
    int applied = -1;       // KeyClass applied by the current key
    int previous = -1;      // KeyClass applied by the previous key
};

std::u16string lowerMarked(const std::vector<Letter>& letters) {
    std::u16string s;
    s.reserve(letters.size());
    for (const Letter& l : letters) s.push_back(markedLetter(l.base, l.mark));
    return s;
}

// [begin, end) of the vowel nucleus, skipping the u of "qu" and the i of "gi".
void vowelRun(const std::vector<Letter>& w, size_t& begin, size_t& end) {
    const size_t n = w.size();
    size_t init = 0;
    auto vowelAt = [&](size_t i) { return i < n && isVowelBase(w[i].base); };
    if (n > 2 && w[0].base == 'q' && w[1].base == 'u' && vowelAt(2)) {
        init = 2;
    } else if (n > 2 && w[0].base == 'g' && w[1].base == 'i' && w[1].mark == Mark::None && vowelAt(2)) {
        init = 2;
    } else {
        while (init < n && !isVowelBase(w[init].base)) init++;
    }
    begin = init;
    end = init;
    while (end < n && isVowelBase(w[end].base)) end++;
}

bool hasVowel(const std::vector<Letter>& w) {
    size_t b, e;
    vowelRun(w, b, e);
    return e > b;
}

bool stopFinal(const std::vector<Letter>& w) {
    size_t b, e;
    vowelRun(w, b, e);
    if (e == b) return false;
    std::u16string fin = lowerMarked(std::vector<Letter>(w.begin() + e, w.end()));
    return fin == u"c" || fin == u"ch" || fin == u"p" || fin == u"t" || fin == u"k";
}

// "ư" + "o" before a final consonant can only be "ươ": typing "uwon" means
// "ươn", not a word that cannot exist ("ưon").
void completeUo(std::vector<Letter>& w) {
    for (size_t i = 0; i + 2 < w.size(); i++) {
        Letter& u = w[i];
        Letter& o = w[i + 1];
        const char next = w[i + 2].base;
        if (u.base == 'u' && u.mark == Mark::Horn && o.base == 'o' && o.mark == Mark::None &&
            std::strchr("ncimpt", next)) {
            o.mark = Mark::Horn;
        }
    }
}

bool toneAllowed(const std::vector<Letter>& w, Tone tone) {
    if (tone == Tone::None) return true;
    if (!hasVowel(w)) return false;
    if (stopFinal(w)) return tone == Tone::Acute || tone == Tone::Dot;
    return true;
}

// May this word still become a Vietnamese syllable?
bool plausible(const std::vector<Letter>& w, Tone tone, bool requireMarks) {
    if (w.empty()) return true;
    if (!toneAllowed(w, tone)) return false;
    std::u16string s = lowerMarked(w);
    if (isSyllablePrefix(s)) return true;
    if (requireMarks) return false;
    // Accept if adding diacritics to the plain letters can still make a
    // syllable: "đuo" becomes đuôi, được (marks typed so far must match).
    return isCompatibleSyllablePrefix(s);
}

size_t tonePosition(const std::vector<Letter>& w, bool modern) {
    size_t b, e;
    vowelRun(w, b, e);
    if (e == b) return w.size();
    // 1. A vowel with a diacritic takes the tone (the last one: ươ -> ơ).
    for (size_t i = e; i-- > b;) {
        if (w[i].mark != Mark::None) return i;
    }
    const size_t len = e - b;
    // 2. Closed syllable: last vowel of the nucleus.
    if (e < w.size()) return e - 1;
    // 3./4./5. Open syllable.
    if (len >= 3) return b + 1;
    if (len == 2) {
        char a = w[b].base, c = w[b + 1].base;
        bool modernPair = (a == 'o' && (c == 'a' || c == 'e')) || (a == 'u' && c == 'y');
        return (modern && modernPair) ? b + 1 : b;
    }
    return b;
}

class Parser {
public:
    Parser(const Options& o) : opt_(o) {}

    Word parse(const std::u16string& keys) {
        Word word;
        for (char16_t k : keys) feed(word, k);
        return word;
    }

private:
    bool ok(const Word& w, const std::vector<Letter>& letters, Tone tone, bool requireMarks) const {
        (void)w;
        return !opt_.checkSpelling || plausible(letters, tone, requireMarks);
    }

    static void appendLiteral(Word& w, char16_t k) {
        bool upper = k >= u'A' && k <= u'Z';
        char base = static_cast<char>(upper ? k - u'A' + u'a' : k);
        w.letters.push_back({base, Mark::None, upper, false});
    }

    // Returns true if the key was consumed as a tone key.
    bool applyTone(Word& w, Tone t, char16_t key) {
        if (w.disabled[kTone] || !hasVowel(w.letters)) return false;
        if (w.tone == t && w.previous == kTone) {  // undo: "ass" -> "as"
            w.tone = Tone::None;
            w.disabled[kTone] = true;
            appendLiteral(w, key);
            w.undid = true;
            return true;
        }
        if (w.tone == t) return false;
        if (!ok(w, w.letters, t, false)) return false;
        w.tone = t;
        w.applied = kTone;
        return true;
    }

    bool removeTone(Word& w) {
        if (w.tone == Tone::None) return false;
        w.tone = Tone::None;
        return true;
    }

    bool applyCircumflex(Word& w, KeyClass cls, char16_t key, const char* bases) {
        if (w.disabled[cls]) return false;
        size_t b, e;
        vowelRun(w.letters, b, e);
        for (size_t i = e; i-- > b;) {
            Letter& l = w.letters[i];
            if (!std::strchr(bases, l.base)) continue;
            if (l.mark == Mark::Circumflex) {  // undo: "aaa" -> "aa"
                if (w.previous != cls) return false;
                l.mark = Mark::None;
                w.disabled[cls] = true;
                appendLiteral(w, key);
                w.undid = true;
                return true;
            }
            if (l.mark != Mark::None) continue;
            std::vector<Letter> trial = w.letters;
            trial[i].mark = Mark::Circumflex;
            if (ok(w, trial, w.tone, true)) {
                w.letters = trial;
                w.applied = cls;
                return true;
            }
            return false;
        }
        return false;
    }

    // Telex w / VNI 7 (horn) and VNI 8 (breve). Telex w also does breve on a.
    bool applyHornBreve(Word& w, char16_t key, bool horn, bool breve, bool standalone) {
        const KeyClass cls = horn ? kHorn : kBreve;
        if (w.disabled[cls]) return false;
        size_t b, e;
        vowelRun(w.letters, b, e);

        // Undo when every candidate already carries the mark.
        std::vector<size_t> marked;
        for (size_t i = b; i < e; i++) {
            const Letter& l = w.letters[i];
            if ((horn && l.mark == Mark::Horn) || (breve && l.mark == Mark::Breve)) marked.push_back(i);
        }

        // u+o -> ươ together.
        for (size_t i = b; i + 1 < e; i++) {
            Letter& u = w.letters[i];
            Letter& o = w.letters[i + 1];
            if (horn && u.base == 'u' && o.base == 'o') {
                if (u.mark == Mark::Horn && o.mark == Mark::Horn) {
                    if (w.previous != cls) return false;
                    return undo(w, cls, key, marked);
                }
                if ((u.mark == Mark::None || u.mark == Mark::Horn) && o.mark == Mark::None) {
                    std::vector<Letter> trial = w.letters;
                    trial[i].mark = Mark::Horn;
                    trial[i + 1].mark = Mark::Horn;
                    if (ok(w, trial, w.tone, true)) {
                        w.letters = trial;
                        w.applied = cls;
                        return true;
                    }
                }
            }
        }
        // Otherwise the last vowel that accepts the mark.
        bool candidate = false;
        for (size_t i = e; i-- > b;) {
            const Letter& l = w.letters[i];
            Mark m = Mark::None;
            if (horn && (l.base == 'o' || l.base == 'u')) m = Mark::Horn;
            else if (breve && l.base == 'a') m = Mark::Breve;
            else continue;
            candidate = true;
            if (l.mark == m) continue;
            if (l.mark != Mark::None) continue;
            std::vector<Letter> trial = w.letters;
            trial[i].mark = m;
            if (ok(w, trial, w.tone, true)) {
                w.letters = trial;
                w.applied = cls;
                return true;
            }
        }
        if (!marked.empty() && w.previous == cls) return undo(w, cls, key, marked);
        // Telex: a lone w is "ư" (nhw -> như).
        if (standalone && !candidate && e == b) {
            std::vector<Letter> trial = w.letters;
            bool upper = key == u'W';
            trial.push_back({'u', Mark::Horn, upper, true});
            if (ok(w, trial, w.tone, true)) {
                w.letters = trial;
                w.applied = cls;
                return true;
            }
        }
        return false;
    }

    bool undo(Word& w, KeyClass cls, char16_t key, const std::vector<size_t>& marked) {
        bool replacedStandalone = false;
        for (size_t idx = marked.size(); idx-- > 0;) {
            Letter& l = w.letters[marked[idx]];
            if (l.standaloneW) {  // "ww" -> "w"
                l = {'w', Mark::None, l.upper, false};
                replacedStandalone = true;
            } else {
                l.mark = Mark::None;
            }
        }
        w.disabled[cls] = true;
        if (!replacedStandalone) appendLiteral(w, key);
        w.undid = true;
        return true;
    }

    bool applyStroke(Word& w, char16_t key) {
        if (w.disabled[kStroke] || w.letters.empty() || w.letters[0].base != 'd') return false;
        Letter& d = w.letters[0];
        if (d.mark == Mark::Stroke) {  // "ddd" -> "dd"
            if (w.previous != kStroke) return false;
            d.mark = Mark::None;
            w.disabled[kStroke] = true;
            appendLiteral(w, key);
            w.undid = true;
            return true;
        }
        std::vector<Letter> trial = w.letters;
        trial[0].mark = Mark::Stroke;
        if (!ok(w, trial, w.tone, true)) return false;
        w.letters = trial;
        w.applied = kStroke;
        return true;
    }

    void feed(Word& w, char16_t k) {
        const char16_t lower = (k >= u'A' && k <= u'Z') ? static_cast<char16_t>(k - u'A' + u'a') : k;
        bool used = false;
        w.undid = false;
        w.previous = w.applied;
        w.applied = -1;
        if (opt_.method == InputMethod::Telex) {
            switch (lower) {
                case u's': used = applyTone(w, Tone::Acute, k); break;
                case u'f': used = applyTone(w, Tone::Grave, k); break;
                case u'r': used = applyTone(w, Tone::Hook, k); break;
                case u'x': used = applyTone(w, Tone::Tilde, k); break;
                case u'j': used = applyTone(w, Tone::Dot, k); break;
                case u'z': used = !w.disabled[kTone] && removeTone(w); break;
                case u'a': used = applyCircumflex(w, kCircA, k, "a"); break;
                case u'e': used = applyCircumflex(w, kCircE, k, "e"); break;
                case u'o': used = applyCircumflex(w, kCircO, k, "o"); break;
                case u'w': used = applyHornBreve(w, k, true, true, true); break;
                case u'd': used = applyStroke(w, k); break;
                default: break;
            }
            // Telex w both horns and breves: share one undo state.
            if (lower == u'w' && (w.disabled[kHorn] || w.disabled[kBreve])) {
                w.disabled[kHorn] = w.disabled[kBreve] = true;
            }
        } else {
            switch (lower) {
                case u'1': used = applyTone(w, Tone::Acute, k); break;
                case u'2': used = applyTone(w, Tone::Grave, k); break;
                case u'3': used = applyTone(w, Tone::Hook, k); break;
                case u'4': used = applyTone(w, Tone::Tilde, k); break;
                case u'5': used = applyTone(w, Tone::Dot, k); break;
                case u'0': used = !w.disabled[kTone] && removeTone(w); break;
                case u'6': used = applyCircumflex(w, kCircA, k, "aeo"); break;
                case u'7': used = applyHornBreve(w, k, true, false, false); break;
                case u'8': used = applyHornBreve(w, k, false, true, false); break;
                case u'9': used = applyStroke(w, k); break;
                default: break;
            }
        }
        if (!used) appendLiteral(w, k);
        // An undo key replaces the modifier key it cancels ("aaa" -> "aa").
        if (!w.undid) w.typed.push_back(k);
    }

    const Options& opt_;
};

// Was a tone key cancelled by repeating it ("ss", "rr", "ff"...)?
bool toneUndone(const std::u16string& keys, const Options& options, std::u16string& shown) {
    Parser parser(options);
    Word w = parser.parse(keys);
    shown = w.typed;
    return w.disabled[kTone];
}

bool isWordKey(char32_t ch, InputMethod method) {
    if ((ch >= U'a' && ch <= U'z') || (ch >= U'A' && ch <= U'Z')) return true;
    return method == InputMethod::VNI && ch >= U'0' && ch <= U'9';
}

} // namespace

Engine::Engine(const Options& options) : options_(options) {}

void Engine::setOptions(const Options& options) {
    options_ = options;
    reset();
}

void Engine::setMacros(const std::vector<Macro>& macros) {
    macros_.clear();
    for (const Macro& m : macros) {
        if (m.key.empty() || m.key.size() > kMaxWordKeys) continue;
        Macro lower = m;
        for (char16_t& c : lower.key) {
            if (c >= u'A' && c <= u'Z') c = static_cast<char16_t>(c - u'A' + u'a');
        }
        macros_.push_back(lower);
    }
}

void Engine::endWord() {
    raw_.clear();
    typed_.clear();
    display_.clear();
    literal_ = false;
}

void Engine::reset() {
    endWord();
    hasPrevious_ = false;
}

namespace {

char16_t upperLetter(char16_t c) {
    if (c >= u'a' && c <= u'z') return static_cast<char16_t>(c - u'a' + u'A');
    char base;
    Mark mark;
    Tone tone;
    bool upper;
    if (c > 0x7F && decomposeLetter(c, base, mark, tone, upper) && !upper) return composeLetter(base, mark, tone, true);
    return c;
}

} // namespace

bool Engine::expandMacro(char32_t breakKey, Edit& edit) {
    if (macros_.empty() || typed_.empty() || literal_) return false;
    std::u16string key = typed_;
    size_t uppers = 0;
    for (char16_t& c : key) {
        if (c >= u'A' && c <= u'Z') {
            c = static_cast<char16_t>(c - u'A' + u'a');
            uppers++;
        }
    }
    for (const Macro& m : macros_) {
        if (m.key != key) continue;
        std::u16string text = m.text;
        if (uppers == key.size() && key.size() > 1) {
            for (char16_t& c : text) c = upperLetter(c);       // BTW -> BY THE WAY
        } else if (uppers > 0 && typed_[0] >= u'A' && typed_[0] <= u'Z' && !text.empty()) {
            text[0] = upperLetter(text[0]);                    // Btw -> By the way
        }
        if (breakKey <= 0xFFFF) text.push_back(static_cast<char16_t>(breakKey));
        edit = commit(text, breakKey);
        return true;
    }
    return false;
}

std::u16string Engine::render(const std::u16string& keys, bool wordEnded) const {
    Parser parser(options_);
    Word w = parser.parse(keys);
    completeUo(w.letters);
    const bool show = !options_.checkSpelling || plausible(w.letters, w.tone, false);
    if (!show) return w.typed;  // not Vietnamese: show what was typed

    // "ươ" cannot end a syllable: at the end of the word it must be "uơ" (thuở, huơ).
    if (wordEnded && w.letters.size() >= 2) {
        Letter& u = w.letters[w.letters.size() - 2];
        const Letter& o = w.letters.back();
        if (u.base == 'u' && u.mark == Mark::Horn && !u.standaloneW && o.base == 'o' && o.mark == Mark::Horn)
            u.mark = Mark::None;
    }
    // A finished word must be a whole syllable, not just the start of one
    // ("use" stays "use" rather than "úe"). Vowel-less words (đ) are kept.
    if (wordEnded && options_.checkSpelling && hasVowel(w.letters) && !isSyllable(lowerMarked(w.letters)))
        return w.typed;

    // A lone VNI digit with nothing to modify stays a digit; letters keep case.
    const size_t tonePos = w.tone == Tone::None ? w.letters.size() : tonePosition(w.letters, options_.modernToneStyle);
    std::u16string out;
    out.reserve(w.letters.size() + 1);
    for (size_t i = 0; i < w.letters.size(); i++) {
        const Letter& l = w.letters[i];
        if (l.base < 'a' || l.base > 'z') {  // VNI digit typed literally
            out.push_back(static_cast<char16_t>(l.base));
            continue;
        }
        const bool toned = i == tonePos;
        if (options_.encoding == Encoding::UnicodeCombining && toned) {
            out.push_back(composeLetter(l.base, l.mark, Tone::None, l.upper));
            out.push_back(combiningTone(w.tone));
        } else {
            out.push_back(composeLetter(l.base, l.mark, toned ? w.tone : Tone::None, l.upper));
        }
    }
    return out;
}

Edit Engine::commit(std::u16string next, char32_t typed) {
    Edit edit;
    size_t common = 0;
    while (common < display_.size() && common < next.size() && display_[common] == next[common]) common++;
    edit.backspaces = static_cast<int>(display_.size() - common);
    edit.insert = next.substr(common);
    edit.handled = !(edit.backspaces == 0 && edit.insert.size() == 1 && edit.insert[0] == typed);
    display_ = std::move(next);
    return edit;
}

Edit Engine::key(char32_t ch) {
    if (!isWordKey(ch, options_.method)) {
        // Word break: space, punctuation, Telex digits... Apply end-of-word
        // corrections, then let the break key through as part of the edit.
        Edit edit;
        const bool hadWord = !display_.empty();
        const bool expanded = expandMacro(ch, edit);
        if (!expanded && !literal_ && !raw_.empty() && raw_.size() <= kMaxWordKeys && ch <= 0xFFFF) {
            std::u16string done = render(raw_, true);
            // A longer word that is not Vietnamese and only lost a letter to a
            // cancelled tone key is English with a double letter when the
            // double ends the word or a vowel (or w) follows it: pass, message,
            // password. Show every key typed. Before a consonant the double
            // is the Telex way to type the letter once: "tesst" -> "test",
            // "marrketing" -> "marketing". Short "ass" -> "as" keeps it too.
            std::u16string shown;
            if (typed_.size() >= 4 && typed_.size() == raw_.size() && toneUndone(raw_, options_, shown) &&
                done == shown && done.size() < typed_.size()) {
                size_t cancel = 2;  // keys up to and including the cancelling one
                std::u16string prefix;
                while (cancel < raw_.size() && !toneUndone(raw_.substr(0, cancel), options_, prefix)) cancel++;
                char16_t next = cancel < raw_.size() ? raw_[cancel] : u'\0';
                if (next >= u'A' && next <= u'Z') next = static_cast<char16_t>(next - u'A' + u'a');
                if (next == u'\0' || std::u16string(u"aeiouwy").find(next) != std::u16string::npos) done = typed_;
            }
            if (done != display_) {
                edit = commit(done + static_cast<char16_t>(ch), ch);
                display_.pop_back();  // the break key is not part of the word
            }
        }
        // Remember the word while a single space follows it, so Backspace can reopen it.
        hasPrevious_ = ch == U' ' && hadWord && !expanded && !literal_ && raw_.size() <= kMaxWordKeys;
        if (hasPrevious_) {
            prevRaw_ = raw_;
            prevTyped_ = typed_;
            prevDisplay_ = display_;
        }
        endWord();
        return edit;
    }
    hasPrevious_ = false;
    if (literal_) {  // after undo, the rest of the word stays as typed
        typed_.push_back(static_cast<char16_t>(ch));
        display_.push_back(static_cast<char16_t>(ch));
        return Edit();
    }
    if (raw_.empty() && ch >= U'0' && ch <= U'9') {
        return Edit();  // a number, not a word
    }
    typed_.push_back(static_cast<char16_t>(ch));
    // Quick Telex: a doubled first consonant is a two-letter initial (cc -> ch).
    if (options_.quickTelex && options_.method == InputMethod::Telex && raw_.size() == 1 && typed_.size() == 2) {
        static const char16_t from[] = u"cgknpqt";
        static const char16_t to[] = u"hihghuh";
        const char16_t first = raw_[0];
        const char16_t lower = (ch >= U'A' && ch <= U'Z') ? static_cast<char16_t>(ch - U'A' + U'a') : static_cast<char16_t>(ch);
        const char16_t firstLower = (first >= u'A' && first <= u'Z') ? static_cast<char16_t>(first - u'A' + u'a') : first;
        for (int i = 0; from[i]; i++) {
            if (lower == from[i] && firstLower == from[i]) {
                const bool upper = ch >= U'A' && ch <= U'Z';
                raw_.push_back(upper ? static_cast<char16_t>(to[i] - u'a' + u'A') : to[i]);
                return commit(render(raw_, false), ch);
            }
        }
    }
    raw_.push_back(static_cast<char16_t>(ch));
    if (raw_.size() > kMaxWordKeys) {  // long tokens (URLs, IDs): stop transforming
        display_.push_back(static_cast<char16_t>(ch));
        return Edit();
    }
    return commit(render(raw_, false), ch);
}

namespace {

// Canonical keys that produce `text` (used to resume after Backspace).
bool encodeKeys(const std::u16string& text, InputMethod method, std::u16string& keys) {
    keys.clear();
    Tone tone = Tone::None;
    for (char16_t c : text) {
        char base;
        Mark mark;
        Tone t;
        bool upper;
        if (c >= u'0' && c <= u'9') {
            keys.push_back(c);
            continue;
        }
        if (!decomposeLetter(c, base, mark, t, upper)) return false;
        if (t != Tone::None) tone = t;
        keys.push_back(static_cast<char16_t>(upper ? base - 'a' + 'A' : base));
        if (method == InputMethod::Telex) {
            switch (mark) {
                case Mark::Circumflex: keys.push_back(static_cast<char16_t>(base)); break;
                case Mark::Breve:
                case Mark::Horn: keys.push_back(u'w'); break;
                case Mark::Stroke: keys.push_back(u'd'); break;
                default: break;
            }
        } else {
            switch (mark) {
                case Mark::Circumflex: keys.push_back(u'6'); break;
                case Mark::Horn: keys.push_back(u'7'); break;
                case Mark::Breve: keys.push_back(u'8'); break;
                case Mark::Stroke: keys.push_back(u'9'); break;
                default: break;
            }
        }
    }
    if (tone != Tone::None) {
        static const char16_t telex[] = {0, u's', u'f', u'r', u'x', u'j'};
        static const char16_t vni[] = {0, u'1', u'2', u'3', u'4', u'5'};
        keys.push_back((method == InputMethod::Telex ? telex : vni)[static_cast<int>(tone)]);
    }
    return true;
}

} // namespace

void Engine::backspace() {
    backspaceImpl(false);
}

Edit Engine::backspaceEdit() {
    return backspaceImpl(true);
}

Edit Engine::backspaceImpl(bool allowEdit) {
    if (display_.empty()) {
        // Deleting the single space after a word reopens that word.
        if (hasPrevious_ && raw_.empty()) {
            raw_ = prevRaw_;
            typed_ = prevTyped_;
            display_ = prevDisplay_;
            hasPrevious_ = false;
            literal_ = raw_.empty();
            return Edit();
        }
        reset();
        return Edit();
    }
    hasPrevious_ = false;
    if (literal_) {
        display_.pop_back();
        if (!typed_.empty()) typed_.pop_back();
        if (display_.empty()) endWord();
        return Edit();
    }
    if (options_.encoding != Encoding::Unicode) {
        reset();
        return Edit();
    }
    std::u16string remaining = display_.substr(0, display_.size() - 1);
    std::u16string keys;
    if (remaining.empty() || !encodeKeys(remaining, options_.method, keys)) {
        reset();  // cannot resume this word: the next key starts a new one
        return Edit();
    }
    std::u16string next = render(keys, false);
    if (next == remaining) {
        raw_ = keys;
        typed_ = keys;
        display_ = remaining;
        return Edit();
    }
    // Same letters, different tone position ("hoàn" -> "hòa" in the old style):
    // the platform applies the corrected word instead of a plain Backspace.
    if (allowEdit && next.size() == remaining.size()) {
        Edit edit = commit(next, 0);
        raw_ = keys;
        typed_ = keys;
        return edit;
    }
    reset();
    return Edit();
}

Edit Engine::undo() {
    if (display_.empty() || literal_ || typed_ == display_) return Edit();
    Edit edit = commit(typed_, 0);
    literal_ = true;
    hasPrevious_ = false;
    return edit;
}

std::u16string Engine::simulate(const std::string& keys, const Options& options) {
    Engine engine(options);
    std::u16string text;
    // Non-ASCII input (already Vietnamese text, emoji...) passes through unchanged.
    for (char16_t c : fromUtf8(keys)) {
        if (c == u'\b') {
            if (!text.empty()) text.pop_back();
            engine.backspace();
            continue;
        }
        Edit e = engine.key(c);
        if (!e.handled) {
            text.push_back(c);
            continue;
        }
        text.erase(text.size() - static_cast<size_t>(std::min<int>(e.backspaces, static_cast<int>(text.size()))));
        text += e.insert;
    }
    return text;
}

std::string toUtf8(const std::u16string& s) {
    std::string out;
    for (char16_t c : s) {
        if (c < 0x80) {
            out += static_cast<char>(c);
        } else if (c < 0x800) {
            out += static_cast<char>(0xC0 | (c >> 6));
            out += static_cast<char>(0x80 | (c & 0x3F));
        } else {
            out += static_cast<char>(0xE0 | (c >> 12));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (c & 0x3F));
        }
    }
    return out;
}

std::u16string fromUtf8(const std::string& s) {
    std::u16string out;
    for (size_t i = 0; i < s.size();) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        char32_t cp;
        if (c < 0x80) {
            cp = c;
            i += 1;
        } else if ((c >> 5) == 0x6 && i + 1 < s.size()) {
            cp = ((c & 0x1F) << 6) | (s[i + 1] & 0x3F);
            i += 2;
        } else if (i + 2 < s.size()) {
            cp = ((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
            i += 3;
        } else {
            break;
        }
        out.push_back(static_cast<char16_t>(cp));
    }
    return out;
}

} // namespace dokey
