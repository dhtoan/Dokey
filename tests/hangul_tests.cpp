// Dokey Core - Hangul (2-beolsik) composer tests.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "dokey/hangul.hpp"
#include "dokey/dokey.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace dokey;

static int g_failed = 0, g_total = 0;

static void fail(const char* label, const std::string& keys, const std::u16string& got, const std::u16string& expected) {
    g_failed++;
    if (g_failed > 60) return;
    std::string shown;
    for (char c : keys) shown += c == '\b' ? std::string("⌫") : std::string(1, c);
    std::printf("FAIL [%s] %-20s => \"%s\" (expected \"%s\")\n", label, shown.c_str(), toUtf8(got).c_str(),
                toUtf8(expected).c_str());
}

static void check(const std::string& keys, const std::string& expected, const char* label = "hangul") {
    g_total++;
    std::u16string want = fromUtf8(expected);
    std::u16string got = HangulEngine::simulate(keys);
    if (got != want) fail(label, keys, got, want);
}

struct Case {
    const char* keys;
    const char* expected;
};

// Hand-written expectations: 2-beolsik keys on a US/ABC layout.
static const Case kWords[] = {
    {"gksrnr", "한국"},
    {"gksrmf", "한글"},
    {"dkssudgktpdy", "안녕하세요"},
    {"rkatkgkqslek", "감사합니다"},
    {"tkfkdgo", "사랑해"},
    {"wjsms gkrtoddlqslek.", "저는 학생입니다."},
    {"dlTdj", "있어"},
    {"dlTtmqslek", "있습니다"},
    {"ekfrdl", "닭이"},
    {"dlfrdj", "읽어"},
    {"dksgdk", "않아"},
    {"qkfqdk", "밟아"},
    {"rkqtdl", "값이"},
    {"RkRdk", "깎아"},
    {"Ekfrl", "딸기"},
    {"Tmrl", "쓰기"},
    {"Qkfrks", "빨간"},
    {"Wkek", "짜다"},
    // Compound vowels.
    {"rhk", "과"},
    {"rhkd", "광"},
    {"dho", "왜"},
    {"dhl", "외"},
    {"dnjs", "원"},
    {"dnp", "웨"},
    {"dnl", "위"},
    {"dml", "의"},
    {"rnjs", "권"},
    {"ghkdlxld", "화이팅"},
    // Shift matters only on q w e r t o p.
    {"GKS", "한"},
    {"rK", "가"},
    {"dO", "얘"},
    {"dP", "예"},
    {"dkO", "아ㅒ"},
    // Space, digits and punctuation end the word and go through unchanged.
    {"gks rnr", "한 국"},
    {"gks1rnr", "한1국"},
    {"dkssud!", "안녕!"},
    {"gks\nrnr", "한\n국"},
};

// The final consonant moves to the next syllable when a vowel follows it.
static const Case kSplit[] = {
    {"rkq", "갑"},
    {"rkqk", "가바"},
    {"rkqt", "값"},
    {"rkqtl", "갑시"},
    {"ekfr", "닭"},
    {"ekfrl", "달기"},
    {"dkfg", "앓"},
    {"dkfgk", "알하"},
    {"dlT", "있"},
    {"dlTj", "이써"},
    {"gksk", "하나"},
};

// Jamo that cannot join a syllable stay as compatibility jamo.
static const Case kLoneJamo[] = {
    {"r", "ㄱ"},
    {"k", "ㅏ"},
    {"rr", "ㄱㄱ"},
    {"rt", "ㄱㅅ"},   // lone consonants do not cluster
    {"kk", "ㅏㅏ"},
    {"hk", "ㅘ"},     // lone compound vowel
    {"hkl", "ㅘㅣ"},
    {"rhkl", "과ㅣ"},
    {"kr", "ㅏㄱ"},   // a syllable needs an initial consonant
    {"kRk", "ㅏ까"},
    {"dkE", "아ㄸ"},  // ㄸ ㅃ ㅉ are never finals
    {"dkEk", "아따"},
    {"dkQ", "아ㅃ"},
    {"dkW", "아ㅉ"},
    {"gkss", "한ㄴ"},  // ㄴ + ㄴ is not a cluster
    {"rkqtt", "값ㅅ"}, // a cluster takes no third consonant
    {"QQ", "ㅃㅃ"},
};

