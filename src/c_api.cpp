// Dokey Core - C API.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "dokey/dokey.h"

#include "dokey/engine.hpp"
#include "dokey/hangul.hpp"

struct dokey_engine {
    dokey::Engine engine;
    dokey::HangulEngine hangul;
    bool korean = false;
};

namespace {

dokey::Options convert(const dokey_options* o) {
    dokey::Options out;
    if (o == nullptr) return out;
    out.method = o->method == DOKEY_VNI ? dokey::InputMethod::VNI : dokey::InputMethod::Telex;
    out.encoding = o->encoding == DOKEY_UNICODE_COMBINING ? dokey::Encoding::UnicodeCombining : dokey::Encoding::Unicode;
    out.modernToneStyle = o->modern_tone_style != 0;
    out.checkSpelling = o->check_spelling != 0;
    out.quickTelex = o->quick_telex != 0;
    return out;
}

} // namespace

extern "C" {

dokey_engine* dokey_create(const dokey_options* options) {
    return new dokey_engine{dokey::Engine(convert(options)), dokey::HangulEngine(), false};
}

void dokey_set_options(dokey_engine* e, const dokey_options* options) {
    if (e) e->engine.setOptions(convert(options));
}

void dokey_set_language(dokey_engine* e, int language) {
    if (!e) return;
    e->korean = language == DOKEY_LANG_KOREAN;
    e->engine.reset();
    e->hangul.reset();
}

namespace {

int toC(dokey_engine* e, const dokey::Edit& edit, dokey_edit* out) {
    out->backspaces = 0;
    out->length = 0;
    if (!edit.handled || edit.insert.size() > DOKEY_MAX_EDIT) {
        if (edit.handled) {  // cannot express it: give up on this word
            e->engine.reset();
            e->hangul.reset();
        }
        return 0;
    }
    out->backspaces = edit.backspaces;
    out->length = static_cast<int>(edit.insert.size());
    for (size_t i = 0; i < edit.insert.size(); i++) out->text[i] = edit.insert[i];
    return 1;
}

} // namespace

int dokey_key(dokey_engine* e, uint32_t ch, dokey_edit* out) {
    if (!e || !out) return 0;
    const char32_t c = static_cast<char32_t>(ch);
    return toC(e, e->korean ? e->hangul.key(c) : e->engine.key(c), out);
}

int dokey_backspace_edit(dokey_engine* e, dokey_edit* out) {
    if (!e || !out) return 0;
    return toC(e, e->korean ? e->hangul.backspaceEdit() : e->engine.backspaceEdit(), out);
}

int dokey_undo(dokey_engine* e, dokey_edit* out) {
    if (!e || !out) return 0;
    if (e->korean) return toC(e, dokey::Edit(), out);
    return toC(e, e->engine.undo(), out);
}

void dokey_set_macros(dokey_engine* e, const char* lines) {
    if (!e) return;
    std::vector<dokey::Macro> macros;
    const std::u16string all = lines ? dokey::fromUtf8(lines) : std::u16string();
    size_t start = 0;
    while (start <= all.size()) {
        size_t end = all.find(u'\n', start);
        if (end == std::u16string::npos) end = all.size();
        std::u16string line = all.substr(start, end - start);
        if (!line.empty() && line.back() == u'\r') line.pop_back();
        start = end + 1;
        if (line.empty() || line[0] == u'#') continue;
        size_t sep = line.find(u'=');
        if (sep == std::u16string::npos) sep = line.find(u':');
        if (sep == std::u16string::npos || sep == 0) continue;
        auto trim = [](std::u16string s) {
            while (!s.empty() && (s.front() == u' ' || s.front() == u'\t')) s.erase(0, 1);
            while (!s.empty() && (s.back() == u' ' || s.back() == u'\t')) s.pop_back();
            return s;
        };
        dokey::Macro m{trim(line.substr(0, sep)), trim(line.substr(sep + 1))};
        if (!m.key.empty() && !m.text.empty()) macros.push_back(m);
    }
    e->engine.setMacros(macros);
}

void dokey_backspace(dokey_engine* e) {
    if (!e) return;
    if (e->korean) {
        e->hangul.reset();  // a plain Backspace removed a whole syllable: start over
    } else {
        e->engine.backspace();
    }
}

void dokey_reset(dokey_engine* e) {
    if (!e) return;
    e->engine.reset();
    e->hangul.reset();
}

void dokey_destroy(dokey_engine* e) {
    delete e;
}

} // extern "C"
