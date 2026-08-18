#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

APP_NAME="AgenTM5N"
VERSION="${AGENTM5N_VERSION:-1.3.7}"
BUILD_NUMBER="${AGENTM5N_BUILD_NUMBER:-37}"
NOTARY_PROFILE="${AGENTM5N_NOTARY_PROFILE:-AgenTM5NNotary}"
SIGNING_IDENTITY="${AGENTM5N_SIGNING_IDENTITY:-}"
DEFAULT_META="$HOME/Downloads/AgenTM5N-Qwen3-ANE/anemll-Qwen-Qwen3-0.6B-ctx512_0.3.4/meta.yaml"
MODEL_META="${AGENTM5N_ANEMLL_META:-$DEFAULT_META}"
HELPER_SOURCE_DIR="$ROOT_DIR/.build-artifacts/anemll-runtime"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ENTITLEMENTS_FILE="$ROOT_DIR/Resources/AgenTM5N.entitlements"
HELPER_DEST_DIR="$APP_DIR/Contents/Helpers/ANEMLL"
MODEL_DEST_DIR="$APP_DIR/Contents/Resources/Models/ANEMLL/Qwen3"
DMG_NAME="$APP_NAME-$VERSION-build$BUILD_NUMBER.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
RELEASE_WORK_DIR="$ROOT_DIR/.build-artifacts/portable-release-$VERSION-$BUILD_NUMBER"
DMG_ROOT="$RELEASE_WORK_DIR/dmg-root"
NOTARY_RESULT="$DIST_DIR/$APP_NAME-$VERSION-notary-result.json"
NOTARY_LOG="$DIST_DIR/$APP_NAME-$VERSION-notary-log.json"
FINAL_MOUNT="$RELEASE_WORK_DIR/final-mount"
ATTACHED=0

