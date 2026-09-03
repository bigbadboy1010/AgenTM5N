#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

APP_NAME="AgenTM5N"
BUNDLE_ID="team.cloudforge.AgenTM5N"
# Build 42: resource-safe model control plane with local Ollama discovery.
VERSION="${AGENTM5N_VERSION:-1.4.2}"
BUILD_NUMBER="${AGENTM5N_BUILD_NUMBER:-42}"
SIGNING_IDENTITY="${AGENTM5N_SIGNING_IDENTITY:--}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENTITLEMENTS_FILE="$ROOT_DIR/Resources/AgenTM5N.entitlements"
ICON_GENERATOR="$ROOT_DIR/scripts/generate-app-icon.swift"
ICON_WORK_DIR="$ROOT_DIR/.build-artifacts/app-icon"
ICONSET_DIR="$ICON_WORK_DIR/$APP_NAME.iconset"
ICON_SOURCE="$ICON_WORK_DIR/${APP_NAME}-1024.png"
ICON_FILE="$RESOURCES_DIR/$APP_NAME.icns"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Dieses Build-Skript muss auf macOS ausgeführt werden." >&2
  exit 1
fi

if [ ! -f "$ENTITLEMENTS_FILE" ]; then
  echo "Entitlements-Datei fehlt: $ENTITLEMENTS_FILE" >&2
  exit 1
fi

if [ ! -f "$ICON_GENERATOR" ]; then
  echo "App-Icon-Generator fehlt: $ICON_GENERATOR" >&2
  exit 1
fi

agentm5n_configure_xcode
cd "$ROOT_DIR"

# Resource-safe default for 16 GB Apple-silicon development machines. A clean
# release build can otherwise create enough concurrent compiler processes to
# saturate unified memory and trigger heavy swap/thermal pressure.
SWIFT_JOBS="${AGENTM5N_SWIFT_JOBS:-4}"
case "$SWIFT_JOBS" in
  ''|*[!0-9]*)
    echo "AGENTM5N_SWIFT_JOBS muss eine positive Ganzzahl sein." >&2
    exit 2
    ;;
esac
if [ "$SWIFT_JOBS" -lt 1 ]; then SWIFT_JOBS=1; fi
if [ "$SWIFT_JOBS" -gt 16 ]; then SWIFT_JOBS=16; fi

FREE_PERCENT="$(
  memory_pressure -Q 2>/dev/null \
    | awk '/System-wide memory free percentage/ { value=$5; gsub(/%/, "", value); print int(value + 0); exit }' \
    || true
)"
SWAP_USED_MB="$(
  sysctl -n vm.swapusage 2>/dev/null \
    | awk '{ for (i = 1; i <= NF; i++) { if ($i == "used") { value=$(i + 2); sub(/M$/, "", value); print int(value + 0); exit } } }' \
    || true
)"

RESOURCE_CRITICAL=0
RESOURCE_WARNING=0

if [ -n "$FREE_PERCENT" ]; then
  printf 'Freier Systemspeicher: %s%%\n' "$FREE_PERCENT"
  if [ "$FREE_PERCENT" -lt 15 ]; then
    RESOURCE_CRITICAL=1
  elif [ "$FREE_PERCENT" -lt 30 ]; then
    RESOURCE_WARNING=1
  fi
fi

if [ -n "$SWAP_USED_MB" ]; then
  printf 'Swap belegt: %s MB\n' "$SWAP_USED_MB"
  if [ "$SWAP_USED_MB" -gt 4096 ]; then
    RESOURCE_CRITICAL=1
  elif [ "$SWAP_USED_MB" -gt 2048 ]; then
    RESOURCE_WARNING=1
  fi
fi

if [ "$RESOURCE_CRITICAL" -eq 1 ]; then
  if [ "${AGENTM5N_FORCE_BUILD:-0}" = "1" ]; then
    echo "WARNUNG: Kritischer Memory/Swap-Druck; Release-Build wurde ausdrücklich erzwungen." >&2
  else
    echo "ABBRUCH: Kritischer Memory/Swap-Druck. Fremdlast reduzieren oder Build bewusst erzwingen." >&2
    exit 70
  fi