// Backspace removes one jamo of the word being typed (key by key).
static const Case kBackspace[] = {
    {"gks\b", "하"},
    {"gks\b\b", "ㅎ"},
    {"gks\b\b\b", ""},
    {"gks\b\b\b\b", ""},
    {"rhk\b", "고"},
    {"rkqt\b", "갑"},
    {"rkqtl\b", "값"},
    {"rkqk\b", "갑"},     // undoing the last key re-joins the final
    {"gksrnr\b\b\b", "한"},
    {"gksrnr\b\b\b\b", "하"},
    {"gks\bs", "한"},
    {"gks\bk", "하ㅏ"},
    // After a word break the previous word is plain text again.
    {"gks \b", "한"},
    {"gks \bk", "한ㅏ"},
    {"gks \b\b", ""},
};

// Every precomposed syllable, typed from keys built with tables written here
// (independent of the composer's own tables).
static const char* const kInitialKeys[19] = {"r", "R", "s", "e", "E", "f", "a", "q", "Q", "t",
                                             "T", "d", "w", "W", "c", "z", "x", "v", "g"};
static const char* const kVowelKeys[21] = {"k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho",
                                           "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l"};
static const char* const kFinalKeys[28] = {"", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr",
                                           "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "qt", "t",
                                           "T", "d", "w", "c", "z", "x", "v", "g"};
// For each final: the final that stays and the initial that moves when a vowel follows.
static const int kFinalStays[28] = {0, 0, 0, 1, 0, 4, 4, 0, 0, 8, 8, 8, 8, 8, 8, 8, 0, 0, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0};
static const int kFinalMoves[28] = {-1, 0, 1, 9, 2, 12, 18, 3, 5, 0, 6, 7, 9, 16, 17, 18,
                                    6, 7, 9, 9, 10, 11, 12, 14, 15, 16, 17, 18};

static char16_t syllable(int l, int v, int t) {
    return static_cast<char16_t>(0xAC00 + (l * 21 + v) * 28 + t);
}

static void exhaustive() {
    const int before = g_failed;
    int count = 0;
    for (int l = 0; l < 19; l++) {
        for (int v = 0; v < 21; v++) {
            for (int t = 0; t < 28; t++) {
                const std::string keys = std::string(kInitialKeys[l]) + kVowelKeys[v] + kFinalKeys[t];
                const char16_t s = syllable(l, v, t);
                count++;
                g_total++;
                std::u16string got = hangul::compose(fromUtf8(keys));
                if (got != std::u16string(1, s)) fail("syllable", keys, got, std::u16string(1, s));

                // + ㅇㅏ: the final stays (값아, 닭아).
                g_total++;
                std::u16string want = std::u16string(1, s) + u"아";
                got = hangul::compose(fromUtf8(keys + "dk"));
                if (got != want) fail("syllable+ㅇㅏ", keys + "dk", got, want);

                // + ㅏ: the (last consonant of the) final becomes the next initial.
                if (t == 0) continue;
                g_total++;
                want = std::u16string(1, syllable(l, v, kFinalStays[t])) + syllable(kFinalMoves[t], 0, 0);
                got = hangul::compose(fromUtf8(keys + "k"));
                if (got != want) fail("syllable+ㅏ", keys + "k", got, want);
            }
        }
    }
    std::printf("exhaustive: %d syllables, each alone, + ㅇㅏ and + ㅏ, %d failures\n", count, g_failed - before);
}

