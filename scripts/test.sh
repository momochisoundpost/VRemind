#!/usr/bin/env bash
# Run the Swift Testing suite with only Xcode Command Line Tools installed.
#
# CLT ships Testing.framework outside SwiftPM's default search paths, so we
# point the compiler/linker at it. Caches are redirected into .build so the
# script also works inside restricted sandboxes. Extra args are passed through
# (e.g. scripts/test.sh --filter ModelTests).
set -euo pipefail

cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
FW="$CLT/Frameworks"
LIB="$CLT/usr/lib"
CACHE="$PWD/.build/caches"
mkdir -p "$CACHE/modules"

export CLANG_MODULE_CACHE_PATH="$CACHE/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/modules"

EXTRA=()
if [[ -d "$FW/Testing.framework" ]]; then
  EXTRA+=(-Xswiftc -F -Xswiftc "$FW"
          -Xlinker -F -Xlinker "$FW"
          -Xlinker -rpath -Xlinker "$FW"
          -Xlinker -rpath -Xlinker "$LIB")
fi

# The linker warns that CLT's Testing.framework targets macOS 14 while the
# package targets 12; that only affects the test binary, so filter it out.
swift test --disable-sandbox --cache-path "$CACHE/spm" ${EXTRA[@]+"${EXTRA[@]}"} "$@" 2>&1 \
  | grep -v -e "is not accessible or not writable" \
            -e "which was built for newer version 14.0"
exit "${PIPESTATUS[0]}"
