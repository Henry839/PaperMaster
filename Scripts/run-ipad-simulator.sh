#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Apps/PaperMasteriPad/PaperMasteriPad.xcodeproj"
WORKSPACE_PATH="$PROJECT_PATH/project.xcworkspace"
SCHEME="PaperMasteriPad"
BUNDLE_ID="com.lihengli.PaperMaster.iPad"
DERIVED_DATA_DIR="$ROOT_DIR/dist/DerivedData/PaperMasteriPad-simulator-debug"
SOURCE_PACKAGES_DIR="$ROOT_DIR/.build/xcode-source-packages"

json_query() {
  local script="$1"
  /usr/bin/ruby -rjson -e "$script"
}

latest_ios_runtime_id() {
  xcrun simctl list runtimes available -j | json_query '
    data = JSON.parse(STDIN.read)
    runtimes = data.fetch("runtimes", []).select do |runtime|
      runtime["isAvailable"] && runtime["identifier"].to_s.include?("iOS")
    end
    runtime = runtimes.max_by do |candidate|
      candidate["version"].to_s.split(/[^\d]+/).reject(&:empty?).map(&:to_i)
    end
    puts(runtime ? runtime["identifier"] : "")
  '
}

preferred_ipad_device_type_id() {
  xcrun simctl list devicetypes available -j | json_query '
    data = JSON.parse(STDIN.read)
    device_types = data.fetch("devicetypes", []).select do |device_type|
      device_type["name"].to_s.start_with?("iPad")
    end
    preferred = device_types.find { |device_type| device_type["name"] == "iPad Pro 13-inch (M4)" }
    device_type = preferred || device_types.first
    puts(device_type ? device_type["identifier"] : "")
  '
}

available_ipad_udid() {
  xcrun simctl list devices available -j | json_query '
    data = JSON.parse(STDIN.read)
    devices = data.fetch("devices", {}).values.flatten.select do |device|
      device["isAvailable"] && device["name"].to_s.start_with?("iPad")
    end
    booted = devices.find { |device| device["state"] == "Booted" }
    device = booted || devices.first
    puts(device ? device["udid"] : "")
  '
}

ensure_ipad_simulator_udid() {
  local existing_udid
  existing_udid="$(available_ipad_udid)"
  if [[ -n "$existing_udid" ]]; then
    printf '%s\n' "$existing_udid"
    return
  fi

  local runtime_id
  runtime_id="$(latest_ios_runtime_id)"
  if [[ -z "$runtime_id" ]]; then
    echo "No iOS Simulator runtime is installed." >&2
    echo "Install one in Xcode > Settings > Components, then rerun this script." >&2
    exit 1
  fi

  local device_type_id
  device_type_id="$(preferred_ipad_device_type_id)"
  if [[ -z "$device_type_id" ]]; then
    echo "No iPad simulator device type is available in this Xcode installation." >&2
    exit 1
  fi

  xcrun simctl create "PaperMaster iPad" "$device_type_id" "$runtime_id"
}

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/generate-ipad-project.rb"
mkdir -p "$SOURCE_PACKAGES_DIR"

UDID="${PAPERMASTER_IPAD_SIMULATOR_UDID:-$(ensure_ipad_simulator_udid)}"

open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -sdk iphonesimulator \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "Launched $SCHEME in simulator $UDID"
