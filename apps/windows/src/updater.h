// Dokey for Windows - finds a newer release on GitHub and installs it in place.
// Copyright (c) 2026 Do Huy Toan. All rights reserved.
#pragma once

#include <windows.h>

#include <string>

namespace dokey_win {

// A release as the GitHub API describes it.
struct Release {
    std::wstring version;     // "0.5.2"
    std::wstring notes;       // release notes as plain text
    std::wstring page;        // the release page
    std::wstring installer;   // https URL of Dokey-<version>-Windows-Setup.exe
    unsigned long long size = 0;
    std::string sha256;       // lower-case hex digest from GitHub, empty when it gave none
};

// "v0.5.2" > "0.5.1"? A pre-release suffix ("0.5.0-beta") is ignored.
bool IsNewerVersion(const std::wstring& tag, const std::wstring& current);

// Reads a GitHub "release" JSON object. False when it is not one.
bool ParseRelease(const std::string& json, Release& out);

// The latest release. Blocks: call it off the UI thread.
bool FetchLatestRelease(Release& out);

// Called while downloading; return false to cancel.
using DownloadProgress = bool (*)(unsigned long long received, unsigned long long total, void* context);

// Downloads the installer to `path` and checks its size, SHA-256 and version.
bool DownloadInstaller(const Release& release, const std::wstring& path, DownloadProgress progress, void* context,
                       std::wstring& error);

// Lower-case hex SHA-256 of a file, empty when it cannot be read.
std::string Sha256File(const std::wstring& path);

// Starts the installer silently. It closes this Dokey, installs over it in the
// same place (per user or for all users) and starts the new Dokey.
bool RunInstaller(const std::wstring& path, std::wstring& error);

// A writable folder for the download: %TEMP%\Dokey-update.
std::wstring UpdateFolder();

} // namespace dokey_win
