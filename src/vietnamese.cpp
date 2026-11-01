// Dokey Core - Vietnamese letters, tones and syllable rules.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// The tables below are linguistic data: the Unicode code points of
// Vietnamese letters and the standard inventory of initials and rhymes.
#include "vietnamese.hpp"

#include "dokey/engine.hpp"

#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace dokey {

namespace {

// Rows: a ă â e ê i o ô ơ u ư y. Columns: no tone, sắc, huyền, hỏi, ngã, nặng.
const char16_t kLower[12][6] = {
    {0x0061, 0x00E1, 0x00E0, 0x1EA3, 0x00E3, 0x1EA1},
    {0x0103, 0x1EAF, 0x1EB1, 0x1EB3, 0x1EB5, 0x1EB7},
    {0x00E2, 0x1EA5, 0x1EA7, 0x1EA9, 0x1EAB, 0x1EAD},
    {0x0065, 0x00E9, 0x00E8, 0x1EBB, 0x1EBD, 0x1EB9},
    {0x00EA, 0x1EBF, 0x1EC1, 0x1EC3, 0x1EC5, 0x1EC7},
    {0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB},
    {0x006F, 0x00F3, 0x00F2, 0x1ECF, 0x00F5, 0x1ECD},
    {0x00F4, 0x1ED1, 0x1ED3, 0x1ED5, 0x1ED7, 0x1ED9},
    {0x01A1, 0x1EDB, 0x1EDD, 0x1EDF, 0x1EE1, 0x1EE3},
    {0x0075, 0x00FA, 0x00F9, 0x1EE7, 0x0169, 0x1EE5},
    {0x01B0, 0x1EE9, 0x1EEB, 0x1EED, 0x1EEF, 0x1EF1},
    {0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5},
};
const char16_t kUpper[12][6] = {
    {0x0041, 0x00C1, 0x00C0, 0x1EA2, 0x00C3, 0x1EA0},
    {0x0102, 0x1EAE, 0x1EB0, 0x1EB2, 0x1EB4, 0x1EB6},
    {0x00C2, 0x1EA4, 0x1EA6, 0x1EA8, 0x1EAA, 0x1EAC},
    {0x0045, 0x00C9, 0x00C8, 0x1EBA, 0x1EBC, 0x1EB8},
    {0x00CA, 0x1EBE, 0x1EC0, 0x1EC2, 0x1EC4, 0x1EC6},
    {0x0049, 0x00CD, 0x00CC, 0x1EC8, 0x0128, 0x1ECA},
    {0x004F, 0x00D3, 0x00D2, 0x1ECE, 0x00D5, 0x1ECC},
    {0x00D4, 0x1ED0, 0x1ED2, 0x1ED4, 0x1ED6, 0x1ED8},
    {0x01A0, 0x1EDA, 0x1EDC, 0x1EDE, 0x1EE0, 0x1EE2},
    {0x0055, 0x00DA, 0x00D9, 0x1EE6, 0x0168, 0x1EE4},
    {0x01AF, 0x1EE8, 0x1EEA, 0x1EEC, 0x1EEE, 0x1EF0},
    {0x0059, 0x00DD, 0x1EF2, 0x1EF6, 0x1EF8, 0x1EF4},
};
const char kRowBase[12] = {'a', 'a', 'a', 'e', 'e', 'i', 'o', 'o', 'o', 'u', 'u', 'y'};
const Mark kRowMark[12] = {Mark::None, Mark::Breve, Mark::Circumflex, Mark::None, Mark::Circumflex, Mark::None,
                           Mark::None, Mark::Circumflex, Mark::Horn, Mark::None, Mark::Horn, Mark::None};

int vowelRow(char base, Mark mark) {
    for (int r = 0; r < 12; r++) {
        if (kRowBase[r] == base && kRowMark[r] == mark) return r;
    }
    return -1;
}

// --- Syllable inventory --------------------------------------------------

const char* const kInitials[] = {
    "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh",
    "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x",
    "kr",  // Central Highlands place names: Krông Búk, Krông Pắc
};

// Rhymes as written after an ordinary initial consonant.
const char* const kRhymes[] = {
    "a", "ac", "ach", "ai", "am", "an", "ang", "anh", "ao", "ap", "at", "au", "ay",
    "ăc", "ăk", "ăm", "ăn", "ăng", "ăp", "ăt",  // ăk: Đắk Lắk
    "âc", "âm", "ân", "âng", "âp", "ât", "âu", "ây",
    "e", "ec", "em", "en", "eng", "eo", "ep", "et",
    "ê", "êch", "êm", "ên", "ênh", "êp", "êt", "êu",
    "i", "ia", "ich", "im", "in", "inh", "ip", "it", "iu",
    "iêc", "iêm", "iên", "iêng", "iêp", "iêt", "iêu",
    "o", "oc", "oi", "om", "on", "ong", "op", "ot",
    "oa", "oac", "oach", "oai", "oam", "oan", "oang", "oanh", "oao", "oap", "oat", "oay",
    "oăc", "oăm", "oăn", "oăng", "oăt", "oe", "oen", "oeo", "oet", "ooc", "oong",
    "ô", "ôc", "ôi", "ôm", "ôn", "ông", "ôp", "ôt",
    "ơ", "ơi", "ơm", "ơn", "ơp", "ơt",
    "u", "ua", "uc", "uk", "ui", "um", "un", "ung", "up", "ut",  // uk: Búk
    "uân", "uâng", "uât", "uây", "uê", "uêch", "uênh", "uơ",
    "uy", "uych", "uynh", "uyp", "uyt", "uya", "uyu", "uyên", "uyêt",
    "uôc", "uôi", "uôm", "uôn", "uông", "uôt",
    "ư", "ưa", "ưc", "ưi", "ưm", "ưn", "ưng", "ưt", "ưu",
    "ươc", "ươi", "ươm", "ươn", "ương", "ươp", "ươt", "ươu",
    "y",
};

// Rhymes that only follow "qu" (the u belongs to the initial).
const char* const kQuOnlyRhymes[] = {"y", "yên", "yêt", "ynh", "ych", "yt", "yp"};

bool isFront(char16_t c) {
    return c == u'e' || c == u'ê' || c == u'i' || c == u'y';
}

struct Dictionary {
    std::unordered_set<std::u16string> marked;
    std::unordered_set<std::u16string> stripped;
    // Marked prefixes grouped by their unmarked form, for isCompatibleSyllablePrefix.
    std::unordered_map<std::u16string, std::vector<std::u16string>> byStripped;
    std::vector<std::u16string> syllables;
    std::unordered_set<std::u16string> complete;

