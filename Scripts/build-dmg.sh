#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PaperMaster"
CONFIGURATION="${1:-release}"
APP_PATH="$ROOT_DIR/dist/${APP_NAME}.app"
DMG_PATH="$ROOT_DIR/dist/${APP_NAME}-${CONFIGURATION}.dmg"
STAGING_DIR="$ROOT_DIR/dist/.dmg-staging"
VOLUME_NAME="${APP_NAME}"

case "$CONFIGURATION" in
  debug|release)
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 1
    ;;
esac

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required to build a DMG." >&2
  exit 1
fi

"$ROOT_DIR/Scripts/build-app.sh" "$CONFIGURATION"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "Built DMG at: $DMG_PATH"
