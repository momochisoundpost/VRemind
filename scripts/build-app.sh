#!/usr/bin/env bash
# Assemble build/CaitlynSwift.app using only Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")/.."

CACHE="$PWD/.build/caches"
mkdir -p "$CACHE/modules"

export CLANG_MODULE_CACHE_PATH="$CACHE/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/modules"

SPM_FLAGS=(--disable-sandbox --cache-path "$CACHE/spm" -c release)

APP_DIR="$PWD/build/CaitlynSwift.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

ARM_BIN="$PWD/.build/arm64-apple-macosx/release/CaitlynSwift"
X86_BIN="$PWD/.build/x86_64-apple-macosx/release/CaitlynSwift"

if swift build "${SPM_FLAGS[@]}" --triple arm64-apple-macosx12.0 2>&1 | grep -v "is not accessible or not writable" \
   && swift build "${SPM_FLAGS[@]}" --triple x86_64-apple-macosx12.0 2>&1 | grep -v "is not accessible or not writable" \
   && [[ -f "$ARM_BIN" && -f "$X86_BIN" ]]; then
  lipo -create -output "$APP_DIR/Contents/MacOS/CaitlynSwift" "$ARM_BIN" "$X86_BIN"
  BUNDLE_SRC="$(dirname "$ARM_BIN")/CaitlynSwift_CaitlynKit.bundle"
else
  echo "warning: cross-architecture build unavailable; falling back to host-architecture binary" >&2
  swift build "${SPM_FLAGS[@]}" 2>&1 | grep -v "is not accessible or not writable"
  BIN_PATH="$(swift build "${SPM_FLAGS[@]}" --show-bin-path 2>/dev/null)"
  cp "$BIN_PATH/CaitlynSwift" "$APP_DIR/Contents/MacOS/CaitlynSwift"
  BUNDLE_SRC="$BIN_PATH/CaitlynSwift_CaitlynKit.bundle"
fi

chmod +x "$APP_DIR/Contents/MacOS/CaitlynSwift"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp -R "$BUNDLE_SRC" "$APP_DIR/Contents/Resources/CaitlynSwift_CaitlynKit.bundle"

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
