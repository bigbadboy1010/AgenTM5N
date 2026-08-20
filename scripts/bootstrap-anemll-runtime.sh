#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

ANEMLL_REPOSITORY="${AGENTM5N_ANEMLL_REPOSITORY:-https://github.com/Anemll/Anemll.git}"
# Pin the upstream Swift runtime so Build 36 is reproducible and does not
# silently change when ANEMLL main moves.
ANEMLL_COMMIT="${AGENTM5N_ANEMLL_COMMIT:-fb42f60b2e7a7b4709052c7146d37480bf21941e}"
# Package.resolved in that ANEMLL commit pins swift-transformers to this exact
# revision. We verify the lock file before building with automatic resolution
# disabled, so branch-based upstream dependencies cannot silently drift.
SWIFT_TRANSFORMERS_COMMIT="${AGENTM5N_SWIFT_TRANSFORMERS_COMMIT:-abf5b1642bb8d095d6e048e6ccd87a95f0f5217a}"
SOURCE_ROOT="$ROOT_DIR/.build-artifacts/anemll-runtime-src"
PACKAGE_ROOT="$SOURCE_ROOT/anemll-swift-cli"
OUTPUT_ROOT="$ROOT_DIR/.build-artifacts/anemll-runtime"
OUTPUT_BINARY="$OUTPUT_ROOT/anemllcli"

fail() {
  printf 'ANEMLL BOOTSTRAP FAILED: %s\n' "$1" >&2
  exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Die native ANEMLL-Runtime muss auf macOS gebaut werden."
fi

for command in git swift codesign ditto file; do
  command -v "$command" >/dev/null 2>&1 || fail "Benötigtes Tool fehlt: $command"
done

agentm5n_configure_xcode
mkdir -p "$ROOT_DIR/.build-artifacts"

printf '\n=== ANEMLL Native Runtime Bootstrap ===\n'
printf 'Repository: %s\n' "$ANEMLL_REPOSITORY"
printf 'Pinned ANEMLL SHA: %s\n' "$ANEMLL_COMMIT"
printf 'Pinned swift-transformers SHA: %s\n' "$SWIFT_TRANSFORMERS_COMMIT"

if [ ! -d "$SOURCE_ROOT/.git" ]; then
  rm -rf "$SOURCE_ROOT"
  git clone --no-checkout "$ANEMLL_REPOSITORY" "$SOURCE_ROOT"
fi

git -C "$SOURCE_ROOT" remote set-url origin "$ANEMLL_REPOSITORY"
git -C "$SOURCE_ROOT" fetch --depth 1 origin "$ANEMLL_COMMIT"
git -C "$SOURCE_ROOT" checkout --detach --force "$ANEMLL_COMMIT"

ACTUAL_COMMIT="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
[ "$ACTUAL_COMMIT" = "$ANEMLL_COMMIT" ] \
  || fail "Checkout ist $ACTUAL_COMMIT statt $ANEMLL_COMMIT."

[ -f "$PACKAGE_ROOT/Package.swift" ] \
  || fail "ANEMLL Swift Package fehlt: $PACKAGE_ROOT/Package.swift"
[ -f "$PACKAGE_ROOT/Package.resolved" ] \
  || fail "ANEMLL Package.resolved fehlt; reproduzierbarer Build wird verweigert."
grep -Fq "$SWIFT_TRANSFORMERS_COMMIT" "$PACKAGE_ROOT/Package.resolved" \
  || fail "Package.resolved enthält nicht den erwarteten swift-transformers Pin."

printf '\n=== Release Build anemllcli (locked dependencies) ===\n'
cd "$PACKAGE_ROOT"
# Source-policy build identity: swift build -c release --product anemllcli
swift build \
  --disable-automatic-resolution \
  -c release \
  --product anemllcli
BIN_DIR="$(swift build --disable-automatic-resolution -c release --show-bin-path)"
SOURCE_BINARY="$BIN_DIR/anemllcli"
[ -x "$SOURCE_BINARY" ] || fail "anemllcli wurde nicht erzeugt: $SOURCE_BINARY"

rm -rf "$OUTPUT_ROOT"
mkdir -p "$OUTPUT_ROOT"
install -m 0755 "$SOURCE_BINARY" "$OUTPUT_BINARY"

# SwiftPM dependencies can carry resource bundles (notably tokenizer/Hub
# helpers). Copy every release bundle next to the standalone CLI binary so
# Bundle.module lookup continues to work outside the source build directory.
RESOURCE_COUNT=0
while IFS= read -r -d '' resource_bundle; do
  ditto "$resource_bundle" "$OUTPUT_ROOT/${resource_bundle##*/}"
  RESOURCE_COUNT=$((RESOURCE_COUNT + 1))
done < <(
  find "$BIN_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -name '*.bundle' \
    -print0
)

# The development helper is signed ad-hoc so Hardened Runtime launches from the
# AgenTM5N development app do not depend on an unsigned arbitrary executable.
codesign --force --sign - --options runtime "$OUTPUT_BINARY"
codesign --verify --strict --verbose=2 "$OUTPUT_BINARY"

printf '\n=== Native Helper Ready ===\n'
printf 'ANEMLL Commit: %s\n' "$ACTUAL_COMMIT"
printf 'Binary:        %s\n' "$OUTPUT_BINARY"
printf 'Resources:     %s bundle(s)\n' "$RESOURCE_COUNT"
printf 'Architecture:  %s\n' "$(file "$OUTPUT_BINARY")"
printf '\nAgenTM5N erkennt diesen Pfad automatisch.\n'
