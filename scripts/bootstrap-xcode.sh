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

printf '\nOptionalen Metal Toolchain installieren ...\n'
DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild -downloadComponent metalToolchain

printf '\nToolchain prüfen ...\n'
agentm5n_require_metal
DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun metal --version

printf '\nAgenTM5N Xcode-Bootstrap erfolgreich.\n'
