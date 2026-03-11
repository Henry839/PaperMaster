#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"
TOOLCHAIN_DIR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain"
TOOLCHAIN_SWIFT="$TOOLCHAIN_DIR/usr/bin/swift"
CLT_SWIFT="/Library/Developer/CommandLineTools/usr/bin/swift"
SWIFT_BIN="$TOOLCHAIN_SWIFT"

if [[ ! -x "$SWIFT_BIN" ]]; then
  SWIFT_BIN="$CLT_SWIFT"
fi

if [[ ! -x "$SWIFT_BIN" ]]; then
  echo "Swift executable not found in Xcode toolchain or Command Line Tools" >&2
  exit 1
fi

OVERLAY_DIR="$("$ROOT_DIR/Scripts/prepare-toolchain-overlay.sh")"
mkdir -p /tmp/swift-module-cache /tmp/clang-module-cache

SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
"$SWIFT_BIN" "$@" \
  -Xswiftc -plugin-path \
  -Xswiftc "$OVERLAY_DIR/lib/swift/host/plugins" \
  -Xswiftc -in-process-plugin-server-path \
  -Xswiftc "$OVERLAY_DIR/bin/swift-plugin-server"