    void add(const std::u16string& syllable) {
        syllables.push_back(syllable);
        complete.insert(syllable);
        for (size_t n = 1; n <= syllable.size(); n++) {
            std::u16string prefix = syllable.substr(0, n);
            if (marked.insert(prefix).second) byStripped[stripMarks(prefix)].push_back(prefix);
            stripped.insert(stripMarks(prefix));
        }
    }

    Dictionary() {
        for (const char* initialUtf8 : kInitials) {
            const std::u16string initial = fromUtf8(initialUtf8);
            if (initial == u"qu") {
                for (const char* r : kRhymes) {
                    std::u16string rhyme = fromUtf8(r);
                    char16_t first = rhyme[0];
                    if (first == u'a' || first == u'ă' || first == u'â' || first == u'e' || first == u'ê' ||
                        first == u'ơ' || (first == u'i' && rhyme.size() <= 3 && rhyme.find(u'ê') == std::u16string::npos))
                        add(initial + rhyme);
                }
                for (const char* r : kQuOnlyRhymes) add(initial + fromUtf8(r));
                continue;
            }
            for (const char* r : kRhymes) {
                std::u16string rhyme = fromUtf8(r);
                if (initial.empty()) {
                    // "iê" is written "yê" when nothing precedes it.
                    if (rhyme.size() >= 2 && rhyme[0] == u'i' && rhyme[1] == u'ê') rhyme[0] = u'y';
                    add(rhyme);
                    continue;
                }
                if (initial == u"gi") {
                    // gi + i... drops one i (gì, gìn, giêng).
                    add(rhyme[0] == u'i' ? initial + rhyme.substr(1) : initial + rhyme);
                    continue;
                }
                const bool front = isFront(rhyme[0]);
                if ((initial == u"c" || initial == u"g" || initial == u"ng") && front) continue;
                if ((initial == u"k") && !front) continue;
                if ((initial == u"gh" || initial == u"ngh") && (!front || rhyme[0] == u'y')) continue;
                add(initial + rhyme);
            }
        }
    }
};

const Dictionary& dictionary() {
    static const Dictionary dict;
    return dict;
}

} // namespace

