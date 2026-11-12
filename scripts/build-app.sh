#!/usr/bin/env bash
# Assemble build/VRemind.app using only Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")/.."

CACHE="$PWD/.build/caches"
mkdir -p "$CACHE/modules"

export CLANG_MODULE_CACHE_PATH="$CACHE/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/modules"

SPM_FLAGS=(--disable-sandbox --cache-path "$CACHE/spm" -c release)

APP_DIR="$PWD/build/VRemind.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

ARM_BIN="$PWD/.build/arm64-apple-macosx/release/VRemind"
X86_BIN="$PWD/.build/x86_64-apple-macosx/release/VRemind"

if swift build "${SPM_FLAGS[@]}" --triple arm64-apple-macosx12.0 2>&1 | grep -v "is not accessible or not writable" \
   && swift build "${SPM_FLAGS[@]}" --triple x86_64-apple-macosx12.0 2>&1 | grep -v "is not accessible or not writable" \
   && [[ -f "$ARM_BIN" && -f "$X86_BIN" ]]; then
  lipo -create -output "$APP_DIR/Contents/MacOS/VRemind" "$ARM_BIN" "$X86_BIN"
else
  echo "warning: cross-architecture build unavailable; falling back to host-architecture binary" >&2
  swift build "${SPM_FLAGS[@]}" 2>&1 | grep -v "is not accessible or not writable"
  BIN_PATH="$(swift build "${SPM_FLAGS[@]}" --show-bin-path 2>/dev/null)"
  cp "$BIN_PATH/VRemind" "$APP_DIR/Contents/MacOS/VRemind"
fi

chmod +x "$APP_DIR/Contents/MacOS/VRemind"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

if [[ -f "Resources/Icons/app-icon.png" ]]; then
  if [[ ! -f "Resources/AppIcon.icns" || "Resources/Icons/app-icon.png" -nt "Resources/AppIcon.icns" ]]; then
    echo "Generating Resources/AppIcon.icns..."
    ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 Resources/Icons/app-icon.png --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1
    iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns
    rm -rf "$(dirname "$ICONSET_DIR")"
  fi
fi

if [[ -f "Resources/AppIcon.icns" ]]; then
  cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ -d "Resources/Icons" ]]; then
  cp -R Resources/Icons "$APP_DIR/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
