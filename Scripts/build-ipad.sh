#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Apps/PaperMasteriPad/PaperMasteriPad.xcodeproj"
WORKSPACE_PATH="$PROJECT_PATH/project.xcworkspace"
SCHEME="PaperMasteriPad"
CONFIGURATION="${1:-debug}"
DESTINATION_KIND="${2:-simulator}"
SOURCE_PACKAGES_DIR="$ROOT_DIR/.build/xcode-source-packages"
DERIVED_DATA_DIR="$ROOT_DIR/dist/DerivedData/PaperMasteriPad-${DESTINATION_KIND}-${CONFIGURATION}"

case "$CONFIGURATION" in
  debug)
    XCODE_CONFIGURATION="Debug"
    PRODUCT_CONFIGURATION_DIR="Debug"
    ;;
  release)
    XCODE_CONFIGURATION="Release"
    PRODUCT_CONFIGURATION_DIR="Release"
    ;;
  *)
    echo "Usage: $0 [debug|release] [simulator|device]" >&2
    exit 1
    ;;
esac

case "$DESTINATION_KIND" in
  simulator)
    SDK="iphonesimulator"
    DESTINATION="generic/platform=iOS Simulator"
    PRODUCT_PLATFORM_DIR="${PRODUCT_CONFIGURATION_DIR}-iphonesimulator"
    ;;
  device)
    SDK="iphoneos"
    DESTINATION="generic/platform=iOS"
    PRODUCT_PLATFORM_DIR="${PRODUCT_CONFIGURATION_DIR}-iphoneos"
    ;;
  *)
    echo "Usage: $0 [debug|release] [simulator|device]" >&2
    exit 1
    ;;
esac

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/generate-ipad-project.rb"
mkdir -p "$SOURCE_PACKAGES_DIR"

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme "$SCHEME" \
  -configuration "$XCODE_CONFIGURATION" \
  -destination "$DESTINATION" \
  -sdk "$SDK" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA_DIR/Build/Products/$PRODUCT_PLATFORM_DIR/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "Built iPad app at: $APP_PATH"