cleanup() {
  if [ "$ATTACHED" -eq 1 ]; then
    hdiutil detach "$FINAL_MOUNT" -quiet >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

fail() {
  printf 'PORTABLE RELEASE FAILED: %s\n' "$1" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] \
  || fail "Der signierte/notarisierte Release muss auf macOS erzeugt werden."

for command in security codesign diskutil hdiutil ditto plutil xcrun spctl shasum find; do
  command -v "$command" >/dev/null 2>&1 || fail "Benötigtes Tool fehlt: $command"
done

agentm5n_configure_xcode
cd "$ROOT_DIR"

printf '\n=== AgenTM5N Portable Release %s Build %s ===\n' "$VERSION" "$BUILD_NUMBER"

if [ -z "$SIGNING_IDENTITY" ]; then
  ALL_DEVELOPER_ID_LINES="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep '\"Developer ID Application:' || true)"
  IDENTITY_LINES="$(printf '%s\n' "$ALL_DEVELOPER_ID_LINES" \
    | grep -v 'CSSMERR_' || true)"
  IDENTITY_COUNT="$(printf '%s\n' "$IDENTITY_LINES" | awk 'NF { count++ } END { print count + 0 }')"

  if [ "$IDENTITY_COUNT" -eq 1 ]; then
    SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITY_LINES" | awk 'NF { print $2; exit }')"
  elif [ "$IDENTITY_COUNT" -eq 0 ]; then
    fail "Keine gültige Developer ID Application Identität im Schlüsselbund gefunden."
  else
    printf '%s\n' "$IDENTITY_LINES" >&2
    fail "Mehrere Developer-ID-Identitäten gefunden. Setze AGENTM5N_SIGNING_IDENTITY explizit."
  fi
fi

IDENTITY_INFO="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -F "$SIGNING_IDENTITY" || true)"
[ -n "$IDENTITY_INFO" ] || fail "Developer-ID-Identität nicht gefunden: $SIGNING_IDENTITY"
printf '%s\n' "$IDENTITY_INFO" | grep -q '\"Developer ID Application:' \
  || fail "Die ausgewählte Identität ist keine Developer ID Application Identität."
printf '%s\n' "$IDENTITY_INFO" | grep -q 'CSSMERR_' \
  && fail "Die ausgewählte Developer-ID-Identität ist ungültig oder widerrufen."

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
Notary-Keychain-Profil '$NOTARY_PROFILE' fehlt oder ist ungültig.
Einmalig anlegen mit:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "DEINE_APPLE_ID" \
    --team-id "DEINE_TEAM_ID"
Danach dieses Release-Skript erneut starten.
EOF
  exit 1
fi

MODEL_META="$(python3 - <<'PY' "$MODEL_META"
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"
MODEL_SOURCE_DIR="$(dirname "$MODEL_META")"

[ -f "$MODEL_META" ] || fail "Qwen3 meta.yaml fehlt: $MODEL_META"
[ -f "$MODEL_SOURCE_DIR/tokenizer.json" ] || fail "Qwen3 tokenizer.json fehlt: $MODEL_SOURCE_DIR/tokenizer.json"
find "$MODEL_SOURCE_DIR" -maxdepth 1 -type d -name '*embeddings*.mlmodelc' -print -quit | grep -q . \
  || fail "Qwen3 Embeddings .mlmodelc fehlt."
find "$MODEL_SOURCE_DIR" -maxdepth 1 -type d -name '*FFN*' -name '*.mlmodelc' -print -quit | grep -q . \
  || fail "Qwen3 FFN/PREFILL .mlmodelc fehlt."
find "$MODEL_SOURCE_DIR" -maxdepth 1 -type d -name '*lm_head*.mlmodelc' -print -quit | grep -q . \
  || fail "Qwen3 LM Head .mlmodelc fehlt."

printf 'Signing Identity: %s\n' "$SIGNING_IDENTITY"
printf 'Notary Profile:   %s\n' "$NOTARY_PROFILE"
printf 'Qwen3 Source:     %s\n' "$MODEL_SOURCE_DIR"

printf '\n=== 1. Source / Test Gate ===\n'
bash "$ROOT_DIR/scripts/verify.sh"

printf '\n=== 2. Native ANEMLL Helper reproduzierbar bauen ===\n'
bash "$ROOT_DIR/scripts/bootstrap-anemll-runtime.sh"
[ -x "$HELPER_SOURCE_DIR/anemllcli" ] \
  || fail "ANEMLL Helper wurde nicht erzeugt."

printf '\n=== 3. Developer-ID-App bauen ===\n'
export AGENTM5N_VERSION="$VERSION"
export AGENTM5N_BUILD_NUMBER="$BUILD_NUMBER"
export AGENTM5N_SIGNING_IDENTITY="$SIGNING_IDENTITY"
bash "$ROOT_DIR/scripts/build-app.sh"

printf '\n=== 4. ANEMLL + Qwen3 portabel in App einbetten ===\n'
rm -rf "$HELPER_DEST_DIR" "$MODEL_DEST_DIR"
mkdir -p "$HELPER_DEST_DIR" "$MODEL_DEST_DIR"

ditto "$HELPER_SOURCE_DIR" "$HELPER_DEST_DIR"

while IFS= read -r -d '' entry; do
  name="${entry##*/}"
  ditto "$entry" "$MODEL_DEST_DIR/$name"
done < <(
  find "$MODEL_SOURCE_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    ! -name '.git' \
    ! -name '.DS_Store' \
    -print0
)

[ -x "$HELPER_DEST_DIR/anemllcli" ] || fail "Gebündelter ANEMLL Helper fehlt."
[ -f "$MODEL_DEST_DIR/meta.yaml" ] || fail "Gebündelte Qwen3 meta.yaml fehlt."

printf '\n=== 5. Nested Helper + App neu signieren ===\n'
codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --options runtime \
  --timestamp \
  "$HELPER_DEST_DIR/anemllcli"

codesign --verify --strict --verbose=2 "$HELPER_DEST_DIR/anemllcli"

codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_FILE" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

AGENTM5N_REQUIRE_DEVELOPER_ID=1 \
  bash "$ROOT_DIR/scripts/check-release.sh"
AGENTM5N_APP_PATH="$APP_DIR" \
  bash "$ROOT_DIR/scripts/check-portable-anemll.sh"

printf '\n=== 6. Portable DMG erzeugen ===\n'
rm -rf "$RELEASE_WORK_DIR"
mkdir -p "$DMG_ROOT" "$DIST_DIR"
ditto "$APP_DIR" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH" "$CHECKSUM_PATH" "$NOTARY_RESULT" "$NOTARY_LOG"

if diskutil image create from \
  --volumeName "$APP_NAME $VERSION" \
  --format UDZO \
  "$DMG_ROOT" \
  "$DMG_PATH" >/dev/null 2>&1
then
  printf 'DMG: diskutil image create\n'
else
  printf 'DMG: diskutil nicht verfügbar, hdiutil-Fallback.\n'
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

printf '\n=== 7. Apple Notarisierung ===\n'
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
  || fail "Apple Notarisierung nicht akzeptiert (Status: ${NOTARY_STATUS:-unbekannt}). Siehe $NOTARY_LOG"

printf '\n=== 8. Ticket stapeln + Gatekeeper ===\n'
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

AGENTM5N_DMG_PATH="$DMG_PATH" \
AGENTM5N_VERSION="$VERSION" \
AGENTM5N_BUILD_NUMBER="$BUILD_NUMBER" \
  bash "$ROOT_DIR/scripts/verify-release-dmg.sh"

printf '\n=== 9. Portable Payload aus finaler DMG erneut prüfen ===\n'
mkdir -p "$FINAL_MOUNT"
hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$FINAL_MOUNT" \
  "$DMG_PATH" >/dev/null
ATTACHED=1

AGENTM5N_APP_PATH="$FINAL_MOUNT/$APP_NAME.app" \
  bash "$ROOT_DIR/scripts/check-portable-anemll.sh"

hdiutil detach "$FINAL_MOUNT" -quiet
ATTACHED=0

printf '\n=== 10. SHA-256 ===\n'
(
  cd "$DIST_DIR"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
cat "$CHECKSUM_PATH"

printf '\nPORTABLE RELEASE READY\n'
printf 'DMG:             %s\n' "$DMG_PATH"
printf 'SHA-256:         %s\n' "$CHECKSUM_PATH"
printf 'Version:         %s Build %s\n' "$VERSION" "$BUILD_NUMBER"
printf 'Developer ID:    valid\n'
printf 'Notarization:    Accepted + stapled\n'
printf 'Qwen3/ANEMLL:    embedded\n'
printf 'Transfer target: another Apple Silicon Mac\n'
