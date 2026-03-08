#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLT_SWIFT="/Library/Developer/CommandLineTools/usr/bin/swift"

if [[ ! -x "$CLT_SWIFT" ]]; then
  echo "Command Line Tools Swift executable not found at $CLT_SWIFT" >&2
  exit 1
fi

OVERLAY_DIR="$("$ROOT_DIR/Scripts/prepare-toolchain-overlay.sh")"
mkdir -p /tmp/swift-module-cache /tmp/clang-module-cache

SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
"$CLT_SWIFT" "$@" \
  -Xswiftc -plugin-path \
  -Xswiftc "$OVERLAY_DIR/lib/swift/host/plugins" \
  -Xswiftc -in-process-plugin-server-path \
  -Xswiftc "$OVERLAY_DIR/bin/swift-plugin-server"
