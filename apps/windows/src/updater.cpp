// Dokey for Windows - finds a newer release on GitHub and installs it in place.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#include "updater.h"

#include <bcrypt.h>
#include <shellapi.h>
#include <shlobj.h>
#include <winhttp.h>

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <utility>
#include <vector>

#include "version.h"

namespace dokey_win {

namespace {

const wchar_t kLatestUrl[] = L"https://api.github.com/repos/dhtoan/Dokey/releases/latest";

// ---- text ------------------------------------------------------------------------

std::wstring Widen(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(n > 0 ? n : 0, L'\0');
    if (n > 0) MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), &out[0], n);
    return out;
}

bool StartsWith(const std::wstring& s, const wchar_t* prefix) { return s.compare(0, wcslen(prefix), prefix) == 0; }

bool EndsWith(const std::wstring& s, const wchar_t* suffix) {
    size_t n = wcslen(suffix);
    return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
}

// ---- a small JSON reader (objects, arrays, strings, numbers, literals) ---------------

struct Json {
    enum Type { Null, Bool, Number, String, Array, Object } type = Null;
    std::string text;  // String
    double number = 0;
    std::vector<Json> items;                           // Array
    std::vector<std::pair<std::string, Json>> members;  // Object

    const Json* Get(const char* key) const {
        for (const auto& m : members) {
            if (m.first == key) return &m.second;
        }
        return nullptr;
    }
    std::string Str(const char* key) const {
        const Json* v = Get(key);
        return v && v->type == String ? v->text : std::string();
    }
};

class JsonReader {
public:
    JsonReader(const std::string& s) : p_(s.data()), end_(s.data() + s.size()) {}

    bool Read(Json& out) {
        if (!Value(out, 0)) return false;
        Space();
        return p_ == end_;
    }

private:
    void Space() {
        while (p_ < end_ && (*p_ == ' ' || *p_ == '\t' || *p_ == '\n' || *p_ == '\r')) p_++;
    }

    bool Literal(const char* word) {
        size_t n = strlen(word);
        if (static_cast<size_t>(end_ - p_) < n || memcmp(p_, word, n) != 0) return false;
        p_ += n;
        return true;
    }

    static void Utf8(std::string& out, unsigned cp) {
        if (cp < 0x80) {
            out += static_cast<char>(cp);
        } else if (cp < 0x800) {
            out += static_cast<char>(0xC0 | (cp >> 6));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out += static_cast<char>(0xE0 | (cp >> 12));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (cp >> 18));
            out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        }
    }

    bool Hex4(unsigned& value) {
        if (end_ - p_ < 4) return false;
        value = 0;
        for (int i = 0; i < 4; i++) {
            char c = *p_++;
            value <<= 4;
            if (c >= '0' && c <= '9') value |= c - '0';
            else if (c >= 'a' && c <= 'f') value |= c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') value |= c - 'A' + 10;
            else return false;
        }
        return true;
    }

    bool StringValue(std::string& out) {
        if (p_ >= end_ || *p_ != '"') return false;
        p_++;
        while (p_ < end_ && *p_ != '"') {
            char c = *p_++;
            if (c != '\\') {
                out += c;
                continue;
            }
            if (p_ >= end_) return false;
            char e = *p_++;
            switch (e) {
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case 'u': {
                    unsigned cp = 0;
                    if (!Hex4(cp)) return false;
                    if (cp >= 0xD800 && cp < 0xDC00 && end_ - p_ >= 6 && p_[0] == '\\' && p_[1] == 'u') {
                        p_ += 2;
                        unsigned low = 0;
                        if (!Hex4(low)) return false;
                        if (low >= 0xDC00 && low < 0xE000) cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                    }
                    Utf8(out, cp);
                    break;
                }
                default: return false;
            }
        }
        if (p_ >= end_) return false;
        p_++;  // closing quote
        return true;
    }

    bool Value(Json& out, int depth) {
        if (depth > 32) return false;
        Space();
        if (p_ >= end_) return false;
        switch (*p_) {
            case '{': {
                p_++;
                out.type = Json::Object;
                Space();
                if (p_ < end_ && *p_ == '}') { p_++; return true; }
                for (;;) {
                    Space();
                    std::string key;
                    if (!StringValue(key)) return false;
                    Space();
                    if (p_ >= end_ || *p_++ != ':') return false;
                    Json value;
                    if (!Value(value, depth + 1)) return false;
                    out.members.emplace_back(std::move(key), std::move(value));
                    Space();
                    if (p_ < end_ && *p_ == ',') { p_++; continue; }
                    if (p_ < end_ && *p_ == '}') { p_++; return true; }
                    return false;
                }
            }
            case '[': {
                p_++;
                out.type = Json::Array;
                Space();
                if (p_ < end_ && *p_ == ']') { p_++; return true; }
                for (;;) {
                    Json value;
                    if (!Value(value, depth + 1)) return false;
                    out.items.push_back(std::move(value));
                    Space();
                    if (p_ < end_ && *p_ == ',') { p_++; continue; }
                    if (p_ < end_ && *p_ == ']') { p_++; return true; }
                    return false;
                }
            }
            case '"':
                out.type = Json::String;
                return StringValue(out.text);
            case 't': out.type = Json::Bool; return Literal("true");
            case 'f': out.type = Json::Bool; return Literal("false");
            case 'n': out.type = Json::Null; return Literal("null");
            default: {
                const char* start = p_;
                while (p_ < end_ && ((*p_ && strchr("+-.eE", *p_)) || (*p_ >= '0' && *p_ <= '9'))) p_++;
                if (p_ == start) return false;
                out.type = Json::Number;
                out.number = strtod(std::string(start, p_).c_str(), nullptr);
                return true;
            }
        }
    }

    const char* p_;
    const char* end_;
};

