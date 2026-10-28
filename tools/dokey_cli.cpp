// dokey - command-line front end for Dokey Core.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
//
// Reads text typed in Telex (or VNI) and prints it as Vietnamese:
//   echo "tieengs Vieetj" | dokey          -> tiếng Việt
//   dokey --vni "Vie65t Nam"               -> Việt Nam
#include "dokey/engine.hpp"

#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>

namespace {

void usage() {
    std::puts(
        "dokey - Vietnamese input engine (Dokey Core " DOKEY_VERSION ")\n"
        "\n"
        "Usage: dokey [options] [text...]\n"
        "  Converts Telex/VNI key sequences to Vietnamese. Without text, reads stdin.\n"
        "\n"
        "Options:\n"
        "  --vni          use VNI instead of Telex\n"
        "  --old-tone     old tone placement (hòa, khỏe, thúy)\n"
        "  --no-spell     do not keep non-Vietnamese words as typed\n"
        "  --combining    output combining tone marks\n"
        "  -v, --version  print version\n"
        "  -h, --help     show this help");
}

std::string convert(const std::string& line, const dokey::Options& options) {
    // Ending with a space finalizes the last word; it is removed afterwards.
    std::string out = dokey::toUtf8(dokey::Engine::simulate(line + " ", options));
    if (!out.empty() && out.back() == ' ') out.pop_back();
    return out;
}

} // namespace

int main(int argc, char** argv) {
    dokey::Options options;
    std::string text;
    bool haveText = false;
    for (int i = 1; i < argc; i++) {
        const char* a = argv[i];
        if (!std::strcmp(a, "--vni")) options.method = dokey::InputMethod::VNI;
        else if (!std::strcmp(a, "--old-tone")) options.modernToneStyle = false;
        else if (!std::strcmp(a, "--no-spell")) options.checkSpelling = false;
        else if (!std::strcmp(a, "--combining")) options.encoding = dokey::Encoding::UnicodeCombining;
        else if (!std::strcmp(a, "-v") || !std::strcmp(a, "--version")) {
            std::puts(DOKEY_VERSION);
            return 0;
        } else if (!std::strcmp(a, "-h") || !std::strcmp(a, "--help")) {
            usage();
            return 0;
        } else if (a[0] == '-' && a[1] == '-') {
            std::fprintf(stderr, "dokey: unknown option %s\n", a);
            return 2;
        } else {
            if (haveText) text += ' ';
            text += a;
            haveText = true;
        }
    }
    if (haveText) {
        std::puts(convert(text, options).c_str());
        return 0;
    }
    std::string line;
    while (std::getline(std::cin, line)) std::puts(convert(line, options).c_str());
    return 0;
}
