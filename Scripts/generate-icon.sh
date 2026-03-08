#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="HenryPaper"
BASE_PNG="$ROOT_DIR/AppBundle/${APP_NAME}-1024.png"
ICNS_PATH="$ROOT_DIR/AppBundle/${APP_NAME}.icns"
WORK_DIR="$ROOT_DIR/AppBundle/.icon-work"
MULTI_TIFF="$WORK_DIR/${APP_NAME}.tiff"
export TMPDIR=/tmp

mkdir -p /tmp/swift-module-cache /tmp/clang-module-cache
SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
swift "$ROOT_DIR/Scripts/generate-icon.swift" "$BASE_PNG" >/dev/null

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

for size in 16 32 48 128 256 512 1024; do
  /usr/bin/sips -z "$size" "$size" -s format tiff "$BASE_PNG" --out "$WORK_DIR/${size}.tiff" >/dev/null
done

/usr/bin/tiffutil -cat \
  "$WORK_DIR/1024.tiff" \
  "$WORK_DIR/512.tiff" \
  "$WORK_DIR/256.tiff" \
  "$WORK_DIR/128.tiff" \
  "$WORK_DIR/48.tiff" \
  "$WORK_DIR/32.tiff" \
  "$WORK_DIR/16.tiff" \
  -out "$MULTI_TIFF" >/dev/null 2>&1

/usr/bin/tiff2icns "$MULTI_TIFF" "$ICNS_PATH" >/dev/null 2>&1
rm -rf "$WORK_DIR"

echo "Generated app icon at: $ICNS_PATH"