// Release notes are Markdown; the dialog shows them as plain text.
std::wstring PlainNotes(const std::wstring& markdown) {
    std::wstring out;
    bool lastEmpty = true, inCode = false;
    size_t start = 0;
    while (start <= markdown.size()) {
        size_t end = markdown.find(L'\n', start);
        if (end == std::wstring::npos) end = markdown.size();
        std::wstring line = markdown.substr(start, end - start);
        start = end + 1;
        while (!line.empty() && (line.back() == L'\r' || line.back() == L' ')) line.pop_back();
        size_t lead = line.find_first_not_of(L' ');
        line = lead == std::wstring::npos ? std::wstring() : line.substr(lead);
        if (StartsWith(line, L"```")) { inCode = !inCode; continue; }
        if (StartsWith(line, L"<") || StartsWith(line, L"![")) continue;
        if (!inCode) {
            while (StartsWith(line, L"#") || StartsWith(line, L">")) line.erase(0, 1);
            if (StartsWith(line, L"- ") || StartsWith(line, L"* ")) line = L"• " + line.substr(2);
            for (const wchar_t* mark : {L"**", L"`"}) {
                for (size_t at; (at = line.find(mark)) != std::wstring::npos;) line.erase(at, wcslen(mark));
            }
            // [text](link) -> text
            for (size_t open; (open = line.find(L'[')) != std::wstring::npos;) {
                size_t close = line.find(L"](", open);
                size_t paren = close == std::wstring::npos ? close : line.find(L')', close);
                if (paren == std::wstring::npos) break;
                line = line.substr(0, open) + line.substr(open + 1, close - open - 1) + line.substr(paren + 1);
            }
            lead = line.find_first_not_of(L' ');
            line = lead == std::wstring::npos ? std::wstring() : line.substr(lead);
        }
        if (line.empty() && lastEmpty) continue;
        out += line + L"\n";
        lastEmpty = line.empty();
    }
    while (!out.empty() && out.back() == L'\n') out.pop_back();
    if (out.size() > 1500) out = out.substr(0, 1500) + L"…";
    return out;
}

// ---- HTTP ------------------------------------------------------------------------------

struct Handle {
    HINTERNET h = nullptr;
    Handle(HINTERNET handle) : h(handle) {}
    ~Handle() { if (h) WinHttpCloseHandle(h); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    operator HINTERNET() const { return h; }
};

// GET over HTTPS. The body goes to `body`, or to `file` when it is set.
bool HttpGet(const std::wstring& url, std::string* body, HANDLE file, unsigned long long expected,
             DownloadProgress progress, void* context, DWORD& status) {
    status = 0;
    URL_COMPONENTS parts = {};
    parts.dwStructSize = sizeof(parts);
    wchar_t host[256] = {}, path[2048] = {};
    parts.lpszHostName = host;
    parts.dwHostNameLength = ARRAYSIZE(host);
    parts.lpszUrlPath = path;
    parts.dwUrlPathLength = ARRAYSIZE(path);
    if (!WinHttpCrackUrl(url.c_str(), 0, 0, &parts) || parts.nScheme != INTERNET_SCHEME_HTTPS) return false;
    std::wstring target = path;
    if (parts.lpszExtraInfo && parts.dwExtraInfoLength) target.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);

