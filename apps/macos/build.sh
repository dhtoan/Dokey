#!/bin/bash
# Builds Dokey.app (Universal: x86_64 for macOS 10.13+, arm64 for macOS 11+)
# with only the Command Line Tools: swiftc, clang, lipo, codesign. No Xcode needed.
#
#   apps/macos/build.sh            # -> apps/macos/build/Dokey.app
#   apps/macos/build.sh --dmg      # also -> apps/macos/build/Dokey-<version>.dmg
#   VERSION=0.2.0 ARCHS="x86_64" apps/macos/build.sh
#
# Copyright (c) 2026 Do Huy Toan. All rights reserved.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/build"
APP="$OUT/Dokey.app"
VERSION="${VERSION:-0.5.1}"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-x86_64 arm64}"
MAKE_DMG=0
[ "${1:-}" = "--dmg" ] && MAKE_DMG=1

SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
TOOLCHAIN_LIB="$(cd "$(dirname "$SWIFTC")/../lib" && pwd)"

min_os() { [ "$1" = arm64 ] && echo 11.0 || echo 10.13; }

rm -rf "$OUT"
mkdir -p "$OUT/obj"

# Some Command Line Tools releases ship both module.modulemap and
# bridging.modulemap defining SwiftBridging, which breaks `import Cocoa`.
# Hide the duplicate through a VFS overlay instead of editing system files.
SWIFT_FLAGS=(-swift-version 5 -sdk "$SDK")
SWIFT_INCLUDE="$(cd "$TOOLCHAIN_LIB/../include/swift" 2>/dev/null && pwd || true)"
if [ -n "$SWIFT_INCLUDE" ] && [ -f "$SWIFT_INCLUDE/module.modulemap" ] && [ -f "$SWIFT_INCLUDE/bridging.modulemap" ]; then
    : > "$OUT/obj/empty.modulemap"
    cat > "$OUT/obj/clt-overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$SWIFT_INCLUDE",
  "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$OUT/obj/empty.modulemap" } ] } ] }
EOF
    SWIFT_FLAGS+=(-vfsoverlay "$OUT/obj/clt-overlay.yaml" -Xcc -ivfsoverlay -Xcc "$OUT/obj/clt-overlay.yaml")
fi

binaries=()
for arch in $ARCHS; do
    min="$(min_os "$arch")"
    echo "==> Dokey Core ($arch, macOS $min+)"
    objs=()
    for src in "$ROOT"/src/*.cpp; do
        obj="$OUT/obj/$arch-$(basename "${src%.cpp}").o"
        clang++ -std=c++17 -O2 -Wall -Wextra -arch "$arch" -isysroot "$SDK" \
            -mmacosx-version-min="$min" -I"$ROOT/include" -c "$src" -o "$obj"
        objs+=("$obj")
    done
    libtool -static -o "$OUT/obj/libdokey_core-$arch.a" "${objs[@]}" 2>/dev/null

    echo "==> Dokey app ($arch)"
    "$SWIFTC" "${SWIFT_FLAGS[@]}" -O -whole-module-optimization \
        -target "$arch-apple-macos$min" \
        -module-name Dokey \
        -import-objc-header "$HERE/Sources/Dokey-Bridging.h" -Xcc -I"$ROOT/include" \
        "$HERE"/Sources/*.swift \
        -L"$OUT/obj" -ldokey_core-"$arch" -lc++ \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -o "$OUT/obj/Dokey-$arch"
    binaries+=("$OUT/obj/Dokey-$arch")
done

echo "==> Bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/Dokey"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" "$HERE/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

echo "==> Icon"
"$SWIFTC" "${SWIFT_FLAGS[@]}" -O "$HERE/tools/make_icon.swift" -o "$OUT/obj/make_icon"
"$OUT/obj/make_icon" "$OUT/obj/AppIcon.iconset"
iconutil -c icns "$OUT/obj/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# macOS before 10.14.4 has no Swift runtime: ship the back-deployment copy.
# Newer systems ignore it and load the runtime from /usr/lib/swift.
BACKDEPLOY="$TOOLCHAIN_LIB/swift-5.0/macosx"
if [[ " $ARCHS " == *" x86_64 "* ]]; then
    if [ -d "$BACKDEPLOY" ]; then
        echo "==> Swift runtime for macOS 10.13 - 10.14.3"
        xcrun swift-stdlib-tool --copy --platform macosx \
            --scan-executable "$APP/Contents/MacOS/Dokey" \
            --destination "$APP/Contents/Frameworks" \
            --source-libraries "$BACKDEPLOY"
    else
        echo "warning: $BACKDEPLOY not found; the app will need macOS 10.14.4 or later" >&2
    fi
fi

echo "==> Sign (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Self-test"
"$APP/Contents/MacOS/Dokey" --self-test

lipo -info "$APP/Contents/MacOS/Dokey"
echo "Built $APP ($VERSION, build $BUILD)"

if [ "$MAKE_DMG" = 1 ]; then
    echo "==> Disk image"
    STAGE="$OUT/dmg"
    DMG="$OUT/Dokey-$VERSION.dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Dokey $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Built $DMG"
fi
