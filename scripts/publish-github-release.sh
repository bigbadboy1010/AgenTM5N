#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${AGENTM5N_VERSION:-1.3.6}"
BUILD_NUMBER="${AGENTM5N_BUILD_NUMBER:-36}"
REPOSITORY="${AGENTM5N_GITHUB_REPOSITORY:-bigbadboy1010/AgenTM5N}"
TAG="${AGENTM5N_GITHUB_TAG:-v${VERSION}-build${BUILD_NUMBER}}"
DIST_DIR="$ROOT_DIR/dist"
DMG_NAME="AgenTM5N-${VERSION}-build${BUILD_NUMBER}.dmg"
DMG_PATH="${AGENTM5N_DMG_PATH:-$DIST_DIR/$DMG_NAME}"
CHECKSUM_PATH="$DMG_PATH.sha256"

fail() {
  printf 'GITHUB RELEASE FAILED: %s\n' "$1" >&2
  exit 1
}

for command in git gh shasum; do
  command -v "$command" >/dev/null 2>&1 || fail "Benötigtes Tool fehlt: $command"
done

[ -f "$DMG_PATH" ] || fail "DMG nicht gefunden: $DMG_PATH"

gh auth status >/dev/null 2>&1 \
  || fail "GitHub CLI ist nicht angemeldet. Führe zuerst 'gh auth login' aus."

cd "$ROOT_DIR"

BRANCH="$(git branch --show-current)"
if [ "$BRANCH" != "main" ] && [ "${AGENTM5N_ALLOW_NON_MAIN_RELEASE:-0}" != "1" ]; then
  fail "Release-Publishing ist standardmäßig nur von main erlaubt (aktuell: $BRANCH)."
fi

# Untracked build/notary artifacts are intentionally allowed. Tracked source
# changes are not: a published binary must map to an exact source commit.
if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "Getrackte lokale Änderungen vorhanden. Vor dem Release committen oder verwerfen."
fi

TARGET_COMMIT="$(git rev-parse HEAD)"

git fetch origin --tags >/dev/null 2>&1
if [ "$BRANCH" = "main" ]; then
  REMOTE_MAIN="$(git rev-parse origin/main)"
  [ "$TARGET_COMMIT" = "$REMOTE_MAIN" ] \
    || fail "Lokales main entspricht nicht origin/main. Erst synchronisieren."
fi

printf '\n=== Finales DMG erneut prüfen ===\n'
if [ "$(uname -s)" = "Darwin" ]; then
  AGENTM5N_VERSION="$VERSION" \
  AGENTM5N_BUILD_NUMBER="$BUILD_NUMBER" \
  AGENTM5N_DMG_PATH="$DMG_PATH" \
    bash "$ROOT_DIR/scripts/verify-release-dmg.sh"
  xcrun stapler validate "$DMG_PATH" >/dev/null
else
  fail "DMG-Publishing muss auf macOS nach finaler Apple-Verifikation erfolgen."
fi

printf '\n=== SHA-256 erzeugen ===\n'
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)
cat "$CHECKSUM_PATH"

printf '\n=== Git Tag prüfen/erzeugen ===\n'
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  TAG_COMMIT="$(git rev-list -n 1 "$TAG")"
  [ "$TAG_COMMIT" = "$TARGET_COMMIT" ] \
    || fail "Tag $TAG zeigt auf $TAG_COMMIT statt auf $TARGET_COMMIT."
else
  git tag -a "$TAG" "$TARGET_COMMIT" \
    -m "AgenTM5N $VERSION Build $BUILD_NUMBER"
  git push origin "$TAG"
fi

printf '\n=== GitHub Release Asset archivieren ===\n'
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$TAG" \
    "$DMG_PATH" \
    "$CHECKSUM_PATH" \
    --repo "$REPOSITORY" \
    --clobber
else
  gh release create "$TAG" \
    "$DMG_PATH" \
    "$CHECKSUM_PATH" \
    --repo "$REPOSITORY" \
    --verify-tag \
    --title "AgenTM5N $VERSION Build $BUILD_NUMBER" \
    --generate-notes
fi

printf '\nGITHUB RELEASE READY\n'
printf 'Repository: %s\n' "$REPOSITORY"
printf 'Tag:        %s\n' "$TAG"
printf 'Commit:     %s\n' "$TARGET_COMMIT"
printf 'DMG:        %s\n' "$DMG_PATH"
printf 'SHA-256:    %s\n' "$CHECKSUM_PATH"
