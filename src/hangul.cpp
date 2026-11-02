// Dokey Core - Korean (Hangul) composition, 2-beolsik (두벌식) layout.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// The tables below are public Unicode data: the jamo of the standard Korean
// 2-set keyboard (KS X 5002), the order of initials, medials and finals used
// by the precomposed syllables (U+AC00 + (initial * 21 + medial) * 28 + final),
// and the standard compound vowels and final consonant clusters.
//
// Like the Vietnamese rules, composition is a pure function of the keys of
// the current word: the engine re-derives the whole word after every key.
#include "dokey/hangul.hpp"

#include <algorithm>
#include <cstddef>

namespace dokey {
namespace hangul {

namespace {

// Lower-case keys and the jamo they type; Shift changes only q w e r t o p.
const char16_t kKeys[] = u"qwertyuiopasdfghjklzxcvbnm";
const char16_t kJamo[] = u"ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡ";
const char16_t kShiftKeys[] = u"qwertop";
const char16_t kShiftJamo[] = u"ㅃㅉㄸㄲㅆㅒㅖ";

// Syllable order of initials (19) and finals (27, after "no final").
// Medials are U+314F..U+3163 in syllable order (ㅏ ㅐ ... ㅣ).
const char16_t kInitials[] = u"ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ";
const char16_t kFinals[] = u"ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ";
constexpr char16_t kFirstVowel = 0x314F;  // ㅏ
constexpr char16_t kLastVowel = 0x3163;   // ㅣ
constexpr char16_t kSyllableBase = 0xAC00;

struct Pair {
    char16_t first, second, joined;
};

const Pair kVowelPairs[] = {
    {u'ㅗ', u'ㅏ', u'ㅘ'}, {u'ㅗ', u'ㅐ', u'ㅙ'}, {u'ㅗ', u'ㅣ', u'ㅚ'}, {u'ㅜ', u'ㅓ', u'ㅝ'},
    {u'ㅜ', u'ㅔ', u'ㅞ'}, {u'ㅜ', u'ㅣ', u'ㅟ'}, {u'ㅡ', u'ㅣ', u'ㅢ'},
};

const Pair kFinalPairs[] = {
    {u'ㄱ', u'ㅅ', u'ㄳ'}, {u'ㄴ', u'ㅈ', u'ㄵ'}, {u'ㄴ', u'ㅎ', u'ㄶ'}, {u'ㄹ', u'ㄱ', u'ㄺ'},
    {u'ㄹ', u'ㅁ', u'ㄻ'}, {u'ㄹ', u'ㅂ', u'ㄼ'}, {u'ㄹ', u'ㅅ', u'ㄽ'}, {u'ㄹ', u'ㅌ', u'ㄾ'},
    {u'ㄹ', u'ㅍ', u'ㄿ'}, {u'ㄹ', u'ㅎ', u'ㅀ'}, {u'ㅂ', u'ㅅ', u'ㅄ'},
};

int indexOf(const char16_t* table, char16_t c) {
    for (int i = 0; table[i]; i++) {
        if (table[i] == c) return i;
    }
    return -1;
}

bool isVowel(char16_t j) {
    return j >= kFirstVowel && j <= kLastVowel;
}

template <size_t N>
char16_t join(const Pair (&pairs)[N], char16_t first, char16_t second) {
    for (const Pair& p : pairs) {
        if (p.first == first && p.second == second) return p.joined;
    }
    return 0;
}

// One character on screen: a syllable, a lone jamo, or a non-jamo key.
struct Block {
    char16_t initial = 0, vowel = 0, final = 0;
    bool closed = false;  // a non-jamo key: nothing joins it
};

char16_t glyph(const Block& b) {
    if (b.initial && b.vowel) {
        const int l = indexOf(kInitials, b.initial);
        const int v = b.vowel - kFirstVowel;
        const int t = b.final ? indexOf(kFinals, b.final) + 1 : 0;
        return static_cast<char16_t>(kSyllableBase + (l * 21 + v) * 28 + t);
    }
    return b.initial ? b.initial : b.vowel;
}

void addConsonant(std::vector<Block>& blocks, char16_t j) {
    Block* cur = blocks.empty() || blocks.back().closed ? nullptr : &blocks.back();
    if (cur && cur->initial && cur->vowel) {
        // 가 + ㄴ -> 간; ㄸ ㅃ ㅉ are never finals.
        if (!cur->final && indexOf(kFinals, j) >= 0) {
            cur->final = j;
            return;
        }
        // 갑 + ㅅ -> 값 (a cluster never takes a third consonant).
        if (cur->final) {
            if (char16_t cluster = join(kFinalPairs, cur->final, j)) {
                cur->final = cluster;
                return;
            }
        }
    }
    // A lone consonant does not join another one (ㄱ + ㅅ -> ㄱㅅ).
    Block b;
    b.initial = j;
    blocks.push_back(b);
}

void addVowel(std::vector<Block>& blocks, char16_t j) {
    Block* cur = blocks.empty() || blocks.back().closed ? nullptr : &blocks.back();
    if (cur && cur->final) {
        // A vowel takes the last consonant of the final as its initial:
        // 갑 + ㅏ -> 가바, 값 + ㅣ -> 갑시, 있 + ㅓ -> 이써.
        Block next;
        next.vowel = j;
        next.initial = cur->final;
        char16_t kept = 0;
        for (const Pair& p : kFinalPairs) {
            if (p.joined == cur->final) {
                kept = p.first;
                next.initial = p.second;
                break;
            }
        }
        cur->final = kept;
        blocks.push_back(next);
        return;
    }
    if (cur && cur->vowel) {
        // 고 + ㅏ -> 과, ㅡ + ㅣ -> ㅢ.
        if (char16_t compound = join(kVowelPairs, cur->vowel, j)) {
            cur->vowel = compound;
            return;
        }
    } else if (cur && cur->initial) {
        cur->vowel = j;  // ㄱ + ㅏ -> 가
        return;
    }
    Block b;
    b.vowel = j;
    blocks.push_back(b);
}

} // namespace

char16_t jamoForKey(char32_t key) {
    if (key >= U'A' && key <= U'Z') {
        const char16_t lower = static_cast<char16_t>(key - U'A' + U'a');
        const int shifted = indexOf(kShiftKeys, lower);
        if (shifted >= 0) return kShiftJamo[shifted];
        return kJamo[indexOf(kKeys, lower)];
    }
    if (key >= U'a' && key <= U'z') return kJamo[indexOf(kKeys, static_cast<char16_t>(key))];
    return 0;
}

bool isJamoKey(char32_t key) {
    return jamoForKey(key) != 0;
}

std::u16string compose(const std::u16string& keys) {
    std::vector<Block> blocks;
    for (size_t i = 0; i < keys.size(); i++) {
        const char16_t j = jamoForKey(static_cast<char32_t>(keys[i]));
        if (j == 0) {
            Block b;
            b.initial = keys[i];
            b.closed = true;
            blocks.push_back(b);
        } else if (isVowel(j)) {
            addVowel(blocks, j);
        } else {
            addConsonant(blocks, j);
        }
    }
    std::u16string out;
    out.reserve(blocks.size());
    for (const Block& b : blocks) out.push_back(glyph(b));
    return out;
}

} // namespace hangul

namespace {

// A word longer than this starts over as a new word (its syllables stay on
// screen but are no longer re-derived or split).
constexpr size_t kMaxWordKeys = 256;

} // namespace

void HangulEngine::reset() {
    raw_.clear();
    display_.clear();
}

Edit HangulEngine::commit(std::u16string next, char32_t typed) {
    Edit edit;
    size_t common = 0;
    while (common < display_.size() && common < next.size() && display_[common] == next[common]) common++;
    edit.backspaces = static_cast<int>(display_.size() - common);
    edit.insert = next.substr(common);
    edit.handled = !(edit.backspaces == 0 && edit.insert.size() == 1 && static_cast<char32_t>(edit.insert[0]) == typed);
    display_ = std::move(next);
    return edit;
}

Edit HangulEngine::key(char32_t ch) {
    if (!hangul::isJamoKey(ch)) {
        // Space, Enter, Tab, digits, punctuation: the word on screen is
        // already final, so the key always goes through untouched.
        reset();
        return Edit();
    }
    if (raw_.size() >= kMaxWordKeys) reset();
    raw_.push_back(static_cast<char16_t>(ch));
    return commit(hangul::compose(raw_), ch);
}

Edit HangulEngine::backspaceEdit() {
    if (display_.empty()) {
        reset();
        return Edit();
    }
    raw_.pop_back();
    std::u16string next = hangul::compose(raw_);
    if (next == display_.substr(0, display_.size() - 1)) {  // a plain Backspace does it
        display_ = next;
        if (display_.empty()) reset();
        return Edit();
    }
    return commit(next, 0);
}

std::u16string HangulEngine::simulate(const std::string& keys) {
    HangulEngine engine;
    std::u16string text;
    for (char16_t c : fromUtf8(keys)) {
        Edit e = c == u'\b' ? engine.backspaceEdit() : engine.key(static_cast<char32_t>(c));
        if (!e.handled) {
            if (c == u'\b') {
                if (!text.empty()) text.pop_back();
            } else {
                text.push_back(c);
            }
            continue;
        }
        text.erase(text.size() - static_cast<size_t>(std::min<int>(e.backspaces, static_cast<int>(text.size()))));
        text += e.insert;
    }
    return text;
}

} // namespace dokey
