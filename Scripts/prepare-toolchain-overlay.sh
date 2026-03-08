#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/.toolchain-overlay"
CLT_DIR="/Library/Developer/CommandLineTools"
DEVELOPER_DIR="$(xcode-select -p)"
XCODE_PLUGIN_DIR="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"

if [[ ! -x "$CLT_DIR/usr/bin/swift" ]]; then
  echo "Command Line Tools Swift toolchain not found at $CLT_DIR/usr/bin/swift" >&2
  exit 1
fi

for required_file in \
  "$CLT_DIR/usr/bin/swift-plugin-server" \
  "$CLT_DIR/usr/lib/swift/host/libSwiftSyntaxBuilder.dylib" \
  "$XCODE_PLUGIN_DIR/libSwiftDataMacros.dylib" \
  "$XCODE_PLUGIN_DIR/libSwiftUIMacros.dylib"; do
  if [[ ! -e "$required_file" ]]; then
    echo "Required toolchain file not found: $required_file" >&2
    exit 1
  fi
done

rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR/bin" "$OVERLAY_DIR/lib/swift"

cp "$CLT_DIR/usr/bin/swift-plugin-server" "$OVERLAY_DIR/bin/"
cp -R "$CLT_DIR/usr/lib/swift/host" "$OVERLAY_DIR/lib/swift/"
cp "$XCODE_PLUGIN_DIR/libSwiftDataMacros.dylib" "$OVERLAY_DIR/lib/swift/host/plugins/"
cp "$XCODE_PLUGIN_DIR/libSwiftUIMacros.dylib" "$OVERLAY_DIR/lib/swift/host/plugins/"

find "$OVERLAY_DIR" -type f \( -name '*.dylib' -o -name '*.bundle' -o -name 'swift-plugin-server' \) -print0 \
  | xargs -0 -n 1 codesign --force --sign - >/dev/null

echo "$OVERLAY_DIR"
