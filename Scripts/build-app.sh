#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE_NAME="PaperMaster"
EXECUTABLE_NAME="PaperMaster"
ICON_NAME="PaperMaster"
SOURCE_BINARY_NAME="PaperMaster"
CONFIGURATION="${1:-release}"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$ROOT_DIR/dist/${APP_BUNDLE_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SOURCE="$ROOT_DIR/AppBundle/Info.plist"
ICON_SOURCE="$ROOT_DIR/AppBundle/${ICON_NAME}.icns"

case "$CONFIGURATION" in
  debug|release)
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 1
    ;;
esac

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/generate-icon.sh"

mkdir -p /tmp/swift-module-cache /tmp/clang-module-cache
"$ROOT_DIR/Scripts/swift-overlay.sh" build -c "$CONFIGURATION"

BINARY_PATH="$BUILD_DIR/arm64-apple-macosx/$CONFIGURATION/$SOURCE_BINARY_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Expected binary not found at $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"
cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_SOURCE" "$RESOURCES_DIR/${ICON_NAME}.icns"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

echo -n 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built app bundle at: $APP_DIR"
