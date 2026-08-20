#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

APP_NAME="AgenTM5N"
VERSION="${AGENTM5N_VERSION:-1.3.9}"
BUILD_NUMBER="${AGENTM5N_BUILD_NUMBER:-39}"
NOTARY_PROFILE="${AGENTM5N_NOTARY_PROFILE:-AgenTM5NNotary}"
SIGNING_IDENTITY="${AGENTM5N_SIGNING_IDENTITY:-}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION-build$BUILD_NUMBER.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RELEASE_WORK_DIR="$ROOT_DIR/.build-artifacts/release-$VERSION-$BUILD_NUMBER"
DMG_ROOT="$RELEASE_WORK_DIR/dmg-root"
NOTARY_RESULT="$DIST_DIR/$APP_NAME-$VERSION-notary-result.json"
NOTARY_LOG="$DIST_DIR/$APP_NAME-$VERSION-notary-log.json"

fail() {
  printf 'RELEASE FAILED: %s\n' "$1" >&2
  exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Der macOS-Release muss auf einem Mac erzeugt werden."
fi

agentm5n_configure_xcode
cd "$ROOT_DIR"

for command in security codesign diskutil hdiutil ditto plutil xcrun spctl; do
  command -v "$command" >/dev/null 2>&1 || fail "Benötigtes Tool fehlt: $command"
done

if [ -z "$SIGNING_IDENTITY" ]; then
  ALL_DEVELOPER_ID_LINES="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep '"Developer ID Application:' || true)"
  IDENTITY_LINES="$(printf '%s\n' "$ALL_DEVELOPER_ID_LINES" \
    | grep -v 'CSSMERR_' || true)"
  IDENTITY_COUNT="$(printf '%s\n' "$IDENTITY_LINES" | awk 'NF { count++ } END { print count + 0 }')"

  if [ "$IDENTITY_COUNT" -eq 1 ]; then
    SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITY_LINES" | awk 'NF { print $2; exit }')"
  elif [ "$IDENTITY_COUNT" -eq 0 ]; then
    if [ -n "$ALL_DEVELOPER_ID_LINES" ]; then
      printf '%s\n' "$ALL_DEVELOPER_ID_LINES" >&2
      fail "Es wurden Developer-ID-Zertifikate gefunden, aber keine gültige Developer ID Application Identität."
    fi
    fail "Keine Developer ID Application Identität im Schlüsselbund gefunden."
  else
    printf '%s\n' "$IDENTITY_LINES" >&2
    fail "Mehrere gültige Developer-ID-Identitäten gefunden. Setze AGENTM5N_SIGNING_IDENTITY auf den gewünschten SHA-1-Hash oder Identitätsnamen."
  fi
fi

IDENTITY_INFO="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -F "$SIGNING_IDENTITY" || true)"
[ -n "$IDENTITY_INFO" ] || fail "Developer-ID-Identität nicht gefunden: $SIGNING_IDENTITY"
printf '%s\n' "$IDENTITY_INFO" | grep -q '"Developer ID Application:' \
  || fail "AGENTM5N_SIGNING_IDENTITY ist keine Developer ID Application Identität."
if printf '%s\n' "$IDENTITY_INFO" | grep -q 'CSSMERR_'; then
  printf '%s\n' "$IDENTITY_INFO" >&2
  fail "Die ausgewählte Developer-ID-Identität ist ungültig, widerrufen oder anderweitig nicht verwendbar."
fi

printf '\n=== AgenTM5N %s Build %s Release ===\n' "$VERSION" "$BUILD_NUMBER"
printf 'Signing Identity: %s\n' "$SIGNING_IDENTITY"
printf 'Notary Profile:    %s\n' "$NOTARY_PROFILE"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
Notary-Keychain-Profil '$NOTARY_PROFILE' ist nicht verfügbar oder ungültig.
Lege es einmalig an mit:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "DEINE_APPLE_ID" \
    --team-id "DEINE_TEAM_ID"
notarytool fragt das app-spezifische Passwort anschließend interaktiv ab und speichert es im Keychain.
Alternativ kannst du ein bestehendes Profil verwenden:
  export AGENTM5N_NOTARY_PROFILE="PROFILNAME"
EOF
  exit 1
fi

export AGENTM5N_VERSION="$VERSION"
export AGENTM5N_BUILD_NUMBER="$BUILD_NUMBER"
export AGENTM5N_SIGNING_IDENTITY="$SIGNING_IDENTITY"

printf '\n=== Source-/Debug-/Test-Gate ===\n'
bash "$ROOT_DIR/scripts/verify.sh"

printf '\n=== Developer-ID-App bauen ===\n'
bash "$ROOT_DIR/scripts/build-app.sh"

printf '\n=== Release-App prüfen ===\n'
AGENTM5N_REQUIRE_DEVELOPER_ID=1 \
  bash "$ROOT_DIR/scripts/check-release.sh"

printf '\n=== DMG erzeugen ===\n'
rm -rf "$RELEASE_WORK_DIR"
mkdir -p "$DMG_ROOT" "$DIST_DIR"
ditto "$APP_DIR" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH" "$NOTARY_RESULT" "$NOTARY_LOG"

# macOS 27 deprecates the older hdiutil create form. Prefer diskutil image and
# retain hdiutil only as a compatibility fallback for earlier host versions.
if diskutil image create from \
  --volumeName "$APP_NAME $VERSION" \
  --format UDZO \
  "$DMG_ROOT" \
  "$DMG_PATH" >/dev/null 2>&1
then
  printf 'DMG: diskutil image create\n'
else
  printf 'DMG: diskutil image create nicht verfügbar, verwende hdiutil-Fallback.\n'
  hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
fi

codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --timestamp \
  "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

printf '\n=== Apple Notarisierung ===\n'
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json \
  | tee "$NOTARY_RESULT"

NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
NOTARY_ID="$(plutil -extract id raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"

if [ -n "$NOTARY_ID" ]; then
  xcrun notarytool log "$NOTARY_ID" \
    --keychain-profile "$NOTARY_PROFILE" \
    "$NOTARY_LOG" >/dev/null 2>&1 || true
fi

[ "$NOTARY_STATUS" = "Accepted" ] \
  || fail "Apple Notarisierung wurde nicht akzeptiert (Status: ${NOTARY_STATUS:-unbekannt}). Siehe $NOTARY_LOG"

printf '\n=== Notarisierungs-Ticket einbetten ===\n'
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

printf '\n=== Finale Artefaktprüfung ===\n'
codesign --verify --verbose=2 "$DMG_PATH"
AGENTM5N_DMG_PATH="$DMG_PATH" \
  bash "$ROOT_DIR/scripts/verify-release-dmg.sh"

printf '\nRELEASE READY\n'
printf 'App:            %s\n' "$APP_DIR"
printf 'DMG:            %s\n' "$DMG_PATH"
printf 'Notary Result:  %s\n' "$NOTARY_RESULT"
printf 'Notary Log:     %s\n' "$NOTARY_LOG"
printf 'Version:        %s Build %s\n' "$VERSION" "$BUILD_NUMBER"
printf 'Notarization:   Accepted + stapled\n'