char16_t markedLetter(char base, Mark mark) {
    if (base == 'd') return mark == Mark::Stroke ? u'đ' : u'd';
    int row = vowelRow(base, mark);
    if (row >= 0) return kLower[row][0];
    return static_cast<char16_t>(base);
}

char16_t composeLetter(char base, Mark mark, Tone tone, bool upper) {
    if (base == 'd' && mark == Mark::Stroke) return upper ? u'Đ' : u'đ';
    int row = vowelRow(base, mark);
    if (row >= 0) return (upper ? kUpper : kLower)[row][static_cast<int>(tone)];
    return static_cast<char16_t>(upper ? base - 'a' + 'A' : base);
}

bool decomposeLetter(char16_t ch, char& base, Mark& mark, Tone& tone, bool& upper) {
    tone = Tone::None;
    mark = Mark::None;
    if (ch == u'đ' || ch == u'Đ') {
        base = 'd';
        mark = Mark::Stroke;
        upper = ch == u'Đ';
        return true;
    }
    if ((ch >= u'a' && ch <= u'z') || (ch >= u'A' && ch <= u'Z')) {
        upper = ch <= u'Z';
        base = static_cast<char>(upper ? ch - u'A' + u'a' : ch);
        return true;
    }
    for (int r = 0; r < 12; r++) {
        for (int t = 0; t < 6; t++) {
            if (kLower[r][t] == ch || kUpper[r][t] == ch) {
                base = kRowBase[r];
                mark = kRowMark[r];
                tone = static_cast<Tone>(t);
                upper = kUpper[r][t] == ch;
                return true;
            }
        }
    }
    return false;
}

char16_t combiningTone(Tone tone) {
    switch (tone) {
        case Tone::Acute: return 0x0301;
        case Tone::Grave: return 0x0300;
        case Tone::Hook: return 0x0309;
        case Tone::Tilde: return 0x0303;
        case Tone::Dot: return 0x0323;
        default: return 0;
    }
}

std::u16string stripMarks(const std::u16string& s) {
    std::u16string out = s;
    for (char16_t& c : out) {
        char base;
        Mark mark;
        Tone tone;
        bool upper;
        if (c > 0x7F && decomposeLetter(c, base, mark, tone, upper)) c = static_cast<char16_t>(base);
    }
    return out;
}

bool isSyllablePrefix(const std::u16string& lowerMarked) {
    return dictionary().marked.count(lowerMarked) != 0;
}

bool isStrippedSyllablePrefix(const std::u16string& lowerUnmarked) {
    return dictionary().stripped.count(lowerUnmarked) != 0;
}

bool isCompatibleSyllablePrefix(const std::u16string& lowerMarked) {
    const auto& groups = dictionary().byStripped;
    auto it = groups.find(stripMarks(lowerMarked));
    if (it == groups.end()) return false;
    for (const std::u16string& prefix : it->second) {
        bool ok = true;
        for (size_t i = 0; ok && i < prefix.size(); i++) {
            // A marked letter must match; a plain letter may still get its mark.
            const char16_t c = lowerMarked[i];
            ok = c == prefix[i] || c < 0x80;
        }
        if (ok) return true;
    }
    return false;
}

bool isSyllable(const std::u16string& lowerMarked) {
    return dictionary().complete.count(lowerMarked) != 0;
}

const std::vector<std::u16string>& allSyllables() {
    return dictionary().syllables;
}

} // namespace dokey
