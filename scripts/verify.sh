#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Vollständige Verifikation erfordert macOS 26 und Xcode 26 oder neuer." >&2
  exit 1
fi

agentm5n_configure_xcode
cd "$ROOT_DIR"

swift package resolve
swift package dump-package >/dev/null
swift build -c debug --arch arm64

printf '\n=== AgenTM5N Security Regression Tests ===\n'
swift test --arch arm64

printf '\nAgenTM5N Debug-Build und Tests erfolgreich.\n'
