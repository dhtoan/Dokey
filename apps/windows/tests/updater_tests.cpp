// Dokey for Windows - tests for the updater's release parsing (no network).
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include <cstdio>
#include <string>

#include "updater.h"

using namespace dokey_win;

namespace {

int g_failed = 0, g_total = 0;

void Check(bool ok, const char* what) {
    g_total++;
    if (!ok) {
        g_failed++;
        std::printf("FAIL %s\n", what);
    }
}

// The shape of https://api.github.com/repos/dhtoan/Dokey/releases/latest.
const char kRelease[] = R"({
  "tag_name": "v0.5.2",
  "html_url": "https://github.com/dhtoan/Dokey/releases/tag/v0.5.2",
  "prerelease": false,
  "body": "## Dokey 0.5.2\r\n\r\n### Tự cập nhật\r\n- **Bấm Cập nhật** là xong: `tesst` → test\r\n- [README](https://github.com/dhtoan/Dokey) 🚀\r\n```bash\r\ngh release download\r\n```\r\n",
  "assets": [
    {"name": "Dokey-0.5.2.dmg", "size": 5285508, "digest": "sha256:c0eb73c74ed60000000000000000000000000000000000000000000000000000",
     "browser_download_url": "https://github.com/dhtoan/Dokey/releases/download/v0.5.2/Dokey-0.5.2.dmg"},
    {"name": "Dokey-0.5.2-Windows-Setup.exe", "size": 2485542, "uploader": {"login": "github-actions[bot]", "id": 41898282},
     "digest": "sha256:8E2D0487726E2000000000000000000000000000000000000000000000000ABC",
     "browser_download_url": "https://github.com/dhtoan/Dokey/releases/download/v0.5.2/Dokey-0.5.2-Windows-Setup.exe"},
    {"name": "SHA256SUMS.txt", "size": 667, "digest": null, "browser_download_url": "https://example.com/x"}
  ]
})";

} // namespace

int main() {
    Check(IsNewerVersion(L"v0.5.2", L"0.5.1"), "0.5.2 > 0.5.1");
    Check(IsNewerVersion(L"0.10.0", L"0.9.9"), "0.10.0 > 0.9.9");
    Check(IsNewerVersion(L"1.0.0", L"0.99.99"), "1.0.0 > 0.99.99");
    Check(!IsNewerVersion(L"v0.5.1", L"0.5.1"), "0.5.1 = 0.5.1");
    Check(!IsNewerVersion(L"0.5.0", L"0.5.1"), "0.5.0 < 0.5.1");
    Check(!IsNewerVersion(L"0.5.0", L"0.5.0-beta"), "0.5.0 = 0.5.0-beta");
    Check(!IsNewerVersion(L"garbage", L"0.5.1"), "garbage is not newer");

    Release r;
    Check(ParseRelease(kRelease, r), "parse release");
    Check(r.version == L"0.5.2", "version");
    Check(r.page == L"https://github.com/dhtoan/Dokey/releases/tag/v0.5.2", "page");
    Check(r.installer == L"https://github.com/dhtoan/Dokey/releases/download/v0.5.2/Dokey-0.5.2-Windows-Setup.exe",
          "installer url");
    Check(r.size == 2485542, "installer size");
    Check(r.sha256 == "8e2d0487726e2000000000000000000000000000000000000000000000000abc", "sha256 lower-cased");
    Check(r.notes.find(L"Tự cập nhật") != std::wstring::npos, "notes keep Vietnamese");
    Check(r.notes.find(L"• Bấm Cập nhật là xong: tesst → test") != std::wstring::npos, "notes: bullet, no ** or `");
    Check(r.notes.find(L"README \U0001F680") != std::wstring::npos, "notes: link text and surrogate pair");
    Check(r.notes.find(L"##") == std::wstring::npos && r.notes.find(L"](") == std::wstring::npos, "notes: no markdown");

    Release none;
    Check(!ParseRelease("{\"message\": \"Not Found\"}", none), "an error reply is not a release");
    Check(!ParseRelease("{\"tag_name\": \"v1\"", none), "truncated JSON");
    Check(!ParseRelease("", none), "empty reply");
    Release noAsset;
    Check(ParseRelease(R"({"tag_name":"v0.6.0","assets":[{"name":"Dokey-0.6.0.dmg","browser_download_url":"https://x/y.dmg"}]})",
                       noAsset) && noAsset.installer.empty(),
          "a release without a Windows installer");
    Release insecure;
    Check(ParseRelease(R"({"tag_name":"v0.6.0","assets":[{"name":"Dokey-0.6.0-Windows-Setup.exe","browser_download_url":"http://x/y.exe"}]})",
                       insecure) && insecure.installer.empty(),
          "only https downloads");

    std::printf("%d/%d passed\n", g_total - g_failed, g_total);
    return g_failed ? 1 : 0;
}
