// Dokey Core - C API.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "dokey/dokey.h"

#include "dokey/engine.hpp"

struct dokey_engine {
    dokey::Engine engine;
};

namespace {

dokey::Options convert(const dokey_options* o) {
    dokey::Options out;
    if (o == nullptr) return out;
    out.method = o->method == DOKEY_VNI ? dokey::InputMethod::VNI : dokey::InputMethod::Telex;
    out.encoding = o->encoding == DOKEY_UNICODE_COMBINING ? dokey::Encoding::UnicodeCombining : dokey::Encoding::Unicode;
    out.modernToneStyle = o->modern_tone_style != 0;
    out.checkSpelling = o->check_spelling != 0;
    return out;
}

} // namespace

extern "C" {

dokey_engine* dokey_create(const dokey_options* options) {
    return new dokey_engine{dokey::Engine(convert(options))};
}

void dokey_set_options(dokey_engine* e, const dokey_options* options) {
    if (e) e->engine.setOptions(convert(options));
}

int dokey_key(dokey_engine* e, uint32_t ch, dokey_edit* out) {
    if (!e || !out) return 0;
    dokey::Edit edit = e->engine.key(static_cast<char32_t>(ch));
    out->backspaces = 0;
    out->length = 0;
    if (!edit.handled || edit.insert.size() > DOKEY_MAX_EDIT) {
        if (edit.handled) e->engine.reset();  // cannot express it: give up on this word
        return 0;
    }
    out->backspaces = edit.backspaces;
    out->length = static_cast<int>(edit.insert.size());
    for (size_t i = 0; i < edit.insert.size(); i++) out->text[i] = edit.insert[i];
    return 1;
}

void dokey_backspace(dokey_engine* e) {
    if (e) e->engine.backspace();
}

void dokey_reset(dokey_engine* e) {
    if (e) e->engine.reset();
}

void dokey_destroy(dokey_engine* e) {
    delete e;
}

} // extern "C"
