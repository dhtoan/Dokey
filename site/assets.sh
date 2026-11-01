#!/bin/bash
# Copies the images the website uses into site/assets (not committed; the
# Pages workflow runs this too). Copyright (c) 2026 Do Huy Toan. All rights reserved.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/site/assets"
mkdir -p "$A"
cp "$ROOT/docs/images/dashboard.png" "$ROOT/docs/images/typing.png" "$ROOT/docs/images/social.png" "$A/"
cp "$ROOT/docs/images/sponsor/momo.png" "$A/momo.png"
cp "$ROOT/apps/windows/docs/panel.jpg" "$A/windows.jpg"
if [ -f "$ROOT/apps/macos/build/Dokey.app/Contents/Resources/AppIcon.icns" ] && command -v sips >/dev/null; then
    sips -s format png -Z 256 "$ROOT/apps/macos/build/Dokey.app/Contents/Resources/AppIcon.icns" --out "$A/icon.png" >/dev/null
elif [ -f "$ROOT/docs/images/icon.png" ]; then
    cp "$ROOT/docs/images/icon.png" "$A/icon.png"
fi
