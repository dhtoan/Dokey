// Dokey for Windows - tests for input building and the engine contract.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include <cstdio>
#include <string>

#include "../src/inject.h"
#include "dokey/dokey.h"

using namespace dokey_win;

namespace {

int g_failures = 0;

void Check(bool ok, const char* what) {
    if (!ok) {
        std::printf("FAIL: %s\n", what);
        g_failures++;
    }
}

bool IsUp(const INPUT& in) { return (in.ki.dwFlags & KEYEVENTF_KEYUP) != 0; }

void TestBuildInputs() {
    Job job;
    job.backspaces = 2;
    job.text = u"ệt";  // ệt
    size_t split = 0;
    std::vector<INPUT> in = BuildInputs(job, &split);
    Check(in.size() == 8, "2 backspaces + 2 chars = 8 events");
    Check(split == 4, "split after the backspaces");
    for (size_t i = 0; i < 4; i++) {
        Check(in[i].ki.wVk == VK_BACK, "backspace vk");
        Check(IsUp(in[i]) == (i % 2 == 1), "backspace down/up order");
    }
    Check(in[4].ki.wVk == 0 && in[4].ki.wScan == 0x1EC7 && (in[4].ki.dwFlags & KEYEVENTF_UNICODE), "unicode ệ");
    Check(in[6].ki.wScan == u't', "unicode t");
    for (size_t i = 0; i + 1 < in.size(); i++) Check(in[i].ki.dwExtraInfo == kTagMid, "middle events tagged");
    Check(in.back().ki.dwExtraInfo == kTagEnd && IsUp(in.back()), "last event is the end marker (key up)");
    for (const INPUT& e : in) Check(IsOwnEvent(e.ki.dwExtraInfo), "every event is recognisable");
    Check(!IsOwnEvent(0) && !IsOwnEvent(1), "foreign events are not ours");

    Job enter;
    enter.text = u"à";
    enter.replayVk = VK_RETURN;
    enter.replayScan = 0x1C;
    in = BuildInputs(enter, &split);
    Check(split == 0 && in.size() == 4, "text then replayed key");
    Check(in[2].ki.wVk == VK_RETURN && !IsUp(in[2]) && IsUp(in[3]), "replayed Enter down/up");
    Check(in[3].ki.dwExtraInfo == kTagEnd, "replayed key carries the end marker");

    Check(BuildInputs(Job(), &split).empty(), "empty job, no events");
}

// Applies the engine's edits to a text buffer, as keyboard.cpp does:
// '\b' is Backspace (dokey_backspace_edit), '\x1b' is Esc with undo on.
std::u16string Type(const char* keys, int method, const char* macros = nullptr, int language = DOKEY_LANG_VIETNAMESE) {
    dokey_options o = {};
    o.method = method;
    o.encoding = DOKEY_UNICODE;
    o.modern_tone_style = 1;
    o.check_spelling = 1;
    dokey_engine* e = dokey_create(&o);
    dokey_set_macros(e, macros);
    dokey_set_language(e, language);
    std::u16string buffer;
    for (const char* p = keys; *p; p++) {
        dokey_edit edit;
        int handled;
        if (*p == '\b') {
            handled = dokey_backspace_edit(e, &edit);
            if (!handled && !buffer.empty()) buffer.pop_back();
        } else if (*p == '\x1b') {
            handled = dokey_undo(e, &edit);
        } else {
            handled = dokey_key(e, static_cast<unsigned char>(*p), &edit);
        }
        if (*p == '\b' || *p == '\x1b') {
            if (!handled) continue;
        }
        if (handled) {
            Job job;
            job.backspaces = edit.backspaces;
            job.text.assign(reinterpret_cast<const char16_t*>(edit.text), static_cast<size_t>(edit.length));
            for (int i = 0; i < job.backspaces && !buffer.empty(); i++) buffer.pop_back();
            buffer += job.text;
        } else {
            buffer.push_back(static_cast<char16_t>(*p));
        }
    }
    dokey_destroy(e);
    return buffer;
}

void TestEngineContract() {
    Check(Type("Vieetj Nam", DOKEY_TELEX) == u"Việt Nam", "Telex: Việt Nam");
    Check(Type("dduowngf ", DOKEY_TELEX) == u"đường ", "Telex: đường");
    Check(Type("Vie65t", DOKEY_VNI) == u"Việt", "VNI: Việt");
    Check(Type("windows ", DOKEY_TELEX) == u"windows ", "English word kept");
    Check(Type("tieesng\b\bs", DOKEY_TELEX).size() > 0, "backspace inside a word");
    Check(Type("Haxy ", DOKEY_TELEX) == u"Hãy ", "Telex: Hãy");
    Check(Type("xin \bf", DOKEY_TELEX) == u"xìn", "Backspace after the space reopens the word");
    Check(Type("tieesng\x1b", DOKEY_TELEX) == u"tieesng", "Esc undoes the marks");
    Check(Type("btw ", DOKEY_TELEX, "btw = by the way") == u"by the way ", "macro expands on space");
    Check(Type("Btw ", DOKEY_TELEX, "btw = by the way") == u"By the way ", "macro keeps the capital");
    Check(Type("dkssudgktpdy ", DOKEY_TELEX, nullptr, DOKEY_LANG_KOREAN) == u"안녕하세요 ", "Korean: 안녕하세요");
    Check(Type("gksrnr\r", DOKEY_TELEX, nullptr, DOKEY_LANG_KOREAN) == u"한국\r", "Korean: Enter goes through");
    Check(Type("gks\b", DOKEY_TELEX, nullptr, DOKEY_LANG_KOREAN) == u"하", "Korean: Backspace drops one jamo");
}

} // namespace

int main() {
    TestBuildInputs();
    TestEngineContract();
    if (g_failures == 0) std::printf("All Windows app tests passed.\n");
    return g_failures == 0 ? 0 : 1;
}
