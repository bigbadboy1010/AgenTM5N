#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

ANEMLL_REPOSITORY="${AGENTM5N_ANEMLL_REPOSITORY:-https://github.com/Anemll/Anemll.git}"
# Pin the upstream Swift runtime so Build 36 is reproducible and does not
# silently change when ANEMLL main moves.
ANEMLL_COMMIT="${AGENTM5N_ANEMLL_COMMIT:-fb42f60b2e7a7b4709052c7146d37480bf21941e}"
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

for command in git swift codesign; do
  command -v "$command" >/dev/null 2>&1 || fail "Benötigtes Tool fehlt: $command"
done

agentm5n_configure_xcode
mkdir -p "$ROOT_DIR/.build-artifacts" "$OUTPUT_ROOT"

printf '\n=== ANEMLL Native Runtime Bootstrap ===\n'
printf 'Repository: %s\n' "$ANEMLL_REPOSITORY"
printf 'Pinned SHA: %s\n' "$ANEMLL_COMMIT"

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

printf '\n=== Swift Package Resolve ===\n'
cd "$PACKAGE_ROOT"
swift package resolve

printf '\n=== Release Build anemllcli ===\n'
swift build -c release --product anemllcli
BIN_DIR="$(swift build -c release --show-bin-path)"
SOURCE_BINARY="$BIN_DIR/anemllcli"
[ -x "$SOURCE_BINARY" ] || fail "anemllcli wurde nicht erzeugt: $SOURCE_BINARY"

install -m 0755 "$SOURCE_BINARY" "$OUTPUT_BINARY"

# The development helper is signed ad-hoc so Hardened Runtime launches from the
# AgenTM5N development app do not depend on an unsigned arbitrary executable.
codesign --force --sign - --options runtime "$OUTPUT_BINARY"
codesign --verify --strict --verbose=2 "$OUTPUT_BINARY"

printf '\n=== Native Helper Ready ===\n'
printf 'ANEMLL Commit: %s\n' "$ACTUAL_COMMIT"
printf 'Binary:        %s\n' "$OUTPUT_BINARY"
printf 'Architecture:  %s\n' "$(file "$OUTPUT_BINARY")"
printf '\nAgenTM5N erkennt diesen Pfad automatisch.\n'