// Platform view: the text on screen after every key equals compose() of the
// keys so far, every character is Hangul, and Enter is never handled: there
// is no pending composition to flush when the user presses it.
static void invariants() {
    const int before = g_failed;
    const std::string alphabet = "qwertyuiopasdfghjklzxcvbnmQWERTOP";
    unsigned seed = 12345;
    auto next = [&]() {
        seed = seed * 1103515245u + 12345u;
        return (seed >> 16) & 0x7FFF;
    };
    long keys = 0, edited = 0, deleted = 0, inserted = 0;
    for (int run = 0; run < 20000; run++) {
        HangulEngine e;
        std::u16string screen, typed;
        const int len = 1 + static_cast<int>(next() % 24);
        bool ok = true;
        for (int i = 0; i < len; i++) {
            const char16_t k = static_cast<char16_t>(alphabet[next() % alphabet.size()]);
            typed.push_back(k);
            Edit ed = e.key(static_cast<char32_t>(k));
            keys++;
            if (ed.handled) {
                edited++;
                deleted += ed.backspaces;
                inserted += static_cast<long>(ed.insert.size());
                screen.erase(screen.size() - static_cast<size_t>(ed.backspaces));
                screen += ed.insert;
            } else {
                screen.push_back(k);
            }
            if (screen != hangul::compose(typed) || screen != e.currentWord()) ok = false;
            for (char16_t c : screen) {
                if (!((c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x3131 && c <= 0x3163))) ok = false;
            }
        }
        const std::u16string before = screen;
        Edit enter = e.key(U'\r');
        if (enter.handled || !e.currentWord().empty()) ok = false;
        g_total++;
        if (!ok) {
            std::string shown;
            for (char16_t c : typed) shown += static_cast<char>(c);
            fail("invariant", shown, before, hangul::compose(typed));
        }
    }
    std::printf("invariants: 20000 random words, %ld keys; %ld%% of keys rewritten, %.2f deleted and %.2f inserted "
                "per key, Enter never handled; %d failures\n",
                keys, edited * 100 / keys, double(deleted) / keys, double(inserted) / keys, g_failed - before);
}

// Long words: typing and Backspace work across many syllables; past the key
// limit a new word starts (the last syllable no longer splits back).
static void longWords() {
    std::string keys, expected;
    for (int i = 0; i < 40; i++) {
        keys += "gks";
        expected += "한";
    }
    const std::string all = expected, butLast = expected.substr(0, expected.size() - 3);
    check(keys, all, "long");
    check(keys + "k", butLast + "하나", "long");
    check(keys + "", butLast.substr(0, butLast.size() - 3) + "하", "long");
    std::string many, shown;
    for (int i = 0; i < 128; i++) {
        many += "rk";
        shown += "가";
    }
    check(many + "s", shown + "ㄴ", "long");     // key 257 starts a new word
    check(many + "sk", shown + "나", "long");
}

// The C API the platform apps use: switching language, typing, Enter, Backspace.
static void cApi() {
    g_total++;
    dokey_options opt = {};
    opt.check_spelling = 1;
    dokey_engine* e = dokey_create(&opt);
    dokey_edit edit;
    dokey_set_language(e, DOKEY_LANG_KOREAN);
    for (char c : std::string("gk")) dokey_key(e, static_cast<uint32_t>(c), &edit);
    const int n = dokey_key(e, 's', &edit);  // 하 -> 한
    const bool keyOk = n == 1 && edit.backspaces == 1 && edit.length == 1 && edit.text[0] == 0xD55C;
    const int bs = dokey_backspace_edit(e, &edit);  // 한 -> 하
    const bool bsOk = bs == 1 && edit.backspaces == 1 && edit.length == 1 && edit.text[0] == 0xD558;
    const bool enterOk = dokey_key(e, 0x0D, &edit) == 0 && dokey_undo(e, &edit) == 0;
    dokey_set_language(e, DOKEY_LANG_VIETNAMESE);
    dokey_key(e, 'a', &edit);
    const bool vietOk = dokey_key(e, 'a', &edit) == 1 && edit.text[0] == 0x00E2;  // aa -> â
    dokey_destroy(e);
    if (!keyOk || !bsOk || !enterOk || !vietOk) {
        g_failed++;
        std::printf("FAIL [c-api] key=%d backspace=%d enter=%d vietnamese=%d\n", keyOk, bsOk, enterOk, vietOk);
    }
}

int main() {
    for (const Case& c : kWords) check(c.keys, c.expected, "word");
    for (const Case& c : kSplit) check(c.keys, c.expected, "split");
    for (const Case& c : kLoneJamo) check(c.keys, c.expected, "jamo");
    for (const Case& c : kBackspace) check(c.keys, c.expected, "backspace");
    exhaustive();
    invariants();
    longWords();
    cApi();

    // Plain letters are always rewritten; non-jamo keys never are.
    g_total++;
    HangulEngine e;
    if (!e.key(U'g').handled || e.key(U' ').handled || e.key(U'\t').handled || e.key(U'1').handled) {
        g_failed++;
        std::printf("FAIL [handled] jamo keys must be handled, word breaks must not\n");
    }

    std::printf("\n%d/%d passed\n", g_total - g_failed, g_total);
    return g_failed == 0 ? 0 : 1;
}