elif [ "$RESOURCE_WARNING" -eq 1 ] && [ "$SWIFT_JOBS" -gt 2 ]; then
  echo "WARNUNG: Erhöhter Memory/Swap-Druck; SwiftPM wird automatisch auf 2 Jobs reduziert." >&2
  SWIFT_JOBS=2
fi

printf '\n=== Thermal state before release build ===\n'
pmset -g therm 2>/dev/null || true
printf 'SwiftPM Parallelität: %s Jobs\n' "$SWIFT_JOBS"

swift package resolve
swift build -c release --arch arm64 --jobs "$SWIFT_JOBS"
BIN_DIR="$(swift build -c release --arch arm64 --jobs "$SWIFT_JOBS" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

if [ ! -x "$BINARY" ]; then
  echo "Release-Binary wurde nicht erzeugt: $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 0755 "$BINARY" "$MACOS_DIR/$APP_NAME"

while IFS= read -r -d '' local_bundle; do
  bundle_name="${local_bundle##*/}"
  ditto "$local_bundle" "$RESOURCES_DIR/$bundle_name"
  ln -s "Contents/Resources/$bundle_name" "$APP_DIR/$bundle_name"
done < <(
  find "$BIN_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -name '*.bundle' \
    -print0
)

rm -rf "$ICON_WORK_DIR"
mkdir -p "$ICONSET_DIR"
xcrun swift "$ICON_GENERATOR" "$ICON_SOURCE"

make_icon_size() {
  local pixels="$1"
  local output_name="$2"
  sips -z "$pixels" "$pixels" "$ICON_SOURCE" \
    --out "$ICONSET_DIR/$output_name" >/dev/null
}

make_icon_size 16   "icon_16x16.png"
make_icon_size 32   "icon_16x16@2x.png"
make_icon_size 32   "icon_32x32.png"
make_icon_size 64   "icon_32x32@2x.png"
make_icon_size 128  "icon_128x128.png"
make_icon_size 256  "icon_128x128@2x.png"
make_icon_size 256  "icon_256x256.png"
make_icon_size 512  "icon_256x256@2x.png"
make_icon_size 512  "icon_512x512.png"
make_icon_size 1024 "icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>AgenTM5N benötigt Zugriff auf deinen Kalender, damit freigegebene KI-Agenten Termine lesen und verwalten können.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>AgenTM5N benötigt Zugriff auf deine Erinnerungen, damit freigegebene KI-Agenten Erinnerungen lesen und verwalten können.</string>
    <key>NSContactsUsageDescription</key>
    <string>AgenTM5N benötigt Zugriff auf deine Kontakte, damit freigegebene KI-Agenten Kontakte suchen und verwalten können.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>AgenTM5N verwendet Apple Events, um auf deine ausdrückliche Anfrage mit Apple Mail, Kurzbefehlen und anderen freigegebenen macOS-Funktionen zu interagieren.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
plutil -lint "$ENTITLEMENTS_FILE" >/dev/null

if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign \
    --force \
    --sign - \
    --options runtime \
    --entitlements "$ENTITLEMENTS_FILE" \
    "$APP_DIR"
  SIGNING_DESCRIPTION="Ad-hoc (development)"
else
  codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS_FILE" \
    "$APP_DIR"
  SIGNING_DESCRIPTION="Developer ID ($SIGNING_IDENTITY)"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign -d --entitlements - --xml "$APP_DIR" >/dev/null

printf '\nApp erstellt: %s\n' "$APP_DIR"
printf 'Version: %s Build %s\n' "$VERSION" "$BUILD_NUMBER"
printf 'App-Icon: %s\n' "$ICON_FILE"
printf 'Hardened Runtime: aktiv\n'
printf 'Signierung: %s\n' "$SIGNING_DESCRIPTION"
printf 'Entitlements: %s\n' "$ENTITLEMENTS_FILE"
printf 'Starten mit: open %q\n' "$APP_DIR"
