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

printf '\nAgenTM5N verwendet für das eingebettete Terminal den CoreText-Renderer.\n'
printf 'Die optionale Metal Toolchain wird für diesen Build nicht benötigt.\n'
printf '\nAgenTM5N Xcode-Bootstrap erfolgreich.\n'
