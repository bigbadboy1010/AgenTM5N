#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

APP_NAME="AgenTM5N"
BUNDLE_ID="team.cloudforge.AgenTM5N"
VERSION="0.7.0"
BUILD_NUMBER="19"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Dieses Build-Skript muss auf macOS ausgeführt werden." >&2
  exit 1
fi

agentm5n_configure_xcode
cd "$ROOT_DIR"

swift package resolve
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

if [ ! -x "$BINARY" ]; then
  echo "Release-Binary wurde nicht erzeugt: $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 0755 "$BINARY" "$MACOS_DIR/$APP_NAME"

# Copy SwiftPM resource bundles when dependencies provide any. A find loop is
# used instead of an empty Bash array because macOS Bash 3.2 treats empty arrays
# as unbound variables when `set -u` is active.
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
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf '\nApp erstellt: %s\n' "$APP_DIR"
printf 'Starten mit: open %q\n' "$APP_DIR"
