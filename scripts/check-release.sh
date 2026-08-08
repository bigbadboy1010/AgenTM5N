#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgenTM5N"
EXPECTED_VERSION="${AGENTM5N_VERSION:-1.1.0}"
EXPECTED_BUILD="${AGENTM5N_BUILD_NUMBER:-24}"
REQUIRE_DEVELOPER_ID="${AGENTM5N_REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_GATEKEEPER="${AGENTM5N_REQUIRE_GATEKEEPER:-0}"
APP_DIR="${AGENTM5N_APP_PATH:-$ROOT_DIR/dist/$APP_NAME.app}"
PLIST="$APP_DIR/Contents/Info.plist"
ICON="$APP_DIR/Contents/Resources/$APP_NAME.icns"
ENTITLEMENTS_TMP="$(mktemp -t agentm5n-entitlements)"
trap 'rm -f "$ENTITLEMENTS_TMP"' EXIT

fail() {
  printf 'RELEASE CHECK FAILED: %s\n' "$1" >&2
  exit 1
}

[ -d "$APP_DIR" ] || fail "App fehlt: $APP_DIR"
[ -f "$PLIST" ] || fail "Info.plist fehlt."
[ -f "$ICON" ] || fail "App-Icon fehlt: $ICON"
[ -x "$APP_DIR/Contents/MacOS/$APP_NAME" ] || fail "Executable fehlt."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")"

[ "$VERSION" = "$EXPECTED_VERSION" ] \
  || fail "Version ist $VERSION statt $EXPECTED_VERSION."
[ "$BUILD" = "$EXPECTED_BUILD" ] \
  || fail "Build ist $BUILD statt $EXPECTED_BUILD."
[ "$BUNDLE_ID" = "team.cloudforge.AgenTM5N" ] \
  || fail "Unerwartete Bundle-ID: $BUNDLE_ID"
[ "$ICON_NAME" = "$APP_NAME" ] \
  || fail "CFBundleIconFile ist $ICON_NAME statt $APP_NAME."

for usage_key in \
  NSCalendarsFullAccessUsageDescription \
  NSRemindersFullAccessUsageDescription \
  NSContactsUsageDescription \
  NSAppleEventsUsageDescription
do
  USAGE_VALUE="$(/usr/libexec/PlistBuddy -c "Print :$usage_key" "$PLIST" 2>/dev/null || true)"
  [ -n "$USAGE_VALUE" ] || fail "Privacy Usage Description fehlt: $usage_key"
done

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
printf '%s\n' "$SIGNATURE_INFO" | grep -q 'runtime' \
  || fail "Hardened Runtime ist in der Signatur nicht sichtbar."

codesign -d --entitlements - --xml "$APP_DIR" >"$ENTITLEMENTS_TMP" 2>/dev/null
plutil -lint "$ENTITLEMENTS_TMP" >/dev/null

for entitlement in \
  com.apple.security.automation.apple-events \
  com.apple.security.personal-information.addressbook \
  com.apple.security.personal-information.calendars
do
  /usr/libexec/PlistBuddy -c "Print :$entitlement" "$ENTITLEMENTS_TMP" 2>/dev/null \
    | grep -q '^true$' \
    || fail "Benötigtes Entitlement fehlt oder ist nicht true: $entitlement"
done

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_TMP" 2>/dev/null \
  | grep -q '^true$'; then
  fail "Debug-Entitlement com.apple.security.get-task-allow darf im Release nicht aktiv sein."
fi

if [ "$REQUIRE_DEVELOPER_ID" = "1" ]; then
  printf '%s\n' "$SIGNATURE_INFO" | grep -q 'Authority=Developer ID Application:' \
    || fail "Keine Developer ID Application Signatur gefunden."
fi

if [ "$REQUIRE_GATEKEEPER" = "1" ]; then
  spctl --assess --type execute --verbose=4 "$APP_DIR"
fi

printf '\n=== AgenTM5N Release Check ===\n'
printf 'App:        %s\n' "$APP_DIR"
printf 'Version:    %s\n' "$VERSION"
printf 'Build:      %s\n' "$BUILD"
printf 'Bundle ID:  %s\n' "$BUNDLE_ID"
printf 'Icon:       vorhanden\n'
printf 'Runtime:    hardened\n'
printf 'Privacy:    Calendar + Reminders + Contacts + Apple Events\n'
printf 'Entitlements: Calendar + Contacts + Apple Events\n'
if [ "$REQUIRE_DEVELOPER_ID" = "1" ]; then
  printf 'Developer ID: bestanden\n'
else
  printf 'Developer ID: nicht erzwungen (Development Gate)\n'
fi
if [ "$REQUIRE_GATEKEEPER" = "1" ]; then
  printf 'Gatekeeper: bestanden\n'
else
  printf 'Gatekeeper: nicht erzwungen (vor Notarisierung normal)\n'
fi
printf 'Release Check: OK\n'