    std::wstring agent = std::wstring(L"Dokey/") + DOKEY_APP_VERSION_W + L" (Windows)";
    Handle session(WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
                               WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session) return false;
    WinHttpSetTimeouts(session, 15000, 15000, 20000, 60000);
    Handle connect(WinHttpConnect(session, host, parts.nPort, 0));
    if (!connect) return false;
    Handle request(WinHttpOpenRequest(connect, L"GET", target.c_str(), nullptr, WINHTTP_NO_REFERER,
                                      WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE));
    if (!request) return false;
    const wchar_t* headers = body ? L"Accept: application/vnd.github+json\r\n" : L"Accept: application/octet-stream\r\n";
    if (!WinHttpSendRequest(request, headers, static_cast<DWORD>(-1L), WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(request, nullptr)) {
        return false;
    }
    DWORD size = sizeof(status);
    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                        &status, &size, WINHTTP_NO_HEADER_INDEX);
    if (status != 200) return false;

    unsigned long long received = 0;
    std::vector<char> buffer(64 * 1024);
    for (;;) {
        DWORD read = 0;
        if (!WinHttpReadData(request, buffer.data(), static_cast<DWORD>(buffer.size()), &read)) return false;
        if (read == 0) break;
        received += read;
        if (body) {
            if (body->size() + read > 4u * 1024 * 1024) return false;  // a release is a few KB
            body->append(buffer.data(), read);
        } else {
            DWORD written = 0;
            if (!WriteFile(file, buffer.data(), read, &written, nullptr) || written != read) return false;
            if (expected && received > expected) return false;
        }
        if (progress && !progress(received, expected, context)) return false;
    }
    return true;
}

// Major, minor, patch of a version string ("v0.5.2-beta" -> 0, 5, 2).
std::vector<int> VersionParts(const std::wstring& s) {
    std::vector<int> parts;
    size_t i = (!s.empty() && (s[0] == L'v' || s[0] == L'V')) ? 1 : 0;
    while (i < s.size() && parts.size() < 4) {
        if (s[i] < L'0' || s[i] > L'9') break;
        int n = 0;
        while (i < s.size() && s[i] >= L'0' && s[i] <= L'9') n = n * 10 + (s[i++] - L'0');
        parts.push_back(n);
        if (i < s.size() && s[i] == L'.') i++;
        else break;
    }
    while (parts.size() < 3) parts.push_back(0);
    return parts;
}

// The installer's file version must be the release's.
bool InstallerVersionMatches(const std::wstring& path, const std::wstring& version) {
    DWORD ignored = 0;
    DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (!size) return false;
    std::vector<BYTE> data(size);
    if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) return false;
    VS_FIXEDFILEINFO* info = nullptr;
    UINT length = 0;
    if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &length) || !info) return false;
    std::vector<int> want = VersionParts(version);
    return static_cast<int>(HIWORD(info->dwFileVersionMS)) == want[0] &&
           static_cast<int>(LOWORD(info->dwFileVersionMS)) == want[1] &&
           static_cast<int>(HIWORD(info->dwFileVersionLS)) == want[2];
}

bool PathStartsWith(const std::wstring& path, REFKNOWNFOLDERID folder) {
    PWSTR known = nullptr;
    bool inside = false;
    if (SUCCEEDED(SHGetKnownFolderPath(folder, 0, nullptr, &known)) && known) {
        std::wstring prefix = std::wstring(known) + L"\\";
        inside = path.size() > prefix.size() &&
                 CompareStringOrdinal(path.c_str(), static_cast<int>(prefix.size()), prefix.c_str(),
                                      static_cast<int>(prefix.size()), TRUE) == CSTR_EQUAL;
    }
    CoTaskMemFree(known);
    return inside;
}

} // namespace

