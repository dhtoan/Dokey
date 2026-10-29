// Dokey Core - engine tests.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "dokey/engine.hpp"
#include "dokey/dokey.h"
#include "../src/vietnamese.hpp"

#include <cstdio>
#include <string>
#include <vector>

using namespace dokey;

static int g_failed = 0, g_total = 0;

static void check(const std::string& keys, const std::string& expected, const Options& o, const char* label) {
    g_total++;
    std::string got = toUtf8(Engine::simulate(keys, o));
    if (got != expected) {
        g_failed++;
        if (g_failed <= 60)
            std::printf("FAIL [%s] %-24s => \"%s\" (expected \"%s\")\n", label, keys.c_str(), got.c_str(), expected.c_str());
    }
}

struct Case {
    const char* keys;
    const char* expected;
};

// Hand-written expectations (independent of the engine's own tables).
static const Case kTelex[] = {
    {"tieengs Vieetj ", "tiếng Việt "},
    {"dduowngf ", "đường "},
    // Mid-word "đuo" must stay Vietnamese (it can still become được, đuôi),
    // not flip back to the typed keys "dduo" and forth again.
    {"dduo", "đuo"},
    {"dduocwj ", "được "},
    {"dduocjw ", "được "},
    {"dduowcj ", "được "},
    {"haxy hayx ", "hãy hãy "},
    {"maf vaf ", "mà và "},
    {"DDuowngf ", "Đường "},
    {"nguoiwf ", "người "},
    {"nguowif ", "người "},
    {"chaof cacs banj ", "chào các bạn "},
    {"khoong ", "không "},
    {"cuar ", "của "},
    {"thuowr ", "thuở "},
    {"nguyeenx ", "nguyễn "},
    {"muoons ", "muốn "},
    {"hoaf ", "hoà "},
    {"khoer ", "khoẻ "},
    {"thuys ", "thuý "},
    {"hoanf ", "hoàn "},
    {"toans ", "toán "},
    {"quas ", "quá "},
    {"giaf ", "già "},
    {"gif ", "gì "},
    {"giuwx ", "giữ "},
    {"gifn ", "gìn "},
    {"ngoaif ", "ngoài "},
    {"xoays ", "xoáy "},
    {"khuyeen ", "khuyên "},
    {"chuyeenj ", "chuyện "},
    {"yeeu ", "yêu "},
    {"huwowng ", "hương "},
    {"mwa ", "mưa "},
    {"muwa ", "mưa "},
    {"nhw ", "như "},
    {"w ", "ư "},
    {"tuw ", "tư "},
    {"aw ", "aw "},      // "ă" alone is not a syllable
    {"use ", "use "},
    {"tiengs ", "tiengs "},  // no circumflex typed: not a word
    {"awn ", "ăn "},
    {"tieengs ", "tiếng "},
    {"tienges ", "tiếng "},
    {"tiengse ", "tiếng "},
    {"Tieengs ", "Tiếng "},
    {"TIEENGS ", "TIẾNG "},
    {"cuwowis ", "cưới "},
    {"ruowuj ", "rượu "},
    {"khuyux ", "khuỹu "},
    {"Vieetj Nam ", "Việt Nam "},
    {"hocj ", "học "},
    {"sachs ", "sách "},
    {"mootj ", "một "},
    {"hai ", "hai "},
    {"ba ", "ba "},
    {"boons ", "bốn "},
    {"nawm ", "năm "},
    {"sasu ", "sáu "},
    {"bayr ", "bảy "},
    {"tams ", "tám "},
    {"chins ", "chín "},
    {"muwowif ", "mười "},
    {"ddi ", "đi "},
    {"ddeens ", "đến "},
    {"dda ", "đa "},
    {"ddaauf ", "đầu "},
    {"ddoongf ", "đồng "},
    {"truwowngf ", "trường "},
    {"nghieengf ", "nghiềng "},
    {"nghiax ", "nghĩa "},
    {"phaanr ", "phẩn "},
    {"kys ", "ký "},
    {"lyx ", "lỹ "},
    {"thees ", "thế "},
    {"gioongs ", "giống "},
    {"quyeets ", "quyết "},
    {"quaan ", "quân "},
    {"oong ", "ông "},
    {"uoongs ", "uống "},
    {"ow ", "ơ "},
    {"owr ", "ở "},
    {"ddaay ", "đây "},
    // undo by repeating the key
    {"aaa ", "aa "},
    {"ass ", "as "},
    {"ddd ", "dd "},
    {"ww ", "w "},
    {"asf ", "à "},
    {"asz ", "a "},
    // English words are kept as typed
    {"windows ", "windows "},
    {"master ", "master "},
    {"chrome ", "chrome "},
    {"with ", "with "},
    {"google ", "google "},
    {"email ", "email "},
    {"github ", "github "},
    {"street ", "street "},
    {"Dokey ", "Dokey "},
    // punctuation and numbers break words
    {"vieetj, nam.", "việt, nam."},
    {"2026 laf nawm ", "2026 là năm "},
    // backspace
    {"tieengs\b\bn ", "tiến "},
    {"vieetj\bt ", "việt "},
    {"booong ", "boong "},
    {"xooong ", "xoong "},
    {"huow ", "huơ "},
};

static const Case kTelexOld[] = {
    {"hoaf ", "hòa "},
    {"khoer ", "khỏe "},
    {"thuys ", "thúy "},
    {"hoanf ", "hoàn "},
};

