#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Der Xcode-Bootstrap muss auf macOS ausgeführt werden." >&2
  exit 1
fi

agentm5n_resolve_xcode

printf '\nXcode First-Launch-Komponenten initialisieren ...\n'
sudo env DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -runFirstLaunch

metal_is_operational() {
  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun --find metal >/dev/null 2>&1 &&
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun metal --version >/dev/null 2>&1
}

if [ "${AGENTM5N_FORCE_METAL_DOWNLOAD:-0}" = "1" ]; then
  printf '\nMetal Toolchain wird erzwungen neu angefordert ...\n'
  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -downloadComponent metalToolchain
elif metal_is_operational; then
  printf '\nMetal Toolchain ist bereits installiert; Download wird übersprungen.\n'
else
  printf '\nMetal Toolchain fehlt; optionale Komponente installieren ...\n'
  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -downloadComponent metalToolchain
fi

printf '\nToolchain prüfen ...\n'
agentm5n_require_metal
DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun metal --version

printf '\nAgenTM5N Xcode-Bootstrap erfolgreich.\n'