bool IsNewerVersion(const std::wstring& tag, const std::wstring& current) {
    std::vector<int> a = VersionParts(tag), b = VersionParts(current);
    for (size_t i = 0; i < 3; i++) {
        if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
}

bool ParseRelease(const std::string& json, Release& out) {
    Json root;
    if (!JsonReader(json).Read(root) || root.type != Json::Object) return false;
    const std::string tag = root.Str("tag_name");
    if (tag.empty()) return false;
    out = Release();
    out.version = Widen(tag[0] == 'v' || tag[0] == 'V' ? tag.substr(1) : tag);
    out.page = Widen(root.Str("html_url"));
    out.notes = PlainNotes(Widen(root.Str("body")));
    const Json* assets = root.Get("assets");
    if (assets && assets->type == Json::Array) {
        for (const Json& asset : assets->items) {
            std::wstring name = Widen(asset.Str("name"));
            std::wstring link = Widen(asset.Str("browser_download_url"));
            if (!StartsWith(name, L"Dokey-") || !EndsWith(name, L"-Windows-Setup.exe") ||
                !StartsWith(link, L"https://")) {
                continue;
            }
            out.installer = link;
            const Json* size = asset.Get("size");
            out.size = size && size->type == Json::Number && size->number > 0 ? static_cast<unsigned long long>(size->number) : 0;
            std::string digest = asset.Str("digest");
            if (digest.compare(0, 7, "sha256:") == 0 && digest.size() == 7 + 64) {
                out.sha256 = digest.substr(7);
                for (char& c : out.sha256) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
            }
        }
    }
    return !out.version.empty();
}

bool FetchLatestRelease(Release& out) {
    std::string body;
    DWORD status = 0;
    return HttpGet(kLatestUrl, &body, nullptr, 0, nullptr, nullptr, status) && ParseRelease(body, out);
}

std::string Sha256File(const std::wstring& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (file == INVALID_HANDLE_VALUE) return std::string();
    std::string hex;
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) == 0 &&
        BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) == 0) {
        std::vector<BYTE> buffer(256 * 1024);
        DWORD read = 0;
        bool ok = true;
        while (ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) && read > 0) {
            if (BCryptHashData(hash, buffer.data(), read, 0) != 0) { ok = false; break; }
        }
        BYTE digest[32];
        if (ok && BCryptFinishHash(hash, digest, sizeof(digest), 0) == 0) {
            char two[3];
            for (BYTE b : digest) {
                snprintf(two, sizeof(two), "%02x", b);
                hex += two;
            }
        }
    }
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file);
    return hex;
}

std::wstring UpdateFolder() {
    wchar_t temp[MAX_PATH + 1] = {};
    DWORD n = GetTempPathW(ARRAYSIZE(temp), temp);
    std::wstring folder = (n > 0 && n < ARRAYSIZE(temp)) ? std::wstring(temp) : std::wstring(L".\\");
    folder += L"Dokey-update";
    CreateDirectoryW(folder.c_str(), nullptr);
    return folder;
}

bool DownloadInstaller(const Release& release, const std::wstring& path, DownloadProgress progress, void* context,
                       std::wstring& error) {
    if (release.installer.empty()) {
        error = L"no installer";
        return false;
    }
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = L"cannot write " + path;
        return false;
    }
    DWORD status = 0;
    bool ok = HttpGet(release.installer, nullptr, file, release.size, progress, context, status);
    LARGE_INTEGER size = {};
    GetFileSizeEx(file, &size);
    CloseHandle(file);
    if (!ok) {
        error = status ? L"HTTP " + std::to_wstring(status) : L"download failed";
    } else if (release.size && static_cast<unsigned long long>(size.QuadPart) != release.size) {
        error = L"size mismatch";
        ok = false;
    } else if (!release.sha256.empty() && Sha256File(path) != release.sha256) {
        error = L"SHA-256 mismatch";
        ok = false;
    } else if (!InstallerVersionMatches(path, release.version)) {
        error = L"installer version mismatch";
        ok = false;
    }
    if (!ok) DeleteFileW(path.c_str());
    return ok;
}

bool RunInstaller(const std::wstring& path, std::wstring& error) {
    wchar_t self[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, self, MAX_PATH);
    const bool allUsers = PathStartsWith(self, FOLDERID_ProgramFiles) || PathStartsWith(self, FOLDERID_ProgramFilesX86);
    // /SILENT shows only a progress window. /relaunch=1 starts the new Dokey afterwards.
    std::wstring arguments = L"/SILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /relaunch=1 ";
    arguments += allUsers ? L"/ALLUSERS" : L"/CURRENTUSER";
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOASYNC;
    info.lpVerb = L"open";
    info.lpFile = path.c_str();
    info.lpParameters = arguments.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
        error = L"cannot start the installer (" + std::to_wstring(GetLastError()) + L")";
        return false;
    }
    return true;
}

} // namespace dokey_win