static const Case kVni[] = {
    {"tie61ng Vie65t ", "tiếng Việt "},
    {"d9u7o7ng2 ", "đường "},
    {"ngu7o7i2 ", "người "},
    {"nguoi72 ", "người "},
    {"cha2o ca1c ba5n ", "chào các bạn "},
    {"kho6ng ", "không "},
    {"hoa2 ", "hoà "},
    {"qua1 ", "quá "},
    {"a8n ", "ăn "},
    {"a11 ", "a1 "},
    {"a66 ", "a6 "},
    {"2026 ", "2026 "},
    {"windows ", "windows "},
};

static const char16_t kTelexToneKey[] = {0, u's', u'f', u'r', u'x', u'j'};

// Telex keys that a person would type for `word` (marks right after the
// letter, tone at the end). Written independently of the engine's encoder.
static std::string telexKeys(const std::u16string& word, int tone) {
    std::string out;
    for (char16_t c : word) {
        switch (c) {
            case u'â': out += "aa"; break;
            case u'ê': out += "ee"; break;
            case u'ô': out += "oo"; break;
            case u'ă': out += "aw"; break;
            case u'ơ': out += "ow"; break;
            case u'ư': out += "uw"; break;
            case u'đ': out += "dd"; break;
            default: out += static_cast<char>(c); break;
        }
    }
    if (tone) out += static_cast<char>(kTelexToneKey[tone]);
    return out;
}

static bool isV(char16_t c) {
    std::u16string vowels = u"aăâeêioôơuưy";
    return vowels.find(c) != std::u16string::npos;
}

// Expected placement, implemented separately from the engine.
static std::u16string expectedWithTone(const std::u16string& w, int tone, bool modern) {
    if (!tone) return w;
    size_t start = 0;
    if (w.size() > 2 && w.compare(0, 2, u"qu") == 0 && isV(w[2])) start = 2;
    else if (w.size() > 2 && w.compare(0, 2, u"gi") == 0 && isV(w[2])) start = 2;
    else while (start < w.size() && !isV(w[start])) start++;
    size_t end = start;
    while (end < w.size() && isV(w[end])) end++;
    std::u16string nucleus = w.substr(start, end - start);
    size_t pos;
    size_t marked = nucleus.find_last_of(u"ăâêôơư");
    if (marked != std::u16string::npos) pos = marked;
    else if (end < w.size()) pos = nucleus.size() - 1;
    else if (nucleus.size() == 3) pos = 1;
    else if (nucleus.size() == 2) pos = (modern && (nucleus == u"oa" || nucleus == u"oe" || nucleus == u"uy")) ? 1 : 0;
    else pos = 0;
    std::u16string out = w;
    char base;
    Mark mark;
    Tone t;
    bool upper;
    decomposeLetter(out[start + pos], base, mark, t, upper);
    out[start + pos] = composeLetter(base, mark, static_cast<Tone>(tone), false);
    return out;
}

static bool isStop(const std::u16string& w) {
    auto ends = [&](const char16_t* s) {
        std::u16string e(s);
        return w.size() >= e.size() && w.compare(w.size() - e.size(), e.size(), e) == 0;
    };
    return ends(u"c") || ends(u"ch") || ends(u"p") || ends(u"t");
}

static void roundTrip() {
    Options o;
    int before = g_failed;
    for (const std::u16string& syl : allSyllables()) {
        // "oo" needs a third o in Telex (booong -> boong); covered by hand cases.
        if (syl.find(u"oo") != std::u16string::npos) continue;
        for (int tone = 0; tone <= 5; tone++) {
            if (isStop(syl) && tone != 0 && tone != 1 && tone != 5) continue;
            std::u16string expected = expectedWithTone(syl, tone, true) + u" ";
            check(telexKeys(syl, tone) + " ", toUtf8(expected), o, "roundtrip");
        }
    }
    std::printf("round-trip: %zu syllables x tones, %d failures\n", allSyllables().size(), g_failed - before);
}

static void cApi() {
    g_total++;
    dokey_options opt = {DOKEY_TELEX, DOKEY_UNICODE, 1, 1};
    dokey_engine* e = dokey_create(&opt);
    dokey_edit edit;
    dokey_key(e, 'a', &edit);
    int handled = dokey_key(e, 'a', &edit);
    bool good = handled == 1 && edit.backspaces == 1 && edit.length == 1 && edit.text[0] == 0x00E2;
    dokey_destroy(e);
    if (!good) {
        g_failed++;
        std::printf("FAIL [c-api] aa\n");
    }
}

static void passthrough() {
    // Plain letters must not cause synthetic events.
    g_total++;
    Engine e;
    Edit a = e.key(U'b');
    Edit b = e.key(U'a');
    Edit c = e.key(U'n');
    if (a.handled || b.handled || c.handled) {
        g_failed++;
        std::printf("FAIL [passthrough] plain letters were rewritten\n");
    }
}

int main() {
    Options telex;
    for (const Case& c : kTelex) check(c.keys, c.expected, telex, "telex");

    Options old = telex;
    old.modernToneStyle = false;
    for (const Case& c : kTelexOld) check(c.keys, c.expected, old, "telex-old");

    Options vni;
    vni.method = InputMethod::VNI;
    for (const Case& c : kVni) check(c.keys, c.expected, vni, "vni");

    Options combining;
    combining.encoding = Encoding::UnicodeCombining;
    check("vieetj ", "vi\xC3\xAA\xCC\xA3t ", combining, "combining");

    roundTrip();
    cApi();
    passthrough();

    std::printf("\n%d/%d passed\n", g_total - g_failed, g_total);
    return g_failed == 0 ? 0 : 1;
}
