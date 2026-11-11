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

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
