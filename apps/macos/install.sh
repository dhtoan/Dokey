#!/bin/bash
# Installs Dokey for macOS into /Applications without Gatekeeper warnings.
#
# Dokey is signed ad-hoc, not notarized by Apple, so a .dmg downloaded with a
# browser is quarantined and macOS refuses to open it. This script installs the
# app and clears the quarantine flag, so Dokey opens normally.
#
#   bash install-macos.sh                     # latest release (needs `gh auth login`)
#   bash install-macos.sh v0.3.1              # a specific release
#   bash install-macos.sh ~/Downloads/Dokey-0.3.1.dmg   # a .dmg you already downloaded
#
# Copyright (c) 2026 Do Huy Toan. All rights reserved.
set -euo pipefail

REPO="dhtoan/Dokey"
APP="${DOKEY_APP:-/Applications/Dokey.app}"   # DOKEY_APP: install elsewhere (testing)
WORK="$(mktemp -d)"
MOUNT="$WORK/mnt"
cleanup() {
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

ARG="${1:-latest}"
if [ -f "$ARG" ]; then
    DMG="$ARG"
else
    if ! command -v gh >/dev/null 2>&1; then
        echo "Cần GitHub CLI (gh) để tải bản phát hành. Hoặc tải Dokey-*.dmg bằng trình duyệt rồi chạy:" >&2
        echo "  bash $0 ~/Downloads/Dokey-<phiên bản>.dmg" >&2
        exit 1
    fi
    say "Tải Dokey ($ARG) từ GitHub"
    if [ "$ARG" = latest ]; then
        gh release download -R "$REPO" --pattern 'Dokey-*.dmg' --dir "$WORK"
    else
        gh release download "$ARG" -R "$REPO" --pattern 'Dokey-*.dmg' --dir "$WORK"
    fi
    DMG="$(ls "$WORK"/Dokey-*.dmg | head -n 1)"
fi

say "Mở $(basename "$DMG")"
xattr -d com.apple.quarantine "$DMG" 2>/dev/null || true
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
[ -d "$MOUNT/Dokey.app" ] || { echo "Không thấy Dokey.app trong $DMG" >&2; exit 1; }

if [ -z "${DOKEY_APP:-}" ] && pgrep -x Dokey >/dev/null 2>&1; then
    say "Thoát Dokey đang chạy"
    osascript -e 'tell application id "com.dhtoan.dokey.mac" to quit' 2>/dev/null || true
    sleep 1
    pkill -x Dokey 2>/dev/null || true
fi

say "Cài vào $APP"
rm -rf "$APP"
ditto "$MOUNT/Dokey.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"

if [ -z "${DOKEY_APP:-}" ]; then
    say "Mở Dokey"
    open "$APP"
fi

cat <<'EOF'

Đã cài xong Dokey.
Nếu đây là bản mới, hãy cấp lại quyền Trợ năng:
  System Settings › Privacy & Security › Accessibility
  xoá Dokey (dấu −), thêm lại /Applications/Dokey.app (dấu +) rồi bật công tắc.
EOF
