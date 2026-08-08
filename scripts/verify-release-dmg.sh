#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgenTM5N"
VERSION="${AGENTM5N_VERSION:-1.0.1}"
BUILD_NUMBER="${AGENTM5N_BUILD_NUMBER:-23}"
DMG_PATH="${AGENTM5N_DMG_PATH:-$ROOT_DIR/dist/$APP_NAME-$VERSION-build$BUILD_NUMBER.dmg}"
MOUNT_POINT="$(mktemp -d -t agentm5n-release-mount)"
ATTACHED=0

cleanup() {
  if [ "$ATTACHED" -eq 1 ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  printf 'DMG VERIFY FAILED: %s\n' "$1" >&2
  exit 1
}

[ -f "$DMG_PATH" ] || fail "DMG fehlt: $DMG_PATH"

printf '\n=== DMG-Struktur prüfen ===\n'
hdiutil verify "$DMG_PATH" >/dev/null
codesign --verify --verbose=2 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

printf '\n=== DMG read-only mounten ===\n'
hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$MOUNT_POINT" \
  "$DMG_PATH" >/dev/null
ATTACHED=1

MOUNTED_APP="$MOUNT_POINT/$APP_NAME.app"
[ -d "$MOUNTED_APP" ] || fail "AgenTM5N.app fehlt in der DMG."
[ -L "$MOUNT_POINT/Applications" ] || fail "Applications-Verknüpfung fehlt in der DMG."

printf '\n=== Ausgelieferte App prüfen ===\n'
AGENTM5N_APP_PATH="$MOUNTED_APP" \
AGENTM5N_VERSION="$VERSION" \
AGENTM5N_BUILD_NUMBER="$BUILD_NUMBER" \
AGENTM5N_REQUIRE_DEVELOPER_ID=1 \
AGENTM5N_REQUIRE_GATEKEEPER=1 \
  bash "$ROOT_DIR/scripts/check-release.sh"

printf '\nDMG VERIFY: OK\n'
printf 'Artefakt: %s\n' "$DMG_PATH"
printf 'Version:  %s Build %s\n' "$VERSION" "$BUILD_NUMBER"
